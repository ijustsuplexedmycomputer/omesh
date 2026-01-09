// =============================================================================
// Omesh - store.inc
// Storage layer constants and structure definitions
// =============================================================================

// -----------------------------------------------------------------------------
// Document Record Header (28 bytes)
// Used in docs.dat append-only log
// -----------------------------------------------------------------------------

.equ DOC_MAGIC,             0x00434F44  // "DOC\0" little-endian
.equ DOC_HDR_SIZE,          28

.equ DOC_OFF_MAGIC,         0           // 4 bytes - magic number
.equ DOC_OFF_LENGTH,        4           // 4 bytes - total record length
.equ DOC_OFF_ID,            8           // 8 bytes - document ID
.equ DOC_OFF_TIMESTAMP,     16          // 4 bytes - unix timestamp
.equ DOC_OFF_FLAGS,         20          // 4 bytes - flags (deleted, etc.)
.equ DOC_OFF_CHECKSUM,      24          // 4 bytes - CRC32 of content
.equ DOC_OFF_CONTENT,       28          // N bytes - document content

// Document flags
.equ DOC_FLAG_DELETED,      0x01        // Document has been deleted
.equ DOC_FLAG_COMPRESSED,   0x02        // Content is LZ4 compressed

// -----------------------------------------------------------------------------
// Document Index Entry (16 bytes)
// Used in docs.idx sorted array
// -----------------------------------------------------------------------------

.equ IDX_MAGIC,             0x58444944  // "DIDX" little-endian
.equ IDX_VERSION,           1
.equ IDX_HDR_SIZE,          16
.equ IDX_ENTRY_SIZE,        16

// Index header offsets
.equ IDX_HDR_MAGIC,         0           // 4 bytes
.equ IDX_HDR_VERSION,       4           // 4 bytes
.equ IDX_HDR_COUNT,         8           // 8 bytes - entry count

// Index entry offsets
.equ IDX_OFF_DOC_ID,        0           // 8 bytes - document ID
.equ IDX_OFF_FILE_OFFSET,   8           // 8 bytes - offset in docs.dat

// Special values
.equ IDX_OFFSET_DELETED,    -1          // Entry has been deleted

// -----------------------------------------------------------------------------
// Write-Ahead Log Entry Header (24 bytes)
// -----------------------------------------------------------------------------

.equ WAL_MAGIC,             0x004C4157  // "WAL\0" little-endian
.equ WAL_HDR_SIZE,          24

.equ WAL_OFF_MAGIC,         0           // 4 bytes
.equ WAL_OFF_LENGTH,        4           // 4 bytes - total entry length
.equ WAL_OFF_SEQ,           8           // 8 bytes - sequence number
.equ WAL_OFF_OP,            16          // 4 bytes - operation type
.equ WAL_OFF_CHECKSUM,      20          // 4 bytes - CRC32
.equ WAL_OFF_DATA,          24          // N bytes - operation data

// WAL operation types
.equ WAL_OP_PUT,            1           // Store document
.equ WAL_OP_DELETE,         2           // Delete document
.equ WAL_OP_COMMIT,         3           // Commit marker

// -----------------------------------------------------------------------------
// Document Store State Structure (48 bytes)
// Global state for document storage
// -----------------------------------------------------------------------------

.equ DOCSTORE_OFF_FD,           0       // 8 bytes - file descriptor
.equ DOCSTORE_OFF_WRITE_POS,    8       // 8 bytes - current write position
.equ DOCSTORE_OFF_FILE_SIZE,    16      // 8 bytes - total file size
.equ DOCSTORE_OFF_MMAP_BASE,    24      // 8 bytes - mmap base address
.equ DOCSTORE_OFF_MMAP_SIZE,    32      // 8 bytes - mmap size
.equ DOCSTORE_OFF_NEXT_ID,      40      // 8 bytes - next document ID
.equ DOCSTORE_SIZE,             48

// -----------------------------------------------------------------------------
// Document Index State Structure (64 bytes)
// Global state for document index
// -----------------------------------------------------------------------------

.equ DOCIDX_OFF_FD,             0       // 8 bytes - file descriptor
.equ DOCIDX_OFF_MMAP_BASE,      8       // 8 bytes - mmap base address
.equ DOCIDX_OFF_MMAP_SIZE,      16      // 8 bytes - mmap size
.equ DOCIDX_OFF_COUNT,          24      // 8 bytes - entry count
.equ DOCIDX_OFF_CAPACITY,       32      // 8 bytes - allocated capacity
.equ DOCIDX_OFF_DIRTY,          40      // 8 bytes - dirty flag
.equ DOCIDX_OFF_BUF_PTR,        48      // 8 bytes - buffer pointer
.equ DOCIDX_OFF_BUF_COUNT,      56      // 8 bytes - buffer count
.equ DOCIDX_SIZE,               64

// Index buffer settings
.equ IDX_BUFFER_CAPACITY,       256     // Entries before merge

// -----------------------------------------------------------------------------
// WAL State Structure (48 bytes)
// Global state for write-ahead log
// -----------------------------------------------------------------------------

.equ WAL_STATE_OFF_FD,          0       // 8 bytes - current WAL file fd
.equ WAL_STATE_OFF_SEQ,         8       // 8 bytes - sequence number
.equ WAL_STATE_OFF_DIR_FD,      16      // 8 bytes - WAL directory fd
.equ WAL_STATE_OFF_SYNC_INT,    24      // 8 bytes - sync interval (ns)
.equ WAL_STATE_OFF_LAST_SYNC,   32      // 8 bytes - last sync time
.equ WAL_STATE_OFF_SIZE,        40      // 8 bytes - current file size
.equ WAL_STATE_SIZE,            48

// WAL sync interval (1 second in nanoseconds)
.equ WAL_SYNC_INTERVAL,         1000000000

// -----------------------------------------------------------------------------
// File Limits and Defaults
// -----------------------------------------------------------------------------

.equ DOC_MAX_SIZE,              (16 << 20)  // 16 MB max document
.equ IDX_INITIAL_CAPACITY,      1024        // Initial index entries
.equ WAL_MAX_SIZE,              (64 << 20)  // 64 MB WAL before rotate
.equ MMAP_CHUNK_SIZE,           (4 << 20)   // 4 MB mmap growth

// -----------------------------------------------------------------------------
// CRC32 Constants
// Using IEEE 802.3 polynomial (same as Ethernet, gzip, etc.)
// -----------------------------------------------------------------------------

.equ CRC32_INIT,            0xFFFFFFFF
.equ CRC32_POLY,            0xEDB88320  // Reflected polynomial

// -----------------------------------------------------------------------------
// Feature bit for CRC32 hardware (from features.s)
// -----------------------------------------------------------------------------

.equ FEAT_BIT_CRC32,        1
.equ FEAT_OFF_FLAGS,        72

// =============================================================================
// End of store.inc
// =============================================================================
