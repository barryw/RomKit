//
//  lib7z_wrapper.c
//  RomKit
//
//  C wrapper for 7z library
//

#include "lib7z_wrapper.h"
#include "7z.h"
#include "7zAlloc.h"
#include "7zBuf.h"
#include "7zCrc.h"
#include "7zFile.h"
#include "7zVersion.h"
#include "LzmaDec.h"
#include "Lzma2Dec.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Allocator callbacks - use the ones from 7zAlloc.h
static ISzAlloc g_Alloc = { SzAlloc, SzFree };

// Initialize CRC table
static int g_CrcTableInitialized = 0;

// Archive handle structure
typedef struct {
    CSzArEx db;
    CFileInStream archiveStream;
    CLookToRead2 lookStream;
    ISzAlloc allocImp;
    ISzAlloc allocTempImp;
    UInt16 *temp;
    size_t tempSize;
} SevenZipArchiveImpl;

// Initialize lib7z with thread safety
int lib7z_init(void) {
    static int initialized = 0;
    if (!initialized) {
        // Initialize CRC tables once
        CrcGenerateTable();
        initialized = 1;
        g_CrcTableInitialized = 1;
    }
    return 1;
}

void lib7z_cleanup(void) {
    // Nothing to cleanup globally
}

// Open archive
lib7z_archive_t* lib7z_open_archive(const char *path) {
    if (!path) return NULL;
    
    if (!g_CrcTableInitialized) {
        lib7z_init();
    }
    
    SevenZipArchiveImpl *archive = (SevenZipArchiveImpl*)calloc(1, sizeof(SevenZipArchiveImpl));
    if (!archive) return NULL;
    
    archive->allocImp = g_Alloc;
    archive->allocTempImp = g_Alloc;
    
    // Open file
    if (InFile_Open(&archive->archiveStream.file, path) != 0) {
        free(archive);
        return NULL;
    }
    
    // Setup stream
    FileInStream_CreateVTable(&archive->archiveStream);
    LookToRead2_CreateVTable(&archive->lookStream, False);
    
    // Allocate buffer for LookToRead2
    size_t bufferSize = 1 << 16; // 64KB buffer
    archive->lookStream.buf = (Byte*)ISzAlloc_Alloc(&archive->allocImp, bufferSize);
    if (!archive->lookStream.buf) {
        File_Close(&archive->archiveStream.file);
        free(archive);
        return NULL;
    }
    archive->lookStream.bufSize = bufferSize;
    archive->lookStream.realStream = &archive->archiveStream.vt;
    LookToRead2_Init(&archive->lookStream);
    
    // Initialize database
    SzArEx_Init(&archive->db);
    
    // Open archive
    SRes res = SzArEx_Open(&archive->db, &archive->lookStream.vt, 
                           &archive->allocImp, &archive->allocTempImp);
    
    if (res != SZ_OK) {
        File_Close(&archive->archiveStream.file);
        SzArEx_Free(&archive->db, &archive->allocImp);
        free(archive);
        return NULL;
    }
    
    // Allocate temp buffer for file names
    archive->tempSize = 4096;
    archive->temp = (UInt16*)malloc(archive->tempSize * sizeof(UInt16));
    
    return (lib7z_archive_t*)archive;
}

// Close archive
void lib7z_close_archive(lib7z_archive_t *archive) {
    if (!archive) return;
    
    SevenZipArchiveImpl *impl = (SevenZipArchiveImpl*)archive;
    
    IAlloc_Free(&impl->allocImp, impl->lookStream.buf);
    SzArEx_Free(&impl->db, &impl->allocImp);
    File_Close(&impl->archiveStream.file);
    free(impl->temp);
    free(impl);
}

// Get number of entries
size_t lib7z_get_num_entries(lib7z_archive_t *archive) {
    if (!archive) return 0;
    SevenZipArchiveImpl *impl = (SevenZipArchiveImpl*)archive;
    return impl->db.NumFiles;
}

