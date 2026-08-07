#ifndef MACMERGE_XDIFF_H
#define MACMERGE_XDIFF_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define MMX_DIFF_NEED_MINIMAL ((uint64_t)1 << 0)
#define MMX_DIFF_IGNORE_WHITESPACE ((uint64_t)1 << 1)
#define MMX_DIFF_IGNORE_WHITESPACE_CHANGE ((uint64_t)1 << 2)
#define MMX_DIFF_IGNORE_WHITESPACE_AT_EOL ((uint64_t)1 << 3)
#define MMX_DIFF_IGNORE_CR_AT_EOL ((uint64_t)1 << 4)
#define MMX_DIFF_IGNORE_CASE ((uint64_t)1 << 5)
#define MMX_DIFF_IGNORE_NUMBERS ((uint64_t)1 << 6)
#define MMX_DIFF_IGNORE_BLANK_LINES ((uint64_t)1 << 7)
#define MMX_DIFF_PATIENCE ((uint64_t)1 << 14)
#define MMX_DIFF_HISTOGRAM ((uint64_t)1 << 15)
#define MMX_DIFF_NONE ((uint64_t)1 << 16)
#define MMX_DIFF_INDENT_HEURISTIC ((uint64_t)1 << 23)
enum { MMX_MAX_INPUT_SIZE = 64 * 1024 * 1024 };
enum { MMX_MAX_LINE_COUNT = 1024 * 1024 };

typedef struct mmx_diff_hunk {
    int64_t left_start;
    int64_t left_count;
    int64_t right_start;
    int64_t right_count;
    int32_t is_trivial;
} mmx_diff_hunk;

typedef struct mmx_diff_result {
    mmx_diff_hunk *hunks;
    size_t count;
} mmx_diff_result;

typedef struct mmx_bytes_result {
    uint8_t *bytes;
    size_t size;
} mmx_bytes_result;

int32_t mmx_diff(
    const void *left,
    size_t left_size,
    const void *right,
    size_t right_size,
    uint64_t flags,
    mmx_diff_result *result
);

void mmx_diff_result_free(mmx_diff_result *result);

int32_t mmx_regex_substitute(
    const void *subject,
    size_t subject_size,
    const void *pattern,
    size_t pattern_size,
    const void *replacement,
    size_t replacement_size,
    int32_t case_sensitive,
    size_t maximum_size,
    mmx_bytes_result *result
);

void mmx_bytes_result_free(mmx_bytes_result *result);

#if defined(DEBUG)
/* Deterministic diagnostics used by sanitizer-backed allocation recovery tests. */
void mmx_test_fail_allocation_after(size_t successful_allocations);
void mmx_test_disable_allocation_failures(void);
size_t mmx_test_allocation_attempt_count(void);
size_t mmx_test_outstanding_allocation_count(void);
#endif

#ifdef __cplusplus
}
#endif

#endif
