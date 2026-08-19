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

typedef struct mmx_moved_group {
    xrecord_t *record;
    int32_t left_line;
    int32_t right_line;
} mmx_moved_group;

typedef struct mmx_moved_table {
    uint32_t *slots;
    mmx_moved_group *groups;
    size_t capacity;
    size_t count;
    size_t group_capacity;
    long flags;
} mmx_moved_table;

static size_t moved_group_slot(unsigned long hash, size_t mask) {
    uint64_t value = (uint64_t)hash;
    value ^= value >> 30;
    value *= UINT64_C(0xBF58476D1CE4E5B9);
    value ^= value >> 27;
    value *= UINT64_C(0x94D049BB133111EB);
    value ^= value >> 31;
    return (size_t)value & mask;
}

static mmx_moved_group *find_moved_group(
    mmx_moved_table *table,
    xrecord_t *record,
    int create
) {
    const size_t mask = table->capacity - 1;
    size_t slot = moved_group_slot(record->ha, mask);

    while (table->slots[slot] != 0) {
        mmx_moved_group *group = &table->groups[table->slots[slot] - 1];
        if (group->record->ha == record->ha &&
            xdl_recmatch(
                group->record->ptr,
                group->record->size,
                record->ptr,
                record->size,
                table->flags
            )) {
            return group;
        }
        slot = (slot + 1) & mask;
    }
    if (!create) {
        return NULL;
    }
    if (table->count >= table->group_capacity || table->count >= UINT32_MAX) {
        return NULL;
    }
    table->slots[slot] = (uint32_t)table->count + 1;
    table->groups[table->count].record = record;
    table->groups[table->count].left_line = -1;
    table->groups[table->count].right_line = -1;
    table->count++;
    return &table->groups[table->count - 1];
}

static int moved_group_is_unique(const mmx_moved_group *group) {
    return group != NULL && group->left_line >= 0 && group->right_line >= 0;
}

static int add_moved_group_line(
    mmx_moved_table *table,
    xrecord_t *record,
    long line,
    int side
) {
    mmx_moved_group *group = find_moved_group(table, record, 1);
    int32_t *single_line;

    if (group == NULL || line > INT32_MAX) {
        return -1;
    }
    single_line = side == 0 ? &group->left_line : &group->right_line;
    *single_line = *single_line == -1 ? (int32_t)line : -2;
    return 0;
}

static int changed_line(const xdfile_t *file, long line) {
    return 0 <= line && line < file->nrec && file->rchg[line] != 0;
}

static int records_share_moved_group(
    mmx_moved_table *table,
    xrecord_t *left,
    xrecord_t *right
) {
    mmx_moved_group *left_group = find_moved_group(table, left, 0);
    return left_group != NULL && left_group == find_moved_group(table, right, 0);
}

static int record_moved_range(
    int32_t *partners,
    long source_start,
    long target_start,
    long count
) {
    long offset;

    if (partners == NULL) {
        return count == 0 ? 0 : -1;
    }
    for (offset = 0; offset < count; offset++) {
        partners[source_start + offset] = (int32_t)(target_start + offset);
    }
    return 0;
}

static int detect_moved_from_left(
    const xdfenv_t *environment,
    const xdchange_t *script,
    mmx_moved_table *table,
    int32_t *left_partners
) {
    const xdchange_t *change;

    if (environment->xdf1.nrec != 0 && left_partners == NULL) {
        return -1;
    }

    for (change = script; change != NULL; change = change->next) {
        long cursor = change->i1;
        const long end = change->i1 + change->chg1;

        while (cursor < end) {
            mmx_moved_group *seed_group = NULL;
            long left_seed;
            long right_seed;
            long left_start;
            long right_start;
            long left_end;
            long right_end;

            for (left_seed = cursor; left_seed < end; left_seed++) {
                seed_group = find_moved_group(
                    table,
                    environment->xdf1.recs[left_seed],
                    0
                );
                if (moved_group_is_unique(seed_group)) {
                    break;
                }
            }
            if (left_seed == end) {
                break;
            }
            right_seed = seed_group->right_line;
            left_start = left_seed;
            right_start = right_seed;
            while (left_start > cursor && changed_line(&environment->xdf2, right_start - 1) &&
                   records_share_moved_group(
                       table,
                       environment->xdf1.recs[left_start - 1],
                       environment->xdf2.recs[right_start - 1]
                   )) {
                left_start--;
                right_start--;
            }
            left_end = left_seed + 1;
            right_end = right_seed + 1;
            while (left_end < end && changed_line(&environment->xdf2, right_end) &&
                   records_share_moved_group(
                       table,
                       environment->xdf1.recs[left_end],
                       environment->xdf2.recs[right_end]
                   )) {
                left_end++;
                right_end++;
            }
            if (record_moved_range(
                    left_partners,
                    left_start,
                    right_start,
                    left_end - left_start
                ) != 0) {
                return -1;
            }
            cursor = left_end;
        }
    }
    return 0;
}

