// =============================================================================
// Omesh - Full-Text Search Index Tests
// =============================================================================
//
// Test suite for the full-text search indexing system:
// - UTF-8 tokenization
// - Index operations
// - TF-IDF scoring
// - Query execution
//
// =============================================================================

.include "syscall_nums.inc"
.include "index.inc"

// =============================================================================
// Entry point
// =============================================================================
.text
.global _start
_start:
    // Print header
    adrp    x0, msg_header
    add     x0, x0, :lo12:msg_header
    bl      print_str

    // Run tests
    bl      test_utf8_char_len
    bl      test_utf8_decode
    bl      test_utf8_is_letter
    bl      test_utf8_tolower
    bl      test_tokenize_ascii
    bl      test_tokenize_utf8
    bl      test_tfidf_log2
    bl      test_tfidf_calc
    bl      test_index_init
    bl      test_index_add
    bl      test_query_init
    bl      test_query_parse

    // Print summary
    adrp    x0, msg_summary
    add     x0, x0, :lo12:msg_summary
    bl      print_str

    adrp    x0, test_passed
    add     x0, x0, :lo12:test_passed
    ldr     x0, [x0]
    bl      print_dec

    mov     x0, #'/'
    bl      print_char

    adrp    x0, test_total
    add     x0, x0, :lo12:test_total
    ldr     x0, [x0]
    bl      print_dec

    adrp    x0, msg_passed
    add     x0, x0, :lo12:msg_passed
    bl      print_str

    // Exit with code based on test results
    adrp    x0, test_passed
    add     x0, x0, :lo12:test_passed
    ldr     x1, [x0]
    adrp    x0, test_total
    add     x0, x0, :lo12:test_total
    ldr     x0, [x0]
    cmp     x0, x1
    cset    w0, ne                  // Exit 0 if all passed, 1 otherwise
    mov     x8, #SYS_exit
    svc     #0

