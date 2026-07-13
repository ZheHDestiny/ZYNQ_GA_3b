#ifndef GA3B_PROTOCOL_H
#define GA3B_PROTOCOL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define GA3B_MAGIC_TASK          0x47413342u /* "GA3B" */
#define GA3B_MAGIC_RESULT        0x52534C54u /* "RSLT" */
#define GA3B_V1_MIN_VERSION      0x00010000u
#define GA3B_PROFILE_PURE3_RF    0x00000003u

#define GA3B_PURE3_GENE_COUNT    8u
#define GA3B_PURE3_POP_SIZE      32u
#define GA3B_TASK_HEADER_WORDS   7u
#define GA3B_GENE_BOUND_WORDS    3u
#define GA3B_PURE3_TASK_WORDS    (GA3B_TASK_HEADER_WORDS + GA3B_PURE3_GENE_COUNT * GA3B_GENE_BOUND_WORDS)
#define GA3B_PURE3_RESULT_WORDS  (6u + GA3B_PURE3_GENE_COUNT)

#define GA3B_TASK_WORD1_PURE3_RF ((GA3B_PURE3_GENE_COUNT << 2) | (GA3B_PURE3_POP_SIZE << 8))

/* ga3b_v1_min_accel_top AXI4-Lite register offsets. */
#define GA3B_REG_CTRL            0x00u
#define GA3B_REG_STATUS          0x04u
#define GA3B_REG_VERSION         0x08u
#define GA3B_REG_PROFILE         0x0Cu
#define GA3B_REG_RAW             0x10u

#define GA3B_CTRL_ENABLE         (1u << 0)
#define GA3B_CTRL_IRQ_ENABLE     (1u << 1)
#define GA3B_CTRL_CLEAR_DONE     (1u << 2)
#define GA3B_CTRL_SOFT_RESET     (1u << 3)

#define GA3B_STATUS_DONE         (1u << 0)
#define GA3B_STATUS_PROTO_ERROR  (1u << 1)
#define GA3B_STATUS_IRQ_RAW      (1u << 2)
#define GA3B_STATUS_IRQ_OUT      (1u << 3)
#define GA3B_STATUS_ENABLED      (1u << 8)

static inline uint32_t ga3b_q16_from_int(int32_t x) {
    return (uint32_t)(x << 16);
}

static inline size_t ga3b_make_pure3_task(uint32_t *task_words,
                                          uint16_t max_gen,
                                          uint32_t steps_limit,
                                          uint16_t mutation_rate_q16,
                                          uint16_t crossover_rate_q16,
                                          uint32_t seed0,
                                          uint32_t seed1,
                                          const int32_t bounds_min[GA3B_PURE3_GENE_COUNT],
                                          const int32_t bounds_max[GA3B_PURE3_GENE_COUNT],
                                          const int32_t bounds_scale[GA3B_PURE3_GENE_COUNT]) {
    size_t w = 0;
    task_words[w++] = GA3B_MAGIC_TASK;
    task_words[w++] = GA3B_TASK_WORD1_PURE3_RF;
    task_words[w++] = (uint32_t)max_gen;
    task_words[w++] = steps_limit;
    task_words[w++] = ((uint32_t)crossover_rate_q16 << 16) | mutation_rate_q16;
    task_words[w++] = seed0;
    task_words[w++] = seed1;
    for (size_t i = 0; i < GA3B_PURE3_GENE_COUNT; ++i) {
        task_words[w++] = (uint32_t)bounds_min[i];
        task_words[w++] = (uint32_t)bounds_max[i];
        task_words[w++] = (uint32_t)bounds_scale[i];
    }
    return w;
}

#ifdef __cplusplus
}
#endif

#endif /* GA3B_PROTOCOL_H */