static int detect_moved_from_right(
    const xdfenv_t *environment,
    const xdchange_t *script,
    mmx_moved_table *table,
    int32_t *right_partners
) {
    const xdchange_t *change;

    if (environment->xdf2.nrec != 0 && right_partners == NULL) {
        return -1;
    }

    for (change = script; change != NULL; change = change->next) {
        long cursor = change->i2;
        const long end = change->i2 + change->chg2;

        while (cursor < end) {
            mmx_moved_group *seed_group = NULL;
            long right_seed;
            long left_seed;
            long left_start;
            long right_start;
            long left_end;
            long right_end;

            for (right_seed = cursor; right_seed < end; right_seed++) {
                seed_group = find_moved_group(
                    table,
                    environment->xdf2.recs[right_seed],
                    0
                );
                if (moved_group_is_unique(seed_group)) {
                    break;
                }
            }
            if (right_seed == end) {
                break;
            }
            left_seed = seed_group->left_line;
            left_start = left_seed;
            right_start = right_seed;
            while (right_start > cursor && changed_line(&environment->xdf1, left_start - 1) &&
                   records_share_moved_group(
                       table,
                       environment->xdf1.recs[left_start - 1],
                       environment->xdf2.recs[right_start - 1]
                   )) {
                left_start--;
                right_start--;
            }
            left_end = left_seed + 1;
            right_end = right_seed + 1;
            while (right_end < end && changed_line(&environment->xdf1, left_end) &&
                   records_share_moved_group(
                       table,
                       environment->xdf1.recs[left_end],
                       environment->xdf2.recs[right_end]
                   )) {
                left_end++;
                right_end++;
            }
            if (record_moved_range(
                    right_partners,
                    right_start,
                    left_start,
                    left_end - left_start
                ) != 0) {
                return -1;
            }
            cursor = right_end;
        }
    }
    return 0;
}

static int detect_moved_lines(
    const xdfenv_t *environment,
    const xdchange_t *script,
    long flags,
    mmx_moved_result *result
) {
    const xdchange_t *change;
    size_t altered_count = 0;
    size_t capacity = 1;
    size_t left_moved_count = 0;
    size_t right_moved_count = 0;
    size_t output_index = 0;
    mmx_moved_table table = {0};
    int32_t *left_partners = NULL;
    int32_t *right_partners = NULL;
    long line;

    for (change = script; change != NULL; change = change->next) {
        if ((size_t)change->chg1 > SIZE_MAX - altered_count) {
            return -1;
        }
        altered_count += (size_t)change->chg1;
        if ((size_t)change->chg2 > SIZE_MAX - altered_count) {
            return -1;
        }
        altered_count += (size_t)change->chg2;
    }
    if (altered_count == 0) {
        return 0;
    }
    if (altered_count > SIZE_MAX / 2) {
        return -1;
    }
    while (capacity < altered_count * 2) {
        if (capacity > SIZE_MAX / 2) {
            return -1;
        }
        capacity <<= 1;
    }
    if (capacity > SIZE_MAX / sizeof(*table.slots) ||
        altered_count > SIZE_MAX / sizeof(*table.groups) ||
        (size_t)environment->xdf1.nrec > SIZE_MAX / sizeof(*left_partners) ||
        (size_t)environment->xdf2.nrec > SIZE_MAX / sizeof(*right_partners)) {
        return -1;
    }
    table.slots = mmx_allocator_calloc(capacity, sizeof(*table.slots));
    table.groups = mmx_allocator_calloc(altered_count, sizeof(*table.groups));
    table.capacity = capacity;
    table.group_capacity = altered_count;
    table.flags = flags;
    if (table.slots == NULL || table.groups == NULL) {
        mmx_allocator_free(table.groups);
        mmx_allocator_free(table.slots);
        return -1;
    }
    if (environment->xdf1.nrec != 0) {
        left_partners = mmx_allocator_malloc((size_t)environment->xdf1.nrec * sizeof(*left_partners));
        if (left_partners == NULL) {
            goto failure;
        }
        for (line = 0; line < environment->xdf1.nrec; line++) {
            left_partners[line] = -1;
        }
    }
    if (environment->xdf2.nrec != 0) {
        right_partners = mmx_allocator_malloc((size_t)environment->xdf2.nrec * sizeof(*right_partners));
        if (right_partners == NULL) {
            goto failure;
        }
        for (line = 0; line < environment->xdf2.nrec; line++) {
            right_partners[line] = -1;
        }
    }

    for (change = script; change != NULL; change = change->next) {
        for (line = change->i1; line < change->i1 + change->chg1; line++) {
            if (add_moved_group_line(
                    &table,
                    environment->xdf1.recs[line],
                    line,
                    0
                ) != 0) {
                goto failure;
            }
        }
        for (line = change->i2; line < change->i2 + change->chg2; line++) {
            if (add_moved_group_line(
                    &table,
                    environment->xdf2.recs[line],
                    line,
                    1
                ) != 0) {
                goto failure;
            }
        }
    }

    if (detect_moved_from_left(environment, script, &table, left_partners) != 0 ||
        detect_moved_from_right(environment, script, &table, right_partners) != 0) {
        goto failure;
    }
    for (line = 0; line < environment->xdf1.nrec; line++) {
        if (left_partners[line] >= 0) {
            left_moved_count++;
        }
    }
    for (line = 0; line < environment->xdf2.nrec; line++) {
        if (right_partners[line] >= 0) {
            right_moved_count++;
        }
    }
    if (left_moved_count > SIZE_MAX / sizeof(*result->left_to_right) ||
        right_moved_count > SIZE_MAX / sizeof(*result->right_to_left)) {
        goto failure;
    }
    if (left_moved_count != 0) {
        result->left_to_right = mmx_allocator_malloc(
            left_moved_count * sizeof(*result->left_to_right)
        );
        if (result->left_to_right == NULL) {
            goto failure;
        }
    }
    if (right_moved_count != 0) {
        result->right_to_left = mmx_allocator_malloc(
            right_moved_count * sizeof(*result->right_to_left)
        );
        if (result->right_to_left == NULL) {
            goto failure;
        }
    }
    for (line = 0; line < environment->xdf1.nrec; line++) {
        if (left_partners[line] >= 0) {
            result->left_to_right[output_index].left_line = (int32_t)line;
            result->left_to_right[output_index].right_line = left_partners[line];
            output_index++;
        }
    }
    result->left_to_right_count = left_moved_count;
    output_index = 0;
    for (line = 0; line < environment->xdf2.nrec; line++) {
        if (right_partners[line] >= 0) {
            result->right_to_left[output_index].left_line = right_partners[line];
            result->right_to_left[output_index].right_line = (int32_t)line;
            output_index++;
        }
    }
    result->right_to_left_count = right_moved_count;
    mmx_allocator_free(right_partners);
    mmx_allocator_free(left_partners);
    mmx_allocator_free(table.groups);
    mmx_allocator_free(table.slots);
    return 0;

failure:
    mmx_allocator_free(result->right_to_left);
    mmx_allocator_free(result->left_to_right);
    result->left_to_right = NULL;
    result->left_to_right_count = 0;
    result->right_to_left = NULL;
    result->right_to_left_count = 0;
    mmx_allocator_free(right_partners);
    mmx_allocator_free(left_partners);
    mmx_allocator_free(table.groups);
    mmx_allocator_free(table.slots);
    return -1;
}

