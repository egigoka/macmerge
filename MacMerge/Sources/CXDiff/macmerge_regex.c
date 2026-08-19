#define PCRE2_CODE_UNIT_WIDTH 8
#include "macmerge_xdiff.h"
#include "../../../Externals/poco/dependencies/pcre2/src/pcre2.h"

#include <stdlib.h>
#include <string.h>

enum {
    MMX_REGEX_COMPILE_ERROR = 1,
    MMX_REGEX_MATCH_ERROR = 2,
    MMX_REGEX_ALLOCATION_ERROR = 3,
    MMX_REGEX_OUTPUT_TOO_LARGE = 4,
    MMX_REGEX_SKIP_RULE = 5,
    MMX_REGEX_MATCH_LIMIT = 1000000,
    MMX_REGEX_DEPTH_LIMIT = 1000,
    MMX_REGEX_HEAP_LIMIT = 65536
};

typedef struct mmx_line_filter {
    pcre2_code *code;
    pcre2_match_context *match_context;
} mmx_line_filter;

static int configure_match_limits(pcre2_match_context *context) {
    if (pcre2_set_match_limit(context, MMX_REGEX_MATCH_LIMIT) != 0 ||
        pcre2_set_depth_limit(context, MMX_REGEX_DEPTH_LIMIT) != 0 ||
        pcre2_set_heap_limit(context, MMX_REGEX_HEAP_LIMIT) != 0) {
        return MMX_REGEX_MATCH_ERROR;
    }
    return 0;
}

static int append_bytes(
    uint8_t **output,
    size_t *size,
    size_t *capacity,
    const uint8_t *bytes,
    size_t count,
    size_t maximum_size
) {
    size_t required;
    size_t grown;
    uint8_t *resized;

    if (count > maximum_size - *size) {
        return MMX_REGEX_OUTPUT_TOO_LARGE;
    }
    required = *size + count;
    if (required <= *capacity) {
        if (count > 0) memcpy(*output + *size, bytes, count);
        *size = required;
        return 0;
    }
    grown = *capacity == 0 ? 256 : *capacity;
    while (grown < required) {
        size_t next = grown > maximum_size / 2 ? maximum_size : grown * 2;
        if (next <= grown) {
            grown = required;
            break;
        }
        grown = next;
    }
    resized = (uint8_t *)realloc(*output, grown);
    if (resized == NULL) return MMX_REGEX_ALLOCATION_ERROR;
    *output = resized;
    *capacity = grown;
    if (count > 0) memcpy(*output + *size, bytes, count);
    *size = required;
    return 0;
}

