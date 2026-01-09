// =============================================================================
// Omesh - Full-Text Search Index Constants and Structures
// =============================================================================
//
// This file defines constants for the full-text search indexing system:
// - Term dictionary format
// - Posting list format
// - Query structures
// - UTF-8 handling constants
//
// =============================================================================

#ifndef INDEX_INC
#define INDEX_INC

// =============================================================================
// Magic Numbers and Version
// =============================================================================

.equ FTS_TERM_MAGIC,        0x4D524554  // "TERM" - term dictionary file
.equ FTS_POST_MAGIC,        0x54534F50  // "POST" - posting list file
.equ FTS_META_MAGIC,        0x4154454D  // "META" - metadata file
.equ FTS_VERSION,           1

// =============================================================================
// Term Dictionary File Format (terms.fts)
// =============================================================================
//
// Header (32 bytes):
//   +0   [4] magic         FTS_TERM_MAGIC
//   +4   [4] version       FTS_VERSION
//   +8   [8] term_count    Number of unique terms
//   +16  [8] total_post    Total posting entries
//   +24  [4] checksum      CRC32 of file
//   +28  [4] reserved      Padding
//
// Entries follow header (variable length, 8-byte aligned)

.equ FTS_TERM_HDR_SIZE,         32

.equ FTS_TERM_HDR_MAGIC,        0
.equ FTS_TERM_HDR_VERSION,      4
.equ FTS_TERM_HDR_COUNT,        8
.equ FTS_TERM_HDR_TOTAL_POST,   16
.equ FTS_TERM_HDR_CHECKSUM,     24
.equ FTS_TERM_HDR_RESERVED,     28

// =============================================================================
// Term Entry Format (variable length)
// =============================================================================
//
// Fixed portion (24 bytes):
//   +0   [4] term_hash     CRC32 hash of normalized term
//   +4   [2] term_len      Length of term string (1-255)
//   +6   [2] flags         Term flags
//   +8   [8] post_offset   Offset into postings file
//   +16  [4] doc_freq      Documents containing this term
//   +20  [4] total_freq    Total occurrences across all docs
//
// Variable portion:
//   +24  [N] term_data     UTF-8 term bytes (padded to 8-byte boundary)

.equ FTS_TERM_ENTRY_FIXED,      24

.equ FTS_TERM_OFF_HASH,         0
.equ FTS_TERM_OFF_LEN,          4
.equ FTS_TERM_OFF_FLAGS,        6
.equ FTS_TERM_OFF_POST_OFFSET,  8
.equ FTS_TERM_OFF_DOC_FREQ,     16
.equ FTS_TERM_OFF_TOTAL_FREQ,   20
.equ FTS_TERM_OFF_DATA,         24

// Term flags
.equ FTS_TERM_FLAG_STOPWORD,    0x0001
.equ FTS_TERM_FLAG_NUMERIC,     0x0002
.equ FTS_TERM_FLAG_PUNCT,       0x0004

// =============================================================================
// Posting List File Format (postings.fts)
// =============================================================================
//
// File Header (24 bytes):
//   +0   [4] magic         FTS_POST_MAGIC
//   +4   [4] version       FTS_VERSION
//   +8   [8] entry_count   Total posting entries
//   +16  [4] checksum      CRC32 of file
//   +20  [4] reserved      Padding

.equ FTS_POST_HDR_SIZE,         24

.equ FTS_POST_HDR_MAGIC,        0
.equ FTS_POST_HDR_VERSION,      4
.equ FTS_POST_HDR_COUNT,        8
.equ FTS_POST_HDR_CHECKSUM,     16
.equ FTS_POST_HDR_RESERVED,     20

// =============================================================================
// Posting List (per term)
// =============================================================================
//
// List Header (16 bytes):
//   +0   [4] term_hash     CRC32 of term (verification)
//   +4   [4] entry_count   Number of doc entries in list
//   +8   [4] list_size     Total bytes of this list
//   +12  [4] flags         Compression flags, etc.

.equ FTS_POST_LIST_HDR_SIZE,    16

.equ FTS_POST_LIST_HASH,        0
.equ FTS_POST_LIST_COUNT,       4
.equ FTS_POST_LIST_SIZE,        8
.equ FTS_POST_LIST_FLAGS,       12

// =============================================================================
// Posting Entry (per document in list)
// =============================================================================
//
// Fixed portion (12 bytes):
//   +0   [8] doc_id        Document ID
//   +8   [2] term_freq     Occurrences of term in doc
//   +10  [2] pos_count     Number of positions stored
//
// Variable portion:
//   +12  [N] positions     Array of 4-byte position offsets

.equ FTS_POST_ENTRY_FIXED,      12

