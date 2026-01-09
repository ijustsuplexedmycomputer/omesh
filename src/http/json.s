// =============================================================================
// Omesh - JSON Parser Module
// =============================================================================
//
// Minimal JSON parser and writer for the API server.
//
// CALLING CONVENTION: AAPCS64
//
// PUBLIC API:
//
//   json_parse(input, len, arena, arena_size) -> JSON_VAL* | NULL
//       Parse JSON from input buffer. Returns root value or NULL on error.
//
//   json_get_string(val, key, out_ptr, out_len) -> 0 | -1
//       Get string value from object by key name.
//
//   json_get_number(val, key) -> number | 0
//       Get number value from object by key name.
//
//   json_write_start(buf, len) -> writer state ptr
//       Initialize JSON writer.
//
//   json_write_object_start(writer) -> 0 | -1
//   json_write_object_end(writer) -> 0 | -1
//   json_write_array_start(writer) -> 0 | -1
//   json_write_array_end(writer) -> 0 | -1
//   json_write_key(writer, key, key_len) -> 0 | -1
//   json_write_string(writer, str, len) -> 0 | -1
//   json_write_number(writer, num) -> 0 | -1
//   json_write_bool(writer, val) -> 0 | -1
//   json_write_null(writer) -> 0 | -1
//   json_write_finish(writer) -> bytes written | -1
//
// =============================================================================

.include "syscall_nums.inc"
.include "json.inc"

.data

str_true:   .asciz "true"
str_false:  .asciz "false"
str_null:   .asciz "null"

.bss
.align 8
// Global parser state
g_json_parser:
    .skip   JSON_PARSE_SIZE

// Global writer state
g_json_writer:
    .skip   JSON_WRITE_SIZE

.text