// Get entry info
int lib7z_get_entry_info(lib7z_archive_t *archive, size_t index, lib7z_entry_t *entry) {
    if (!archive || !entry) return 0;
    
    SevenZipArchiveImpl *impl = (SevenZipArchiveImpl*)archive;
    
    if (index >= impl->db.NumFiles) return 0;
    
    // Clear entry
    memset(entry, 0, sizeof(lib7z_entry_t));
    entry->index = index;
    
    // Get file name
    size_t len = SzArEx_GetFileNameUtf16(&impl->db, index, NULL);
    if (len > impl->tempSize) {
        free(impl->temp);
        impl->tempSize = len;
        impl->temp = (UInt16*)malloc(impl->tempSize * sizeof(UInt16));
    }
    
    SzArEx_GetFileNameUtf16(&impl->db, index, impl->temp);
    
    // Convert UTF-16 to UTF-8 (simplified - assumes ASCII)
    for (size_t i = 0; i < len && i < sizeof(entry->path) - 1; i++) {
        entry->path[i] = (char)impl->temp[i];
    }
    
    // Get file info
    entry->is_directory = SzArEx_IsDir(&impl->db, index);
    
    if (!entry->is_directory) {
        entry->size = SzArEx_GetFileSize(&impl->db, index);
        
        // Get CRC if available
        // Get CRC if available
        if (SzBitArray_Check(impl->db.CRCs.Defs, index)) {
            entry->crc32 = impl->db.CRCs.Vals[index];
            entry->has_crc32 = 1;
        }
        
        // Get modification time if available
        // Get modification time if available
        if (SzBitArray_Check(impl->db.MTime.Defs, index)) {
            // Convert from Windows FILETIME to Unix timestamp
            CNtfsFileTime fileTime = impl->db.MTime.Vals[index];
            UInt64 winTime = fileTime.Low | ((UInt64)fileTime.High << 32);
            entry->mtime = (winTime / 10000000ULL) - 11644473600ULL;
            entry->has_mtime = 1;
        }
    }
    
    return 1;
}

// Extract file to memory
lib7z_extract_result_t lib7z_extract_to_memory(lib7z_archive_t *archive, size_t index) {
    lib7z_extract_result_t result = {NULL, 0, 0};
    
    if (!archive) return result;
    
    SevenZipArchiveImpl *impl = (SevenZipArchiveImpl*)archive;
    
    if (index >= impl->db.NumFiles) return result;
    
    // Skip directories
    if (SzArEx_IsDir(&impl->db, index)) return result;
    
    // Prepare for extraction
    UInt32 blockIndex = 0xFFFFFFFF;
    size_t offset = 0;
    size_t outSizeProcessed = 0;
    Byte *outBuffer = NULL;
    size_t outBufferSize = 0;
    
    SRes res = SzArEx_Extract(&impl->db, &impl->lookStream.vt, index,
                              &blockIndex, &outBuffer, &outBufferSize,
                              &offset, &outSizeProcessed,
                              &impl->allocImp, &impl->allocTempImp);
    
    if (res == SZ_OK) {
        // Copy data to result
        result.data = (uint8_t*)malloc(outSizeProcessed);
        if (result.data) {
            memcpy(result.data, outBuffer + offset, outSizeProcessed);
            result.size = outSizeProcessed;
            result.success = 1;
        }
    }
    
    // Free temp buffer
    IAlloc_Free(&impl->allocImp, outBuffer);
    
    return result;
}

// Free extract result
void lib7z_free_extract_result(lib7z_extract_result_t *result) {
    if (result && result->data) {
        free(result->data);
        result->data = NULL;
        result->size = 0;
        result->success = 0;
    }
}

// Check if file is valid 7z
int lib7z_is_valid_archive(const char *path) {
    if (!path) return 0;
    
    FILE *file = fopen(path, "rb");
    if (!file) return 0;
    
    unsigned char sig[6];
    size_t read = fread(sig, 1, 6, file);
    fclose(file);
    
    if (read != 6) return 0;
    
    // Check 7z signature
    return sig[0] == '7' && sig[1] == 'z' &&
           sig[2] == 0xBC && sig[3] == 0xAF &&
           sig[4] == 0x27 && sig[5] == 0x1C;
}