static int append_replacement(
    uint8_t **output,
    size_t *size,
    size_t *capacity,
    const uint8_t *subject,
    const PCRE2_SIZE *ovector,
    int capture_count,
    const uint8_t *replacement,
    size_t replacement_size,
    size_t maximum_size
) {
    size_t index = 0;
    while (index < replacement_size) {
        if (replacement[index] == '$') {
            if (++index == replacement_size) {
                return append_bytes(output, size, capacity, (const uint8_t *)"$", 1, maximum_size);
            }
            if (replacement[index] >= '0' && replacement[index] <= '9') {
                int capture = replacement[index] - '0';
                if (capture < capture_count) {
                    if (ovector[capture * 2] == PCRE2_UNSET) return MMX_REGEX_SKIP_RULE;
                    PCRE2_SIZE start = ovector[capture * 2];
                    PCRE2_SIZE end = ovector[capture * 2 + 1];
                    int status = append_bytes(output, size, capacity, subject + start, end - start, maximum_size);
                    if (status != 0) return status;
                }
                index++;
                continue;
            }
            {
                int status = append_bytes(output, size, capacity, (const uint8_t *)"$", 1, maximum_size);
                if (status != 0) return status;
            }
        }
        {
            int status = append_bytes(output, size, capacity, replacement + index, 1, maximum_size);
            if (status != 0) return status;
        }
        index++;
    }
    return 0;
}

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
) {
    const uint8_t *pattern_bytes = (const uint8_t *)pattern;
    const uint8_t *replacement_bytes = (const uint8_t *)replacement;
    uint8_t *current = NULL;
    size_t current_size = 0;
    size_t current_capacity = 0;
    size_t offset = 0;
    int error_code = 0;
    PCRE2_SIZE error_offset = 0;
    pcre2_code *code;
    pcre2_match_data *match_data;
    pcre2_compile_context *compile_context;
    pcre2_match_context *match_context;
    uint32_t options = PCRE2_MULTILINE | (case_sensitive ? 0 : PCRE2_CASELESS);
    int status;

    if (result == NULL || result->bytes != NULL || result->size != 0) return MMX_REGEX_MATCH_ERROR;
    if ((subject == NULL && subject_size != 0) || (pattern == NULL && pattern_size != 0) ||
        (replacement == NULL && replacement_size != 0)) return MMX_REGEX_MATCH_ERROR;
    if (subject_size > maximum_size) return MMX_REGEX_OUTPUT_TOO_LARGE;
    compile_context = pcre2_compile_context_create(NULL);
    if (compile_context == NULL) return MMX_REGEX_ALLOCATION_ERROR;
    if (pcre2_set_newline(compile_context, PCRE2_NEWLINE_ANYCRLF) != 0) {
        pcre2_compile_context_free(compile_context);
        return MMX_REGEX_COMPILE_ERROR;
    }
    code = pcre2_compile(pattern_bytes, pattern_size, options, &error_code, &error_offset, compile_context);
    pcre2_compile_context_free(compile_context);
    if (code == NULL) return MMX_REGEX_COMPILE_ERROR;
    match_data = pcre2_match_data_create_from_pattern(code, NULL);
    if (match_data == NULL) {
        pcre2_code_free(code);
        return MMX_REGEX_ALLOCATION_ERROR;
    }
    match_context = pcre2_match_context_create(NULL);
    if (match_context == NULL) {
        pcre2_match_data_free(match_data);
        pcre2_code_free(code);
        return MMX_REGEX_ALLOCATION_ERROR;
    }
    status = configure_match_limits(match_context);
    if (status != 0) goto cleanup;
    status = append_bytes(
        &current,
        &current_size,
        &current_capacity,
        (const uint8_t *)subject,
        subject_size,
        maximum_size
    );
    if (status != 0) goto cleanup;

    while (offset < current_size) {
        static const uint8_t empty_subject = 0;
        const uint8_t *match_subject = current_size == 0 ? &empty_subject : current;
        int matches = pcre2_match(code, match_subject, current_size, offset, 0, match_data, match_context);
        const PCRE2_SIZE *ovector;
        uint8_t *next = NULL;
        size_t next_size = 0;
        size_t next_capacity = 0;
        size_t resume;

        if (matches == PCRE2_ERROR_NOMATCH) break;
        if (matches <= 0) {
            status = MMX_REGEX_MATCH_ERROR;
            break;
        }
        ovector = pcre2_get_ovector_pointer(match_data);
        if (ovector[0] >= current_size) break;
        status = append_bytes(&next, &next_size, &next_capacity, current, ovector[0], maximum_size);
        if (status == 0) {
            status = append_replacement(
                &next,
                &next_size,
                &next_capacity,
                current,
                ovector,
                matches,
                replacement_bytes,
                replacement_size,
                maximum_size
            );
        }
        if (status == MMX_REGEX_SKIP_RULE) {
            free(next);
            status = 0;
            break;
        }
        resume = next_size;
        if (status == 0) {
            PCRE2_SIZE tail = ovector[1] > ovector[0] ? ovector[1] : ovector[1] + 1;
            if (tail < current_size) {
                status = append_bytes(
                    &next,
                    &next_size,
                    &next_capacity,
                    current + tail,
                    current_size - tail,
                    maximum_size
                );
            }
        }
        if (status != 0) {
            free(next);
            break;
        }
        free(current);
        current = next;
        current_size = next_size;
        current_capacity = next_capacity;
        offset = resume;
    }

cleanup:
    pcre2_match_context_free(match_context);
    pcre2_match_data_free(match_data);
    pcre2_code_free(code);
    if (status != 0) {
        free(current);
        return status;
    }
    result->bytes = current;
    result->size = current_size;
    return 0;
}