// =============================================================================
// json_parse - Parse JSON input
// =============================================================================
// Input:
//   x0 = input buffer
//   x1 = input length
//   x2 = arena buffer (for allocating values)
//   x3 = arena size
// Output:
//   x0 = pointer to root JSON_VAL, or NULL on error
// =============================================================================
.global json_parse
.type json_parse, %function
json_parse:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    // Initialize parser state
    adrp    x19, g_json_parser
    add     x19, x19, :lo12:g_json_parser

    str     x0, [x19, #JSON_PARSE_OFF_INPUT]
    str     x1, [x19, #JSON_PARSE_OFF_LEN]
    str     xzr, [x19, #JSON_PARSE_OFF_POS]
    str     wzr, [x19, #JSON_PARSE_OFF_LINE]
    str     wzr, [x19, #JSON_PARSE_OFF_COL]
    str     x2, [x19, #JSON_PARSE_OFF_ARENA]
    str     xzr, [x19, #JSON_PARSE_OFF_ARENA_POS]
    str     x3, [x19, #JSON_PARSE_OFF_ARENA_SZ]
    str     wzr, [x19, #JSON_PARSE_OFF_ERROR]
    str     wzr, [x19, #JSON_PARSE_OFF_FLAGS]

    // Skip leading whitespace
    bl      json_skip_ws

    // Parse the root value
    mov     x0, x19
    bl      json_parse_value

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size json_parse, .-json_parse

// =============================================================================
// json_parse_value - Parse a JSON value
// =============================================================================
// Input:
//   x0 = parser state
// Output:
//   x0 = JSON_VAL pointer, or NULL on error
// =============================================================================
.type json_parse_value, %function
json_parse_value:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                 // parser

    // Peek at next character
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    ldr     x2, [x19, #JSON_PARSE_OFF_LEN]
    cmp     x1, x2
    b.ge    .Lparse_val_eof

    ldrb    w20, [x0, x1]           // next char

    // Dispatch based on character
    cmp     w20, #'{'
    b.eq    .Lparse_object
    cmp     w20, #'['
    b.eq    .Lparse_array
    cmp     w20, #'"'
    b.eq    .Lparse_string
    cmp     w20, #'t'
    b.eq    .Lparse_true
    cmp     w20, #'f'
    b.eq    .Lparse_false
    cmp     w20, #'n'
    b.eq    .Lparse_null
    cmp     w20, #'-'
    b.eq    .Lparse_number
    cmp     w20, #'0'
    b.lt    .Lparse_val_error
    cmp     w20, #'9'
    b.le    .Lparse_number

.Lparse_val_error:
    mov     x0, #0
    b       .Lparse_val_done

.Lparse_val_eof:
    mov     x0, #0
    b       .Lparse_val_done

.Lparse_object:
    mov     x0, x19
    bl      json_parse_object
    b       .Lparse_val_done

.Lparse_array:
    mov     x0, x19
    bl      json_parse_array
    b       .Lparse_val_done

.Lparse_string:
    mov     x0, x19
    bl      json_parse_string
    b       .Lparse_val_done

.Lparse_true:
    mov     x0, x19
    bl      json_parse_true
    b       .Lparse_val_done

.Lparse_false:
    mov     x0, x19
    bl      json_parse_false
    b       .Lparse_val_done

.Lparse_null:
    mov     x0, x19
    bl      json_parse_null
    b       .Lparse_val_done

.Lparse_number:
    mov     x0, x19
    bl      json_parse_number

.Lparse_val_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size json_parse_value, .-json_parse_value

// =============================================================================
// json_alloc_val - Allocate a JSON_VAL from arena
// =============================================================================
// Input:
//   x0 = parser state
// Output:
//   x0 = JSON_VAL pointer, or NULL if out of memory
// =============================================================================
.type json_alloc_val, %function
json_alloc_val:
    ldr     x1, [x0, #JSON_PARSE_OFF_ARENA]
    ldr     x2, [x0, #JSON_PARSE_OFF_ARENA_POS]
    ldr     x3, [x0, #JSON_PARSE_OFF_ARENA_SZ]

    // Check space
    add     x4, x2, #JSON_VAL_SIZE
    cmp     x4, x3
    b.gt    .Lalloc_fail

    // Allocate
    add     x5, x1, x2              // ptr = arena + pos
    str     x4, [x0, #JSON_PARSE_OFF_ARENA_POS]

    // Clear the value
    mov     x0, x5
    mov     x1, #JSON_VAL_SIZE
.Lalloc_clear:
    cbz     x1, .Lalloc_done
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Lalloc_clear

.Lalloc_done:
    mov     x0, x5
    ret

.Lalloc_fail:
    mov     x0, #0
    ret
.size json_alloc_val, .-json_alloc_val

// =============================================================================
// json_parse_object - Parse JSON object { ... }
// =============================================================================
.type json_parse_object, %function
json_parse_object:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                 // parser

    // Allocate object value
    bl      json_alloc_val
    cbz     x0, .Lobj_error
    mov     x20, x0                 // object val

    // Set type
    mov     w0, #JSON_TYPE_OBJECT
    str     w0, [x20, #JSON_VAL_OFF_TYPE]

    // Skip '{'
    ldr     x0, [x19, #JSON_PARSE_OFF_POS]
    add     x0, x0, #1
    str     x0, [x19, #JSON_PARSE_OFF_POS]

    bl      json_skip_ws

    // Check for empty object
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    ldrb    w2, [x0, x1]
    cmp     w2, #'}'
    b.eq    .Lobj_empty

    mov     x21, #0                 // first kv ptr
    mov     x22, #0                 // last kv ptr
    mov     x23, #0                 // count

.Lobj_loop:
    // Allocate key-value pair from arena
    mov     x0, x19
    ldr     x1, [x0, #JSON_PARSE_OFF_ARENA]
    ldr     x2, [x0, #JSON_PARSE_OFF_ARENA_POS]
    ldr     x3, [x0, #JSON_PARSE_OFF_ARENA_SZ]
    add     x4, x2, #JSON_KV_SIZE
    cmp     x4, x3
    b.gt    .Lobj_error
    add     x24, x1, x2             // new kv ptr
    str     x4, [x0, #JSON_PARSE_OFF_ARENA_POS]

    // Parse key (must be string)
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    ldrb    w2, [x0, x1]
    cmp     w2, #'"'
    b.ne    .Lobj_error

    // Get key string
    add     x1, x1, #1              // skip "
    str     x1, [x19, #JSON_PARSE_OFF_POS]
    add     x0, x0, x1              // key start
    str     x0, [x24, #JSON_KV_OFF_KEY_PTR]

    // Find end of key
    mov     x2, #0
.Lobj_key_loop:
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    add     x3, x1, x2
    ldr     x4, [x19, #JSON_PARSE_OFF_LEN]
    cmp     x3, x4
    b.ge    .Lobj_error
    ldrb    w5, [x0, x3]
    cmp     w5, #'"'
    b.eq    .Lobj_key_end
    cmp     w5, #'\\'
    b.eq    .Lobj_key_escape
    add     x2, x2, #1
    b       .Lobj_key_loop

.Lobj_key_escape:
    add     x2, x2, #2              // skip escape sequence
    b       .Lobj_key_loop

.Lobj_key_end:
    str     w2, [x24, #JSON_KV_OFF_KEY_LEN]
    add     x3, x1, x2
    add     x3, x3, #1              // skip closing "
    str     x3, [x19, #JSON_PARSE_OFF_POS]

    bl      json_skip_ws

    // Expect ':'
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    ldrb    w2, [x0, x1]
    cmp     w2, #':'
    b.ne    .Lobj_error
    add     x1, x1, #1
    str     x1, [x19, #JSON_PARSE_OFF_POS]

    bl      json_skip_ws

    // Parse value
    mov     x0, x19
    bl      json_parse_value
    cbz     x0, .Lobj_error

    // Copy value into kv struct
    add     x1, x24, #JSON_KV_OFF_VALUE
    mov     x2, #JSON_VAL_SIZE
.Lobj_copy_val:
    cbz     x2, .Lobj_copy_done
    ldrb    w3, [x0], #1
    strb    w3, [x1], #1
    sub     x2, x2, #1
    b       .Lobj_copy_val
.Lobj_copy_done:

    // Link into list
    cbz     x21, .Lobj_first_kv
    str     x24, [x22, #JSON_KV_OFF_VALUE + JSON_VAL_OFF_NEXT]
    b       .Lobj_link_done
.Lobj_first_kv:
    mov     x21, x24
.Lobj_link_done:
    mov     x22, x24
    add     x23, x23, #1

    bl      json_skip_ws

    // Check for ',' or '}'
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    ldrb    w2, [x0, x1]
    cmp     w2, #'}'
    b.eq    .Lobj_done
    cmp     w2, #','
    b.ne    .Lobj_error
    add     x1, x1, #1
    str     x1, [x19, #JSON_PARSE_OFF_POS]
    bl      json_skip_ws
    b       .Lobj_loop

.Lobj_empty:
.Lobj_done:
    // Skip '}'
    ldr     x0, [x19, #JSON_PARSE_OFF_POS]
    add     x0, x0, #1
    str     x0, [x19, #JSON_PARSE_OFF_POS]

    // Store first child pointer
    str     x21, [x20, #JSON_VAL_OFF_DATA]
    str     x23, [x20, #JSON_VAL_OFF_LEN]

    mov     x0, x20
    b       .Lobj_ret

.Lobj_error:
    mov     x0, #0

.Lobj_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size json_parse_object, .-json_parse_object

// =============================================================================
// json_parse_array - Parse JSON array [ ... ]
// =============================================================================
.type json_parse_array, %function
json_parse_array:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                 // parser

    // Allocate array value
    bl      json_alloc_val
    cbz     x0, .Larr_error
    mov     x20, x0

    mov     w0, #JSON_TYPE_ARRAY
    str     w0, [x20, #JSON_VAL_OFF_TYPE]

    // Skip '['
    ldr     x0, [x19, #JSON_PARSE_OFF_POS]
    add     x0, x0, #1
    str     x0, [x19, #JSON_PARSE_OFF_POS]

    bl      json_skip_ws

    // Check for empty array
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    ldrb    w2, [x0, x1]
    cmp     w2, #']'
    b.eq    .Larr_empty

    mov     x21, #0                 // first elem
    mov     x22, #0                 // last elem
    mov     x23, #0                 // count

.Larr_loop:
    // Parse element value
    mov     x0, x19
    bl      json_parse_value
    cbz     x0, .Larr_error
    mov     x24, x0

    // Link into list
    cbz     x21, .Larr_first
    str     x24, [x22, #JSON_VAL_OFF_NEXT]
    b       .Larr_link_done
.Larr_first:
    mov     x21, x24
.Larr_link_done:
    mov     x22, x24
    add     x23, x23, #1

    bl      json_skip_ws

    // Check for ',' or ']'
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    ldrb    w2, [x0, x1]
    cmp     w2, #']'
    b.eq    .Larr_done
    cmp     w2, #','
    b.ne    .Larr_error
    add     x1, x1, #1
    str     x1, [x19, #JSON_PARSE_OFF_POS]
    bl      json_skip_ws
    b       .Larr_loop

.Larr_empty:
.Larr_done:
    // Skip ']'
    ldr     x0, [x19, #JSON_PARSE_OFF_POS]
    add     x0, x0, #1
    str     x0, [x19, #JSON_PARSE_OFF_POS]

    str     x21, [x20, #JSON_VAL_OFF_DATA]
    str     x23, [x20, #JSON_VAL_OFF_LEN]

    mov     x0, x20
    b       .Larr_ret

.Larr_error:
    mov     x0, #0

.Larr_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size json_parse_array, .-json_parse_array

// =============================================================================
// json_parse_string - Parse JSON string "..."
// =============================================================================
.type json_parse_string, %function
json_parse_string:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                 // parser

    // Allocate string value
    bl      json_alloc_val
    cbz     x0, .Lstr_error
    mov     x20, x0

    mov     w0, #JSON_TYPE_STRING
    str     w0, [x20, #JSON_VAL_OFF_TYPE]

    // Skip opening "
    ldr     x0, [x19, #JSON_PARSE_OFF_POS]
    add     x0, x0, #1
    str     x0, [x19, #JSON_PARSE_OFF_POS]

    // Record string start
    ldr     x21, [x19, #JSON_PARSE_OFF_INPUT]
    add     x21, x21, x0            // string start ptr
    str     x21, [x20, #JSON_VAL_OFF_DATA]

    // Find string end
    mov     x22, #0                 // length
.Lstr_loop:
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    add     x2, x1, x22
    ldr     x3, [x19, #JSON_PARSE_OFF_LEN]
    cmp     x2, x3
    b.ge    .Lstr_error

    ldrb    w4, [x0, x2]
    cmp     w4, #'"'
    b.eq    .Lstr_end
    cmp     w4, #'\\'
    b.eq    .Lstr_escape
    add     x22, x22, #1
    b       .Lstr_loop

.Lstr_escape:
    add     x22, x22, #2            // skip escaped char
    b       .Lstr_loop

.Lstr_end:
    str     x22, [x20, #JSON_VAL_OFF_LEN]
    add     x2, x1, x22
    add     x2, x2, #1              // skip closing "
    str     x2, [x19, #JSON_PARSE_OFF_POS]

    mov     x0, x20
    b       .Lstr_ret

.Lstr_error:
    mov     x0, #0

.Lstr_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size json_parse_string, .-json_parse_string

// =============================================================================
// json_parse_number - Parse JSON number
// =============================================================================
.type json_parse_number, %function
json_parse_number:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                 // parser

    // Allocate number value
    bl      json_alloc_val
    cbz     x0, .Lnum_error
    mov     x20, x0

    mov     w0, #JSON_TYPE_NUMBER
    str     w0, [x20, #JSON_VAL_OFF_TYPE]

    // Parse the number
    ldr     x0, [x19, #JSON_PARSE_OFF_INPUT]
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    add     x0, x0, x1

    mov     x21, #0                 // result
    mov     x22, #0                 // negative flag

    // Check for negative
    ldrb    w2, [x0]
    cmp     w2, #'-'
    b.ne    .Lnum_digits
    mov     x22, #1
    add     x0, x0, #1
    add     x1, x1, #1

.Lnum_digits:
    ldr     x3, [x19, #JSON_PARSE_OFF_LEN]
.Lnum_loop:
    cmp     x1, x3
    b.ge    .Lnum_done

    ldrb    w2, [x0]
    cmp     w2, #'0'
    b.lt    .Lnum_done
    cmp     w2, #'9'
    b.gt    .Lnum_check_frac

    sub     w2, w2, #'0'
    mov     x4, #10
    mul     x21, x21, x4
    add     x21, x21, x2

    add     x0, x0, #1
    add     x1, x1, #1
    b       .Lnum_loop

.Lnum_check_frac:
    // Skip fractional part for now (just integer parsing)
    cmp     w2, #'.'
    b.ne    .Lnum_done
    add     x0, x0, #1
    add     x1, x1, #1
.Lnum_frac_loop:
    ldr     x3, [x19, #JSON_PARSE_OFF_LEN]
    cmp     x1, x3
    b.ge    .Lnum_done
    ldrb    w2, [x0]
    cmp     w2, #'0'
    b.lt    .Lnum_done
    cmp     w2, #'9'
    b.gt    .Lnum_done
    add     x0, x0, #1
    add     x1, x1, #1
    b       .Lnum_frac_loop

.Lnum_done:
    // Apply sign
    cbnz    x22, .Lnum_negate
    b       .Lnum_store
.Lnum_negate:
    neg     x21, x21
.Lnum_store:
    // Convert to 32.32 fixed-point (integer in high 32 bits)
    lsl     x21, x21, #32
    str     x21, [x20, #JSON_VAL_OFF_DATA]
    str     x1, [x19, #JSON_PARSE_OFF_POS]

    mov     x0, x20
    b       .Lnum_ret

.Lnum_error:
    mov     x0, #0

.Lnum_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size json_parse_number, .-json_parse_number

// =============================================================================
// json_parse_true - Parse "true"
// =============================================================================
.type json_parse_true, %function
json_parse_true:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    bl      json_alloc_val
    cbz     x0, .Ltrue_error

    mov     w1, #JSON_TYPE_BOOL
    str     w1, [x0, #JSON_VAL_OFF_TYPE]
    mov     x1, #1
    str     x1, [x0, #JSON_VAL_OFF_DATA]

    // Skip "true"
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    add     x1, x1, #4
    str     x1, [x19, #JSON_PARSE_OFF_POS]
    b       .Ltrue_ret

.Ltrue_error:
    mov     x0, #0

.Ltrue_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size json_parse_true, .-json_parse_true

// =============================================================================
// json_parse_false - Parse "false"
// =============================================================================
.type json_parse_false, %function
json_parse_false:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    bl      json_alloc_val
    cbz     x0, .Lfalse_error

    mov     w1, #JSON_TYPE_BOOL
    str     w1, [x0, #JSON_VAL_OFF_TYPE]
    str     xzr, [x0, #JSON_VAL_OFF_DATA]

    // Skip "false"
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    add     x1, x1, #5
    str     x1, [x19, #JSON_PARSE_OFF_POS]
    b       .Lfalse_ret

.Lfalse_error:
    mov     x0, #0

.Lfalse_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size json_parse_false, .-json_parse_false

// =============================================================================
// json_parse_null - Parse "null"
// =============================================================================
.type json_parse_null, %function
json_parse_null:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    bl      json_alloc_val
    cbz     x0, .Lnull_error

    mov     w1, #JSON_TYPE_NULL
    str     w1, [x0, #JSON_VAL_OFF_TYPE]

    // Skip "null"
    ldr     x1, [x19, #JSON_PARSE_OFF_POS]
    add     x1, x1, #4
    str     x1, [x19, #JSON_PARSE_OFF_POS]
    b       .Lnull_ret

.Lnull_error:
    mov     x0, #0

.Lnull_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size json_parse_null, .-json_parse_null

// =============================================================================
// json_skip_ws - Skip whitespace
// =============================================================================
.type json_skip_ws, %function
json_skip_ws:
    adrp    x0, g_json_parser
    add     x0, x0, :lo12:g_json_parser

    ldr     x1, [x0, #JSON_PARSE_OFF_INPUT]
    ldr     x2, [x0, #JSON_PARSE_OFF_POS]
    ldr     x3, [x0, #JSON_PARSE_OFF_LEN]

.Lws_loop:
    cmp     x2, x3
    b.ge    .Lws_done

    ldrb    w4, [x1, x2]
    cmp     w4, #' '
    b.eq    .Lws_skip
    cmp     w4, #'\t'
    b.eq    .Lws_skip
    cmp     w4, #'\n'
    b.eq    .Lws_skip
    cmp     w4, #'\r'
    b.eq    .Lws_skip
    b       .Lws_done

.Lws_skip:
    add     x2, x2, #1
    b       .Lws_loop

.Lws_done:
    str     x2, [x0, #JSON_PARSE_OFF_POS]
    ret
.size json_skip_ws, .-json_skip_ws

// =============================================================================
// json_get_string - Get string value from object by key
// =============================================================================
// Input:
//   x0 = JSON_VAL pointer (must be object)
//   x1 = key string
//   x2 = key length
//   x3 = output: pointer to store string ptr
//   x4 = output: pointer to store string len
// Output:
//   x0 = 0 if found, -1 if not found
// =============================================================================
.global json_get_string
.type json_get_string, %function
json_get_string:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                 // object
    mov     x20, x1                 // key
    mov     x21, x2                 // key len
    mov     x22, x3                 // out ptr ptr
    mov     x23, x4                 // out len ptr

    // Check type is object
    ldr     w0, [x19, #JSON_VAL_OFF_TYPE]
    cmp     w0, #JSON_TYPE_OBJECT
    b.ne    .Lget_str_notfound

    // Get first kv
    ldr     x24, [x19, #JSON_VAL_OFF_DATA]

.Lget_str_loop:
    cbz     x24, .Lget_str_notfound

    // Compare key
    ldr     x0, [x24, #JSON_KV_OFF_KEY_PTR]
    ldr     w1, [x24, #JSON_KV_OFF_KEY_LEN]
    cmp     x1, x21
    b.ne    .Lget_str_next

    // Compare bytes
    mov     x2, #0
.Lget_str_cmp:
    cmp     x2, x21
    b.ge    .Lget_str_found

    ldrb    w3, [x0, x2]
    ldrb    w4, [x20, x2]
    cmp     w3, w4
    b.ne    .Lget_str_next
    add     x2, x2, #1
    b       .Lget_str_cmp

.Lget_str_found:
    // Check value is string
    add     x0, x24, #JSON_KV_OFF_VALUE
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_STRING
    b.ne    .Lget_str_notfound

    // Return string ptr and len
    ldr     x1, [x0, #JSON_VAL_OFF_DATA]
    str     x1, [x22]
    ldr     x1, [x0, #JSON_VAL_OFF_LEN]
    str     x1, [x23]

    mov     x0, #0
    b       .Lget_str_ret

.Lget_str_next:
    // Next kv via value's next pointer
    add     x0, x24, #JSON_KV_OFF_VALUE
    ldr     x24, [x0, #JSON_VAL_OFF_NEXT]
    b       .Lget_str_loop

.Lget_str_notfound:
    mov     x0, #-1

.Lget_str_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size json_get_string, .-json_get_string

// =============================================================================
// json_get_number - Get number value from object by key
// =============================================================================
// Input:
//   x0 = JSON_VAL pointer (must be object)
//   x1 = key string
//   x2 = key length
// Output:
//   x0 = number value, or 0 if not found
// =============================================================================
.global json_get_number
.type json_get_number, %function
json_get_number:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0
    mov     x20, x1
    mov     x21, x2

    // Check type
    ldr     w0, [x19, #JSON_VAL_OFF_TYPE]
    cmp     w0, #JSON_TYPE_OBJECT
    b.ne    .Lget_num_ret_zero

    ldr     x22, [x19, #JSON_VAL_OFF_DATA]

.Lget_num_loop:
    cbz     x22, .Lget_num_ret_zero

    ldr     x0, [x22, #JSON_KV_OFF_KEY_PTR]
    ldr     w1, [x22, #JSON_KV_OFF_KEY_LEN]
    cmp     x1, x21
    b.ne    .Lget_num_next

    mov     x2, #0
.Lget_num_cmp:
    cmp     x2, x21
    b.ge    .Lget_num_found
    ldrb    w3, [x0, x2]
    ldrb    w4, [x20, x2]
    cmp     w3, w4
    b.ne    .Lget_num_next
    add     x2, x2, #1
    b       .Lget_num_cmp

.Lget_num_found:
    add     x0, x22, #JSON_KV_OFF_VALUE
    ldr     w1, [x0, #JSON_VAL_OFF_TYPE]
    cmp     w1, #JSON_TYPE_NUMBER
    b.ne    .Lget_num_ret_zero
    ldr     x0, [x0, #JSON_VAL_OFF_DATA]
    b       .Lget_num_ret

.Lget_num_next:
    add     x0, x22, #JSON_KV_OFF_VALUE
    ldr     x22, [x0, #JSON_VAL_OFF_NEXT]
    b       .Lget_num_loop

.Lget_num_ret_zero:
    mov     x0, #0

.Lget_num_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size json_get_number, .-json_get_number

// =============================================================================
// JSON Writer Functions
// =============================================================================

// =============================================================================
// json_write_init - Initialize JSON writer
// =============================================================================
// Input:
//   x0 = output buffer
//   x1 = buffer size
// Output:
//   x0 = writer state pointer
// =============================================================================
.global json_write_init
.type json_write_init, %function
json_write_init:
    adrp    x2, g_json_writer
    add     x2, x2, :lo12:g_json_writer

    str     x0, [x2, #JSON_WRITE_OFF_BUF]
    str     x1, [x2, #JSON_WRITE_OFF_LEN]
    str     xzr, [x2, #JSON_WRITE_OFF_POS]
    str     wzr, [x2, #JSON_WRITE_OFF_DEPTH]
    mov     w0, #JSON_WRITE_FLAG_FIRST
    str     w0, [x2, #JSON_WRITE_OFF_FLAGS]
    str     wzr, [x2, #JSON_WRITE_OFF_ERROR]

    mov     x0, x2
    ret
.size json_write_init, .-json_write_init

// =============================================================================
// json_write_char - Write single character
// =============================================================================
.type json_write_char, %function
json_write_char:
    // x0 = writer, x1 = char
    ldr     x2, [x0, #JSON_WRITE_OFF_POS]
    ldr     x3, [x0, #JSON_WRITE_OFF_LEN]
    cmp     x2, x3
    b.ge    .Lwc_overflow

    ldr     x4, [x0, #JSON_WRITE_OFF_BUF]
    strb    w1, [x4, x2]
    add     x2, x2, #1
    str     x2, [x0, #JSON_WRITE_OFF_POS]
    mov     x0, #0
    ret

.Lwc_overflow:
    mov     x0, #-1
    ret
.size json_write_char, .-json_write_char

// =============================================================================
// json_write_str - Write string (no quotes)
// =============================================================================
.type json_write_str, %function
json_write_str:
    // x0 = writer, x1 = str, x2 = len
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                 // writer
    mov     x20, x1                 // str
    mov     x21, x2                 // len
    mov     x22, #0                 // index

.Lwstr_loop:
    cmp     x22, x21
    b.ge    .Lwstr_done

    ldrb    w1, [x20, x22]
    mov     x0, x19
    bl      json_write_char
    cmp     x0, #0
    b.lt    .Lwstr_error

    add     x22, x22, #1
    b       .Lwstr_loop

.Lwstr_done:
    mov     x0, #0
    b       .Lwstr_ret

.Lwstr_error:
    mov     x0, #-1

.Lwstr_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size json_write_str, .-json_write_str

// =============================================================================
// json_write_object_start - Write '{'
// =============================================================================
.global json_write_object_start
.type json_write_object_start, %function
json_write_object_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x1, #'{'
    bl      json_write_char
    cmp     x0, #0
    b.lt    .Lwos_ret

    // Set first flag
    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    ldr     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    orr     w1, w1, #JSON_WRITE_FLAG_FIRST
    str     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    mov     x0, #0

.Lwos_ret:
    ldp     x29, x30, [sp], #16
    ret
.size json_write_object_start, .-json_write_object_start

// =============================================================================
// json_write_object_end - Write '}'
// =============================================================================
.global json_write_object_end
.type json_write_object_end, %function
json_write_object_end:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    mov     x1, #'}'
    bl      json_write_char

    // Clear FIRST flag so next item gets a comma
    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    ldr     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    and     w1, w1, #~JSON_WRITE_FLAG_FIRST
    str     w1, [x0, #JSON_WRITE_OFF_FLAGS]

    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret
.size json_write_object_end, .-json_write_object_end

// =============================================================================
// json_write_array_start - Write '['
// =============================================================================
.global json_write_array_start
.type json_write_array_start, %function
json_write_array_start:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    mov     x1, #'['
    bl      json_write_char
    cmp     x0, #0
    b.lt    .Lwas_ret

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    ldr     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    orr     w1, w1, #JSON_WRITE_FLAG_FIRST
    str     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    mov     x0, #0

.Lwas_ret:
    ldp     x29, x30, [sp], #16
    ret
.size json_write_array_start, .-json_write_array_start

// =============================================================================
// json_write_array_end - Write ']'
// =============================================================================
.global json_write_array_end
.type json_write_array_end, %function
json_write_array_end:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    mov     x1, #']'
    bl      json_write_char

    // Clear FIRST flag so next item gets a comma
    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    ldr     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    and     w1, w1, #~JSON_WRITE_FLAG_FIRST
    str     w1, [x0, #JSON_WRITE_OFF_FLAGS]

    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret
.size json_write_array_end, .-json_write_array_end

// =============================================================================
// json_write_key - Write object key with colon
// =============================================================================
// Input:
//   x0 = key string
//   x1 = key length
// =============================================================================
.global json_write_key
.type json_write_key, %function
json_write_key:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0
    mov     x20, x1

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer

    // Check if need comma
    ldr     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    tst     w1, #JSON_WRITE_FLAG_FIRST
    b.ne    .Lwk_no_comma

    mov     x1, #','
    bl      json_write_char
    cmp     x0, #0
    b.lt    .Lwk_error

.Lwk_no_comma:
    // Clear first flag
    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    ldr     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    and     w1, w1, #~JSON_WRITE_FLAG_FIRST
    str     w1, [x0, #JSON_WRITE_OFF_FLAGS]

    // Write quote
    mov     x1, #'"'
    bl      json_write_char
    cmp     x0, #0
    b.lt    .Lwk_error

    // Write key
    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    mov     x1, x19
    mov     x2, x20
    bl      json_write_str
    cmp     x0, #0
    b.lt    .Lwk_error

    // Write quote and colon
    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    mov     x1, #'"'
    bl      json_write_char
    cmp     x0, #0
    b.lt    .Lwk_error

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    mov     x1, #':'
    bl      json_write_char
    b       .Lwk_ret

.Lwk_error:
    mov     x0, #-1

.Lwk_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size json_write_key, .-json_write_key

// =============================================================================
// json_write_string - Write JSON string value
// =============================================================================
.global json_write_string
.type json_write_string, %function
json_write_string:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0
    mov     x20, x1

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer

    // Check if need comma (for array elements)
    ldr     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    tst     w1, #JSON_WRITE_FLAG_FIRST
    b.ne    .Lwstring_no_comma

    // Only add comma if we're in an array context
    // For now, just clear the flag
    b       .Lwstring_no_comma

.Lwstring_no_comma:
    ldr     w1, [x0, #JSON_WRITE_OFF_FLAGS]
    and     w1, w1, #~JSON_WRITE_FLAG_FIRST
    str     w1, [x0, #JSON_WRITE_OFF_FLAGS]

    mov     x1, #'"'
    bl      json_write_char
    cmp     x0, #0
    b.lt    .Lwstring_error

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    mov     x1, x19
    mov     x2, x20
    bl      json_write_str
    cmp     x0, #0
    b.lt    .Lwstring_error

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    mov     x1, #'"'
    bl      json_write_char
    b       .Lwstring_ret

.Lwstring_error:
    mov     x0, #-1

.Lwstring_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size json_write_string, .-json_write_string

// =============================================================================
// json_write_number - Write JSON number value
// =============================================================================
.global json_write_number
.type json_write_number, %function
json_write_number:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                 // number

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    mov     x20, x0

    // Handle negative
    cmp     x19, #0
    b.ge    .Lwnum_positive

    mov     x1, #'-'
    bl      json_write_char
    cmp     x0, #0
    b.lt    .Lwnum_error
    neg     x19, x19

.Lwnum_positive:
    // Convert to decimal
    cbz     x19, .Lwnum_zero

    // Build digits on stack (max 20 digits for uint64)
    // Buffer at sp+56..sp+79 (24 bytes, enough for 20 digits)
    add     x1, sp, #76
    mov     x2, #0                  // digit count

.Lwnum_loop:
    cbz     x19, .Lwnum_write
    mov     x3, #10
    udiv    x4, x19, x3
    msub    x5, x4, x3, x19
    add     x5, x5, #'0'
    sub     x1, x1, #1
    strb    w5, [x1]
    add     x2, x2, #1
    mov     x19, x4
    b       .Lwnum_loop

.Lwnum_write:
    mov     x0, x20
    bl      json_write_str
    b       .Lwnum_ret

.Lwnum_zero:
    mov     x0, x20
    mov     x1, #'0'
    bl      json_write_char
    b       .Lwnum_ret

.Lwnum_error:
    mov     x0, #-1

.Lwnum_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size json_write_number, .-json_write_number

// =============================================================================
// json_write_bool - Write true/false
// =============================================================================
.global json_write_bool
.type json_write_bool, %function
json_write_bool:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    cbz     x0, .Lwbool_false

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    adrp    x1, str_true
    add     x1, x1, :lo12:str_true
    mov     x2, #4
    bl      json_write_str
    b       .Lwbool_ret

.Lwbool_false:
    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    adrp    x1, str_false
    add     x1, x1, :lo12:str_false
    mov     x2, #5
    bl      json_write_str

.Lwbool_ret:
    ldp     x29, x30, [sp], #16
    ret
.size json_write_bool, .-json_write_bool

// =============================================================================
// json_write_null - Write null
// =============================================================================
.global json_write_null
.type json_write_null, %function
json_write_null:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    adrp    x1, str_null
    add     x1, x1, :lo12:str_null
    mov     x2, #4
    bl      json_write_str

    ldp     x29, x30, [sp], #16
    ret
.size json_write_null, .-json_write_null

// =============================================================================
// json_write_finish - Finish writing and return length
// =============================================================================
.global json_write_finish
.type json_write_finish, %function
json_write_finish:
    adrp    x0, g_json_writer
    add     x0, x0, :lo12:g_json_writer
    ldr     x0, [x0, #JSON_WRITE_OFF_POS]
    ret
.size json_write_finish, .-json_write_finish