.equ FTS_POST_OFF_DOC_ID,       0
.equ FTS_POST_OFF_TERM_FREQ,    8
.equ FTS_POST_OFF_POS_COUNT,    10
.equ FTS_POST_OFF_POSITIONS,    12

// =============================================================================
// Metadata File Format (meta.fts)
// =============================================================================
//
// Header (64 bytes):
//   +0   [4] magic             FTS_META_MAGIC
//   +4   [4] version           FTS_VERSION
//   +8   [8] total_docs        Documents indexed
//   +16  [8] total_terms       Unique terms
//   +24  [8] total_tokens      Tokens processed
//   +32  [8] avg_doc_len       Average tokens/doc (16.16 fixed)
//   +40  [8] last_doc_id       Highest doc ID indexed
//   +48  [8] timestamp         Last index update (unix time)
//   +56  [4] checksum          CRC32
//   +60  [4] reserved          Padding

.equ FTS_META_SIZE,             64

.equ FTS_META_OFF_MAGIC,        0
.equ FTS_META_OFF_VERSION,      4
.equ FTS_META_OFF_TOTAL_DOCS,   8
.equ FTS_META_OFF_TOTAL_TERMS,  16
.equ FTS_META_OFF_TOTAL_TOKENS, 24
.equ FTS_META_OFF_AVG_DOC_LEN,  32
.equ FTS_META_OFF_LAST_DOC,     40
.equ FTS_META_OFF_TIMESTAMP,    48
.equ FTS_META_OFF_CHECKSUM,     56
.equ FTS_META_OFF_RESERVED,     60

// =============================================================================
// Query Result Entry (24 bytes)
// =============================================================================
//
//   +0   [8] doc_id        Document ID
//   +8   [8] score         TF-IDF score (24.8 fixed-point)
//   +16  [4] match_pos     First match position
//   +20  [4] match_count   Total matches

.equ FTS_RESULT_ENTRY_SIZE,     24

.equ FTS_RESULT_OFF_DOC_ID,     0
.equ FTS_RESULT_OFF_SCORE,      8
.equ FTS_RESULT_OFF_MATCH_POS,  16
.equ FTS_RESULT_OFF_MATCH_CNT,  20

// =============================================================================
// Query Types
// =============================================================================

.equ FTS_QUERY_TYPE_AND,        1   // All terms must match
.equ FTS_QUERY_TYPE_OR,         2   // Any term matches
.equ FTS_QUERY_TYPE_PHRASE,     3   // Exact phrase (position check)

// Query flags
.equ FTS_QUERY_FLAG_SORTED,     0x01    // Results sorted by score
.equ FTS_QUERY_FLAG_POSITIONS,  0x02    // Include position data

// =============================================================================
// Index State Structure (g_fts_index, 96 bytes)
// =============================================================================

.equ FTS_STATE_OFF_TERM_FD,     0       // Term file descriptor
.equ FTS_STATE_OFF_POST_FD,     8       // Posting file descriptor
.equ FTS_STATE_OFF_META_FD,     16      // Metadata file descriptor
.equ FTS_STATE_OFF_TERM_MMAP,   24      // Term file mmap base
.equ FTS_STATE_OFF_TERM_SIZE,   32      // Term file mmap size
.equ FTS_STATE_OFF_POST_MMAP,   40      // Posting file mmap base
.equ FTS_STATE_OFF_POST_SIZE,   48      // Posting file mmap size
.equ FTS_STATE_OFF_TERM_COUNT,  56      // Number of terms on disk
.equ FTS_STATE_OFF_BUF_PTR,     64      // In-memory term buffer
.equ FTS_STATE_OFF_BUF_COUNT,   72      // Terms in buffer
.equ FTS_STATE_OFF_TOTAL_DOCS,  80      // Total documents indexed
.equ FTS_STATE_OFF_DIRTY,       88      // Dirty flag
.equ FTS_STATE_SIZE,            96

// =============================================================================
// Tokenizer State Structure (40 bytes)
// =============================================================================

.equ TOK_STATE_OFF_CONTENT,     0       // Content pointer
.equ TOK_STATE_OFF_LENGTH,      8       // Content length
.equ TOK_STATE_OFF_POSITION,    16      // Current byte position
.equ TOK_STATE_OFF_TOKEN_POS,   24      // Current token position (word count)
.equ TOK_STATE_OFF_FLAGS,       32      // Tokenizer flags
.equ TOK_STATE_SIZE,            40

// =============================================================================
// Query Context Structure (80 bytes)
// =============================================================================

