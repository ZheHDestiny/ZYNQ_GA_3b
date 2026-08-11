// SPDX-License-Identifier: MIT
// Persistent UART-to-AXI-DMA board agent for the GA3B v1-min pure3 profile.

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "xparameters.h"
#include "xil_cache.h"
#include "xil_io.h"
#include "xil_printf.h"
#include "xaxidma.h"

#include "ga3b_protocol.h"

#ifndef GA3B_ACCEL_BASEADDR
# ifdef XPAR_GA3B_ACCEL_0_S_AXI_BASEADDR
#  define GA3B_ACCEL_BASEADDR XPAR_GA3B_ACCEL_0_S_AXI_BASEADDR
# elif defined(XPAR_GA3B_V1_MIN_ACCEL_TOP_0_S_AXI_BASEADDR)
#  define GA3B_ACCEL_BASEADDR XPAR_GA3B_V1_MIN_ACCEL_TOP_0_S_AXI_BASEADDR
# else
#  define GA3B_ACCEL_BASEADDR 0x43C00000u
# endif
#endif

#ifndef GA3B_AXIDMA_DEVICE_ID
# ifdef XPAR_AXIDMA_0_DEVICE_ID
#  define GA3B_AXIDMA_DEVICE_ID XPAR_AXIDMA_0_DEVICE_ID
# elif defined(XPAR_AXI_DMA_0_DEVICE_ID)
#  define GA3B_AXIDMA_DEVICE_ID XPAR_AXI_DMA_0_DEVICE_ID
# else
#  define GA3B_AXIDMA_DEVICE_ID 0u
# endif
#endif

#define GA3B_DMA_TIMEOUT 200000000u
#define GA3B_LINE_BYTES  192u
#define GA3B_ARG_MAX     10u

static XAxiDma axi_dma;
static uint32_t tx_task[GA3B_PURE3_TASK_WORDS] __attribute__((aligned(64)));
static uint32_t rx_result[GA3B_PURE3_RESULT_WORDS] __attribute__((aligned(64)));

static const int32_t default_min[GA3B_PURE3_GENE_COUNT] = {
    (int32_t)0xFFFE0000, (int32_t)0xFFFE0000, (int32_t)0xFFFF0000, (int32_t)0xFFFF0000,
    (int32_t)0xFFFE0000, (int32_t)0xFFFE0000, (int32_t)0xFFFF0000, (int32_t)0xFFFF0000
};
static const int32_t default_max[GA3B_PURE3_GENE_COUNT] = {
    (int32_t)0x00020000, (int32_t)0x00020000, (int32_t)0x00010000, (int32_t)0x00010000,
    (int32_t)0x00020000, (int32_t)0x00020000, (int32_t)0x00010000, (int32_t)0x00010000
};
static const int32_t default_scale[GA3B_PURE3_GENE_COUNT] = {
    (int32_t)0x0000199A, (int32_t)0x0000199A, (int32_t)0x00000800, (int32_t)0x00000800,
    (int32_t)0x0000199A, (int32_t)0x0000199A, (int32_t)0x00000800, (int32_t)0x00000800
};

static uint32_t reg_read(uint32_t off) {
    return Xil_In32((UINTPTR)(GA3B_ACCEL_BASEADDR + off));
}

static void reg_write(uint32_t off, uint32_t value) {
    Xil_Out32((UINTPTR)(GA3B_ACCEL_BASEADDR + off), value);
}