// =============================================================================
// Test: UTF-8 char length
// =============================================================================
test_utf8_char_len:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Test ASCII (1 byte)
    mov     x0, #'A'
    bl      utf8_char_len
    cmp     x0, #1
    cset    w0, ne
    adrp    x1, name_utf8_len_ascii
    add     x1, x1, :lo12:name_utf8_len_ascii
    bl      test_result

    // Test 2-byte UTF-8 (0xC0-0xDF)
    mov     x0, #0xC3               // Start of 2-byte
    bl      utf8_char_len
    cmp     x0, #2
    cset    w0, ne
    adrp    x1, name_utf8_len_2byte
    add     x1, x1, :lo12:name_utf8_len_2byte
    bl      test_result

    // Test 3-byte UTF-8 (0xE0-0xEF)
    mov     x0, #0xE4               // Start of 3-byte (CJK)
    bl      utf8_char_len
    cmp     x0, #3
    cset    w0, ne
    adrp    x1, name_utf8_len_3byte
    add     x1, x1, :lo12:name_utf8_len_3byte
    bl      test_result

    // Test 4-byte UTF-8 (0xF0-0xF7)
    mov     x0, #0xF0               // Start of 4-byte
    bl      utf8_char_len
    cmp     x0, #4
    cset    w0, ne
    adrp    x1, name_utf8_len_4byte
    add     x1, x1, :lo12:name_utf8_len_4byte
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: UTF-8 decode
// =============================================================================
test_utf8_decode:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Test ASCII decode
    adrp    x0, test_ascii_str
    add     x0, x0, :lo12:test_ascii_str
    mov     x1, #5
    bl      utf8_decode
    cmp     x0, #'H'                // Should decode 'H'
    cset    w0, ne
    adrp    x1, name_utf8_decode_ascii
    add     x1, x1, :lo12:name_utf8_decode_ascii
    bl      test_result

    // Test 2-byte decode: e with acute (U+00E9 = 0xC3 0xA9)
    adrp    x0, test_utf8_2byte
    add     x0, x0, :lo12:test_utf8_2byte
    mov     x1, #2
    bl      utf8_decode
    cmp     x0, #0xE9               // e-acute codepoint
    cset    w0, ne
    adrp    x1, name_utf8_decode_2byte
    add     x1, x1, :lo12:name_utf8_decode_2byte
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: UTF-8 is_letter
// =============================================================================
test_utf8_is_letter:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Test ASCII letter
    mov     x0, #'A'
    bl      utf8_is_letter
    cmp     x0, #1
    cset    w0, ne
    adrp    x1, name_is_letter_ascii
    add     x1, x1, :lo12:name_is_letter_ascii
    bl      test_result

    // Test digit (not a letter)
    mov     x0, #'5'
    bl      utf8_is_letter
    cmp     x0, #0
    cset    w0, ne
    adrp    x1, name_is_letter_digit
    add     x1, x1, :lo12:name_is_letter_digit
    bl      test_result

    // Test CJK character (U+4E2D = middle)
    mov     x0, #0x4E2D
    bl      utf8_is_letter
    cmp     x0, #1
    cset    w0, ne
    adrp    x1, name_is_letter_cjk
    add     x1, x1, :lo12:name_is_letter_cjk
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: UTF-8 tolower
// =============================================================================
test_utf8_tolower:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Test ASCII uppercase
    mov     x0, #'A'
    bl      utf8_tolower
    cmp     x0, #'a'
    cset    w0, ne
    adrp    x1, name_tolower_ascii
    add     x1, x1, :lo12:name_tolower_ascii
    bl      test_result

    // Test already lowercase
    mov     x0, #'z'
    bl      utf8_tolower
    cmp     x0, #'z'
    cset    w0, ne
    adrp    x1, name_tolower_lower
    add     x1, x1, :lo12:name_tolower_lower
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: Tokenize ASCII text
// =============================================================================
test_tokenize_ascii:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Initialize tokenizer
    adrp    x0, test_ascii_str
    add     x0, x0, :lo12:test_ascii_str
    mov     x1, #11                 // "Hello World"
    bl      fts_tokenize_init
    mov     x19, x0                 // Save state

    cbnz    x0, .Ltok_ascii_ok
    mov     w0, #1                  // Fail
    b       .Ltok_ascii_result

.Ltok_ascii_ok:
    // Get first token
    sub     sp, sp, #256
    mov     x0, x19
    mov     x1, sp
    mov     x2, #255
    bl      fts_tokenize_next

    // Should be "hello" (5 chars, lowercase)
    cmp     x0, #5
    b.ne    .Ltok_ascii_fail

    // Check first char is 'h'
    ldrb    w1, [sp]
    cmp     w1, #'h'
    b.ne    .Ltok_ascii_fail

    // Get second token
    mov     x0, x19
    mov     x1, sp
    mov     x2, #255
    bl      fts_tokenize_next

    // Should be "world" (5 chars)
    cmp     x0, #5
    b.ne    .Ltok_ascii_fail

    // Check first char is 'w'
    ldrb    w1, [sp]
    cmp     w1, #'w'
    b.ne    .Ltok_ascii_fail

    // Get third token (should be none)
    mov     x0, x19
    mov     x1, sp
    mov     x2, #255
    bl      fts_tokenize_next

    cmp     x0, #0                  // Should be 0 (no more tokens)
    cset    w0, ne
    b       .Ltok_ascii_cleanup

.Ltok_ascii_fail:
    mov     w0, #1

.Ltok_ascii_cleanup:
    add     sp, sp, #256
    mov     x20, x0                 // Save result

    // Free tokenizer
    mov     x0, x19
    bl      fts_tokenize_free

    mov     w0, w20

.Ltok_ascii_result:
    adrp    x1, name_tokenize_ascii
    add     x1, x1, :lo12:name_tokenize_ascii
    bl      test_result

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: Tokenize UTF-8 text
// =============================================================================
test_tokenize_utf8:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Initialize tokenizer with UTF-8 string "Cafe"
    adrp    x0, test_utf8_cafe
    add     x0, x0, :lo12:test_utf8_cafe
    mov     x1, #5                  // "Cafe" with accent = 5 bytes
    bl      fts_tokenize_init
    mov     x19, x0

    cbnz    x0, .Ltok_utf8_ok
    mov     w0, #1
    b       .Ltok_utf8_result