.equ QUERY_CTX_OFF_RESULTS,     0       // Results buffer pointer
.equ QUERY_CTX_OFF_COUNT,       8       // Result count
.equ QUERY_CTX_OFF_CAPACITY,    16      // Max results
.equ QUERY_CTX_OFF_TYPE,        24      // Query type
.equ QUERY_CTX_OFF_TERMS,       32      // Parsed terms pointer
.equ QUERY_CTX_OFF_TERM_COUNT,  40      // Number of query terms
.equ QUERY_CTX_OFF_TOTAL_DOCS,  48      // Total docs (for IDF)
.equ QUERY_CTX_OFF_SCRATCH,     56      // Scratch buffer pointer
.equ QUERY_CTX_OFF_SCRATCH_SZ,  64      // Scratch buffer size
.equ QUERY_CTX_OFF_FLAGS,       72      // Query flags
.equ QUERY_CTX_SIZE,            80

// =============================================================================
// In-Memory Term Buffer Entry (48 bytes)
// =============================================================================
//
// Holds a term and its posting data during indexing before flush

.equ TERMBUF_OFF_HASH,          0       // 4: Term hash
.equ TERMBUF_OFF_LEN,           4       // 2: Term length
.equ TERMBUF_OFF_FLAGS,         6       // 2: Flags
.equ TERMBUF_OFF_DOC_ID,        8       // 8: Document ID
.equ TERMBUF_OFF_TERM_FREQ,     16      // 4: Frequency in this doc
.equ TERMBUF_OFF_POS_COUNT,     20      // 4: Position count
.equ TERMBUF_OFF_POSITIONS,     24      // 8: Positions array pointer
.equ TERMBUF_OFF_TERM_PTR,      32      // 8: Term string pointer
.equ TERMBUF_OFF_NEXT,          40      // 8: Next entry (hash collision)
.equ TERMBUF_ENTRY_SIZE,        48

// =============================================================================
// UTF-8 Constants
// =============================================================================

// Byte pattern masks (AND with first byte to determine length)
.equ UTF8_1BYTE_MASK,           0x80    // 0xxxxxxx -> ASCII
.equ UTF8_2BYTE_MASK,           0xE0    // 110xxxxx -> 2 bytes
.equ UTF8_3BYTE_MASK,           0xF0    // 1110xxxx -> 3 bytes
.equ UTF8_4BYTE_MASK,           0xF8    // 11110xxx -> 4 bytes
.equ UTF8_CONT_MASK,            0xC0    // 10xxxxxx -> continuation

// Expected values after masking
.equ UTF8_1BYTE_VAL,            0x00    // Single byte (ASCII)
.equ UTF8_2BYTE_VAL,            0xC0    // 2-byte start
.equ UTF8_3BYTE_VAL,            0xE0    // 3-byte start
.equ UTF8_4BYTE_VAL,            0xF0    // 4-byte start
.equ UTF8_CONT_VAL,             0x80    // Continuation byte

// Unicode ranges for character classification
.equ UNICODE_LATIN_START,       0x0041  // 'A'
.equ UNICODE_LATIN_END,         0x007A  // 'z'
.equ UNICODE_LATIN_EXT_START,   0x00C0  // Latin Extended-A start
.equ UNICODE_LATIN_EXT_END,     0x024F  // Latin Extended-B end
.equ UNICODE_CJK_START,         0x4E00  // CJK Unified Ideographs start
.equ UNICODE_CJK_END,           0x9FFF  // CJK Unified Ideographs end
.equ UNICODE_HIRAGANA_START,    0x3040
.equ UNICODE_HIRAGANA_END,      0x309F
.equ UNICODE_KATAKANA_START,    0x30A0
.equ UNICODE_KATAKANA_END,      0x30FF

// =============================================================================
// TF-IDF Constants
// =============================================================================

// Fixed-point format: 24.8 (24 integer bits, 8 fractional bits)
.equ TFIDF_FRAC_BITS,           8
.equ TFIDF_SCALE,               256     // 2^8

// BM25 parameters (scaled by 256)
.equ BM25_K1,                   307     // 1.2 * 256
.equ BM25_B,                    192     // 0.75 * 256

// =============================================================================
// Limits
// =============================================================================

.equ FTS_MAX_TERM_LEN,          255     // Maximum term length in bytes
.equ FTS_MIN_TERM_LEN,          1       // Minimum term length
.equ FTS_BUFFER_CAPACITY,       4096    // Terms in memory before flush
.equ FTS_MAX_POSITIONS,         1000    // Max positions per doc/term
.equ FTS_MAX_QUERY_TERMS,       32      // Max terms in a query
.equ FTS_MAX_RESULTS,           1000    // Max query results
.equ FTS_HASH_TABLE_SIZE,       8192    // Hash table entries
.equ FTS_POST_BUFFER_SIZE,      (4 << 20)  // 4MB posting buffer

// =============================================================================
// File Paths
// =============================================================================

.equ FTS_TERM_FILE,             0       // "terms.fts"
.equ FTS_POST_FILE,             1       // "postings.fts"
.equ FTS_META_FILE,             2       // "meta.fts"

#endif // INDEX_INC
