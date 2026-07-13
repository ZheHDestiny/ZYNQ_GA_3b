// SPDX-License-Identifier: MIT
// Minimal standalone PS smoke test for GA3B v1.0 block design.
//
// Build in Vitis/standalone BSP after exporting hardware from Vivado. The app
// sends one pure3 SearchTask through AXI DMA MM2S, receives one SearchResult
// through S2MM, and reads the GA3B AXI-Lite status registers.

#include <stdint.h>
#include "xparameters.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xaxidma.h"
#include "ga3b_protocol.h"

#ifndef GA3B_ACCEL_BASEADDR
# ifdef XPAR_GA3B_ACCEL_0_S_AXI_BASEADDR
#  define GA3B_ACCEL_BASEADDR XPAR_GA3B_ACCEL_0_S_AXI_BASEADDR
# elif defined(XPAR_GA3B_V1_MIN_ACCEL_TOP_0_S_AXI_BASEADDR)
#  define GA3B_ACCEL_BASEADDR XPAR_GA3B_V1_MIN_ACCEL_TOP_0_S_AXI_BASEADDR
# elif defined(XPAR_GA3B_SYSTEM_GA3B_ACCEL_0_S_AXI_BASEADDR)
#  define GA3B_ACCEL_BASEADDR XPAR_GA3B_SYSTEM_GA3B_ACCEL_0_S_AXI_BASEADDR
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

static uint32_t tx_task[GA3B_PURE3_TASK_WORDS] __attribute__((aligned(64)));
static uint32_t rx_result[GA3B_PURE3_RESULT_WORDS] __attribute__((aligned(64)));
static XAxiDma AxiDma;

static uint32_t ga3b_reg_read(uint32_t off) {
    return Xil_In32((UINTPTR)(GA3B_ACCEL_BASEADDR + off));
}

static void ga3b_reg_write(uint32_t off, uint32_t v) {
    Xil_Out32((UINTPTR)(GA3B_ACCEL_BASEADDR + off), v);
}

static int init_dma(void) {
    XAxiDma_Config *cfg = XAxiDma_LookupConfig(GA3B_AXIDMA_DEVICE_ID);
    if (!cfg) {
        xil_printf("ERR: XAxiDma_LookupConfig failed\r\n");
        return -1;
    }
    int st = XAxiDma_CfgInitialize(&AxiDma, cfg);
    if (st != XST_SUCCESS) {
        xil_printf("ERR: XAxiDma_CfgInitialize=%d\r\n", st);
        return -2;
    }
    if (XAxiDma_HasSg(&AxiDma)) {
        xil_printf("ERR: DMA is configured in SG mode; expected simple mode\r\n");
        return -3;
    }
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);
    return 0;
}