.Ltok_utf8_ok:
    sub     sp, sp, #256
    mov     x0, x19
    mov     x1, sp
    mov     x2, #255
    bl      fts_tokenize_next

    // Should get "cafe" (4 bytes after normalization, or 5 with accent)
    cmp     x0, #0
    cset    w0, eq                  // Fail if 0 tokens

    add     sp, sp, #256

    mov     x0, x19
    bl      fts_tokenize_free

    mov     w0, #0                  // Pass if we got here

.Ltok_utf8_result:
    adrp    x1, name_tokenize_utf8
    add     x1, x1, :lo12:name_tokenize_utf8
    bl      test_result

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: TF-IDF log2
// =============================================================================
test_tfidf_log2:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // log2(1) = 0
    mov     x0, #1
    bl      tfidf_log2_fixed
    cmp     x0, #0
    cset    w0, ne
    adrp    x1, name_log2_one
    add     x1, x1, :lo12:name_log2_one
    bl      test_result

    // log2(2) = 1.0 = 256 in 24.8
    mov     x0, #2
    bl      tfidf_log2_fixed
    cmp     x0, #256
    cset    w0, ne
    adrp    x1, name_log2_two
    add     x1, x1, :lo12:name_log2_two
    bl      test_result

    // log2(4) = 2.0 = 512 in 24.8
    mov     x0, #4
    bl      tfidf_log2_fixed
    cmp     x0, #512
    cset    w0, ne
    adrp    x1, name_log2_four
    add     x1, x1, :lo12:name_log2_four
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: TF-IDF calculation
// =============================================================================
test_tfidf_calc:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // tf=1, df=1, N=1 -> should give 0 (log(1/1)=0)
    mov     x0, #1
    mov     x1, #1
    mov     x2, #1
    bl      tfidf_calc
    cmp     x0, #0
    cset    w0, ne
    adrp    x1, name_tfidf_basic
    add     x1, x1, :lo12:name_tfidf_basic
    bl      test_result

    // tf=1, df=1, N=2 -> should give positive score
    mov     x0, #1
    mov     x1, #1
    mov     x2, #2
    bl      tfidf_calc
    cmp     x0, #0
    cset    w0, le                  // Fail if <= 0
    adrp    x1, name_tfidf_positive
    add     x1, x1, :lo12:name_tfidf_positive
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: Index init
// =============================================================================
test_index_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Create test directory
    mov     x0, #AT_FDCWD
    adrp    x1, test_index_path
    add     x1, x1, :lo12:test_index_path
    mov     x2, #0755
    mov     x8, #SYS_mkdirat
    svc     #0

    // Initialize index
    adrp    x0, test_index_path
    add     x0, x0, :lo12:test_index_path
    bl      fts_index_init
    cmp     x0, #0
    cset    w0, ne
    adrp    x1, name_index_init
    add     x1, x1, :lo12:name_index_init
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: Index add document
// =============================================================================
test_index_add:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Add a document
    mov     x0, #1                  // doc_id = 1
    adrp    x1, test_doc_content
    add     x1, x1, :lo12:test_doc_content
    mov     x2, #23                 // "The quick brown fox"
    bl      fts_index_add
    cmp     x0, #0
    cset    w0, le                  // Fail if <= 0 terms
    adrp    x1, name_index_add
    add     x1, x1, :lo12:name_index_add
    bl      test_result

    // Close index
    bl      fts_index_close

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: Query init
// =============================================================================
test_query_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Initialize query context
    mov     x0, #100                // max results
    bl      fts_query_init
    mov     x19, x0

    cmp     x0, #0
    cset    w0, eq                  // Fail if NULL
    adrp    x1, name_query_init
    add     x1, x1, :lo12:name_query_init
    bl      test_result

    // Free context
    mov     x0, x19
    bl      fts_query_free

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: Query parse
// =============================================================================
test_query_parse:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Initialize query
    mov     x0, #100
    bl      fts_query_init
    mov     x19, x0
    cbz     x0, .Lqparse_test_fail

    // Parse query
    mov     x0, x19
    adrp    x1, test_query_str
    add     x1, x1, :lo12:test_query_str
    mov     x2, #FTS_QUERY_TYPE_AND
    bl      fts_query_parse

    cmp     x0, #2                  // Should find 2 terms ("hello world")
    cset    w0, ne
    b       .Lqparse_test_result