static int32_t mmx_diff_internal(
    const void *left,
    size_t left_size,
    const void *right,
    size_t right_size,
    uint64_t flags,
    mmx_diff_result *result,
    mmx_moved_result *moved
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

    if (result == NULL || result->hunks != NULL || result->count != 0 ||
        (moved != NULL &&
         (moved->left_to_right != NULL || moved->left_to_right_count != 0 ||
          moved->right_to_left != NULL || moved->right_to_left_count != 0))) {
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

    if (moved != NULL && detect_moved_lines(&environment, script, (long)parameters.flags, moved) != 0) {
        xdl_free_script(script);
        xdl_free_env(&environment);
        return -3;
    }

    for (change = script; change != NULL; change = change->next) {
        if (count == SIZE_MAX) {
            if (moved != NULL) {
                mmx_moved_result_free(moved);
            }
            xdl_free_script(script);
            xdl_free_env(&environment);
            return -3;
        }
        count++;
    }

    if (count > SIZE_MAX / sizeof(*result->hunks)) {
        if (moved != NULL) {
            mmx_moved_result_free(moved);
        }
        xdl_free_script(script);
        xdl_free_env(&environment);
        return -3;
    }

    if (count != 0) {
        result->hunks = mmx_allocator_calloc(count, sizeof(*result->hunks));
        if (result->hunks == NULL) {
            if (moved != NULL) {
                mmx_moved_result_free(moved);
            }
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

int32_t mmx_diff(
    const void *left,
    size_t left_size,
    const void *right,
    size_t right_size,
    uint64_t flags,
    mmx_diff_result *result
) {
    return mmx_diff_internal(left, left_size, right, right_size, flags, result, NULL);
}

int32_t mmx_diff_with_moves(
    const void *left,
    size_t left_size,
    const void *right,
    size_t right_size,
    uint64_t flags,
    mmx_diff_result *result,
    mmx_moved_result *moved
) {
    if (moved == NULL) {
        return -1;
    }
    return mmx_diff_internal(left, left_size, right, right_size, flags, result, moved);
}

void mmx_diff_result_free(mmx_diff_result *result) {
    if (result == NULL) {
        return;
    }
    mmx_allocator_free(result->hunks);
    result->hunks = NULL;
    result->count = 0;
}

void mmx_moved_result_free(mmx_moved_result *result) {
    if (result == NULL) {
        return;
    }
    mmx_allocator_free(result->right_to_left);
    mmx_allocator_free(result->left_to_right);
    result->left_to_right = NULL;
    result->left_to_right_count = 0;
    result->right_to_left = NULL;
    result->right_to_left_count = 0;
}