int main(void) {
    xil_printf("\r\nGA3B v1.0 minimal PS/DMA smoke test\r\n");
    xil_printf("GA3B base=0x%08lx DMA device id=%lu\r\n", (unsigned long)GA3B_ACCEL_BASEADDR, (unsigned long)GA3B_AXIDMA_DEVICE_ID);

    if (init_dma() != 0) return -1;

    uint32_t version = ga3b_reg_read(GA3B_REG_VERSION);
    uint32_t profile = ga3b_reg_read(GA3B_REG_PROFILE);
    xil_printf("version=0x%08lx profile=0x%08lx\r\n", (unsigned long)version, (unsigned long)profile);
    if (version != GA3B_V1_MIN_VERSION || profile != GA3B_PROFILE_PURE3_RF) {
        xil_printf("WARN: unexpected GA3B version/profile; continuing for smoke test\r\n");
    }

    ga3b_reg_write(GA3B_REG_CTRL, GA3B_CTRL_ENABLE | GA3B_CTRL_SOFT_RESET);
    ga3b_reg_write(GA3B_REG_CTRL, GA3B_CTRL_ENABLE | GA3B_CTRL_IRQ_ENABLE | GA3B_CTRL_CLEAR_DONE);
    ga3b_reg_write(GA3B_REG_CTRL, GA3B_CTRL_ENABLE | GA3B_CTRL_IRQ_ENABLE);

    const int32_t bmin[GA3B_PURE3_GENE_COUNT] = {
        (int32_t)0xFFFE0000, (int32_t)0xFFFE0000, (int32_t)0xFFFF0000, (int32_t)0xFFFF0000,
        (int32_t)0xFFFE0000, (int32_t)0xFFFE0000, (int32_t)0xFFFF0000, (int32_t)0xFFFF0000
    };
    const int32_t bmax[GA3B_PURE3_GENE_COUNT] = {
        (int32_t)0x00020000, (int32_t)0x00020000, (int32_t)0x00010000, (int32_t)0x00010000,
        (int32_t)0x00020000, (int32_t)0x00020000, (int32_t)0x00010000, (int32_t)0x00010000
    };
    const int32_t bscale[GA3B_PURE3_GENE_COUNT] = {
        (int32_t)0x0000199A, (int32_t)0x0000199A, (int32_t)0x00000800, (int32_t)0x00000800,
        (int32_t)0x0000199A, (int32_t)0x0000199A, (int32_t)0x00000800, (int32_t)0x00000800
    };

    size_t words = ga3b_make_pure3_task(tx_task,
                                        2,       /* max_gen */
                                        16,      /* steps_limit */
                                        0x1000,  /* mutation_rate_q16 */
                                        0xC000,  /* crossover_rate_q16 */
                                        0x12345678u,
                                        0x87654321u,
                                        bmin, bmax, bscale);
    for (size_t i = 0; i < GA3B_PURE3_RESULT_WORDS; ++i) rx_result[i] = 0;

    Xil_DCacheFlushRange((UINTPTR)tx_task, (unsigned)(words * sizeof(uint32_t)));
    Xil_DCacheFlushRange((UINTPTR)rx_result, (unsigned)(GA3B_PURE3_RESULT_WORDS * sizeof(uint32_t)));

    int st = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)rx_result,
                                    GA3B_PURE3_RESULT_WORDS * sizeof(uint32_t),
                                    XAXIDMA_DEVICE_TO_DMA);
    if (st != XST_SUCCESS) {
        xil_printf("ERR: S2MM SimpleTransfer=%d\r\n", st);
        return -2;
    }

    st = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)tx_task,
                                (unsigned)(words * sizeof(uint32_t)),
                                XAXIDMA_DMA_TO_DEVICE);
    if (st != XST_SUCCESS) {
        xil_printf("ERR: MM2S SimpleTransfer=%d\r\n", st);
        return -3;
    }

    uint32_t timeout = GA3B_DMA_TIMEOUT;
    while (timeout--) {
        uint32_t status = ga3b_reg_read(GA3B_REG_STATUS);
        if (!XAxiDma_Busy(&AxiDma, XAXIDMA_DMA_TO_DEVICE) &&
            !XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA) &&
            (status & GA3B_STATUS_DONE)) {
            break;
        }
    }
    if (timeout == 0) {
        xil_printf("ERR: timeout status=0x%08lx raw=0x%08lx\r\n",
                   (unsigned long)ga3b_reg_read(GA3B_REG_STATUS),
                   (unsigned long)ga3b_reg_read(GA3B_REG_RAW));
        return -4;
    }

    Xil_DCacheInvalidateRange((UINTPTR)rx_result, (unsigned)(GA3B_PURE3_RESULT_WORDS * sizeof(uint32_t)));

    xil_printf("result magic=0x%08lx status_word=0x%08lx best_idx=%lu fitness_lo=0x%08lx fitness_hi=0x%08lx steps=%lu\r\n",
               (unsigned long)rx_result[0],
               (unsigned long)rx_result[1],
               (unsigned long)rx_result[2],
               (unsigned long)rx_result[3],
               (unsigned long)rx_result[4],
               (unsigned long)rx_result[5]);

    if (rx_result[0] != GA3B_MAGIC_RESULT) {
        xil_printf("ERR: bad result magic\r\n");
        return -5;
    }
    if (ga3b_reg_read(GA3B_REG_STATUS) & GA3B_STATUS_PROTO_ERROR) {
        xil_printf("ERR: accelerator reported protocol error\r\n");
        return -6;
    }

    xil_printf("GA3B_DMA_SMOKE_PASS\r\n");
    return 0;
}