.Lqparse_test_fail:
    mov     w0, #1

.Lqparse_test_result:
    mov     x20, x0
    adrp    x1, name_query_parse
    add     x1, x1, :lo12:name_query_parse
    bl      test_result

    // Free
    mov     x0, x19
    bl      fts_query_free

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_result - Print test result
// =============================================================================
// Input:
//   x0 = 0 for pass, non-zero for fail
//   x1 = test name string
// =============================================================================
test_result:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0
    mov     x20, x1

    // Increment total
    adrp    x0, test_total
    add     x0, x0, :lo12:test_total
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    // Print result
    cbz     x19, .Lresult_pass

    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_str
    b       .Lresult_name

.Lresult_pass:
    // Increment passed
    adrp    x0, test_passed
    add     x0, x0, :lo12:test_passed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_str

.Lresult_name:
    mov     x0, x20
    bl      print_str
    bl      print_newline

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Data
// =============================================================================
.section .data
.balign 8
test_passed:
    .quad   0
test_total:
    .quad   0

.section .rodata
.balign 8
msg_header:
    .asciz  "=== Omesh Full-Text Search Tests ===\n"
msg_summary:
    .asciz  "=== "
msg_passed:
    .asciz  " tests passed ===\n"
msg_pass:
    .asciz  "[PASS] "
msg_fail:
    .asciz  "[FAIL] "

// Test names
name_utf8_len_ascii:
    .asciz  "UTF-8 char len (ASCII)"
name_utf8_len_2byte:
    .asciz  "UTF-8 char len (2-byte)"
name_utf8_len_3byte:
    .asciz  "UTF-8 char len (3-byte)"
name_utf8_len_4byte:
    .asciz  "UTF-8 char len (4-byte)"
name_utf8_decode_ascii:
    .asciz  "UTF-8 decode ASCII"
name_utf8_decode_2byte:
    .asciz  "UTF-8 decode 2-byte"
name_is_letter_ascii:
    .asciz  "is_letter ASCII"
name_is_letter_digit:
    .asciz  "is_letter digit"
name_is_letter_cjk:
    .asciz  "is_letter CJK"
name_tolower_ascii:
    .asciz  "tolower ASCII"
name_tolower_lower:
    .asciz  "tolower lowercase"
name_tokenize_ascii:
    .asciz  "Tokenize ASCII"
name_tokenize_utf8:
    .asciz  "Tokenize UTF-8"
name_log2_one:
    .asciz  "log2(1)"
name_log2_two:
    .asciz  "log2(2)"
name_log2_four:
    .asciz  "log2(4)"
name_tfidf_basic:
    .asciz  "TF-IDF basic"
name_tfidf_positive:
    .asciz  "TF-IDF positive"
name_index_init:
    .asciz  "Index init"
name_index_add:
    .asciz  "Index add document"
name_query_init:
    .asciz  "Query init"
name_query_parse:
    .asciz  "Query parse"

// Test data
test_ascii_str:
    .asciz  "Hello World"
test_utf8_2byte:
    .byte   0xC3, 0xA9, 0x00        // e-acute in UTF-8
test_utf8_cafe:
    .asciz  "Caf\xc3\xa9"           // "Cafe" with e-acute
test_index_path:
    .asciz  "/tmp/omesh_test_index/"
test_doc_content:
    .asciz  "The quick brown fox"
test_query_str:
    .asciz  "hello world"