int32_t mmx_line_filter_create(
    const void *pattern,
    size_t pattern_size,
    int32_t case_sensitive,
    void **result
) {
    static const uint8_t empty_pattern = 0;
    const uint8_t *pattern_bytes = pattern_size == 0
        ? &empty_pattern
        : (const uint8_t *)pattern;
    mmx_line_filter *filter;
    pcre2_compile_context *compile_context;
    int error_code = 0;
    PCRE2_SIZE error_offset = 0;
    uint32_t options = PCRE2_UTF | PCRE2_UCP | PCRE2_MULTILINE |
        (case_sensitive ? 0 : PCRE2_CASELESS);

    if (result == NULL || *result != NULL || (pattern == NULL && pattern_size != 0)) {
        return MMX_REGEX_COMPILE_ERROR;
    }
    filter = (mmx_line_filter *)malloc(sizeof(*filter));
    if (filter == NULL) return MMX_REGEX_ALLOCATION_ERROR;
    filter->code = NULL;
    filter->match_context = NULL;

    compile_context = pcre2_compile_context_create(NULL);
    if (compile_context == NULL) {
        mmx_line_filter_free(filter);
        return MMX_REGEX_ALLOCATION_ERROR;
    }
    if (pcre2_set_newline(compile_context, PCRE2_NEWLINE_ANYCRLF) != 0) {
        pcre2_compile_context_free(compile_context);
        mmx_line_filter_free(filter);
        return MMX_REGEX_COMPILE_ERROR;
    }
    filter->code = pcre2_compile(
        pattern_bytes,
        pattern_size,
        options,
        &error_code,
        &error_offset,
        compile_context
    );
    pcre2_compile_context_free(compile_context);
    if (filter->code == NULL) {
        mmx_line_filter_free(filter);
        return MMX_REGEX_COMPILE_ERROR;
    }
    filter->match_context = pcre2_match_context_create(NULL);
    if (filter->match_context == NULL) {
        mmx_line_filter_free(filter);
        return MMX_REGEX_ALLOCATION_ERROR;
    }
    if (configure_match_limits(filter->match_context) != 0) {
        mmx_line_filter_free(filter);
        return MMX_REGEX_MATCH_ERROR;
    }
    *result = filter;
    return 0;
}

int32_t mmx_line_filter_matches(
    const void *opaque_filter,
    const void *subject,
    size_t subject_size,
    int32_t *matches
) {
    static const uint8_t empty_subject = 0;
    const mmx_line_filter *filter = (const mmx_line_filter *)opaque_filter;
    const uint8_t *subject_bytes = subject_size == 0
        ? &empty_subject
        : (const uint8_t *)subject;
    pcre2_match_data *match_data;
    int status;

    if (filter == NULL || matches == NULL || (subject == NULL && subject_size != 0)) {
        return MMX_REGEX_MATCH_ERROR;
    }
    *matches = 0;
    match_data = pcre2_match_data_create(1, NULL);
    if (match_data == NULL) return MMX_REGEX_ALLOCATION_ERROR;
    status = pcre2_match(
        filter->code,
        subject_bytes,
        subject_size,
        0,
        0,
        match_data,
        filter->match_context
    );
    pcre2_match_data_free(match_data);
    if (status == PCRE2_ERROR_NOMATCH) return 0;
    if (status < 0) return MMX_REGEX_MATCH_ERROR;
    *matches = 1;
    return 0;
}

void mmx_line_filter_free(void *opaque_filter) {
    mmx_line_filter *filter = (mmx_line_filter *)opaque_filter;
    if (filter == NULL) return;
    pcre2_match_context_free(filter->match_context);
    pcre2_code_free(filter->code);
    free(filter);
}

void mmx_bytes_result_free(mmx_bytes_result *result) {
    if (result == NULL) return;
    free(result->bytes);
    result->bytes = NULL;
    result->size = 0;
}