static int dma_init(void) {
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(GA3B_AXIDMA_DEVICE_ID);
    int status;
    if (cfg == NULL) return -1;
    status = XAxiDma_CfgInitialize(&axi_dma, cfg);
    if (status != XST_SUCCESS) return -2;
    if (XAxiDma_HasSg(&axi_dma)) return -3;
    XAxiDma_IntrDisable(&axi_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&axi_dma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    return 0;
}

static void accelerator_reset(void) {
    reg_write(GA3B_REG_CTRL, GA3B_CTRL_ENABLE | GA3B_CTRL_SOFT_RESET);
    reg_write(GA3B_REG_CTRL, GA3B_CTRL_ENABLE | GA3B_CTRL_IRQ_ENABLE | GA3B_CTRL_CLEAR_DONE);
    reg_write(GA3B_REG_CTRL, GA3B_CTRL_ENABLE | GA3B_CTRL_IRQ_ENABLE);
}

static int run_search(uint16_t max_gen, uint32_t steps, uint16_t mutation,
                      uint16_t crossover, uint32_t seed0, uint32_t seed1) {
    size_t words;
    uint32_t timeout;
    int status;

    accelerator_reset();
    words = ga3b_make_pure3_task(tx_task, max_gen, steps, mutation, crossover,
                                 seed0, seed1, default_min, default_max, default_scale);
    memset(rx_result, 0, sizeof(rx_result));
    Xil_DCacheFlushRange((UINTPTR)tx_task, (unsigned)(words * sizeof(uint32_t)));
    Xil_DCacheFlushRange((UINTPTR)rx_result, (unsigned)sizeof(rx_result));

    status = XAxiDma_SimpleTransfer(&axi_dma, (UINTPTR)rx_result,
                                    (unsigned)sizeof(rx_result), XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) return -10;
    status = XAxiDma_SimpleTransfer(&axi_dma, (UINTPTR)tx_task,
                                    (unsigned)(words * sizeof(uint32_t)), XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) return -11;

    timeout = GA3B_DMA_TIMEOUT;
    while (timeout != 0u) {
        uint32_t hw_status = reg_read(GA3B_REG_STATUS);
        if (!XAxiDma_Busy(&axi_dma, XAXIDMA_DMA_TO_DEVICE) &&
            !XAxiDma_Busy(&axi_dma, XAXIDMA_DEVICE_TO_DMA) &&
            ((hw_status & GA3B_STATUS_DONE) != 0u)) break;
        --timeout;
    }
    if (timeout == 0u) return -12;
    Xil_DCacheInvalidateRange((UINTPTR)rx_result, (unsigned)sizeof(rx_result));
    if (rx_result[0] != GA3B_MAGIC_RESULT) return -13;
    if ((reg_read(GA3B_REG_STATUS) & GA3B_STATUS_PROTO_ERROR) != 0u) return -14;
    return 0;
}

static unsigned split_args(char *line, char *argv[GA3B_ARG_MAX]) {
    unsigned argc = 0u;
    char *p = line;
    while (*p != '\0' && argc < GA3B_ARG_MAX) {
        while (*p == ' ' || *p == '\t') ++p;
        if (*p == '\0') break;
        argv[argc++] = p;
        while (*p != '\0' && *p != ' ' && *p != '\t') ++p;
        if (*p != '\0') *p++ = '\0';
    }
    return argc;
}

static void read_line(char *line, unsigned capacity) {
    unsigned n = 0u;
    for (;;) {
        char c = inbyte();
        if (c == '\r' || c == '\n') {
            if (n != 0u) break;
            continue;
        }
        if ((c == '\b' || c == 0x7f) && n != 0u) {
            --n;
        } else if (n + 1u < capacity && c >= 0x20 && c <= 0x7e) {
            line[n++] = c;
        }
    }
    line[n] = '\0';
}

static void print_result(void) {
    unsigned i;
    xil_printf("GA3B_RSP OK RESULT magic=0x%08lx status=0x%08lx best_idx=%lu "
               "fitness_hi=0x%08lx fitness_lo=0x%08lx steps=%lu",
               (unsigned long)rx_result[0], (unsigned long)rx_result[1],
               (unsigned long)rx_result[2], (unsigned long)rx_result[4],
               (unsigned long)rx_result[3], (unsigned long)rx_result[5]);
    for (i = 0u; i < GA3B_PURE3_GENE_COUNT; ++i)
        xil_printf(" gene%lu=0x%08lx", (unsigned long)i, (unsigned long)rx_result[6u + i]);
    xil_printf("\r\n");
}

static uint32_t parse_u32(const char *s) {
    return (uint32_t)strtoul(s, NULL, 0);
}

int main(void) {
    char line[GA3B_LINE_BYTES];
    char *argv[GA3B_ARG_MAX];
    int dma_status = dma_init();

    xil_printf("\r\nGA3B_AGENT_READY protocol=1 version=0x%08lx profile=0x%08lx dma=%d\r\n",
               (unsigned long)reg_read(GA3B_REG_VERSION),
               (unsigned long)reg_read(GA3B_REG_PROFILE), dma_status);
    if (dma_status != 0) {
        xil_printf("GA3B_RSP ERR DMA_INIT code=%d\r\n", dma_status);
        for (;;) { }
    }

    for (;;) {
        unsigned argc;
        read_line(line, sizeof(line));
        argc = split_args(line, argv);
        if (argc == 0u) continue;

        if (strcmp(argv[0], "PING") == 0) {
            xil_printf("GA3B_RSP OK PONG\r\n");
        } else if (strcmp(argv[0], "INFO") == 0) {
            xil_printf("GA3B_RSP OK INFO protocol=1 version=0x%08lx profile=0x%08lx "
                       "status=0x%08lx raw=0x%08lx\r\n",
                       (unsigned long)reg_read(GA3B_REG_VERSION),
                       (unsigned long)reg_read(GA3B_REG_PROFILE),
                       (unsigned long)reg_read(GA3B_REG_STATUS),
                       (unsigned long)reg_read(GA3B_REG_RAW));
        } else if (strcmp(argv[0], "STATUS") == 0) {
            xil_printf("GA3B_RSP OK STATUS status=0x%08lx raw=0x%08lx\r\n",
                       (unsigned long)reg_read(GA3B_REG_STATUS),
                       (unsigned long)reg_read(GA3B_REG_RAW));
        } else if (strcmp(argv[0], "RESET") == 0) {
            accelerator_reset();
            xil_printf("GA3B_RSP OK RESET\r\n");
        } else if (strcmp(argv[0], "SELFTEST") == 0) {
            int rc = run_search(2u, 16u, 0x1000u, 0xC000u, 0x12345678u, 0x87654321u);
            if (rc == 0 && rx_result[3] == 0x00000010u && rx_result[4] == 0x00000001u && rx_result[5] == 16u) {
                print_result();
                xil_printf("GA3B_RSP OK SELFTEST_PASS\r\n");
            } else {
                xil_printf("GA3B_RSP ERR SELFTEST code=%d status=0x%08lx raw=0x%08lx\r\n",
                           rc, (unsigned long)reg_read(GA3B_REG_STATUS),
                           (unsigned long)reg_read(GA3B_REG_RAW));
            }
        } else if (strcmp(argv[0], "RUN") == 0 && argc == 7u) {
            uint32_t max_gen = parse_u32(argv[1]);
            uint32_t steps = parse_u32(argv[2]);
            uint32_t mutation = parse_u32(argv[3]);
            uint32_t crossover = parse_u32(argv[4]);
            uint32_t seed0 = parse_u32(argv[5]);
            uint32_t seed1 = parse_u32(argv[6]);
            int rc;
            if (max_gen == 0u || max_gen > 65535u || steps == 0u ||
                mutation > 65535u || crossover > 65535u) {
                xil_printf("GA3B_RSP ERR BAD_ARGS\r\n");
                continue;
            }
            rc = run_search((uint16_t)max_gen, steps, (uint16_t)mutation,
                            (uint16_t)crossover, seed0, seed1);
            if (rc == 0) print_result();
            else xil_printf("GA3B_RSP ERR RUN code=%d status=0x%08lx raw=0x%08lx\r\n",
                            rc, (unsigned long)reg_read(GA3B_REG_STATUS),
                            (unsigned long)reg_read(GA3B_REG_RAW));
        } else if (strcmp(argv[0], "HELP") == 0) {
            xil_printf("GA3B_RSP OK HELP commands=PING,INFO,STATUS,RESET,SELFTEST,"
                       "RUN_maxgen_steps_mutation_crossover_seed0_seed1\r\n");
        } else {
            xil_printf("GA3B_RSP ERR UNKNOWN_COMMAND\r\n");
        }
    }
}
