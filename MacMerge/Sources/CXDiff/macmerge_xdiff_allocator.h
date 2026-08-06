#ifndef MACMERGE_XDIFF_ALLOCATOR_H
#define MACMERGE_XDIFF_ALLOCATOR_H

#include <stddef.h>

void *mmx_allocator_malloc(size_t size);
void *mmx_allocator_calloc(size_t count, size_t size);
void *mmx_allocator_realloc(void *pointer, size_t size);
void mmx_allocator_free(void *pointer);

#define xdl_malloc(size) mmx_allocator_malloc(size)
#define xdl_realloc(pointer, size) mmx_allocator_realloc(pointer, size)
#define xdl_free(pointer) mmx_allocator_free(pointer)

#endif
