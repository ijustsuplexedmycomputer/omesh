// =============================================================================
// Omesh - JSON Parser Constants
// =============================================================================
//
// Minimal JSON parsing and generation for the API server.
// Supports objects, arrays, strings, numbers, booleans, and null.
//
// =============================================================================

#ifndef JSON_INC
#define JSON_INC

// =============================================================================
// JSON Value Types
// =============================================================================

.equ JSON_TYPE_NULL,        0
.equ JSON_TYPE_BOOL,        1
.equ JSON_TYPE_NUMBER,      2
.equ JSON_TYPE_STRING,      3
.equ JSON_TYPE_ARRAY,       4
.equ JSON_TYPE_OBJECT,      5

// =============================================================================
// JSON Token Types (for tokenizer)
// =============================================================================

.equ JSON_TOK_EOF,          0
.equ JSON_TOK_LBRACE,       1       // {
.equ JSON_TOK_RBRACE,       2       // }
.equ JSON_TOK_LBRACKET,     3       // [
.equ JSON_TOK_RBRACKET,     4       // ]
.equ JSON_TOK_COLON,        5       // :
.equ JSON_TOK_COMMA,        6       // ,
.equ JSON_TOK_STRING,       7       // "..."
.equ JSON_TOK_NUMBER,       8       // 123, -45.67
.equ JSON_TOK_TRUE,         9       // true
.equ JSON_TOK_FALSE,        10      // false
.equ JSON_TOK_NULL,         11      // null
.equ JSON_TOK_ERROR,        255

// =============================================================================
// JSON Value Structure (32 bytes)
// =============================================================================
//
// Represents a parsed JSON value. For strings and containers,
// pointers reference the original input buffer (zero-copy).
//

.equ JSON_VAL_OFF_TYPE,     0       // [4] JSON_TYPE_*
.equ JSON_VAL_OFF_FLAGS,    4       // [4] Flags
.equ JSON_VAL_OFF_DATA,     8       // [8] Value data (depends on type)
.equ JSON_VAL_OFF_LEN,      16      // [8] Length (for strings/arrays/objects)
.equ JSON_VAL_OFF_NEXT,     24      // [8] Next sibling (for array/object elements)
.equ JSON_VAL_SIZE,         32

// Data field interpretation by type:
//   NULL:   unused
//   BOOL:   0 = false, 1 = true
//   NUMBER: 32.32 fixed-point value
//   STRING: pointer to string start (in source buffer)
//   ARRAY:  pointer to first element JSON_VAL
//   OBJECT: pointer to first key-value pair

// =============================================================================
// JSON Key-Value Pair (for objects, 48 bytes)
// =============================================================================

.equ JSON_KV_OFF_KEY_PTR,   0       // [8] Pointer to key string
.equ JSON_KV_OFF_KEY_LEN,   8       // [4] Key string length
.equ JSON_KV_OFF_RESERVED,  12      // [4] Reserved
.equ JSON_KV_OFF_VALUE,     16      // [32] JSON_VAL for the value
.equ JSON_KV_SIZE,          48

// =============================================================================
// JSON Parser State (64 bytes)
// =============================================================================

.equ JSON_PARSE_OFF_INPUT,  0       // [8] Input buffer pointer
.equ JSON_PARSE_OFF_LEN,    8       // [8] Input length
.equ JSON_PARSE_OFF_POS,    16      // [8] Current position
.equ JSON_PARSE_OFF_LINE,   24      // [4] Current line number
.equ JSON_PARSE_OFF_COL,    28      // [4] Current column
.equ JSON_PARSE_OFF_ARENA,  32      // [8] Memory arena for values
.equ JSON_PARSE_OFF_ARENA_POS, 40   // [8] Arena position
.equ JSON_PARSE_OFF_ARENA_SZ, 48    // [8] Arena size
.equ JSON_PARSE_OFF_ERROR,  56      // [4] Error code
.equ JSON_PARSE_OFF_FLAGS,  60      // [4] Parser flags
.equ JSON_PARSE_SIZE,       64

// =============================================================================
// JSON Writer State (48 bytes)
// =============================================================================

.equ JSON_WRITE_OFF_BUF,    0       // [8] Output buffer
.equ JSON_WRITE_OFF_LEN,    8       // [8] Buffer size
.equ JSON_WRITE_OFF_POS,    16      // [8] Current position
.equ JSON_WRITE_OFF_DEPTH,  24      // [4] Nesting depth
.equ JSON_WRITE_OFF_FLAGS,  28      // [4] Writer flags
.equ JSON_WRITE_OFF_ERROR,  32      // [4] Error code
.equ JSON_WRITE_OFF_RESERVED, 36    // [12] Reserved
.equ JSON_WRITE_SIZE,       48

// Writer flags
.equ JSON_WRITE_FLAG_PRETTY, 0x01   // Pretty-print with indentation
.equ JSON_WRITE_FLAG_FIRST,  0x02   // First element (no comma before)

// =============================================================================
// Error Codes
// =============================================================================

.equ JSON_ERR_NONE,         0
.equ JSON_ERR_UNEXPECTED,   -1      // Unexpected character
.equ JSON_ERR_EOF,          -2      // Unexpected end of input
.equ JSON_ERR_STRING,       -3      // Invalid string
.equ JSON_ERR_NUMBER,       -4      // Invalid number
.equ JSON_ERR_DEPTH,        -5      // Nesting too deep
.equ JSON_ERR_MEMORY,       -6      // Out of arena memory
.equ JSON_ERR_OVERFLOW,     -7      // Output buffer overflow

// =============================================================================
// Limits
// =============================================================================

.equ JSON_MAX_DEPTH,        32      // Maximum nesting depth
.equ JSON_MAX_STRING,       65536   // Maximum string length
.equ JSON_ARENA_SIZE,       (64 * 1024)  // 64KB default arena

// =============================================================================
// Fixed-Point Number Format
// =============================================================================
//
// Numbers are stored as 32.32 fixed-point:
//   High 32 bits: integer part (signed)
//   Low 32 bits: fractional part
//

.equ JSON_NUM_FRAC_BITS,    32
.equ JSON_NUM_SCALE,        0x100000000     // 2^32

#endif // JSON_INC
