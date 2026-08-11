// SPDX-License-Identifier: MIT
// Read-only Linux /dev/mem probe for the GA3B v1-min AXI-Lite block.

#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

#define GA3B_BASE       0x43C00000u
#define GA3B_MAP_SIZE   0x00010000u
#define REG_STATUS      0x04u
#define REG_VERSION     0x08u
#define REG_PROFILE     0x0Cu
#define REG_RAW         0x10u
#define EXPECT_VERSION  0x00010000u
#define EXPECT_PROFILE  0x00000003u

static uint32_t reg_read(volatile uint8_t *base, uint32_t offset) {
    return *(volatile uint32_t *)(base + offset);
}

int main(void) {
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) {
        fprintf(stderr, "GA3B_PROBE_FAIL open(/dev/mem): %s\n", strerror(errno));
        return 2;
    }

    void *map = mmap(NULL, GA3B_MAP_SIZE, PROT_READ | PROT_WRITE,
                     MAP_SHARED, fd, GA3B_BASE);
    if (map == MAP_FAILED) {
        fprintf(stderr, "GA3B_PROBE_FAIL mmap(0x%08x): %s\n",
                GA3B_BASE, strerror(errno));
        close(fd);
        return 3;
    }

    volatile uint8_t *base = (volatile uint8_t *)map;
    uint32_t version = reg_read(base, REG_VERSION);
    uint32_t profile = reg_read(base, REG_PROFILE);
    uint32_t status  = reg_read(base, REG_STATUS);
    uint32_t raw     = reg_read(base, REG_RAW);

    printf("GA3B register probe: base=0x%08x version=0x%08x "
           "profile=0x%08x status=0x%08x raw=0x%08x\n",
           GA3B_BASE, version, profile, status, raw);

    munmap(map, GA3B_MAP_SIZE);
    close(fd);

    if (version != EXPECT_VERSION || profile != EXPECT_PROFILE) {
        fprintf(stderr,
                "GA3B_PROBE_FAIL expected version=0x%08x profile=0x%08x\n",
                EXPECT_VERSION, EXPECT_PROFILE);
        return 4;
    }
    puts("GA3B_REG_PROBE_PASS");
    return 0;
}
