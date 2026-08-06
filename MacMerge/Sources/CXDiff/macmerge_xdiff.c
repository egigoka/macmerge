#include "macmerge_xdiff.h"
#include "macmerge_xdiff_allocator.h"

#include <limits.h>
#include <stdint.h>
#include <stdlib.h>

#include "../../../Externals/xdiff/xinclude.h"

_Static_assert(MMX_DIFF_NEED_MINIMAL == XDF_NEED_MINIMAL, "minimal flag mismatch");
_Static_assert(MMX_DIFF_IGNORE_WHITESPACE == XDF_IGNORE_WHITESPACE, "whitespace flag mismatch");
_Static_assert(MMX_DIFF_IGNORE_WHITESPACE_CHANGE == XDF_IGNORE_WHITESPACE_CHANGE, "whitespace-change flag mismatch");
_Static_assert(MMX_DIFF_IGNORE_WHITESPACE_AT_EOL == XDF_IGNORE_WHITESPACE_AT_EOL, "EOL whitespace flag mismatch");
_Static_assert(MMX_DIFF_IGNORE_CR_AT_EOL == XDF_IGNORE_CR_AT_EOL, "CR flag mismatch");
_Static_assert(MMX_DIFF_IGNORE_CASE == XDF_IGNORE_CASE, "case flag mismatch");
_Static_assert(MMX_DIFF_IGNORE_NUMBERS == XDF_IGNORE_NUMBERS, "numbers flag mismatch");
_Static_assert(MMX_DIFF_IGNORE_BLANK_LINES == XDF_IGNORE_BLANK_LINES, "blank-lines flag mismatch");
_Static_assert(MMX_DIFF_PATIENCE == XDF_PATIENCE_DIFF, "patience flag mismatch");
_Static_assert(MMX_DIFF_HISTOGRAM == XDF_HISTOGRAM_DIFF, "histogram flag mismatch");
_Static_assert(MMX_DIFF_NONE == XDF_NONE_DIFF, "none flag mismatch");
_Static_assert(MMX_DIFF_INDENT_HEURISTIC == XDF_INDENT_HEURISTIC, "indent flag mismatch");

#if defined(DEBUG)
static _Thread_local size_t allocation_failure_after = SIZE_MAX;
static _Thread_local size_t allocation_attempt_count = 0;
static _Thread_local size_t outstanding_allocation_count = 0;

static int should_fail_allocation(void) {
    size_t attempt = allocation_attempt_count++;
    return attempt >= allocation_failure_after;
}

void *mmx_allocator_malloc(size_t size) {
    void *pointer;

    if (should_fail_allocation()) {
        return NULL;
    }
    pointer = malloc(size);
    if (pointer != NULL) {
        outstanding_allocation_count++;
    }
    return pointer;
}

void *mmx_allocator_calloc(size_t count, size_t size) {
    void *pointer;

    if (should_fail_allocation()) {
        return NULL;
    }
    pointer = calloc(count, size);
    if (pointer != NULL) {
        outstanding_allocation_count++;
    }
    return pointer;
}

void *mmx_allocator_realloc(void *pointer, size_t size) {
    const int was_null = pointer == NULL;
    void *resized;

    if (should_fail_allocation()) {
        return NULL;
    }
    resized = realloc(pointer, size);
    if (resized != NULL && was_null) {
        outstanding_allocation_count++;
    }
    return resized;
}

void mmx_allocator_free(void *pointer) {
    if (pointer == NULL) {
        return;
    }
    if (outstanding_allocation_count > 0) {
        outstanding_allocation_count--;
    }
    free(pointer);
}

void mmx_test_fail_allocation_after(size_t successful_allocations) {
    allocation_failure_after = successful_allocations;
    allocation_attempt_count = 0;
}

void mmx_test_disable_allocation_failures(void) {
    allocation_failure_after = SIZE_MAX;
    allocation_attempt_count = 0;
}

size_t mmx_test_allocation_attempt_count(void) {
    return allocation_attempt_count;
}

size_t mmx_test_outstanding_allocation_count(void) {
    return outstanding_allocation_count;
}
#else
void *mmx_allocator_malloc(size_t size) {
    return malloc(size);
}

void *mmx_allocator_calloc(size_t count, size_t size) {
    return calloc(count, size);
}

void *mmx_allocator_realloc(void *pointer, size_t size) {
    return realloc(pointer, size);
}

void mmx_allocator_free(void *pointer) {
    free(pointer);
}
#endif

static int consume_hunk(
    long left_start,
    long left_count,
    long right_start,
    long right_count,
    void *context
) {
    (void)left_start;
    (void)left_count;
    (void)right_start;
    (void)right_count;
    (void)context;
    return 0;
}

