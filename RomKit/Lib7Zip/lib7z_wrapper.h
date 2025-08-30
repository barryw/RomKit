//
//  lib7z_wrapper.h
//  RomKit
//
//  C wrapper for 7z library
//

#ifndef LIB7Z_WRAPPER_H
#define LIB7Z_WRAPPER_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opaque archive handle
typedef void lib7z_archive_t;

// Entry information
typedef struct {
    char path[1024];
    size_t index;
    uint64_t size;
    uint32_t crc32;
    uint64_t mtime;
    int is_directory;
    int has_crc32;
    int has_mtime;
} lib7z_entry_t;

// Extract result
typedef struct {
    uint8_t *data;
    size_t size;
    int success;
} lib7z_extract_result_t;

// Initialize lib7z (call once)
int lib7z_init(void);
void lib7z_cleanup(void);

// Archive operations
lib7z_archive_t* lib7z_open_archive(const char *path);
void lib7z_close_archive(lib7z_archive_t *archive);

// Entry operations
size_t lib7z_get_num_entries(lib7z_archive_t *archive);
int lib7z_get_entry_info(lib7z_archive_t *archive, size_t index, lib7z_entry_t *entry);

// Extraction
lib7z_extract_result_t lib7z_extract_to_memory(lib7z_archive_t *archive, size_t index);
void lib7z_free_extract_result(lib7z_extract_result_t *result);

// Validation
int lib7z_is_valid_archive(const char *path);

#ifdef __cplusplus
}
#endif

#endif /* LIB7Z_WRAPPER_H */