static int exceeds_line_limit(const unsigned char *data, size_t size) {
    size_t index = 0;
    size_t line_count = 0;

    while (index < size) {
        if (data[index] == '\r') {
            line_count++;
            if (index + 1 < size && data[index + 1] == '\n') {
                index++;
            }
        } else if (data[index] == '\n') {
            line_count++;
        }
        if (line_count > MMX_MAX_LINE_COUNT) {
            return 1;
        }
        index++;
    }

    if (size != 0 && data[size - 1] != '\r' && data[size - 1] != '\n') {
        line_count++;
    }
    return line_count > MMX_MAX_LINE_COUNT;
}

int32_t mmx_diff(
    const void *left,
    size_t left_size,
    const void *right,
    size_t right_size,
    uint64_t flags,
    mmx_diff_result *result
) {
    xdfenv_t environment;
    xdchange_t *script = NULL;
    xpparam_t parameters = {0};
    xdemitconf_t emit_configuration = {0};
    xdemitcb_t emit_callback = {0};
    mmfile_t left_file;
    mmfile_t right_file;
    xdchange_t *change;
    size_t count = 0;
    size_t index = 0;
    const uint64_t algorithm_flags = flags &
        (MMX_DIFF_PATIENCE | MMX_DIFF_HISTOGRAM | MMX_DIFF_NONE);
    const uint64_t supported_flags =
        MMX_DIFF_NEED_MINIMAL |
        MMX_DIFF_IGNORE_WHITESPACE |
        MMX_DIFF_IGNORE_WHITESPACE_CHANGE |
        MMX_DIFF_IGNORE_WHITESPACE_AT_EOL |
        MMX_DIFF_IGNORE_CR_AT_EOL |
        MMX_DIFF_IGNORE_CASE |
        MMX_DIFF_IGNORE_NUMBERS |
        MMX_DIFF_IGNORE_BLANK_LINES |
        MMX_DIFF_PATIENCE |
        MMX_DIFF_HISTOGRAM |
        MMX_DIFF_NONE |
        MMX_DIFF_INDENT_HEURISTIC;

    if (result == NULL || result->hunks != NULL || result->count != 0) {
        return -1;
    }

    /* Bound xdiff's line-index allocations and the caller's duplicate buffers. */
    if ((left == NULL && left_size != 0) || (right == NULL && right_size != 0) ||
        left_size > MMX_MAX_INPUT_SIZE || right_size > MMX_MAX_INPUT_SIZE ||
        flags > ULONG_MAX || (flags & ~supported_flags) != 0) {
        return -1;
    }
    if (algorithm_flags != 0 && (algorithm_flags & (algorithm_flags - 1)) != 0) {
        return -1;
    }
    if (exceeds_line_limit(left, left_size) || exceeds_line_limit(right, right_size)) {
        return -1;
    }

    left_file.ptr = (char *)left;
    left_file.size = (long)left_size;
    right_file.ptr = (char *)right;
    right_file.size = (long)right_size;
    parameters.flags = (unsigned long)flags;
    emit_configuration.hunk_func = consume_hunk;

    if (xdl_diff_modified(
            &left_file,
            &right_file,
            &parameters,
            &emit_configuration,
            &emit_callback,
            &environment,
            &script
        ) != 0) {
        return -2;
    }

    for (change = script; change != NULL; change = change->next) {
        if (count == SIZE_MAX) {
            xdl_free_script(script);
            xdl_free_env(&environment);
            return -3;
        }
        count++;
    }

    if (count > SIZE_MAX / sizeof(*result->hunks)) {
        xdl_free_script(script);
        xdl_free_env(&environment);
        return -3;
    }

    if (count != 0) {
        result->hunks = mmx_allocator_calloc(count, sizeof(*result->hunks));
        if (result->hunks == NULL) {
            xdl_free_script(script);
            xdl_free_env(&environment);
            return -3;
        }
    }

    for (change = script; change != NULL; change = change->next) {
        result->hunks[index].left_start = change->i1;
        result->hunks[index].left_count = change->chg1;
        result->hunks[index].right_start = change->i2;
        result->hunks[index].right_count = change->chg2;
        result->hunks[index].is_trivial = change->ignore != 0;
        index++;
    }

    result->count = count;
    xdl_free_script(script);
    xdl_free_env(&environment);
    return 0;
}

void mmx_diff_result_free(mmx_diff_result *result) {
    if (result == NULL) {
        return;
    }
    mmx_allocator_free(result->hunks);
    result->hunks = NULL;
    result->count = 0;
}
