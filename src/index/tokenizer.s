// =============================================================================
// Omesh - UTF-8 Aware Tokenizer
// =============================================================================
//
// This module provides UTF-8 aware word tokenization for full-text indexing.
// Features:
//   - Proper multi-byte UTF-8 character handling
//   - Unicode-aware word boundary detection
//   - Lowercase normalization
//   - Position tracking for phrase search
//
// =============================================================================

.include "syscall_nums.inc"
.include "index.inc"

.text

// =============================================================================
// utf8_char_len - Get length of UTF-8 character from first byte
// =============================================================================
// Input:
//   x0 = first byte of UTF-8 sequence (0-255)
// Output:
//   x0 = character length (1-4), or 0 if invalid
// =============================================================================
.global utf8_char_len
.type utf8_char_len, %function
utf8_char_len:
    // Check for ASCII (0xxxxxxx)
    tst     w0, #0x80
    b.ne    .Lutf8_multi

    // ASCII: single byte
    mov     x0, #1
    ret

.Lutf8_multi:
    // Check for continuation byte (10xxxxxx) - invalid as start
    and     w1, w0, #UTF8_CONT_MASK
    cmp     w1, #UTF8_CONT_VAL
    b.eq    .Lutf8_invalid

    // Check for 2-byte (110xxxxx)
    and     w1, w0, #UTF8_2BYTE_MASK
    cmp     w1, #UTF8_2BYTE_VAL
    b.eq    .Lutf8_2byte

    // Check for 3-byte (1110xxxx)
    and     w1, w0, #UTF8_3BYTE_MASK
    cmp     w1, #UTF8_3BYTE_VAL
    b.eq    .Lutf8_3byte

    // Check for 4-byte (11110xxx)
    and     w1, w0, #UTF8_4BYTE_MASK
    cmp     w1, #UTF8_4BYTE_VAL
    b.eq    .Lutf8_4byte

.Lutf8_invalid:
    mov     x0, #0
    ret

.Lutf8_2byte:
    mov     x0, #2
    ret

.Lutf8_3byte:
    mov     x0, #3
    ret

.Lutf8_4byte:
    mov     x0, #4
    ret
.size utf8_char_len, .-utf8_char_len

// =============================================================================
// utf8_decode - Decode UTF-8 sequence to Unicode codepoint
// =============================================================================
// Input:
//   x0 = pointer to UTF-8 bytes
//   x1 = max bytes available
// Output:
//   x0 = codepoint (or -EILSEQ if invalid)
//   x1 = bytes consumed
// =============================================================================
.global utf8_decode
.type utf8_decode, %function
utf8_decode:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    cbz     x1, .Ldecode_invalid    // No bytes available

    ldrb    w2, [x0]                // First byte

    // ASCII fast path
    tst     w2, #0x80
    b.ne    .Ldecode_multi

    mov     x0, x2                  // Codepoint = byte value
    mov     x1, #1                  // 1 byte consumed
    ldp     x29, x30, [sp], #16
    ret

.Ldecode_multi:
    // Check for continuation byte (invalid as start)
    and     w3, w2, #UTF8_CONT_MASK
    cmp     w3, #UTF8_CONT_VAL
    b.eq    .Ldecode_invalid

    // Determine length and validate
    and     w3, w2, #UTF8_2BYTE_MASK
    cmp     w3, #UTF8_2BYTE_VAL
    b.eq    .Ldecode_2byte

    and     w3, w2, #UTF8_3BYTE_MASK
    cmp     w3, #UTF8_3BYTE_VAL
    b.eq    .Ldecode_3byte

    and     w3, w2, #UTF8_4BYTE_MASK
    cmp     w3, #UTF8_4BYTE_VAL
    b.eq    .Ldecode_4byte

    b       .Ldecode_invalid

.Ldecode_2byte:
    cmp     x1, #2
    b.lt    .Ldecode_invalid

    ldrb    w3, [x0, #1]
    and     w4, w3, #UTF8_CONT_MASK
    cmp     w4, #UTF8_CONT_VAL
    b.ne    .Ldecode_invalid

    // Extract: 110xxxxx 10xxxxxx
    and     w2, w2, #0x1F           // Low 5 bits of first byte
    and     w3, w3, #0x3F           // Low 6 bits of second byte
    lsl     w2, w2, #6
    orr     w0, w2, w3
    mov     x1, #2
    ldp     x29, x30, [sp], #16
    ret

.Ldecode_3byte:
    cmp     x1, #3
    b.lt    .Ldecode_invalid

    ldrb    w3, [x0, #1]
    ldrb    w4, [x0, #2]

    // Validate continuation bytes
    and     w5, w3, #UTF8_CONT_MASK
    cmp     w5, #UTF8_CONT_VAL
    b.ne    .Ldecode_invalid
    and     w5, w4, #UTF8_CONT_MASK
    cmp     w5, #UTF8_CONT_VAL
    b.ne    .Ldecode_invalid

    // Extract: 1110xxxx 10xxxxxx 10xxxxxx
    and     w2, w2, #0x0F           // Low 4 bits
    and     w3, w3, #0x3F           // Low 6 bits
    and     w4, w4, #0x3F           // Low 6 bits
    lsl     w2, w2, #12
    lsl     w3, w3, #6
    orr     w0, w2, w3
    orr     w0, w0, w4
    mov     x1, #3
    ldp     x29, x30, [sp], #16
    ret

.Ldecode_4byte:
    cmp     x1, #4
    b.lt    .Ldecode_invalid

    ldrb    w3, [x0, #1]
    ldrb    w4, [x0, #2]
    ldrb    w5, [x0, #3]

    // Validate continuation bytes
    and     w6, w3, #UTF8_CONT_MASK
    cmp     w6, #UTF8_CONT_VAL
    b.ne    .Ldecode_invalid
    and     w6, w4, #UTF8_CONT_MASK
    cmp     w6, #UTF8_CONT_VAL
    b.ne    .Ldecode_invalid
    and     w6, w5, #UTF8_CONT_MASK
    cmp     w6, #UTF8_CONT_VAL
    b.ne    .Ldecode_invalid

    // Extract: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    and     w2, w2, #0x07           // Low 3 bits
    and     w3, w3, #0x3F           // Low 6 bits
    and     w4, w4, #0x3F           // Low 6 bits
    and     w5, w5, #0x3F           // Low 6 bits
    lsl     w2, w2, #18
    lsl     w3, w3, #12
    lsl     w4, w4, #6
    orr     w0, w2, w3
    orr     w0, w0, w4
    orr     w0, w0, w5
    mov     x1, #4
    ldp     x29, x30, [sp], #16
    ret

.Ldecode_invalid:
    mov     x0, #-EILSEQ
    mov     x1, #0
    ldp     x29, x30, [sp], #16
    ret
.size utf8_decode, .-utf8_decode

// =============================================================================
// utf8_is_letter - Check if codepoint is a letter
// =============================================================================
// Input:
//   x0 = Unicode codepoint
// Output:
//   x0 = 1 if letter, 0 otherwise
// =============================================================================
.global utf8_is_letter
.type utf8_is_letter, %function
utf8_is_letter:
    // ASCII uppercase A-Z (0x41-0x5A)
    cmp     w0, #0x41
    b.lt    .Lis_letter_check_lower
    cmp     w0, #0x5A
    b.le    .Lis_letter_yes

.Lis_letter_check_lower:
    // ASCII lowercase a-z (0x61-0x7A)
    cmp     w0, #0x61
    b.lt    .Lis_letter_extended
    cmp     w0, #0x7A
    b.le    .Lis_letter_yes

.Lis_letter_extended:
    // Latin Extended (0x00C0-0x024F)
    cmp     w0, #0x00C0
    b.lt    .Lis_letter_cjk
    cmp     w0, #0x024F
    b.le    .Lis_letter_yes

.Lis_letter_cjk:
    // CJK Unified Ideographs (0x4E00-0x9FFF)
    ldr     w1, =0x4E00
    cmp     w0, w1
    b.lt    .Lis_letter_hiragana
    ldr     w1, =0x9FFF
    cmp     w0, w1
    b.le    .Lis_letter_yes

.Lis_letter_hiragana:
    // Hiragana (0x3040-0x309F)
    ldr     w1, =0x3040
    cmp     w0, w1
    b.lt    .Lis_letter_katakana
    ldr     w1, =0x309F
    cmp     w0, w1
    b.le    .Lis_letter_yes

.Lis_letter_katakana:
    // Katakana (0x30A0-0x30FF)
    ldr     w1, =0x30A0
    cmp     w0, w1
    b.lt    .Lis_letter_no
    ldr     w1, =0x30FF
    cmp     w0, w1
    b.le    .Lis_letter_yes

.Lis_letter_no:
    mov     x0, #0
    ret

.Lis_letter_yes:
    mov     x0, #1
    ret
.size utf8_is_letter, .-utf8_is_letter

// =============================================================================
// utf8_is_digit - Check if codepoint is a digit
// =============================================================================
// Input:
//   x0 = Unicode codepoint
// Output:
//   x0 = 1 if digit, 0 otherwise
// =============================================================================
.global utf8_is_digit
.type utf8_is_digit, %function
utf8_is_digit:
    // ASCII digits 0-9 (0x30-0x39)
    cmp     w0, #0x30
    b.lt    .Lis_digit_no
    cmp     w0, #0x39
    b.le    .Lis_digit_yes

.Lis_digit_no:
    mov     x0, #0
    ret

.Lis_digit_yes:
    mov     x0, #1
    ret
.size utf8_is_digit, .-utf8_is_digit

// =============================================================================
// utf8_tolower - Convert codepoint to lowercase
// =============================================================================
// Input:
//   x0 = Unicode codepoint
// Output:
//   x0 = lowercase codepoint
// =============================================================================
.global utf8_tolower
.type utf8_tolower, %function
utf8_tolower:
    // ASCII uppercase A-Z -> lowercase a-z
    cmp     w0, #0x41               // 'A'
    b.lt    .Ltolower_extended
    cmp     w0, #0x5A               // 'Z'
    b.gt    .Ltolower_extended

    add     w0, w0, #0x20           // A->a offset
    ret

.Ltolower_extended:
    // Latin-1 uppercase (0x00C0-0x00DE, except 0x00D7 multiplication sign)
    cmp     w0, #0x00C0
    b.lt    .Ltolower_done
    cmp     w0, #0x00DE
    b.gt    .Ltolower_latin_ext
    cmp     w0, #0x00D7             // Skip multiplication sign
    b.eq    .Ltolower_done

    add     w0, w0, #0x20           // Same offset as ASCII
    ret

.Ltolower_latin_ext:
    // Latin Extended-A (0x0100-0x017F) - alternating upper/lower
    cmp     w0, #0x0100
    b.lt    .Ltolower_done
    cmp     w0, #0x017F
    b.gt    .Ltolower_done

    // Even codepoints are uppercase, odd are lowercase
    tst     w0, #1
    b.ne    .Ltolower_done          // Already lowercase
    add     w0, w0, #1              // Make lowercase
    ret

.Ltolower_done:
    ret
.size utf8_tolower, .-utf8_tolower

// =============================================================================
// fts_tokenize_init - Initialize tokenizer for a document
// =============================================================================
// Input:
//   x0 = document content pointer
//   x1 = document length
// Output:
//   x0 = tokenizer state pointer on success, NULL on error
// =============================================================================
.global fts_tokenize_init
.type fts_tokenize_init, %function
fts_tokenize_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                 // Save content ptr
    mov     x20, x1                 // Save length

    // Allocate tokenizer state via mmap
    mov     x0, #0                  // addr hint
    mov     x1, #TOK_STATE_SIZE
    mov     x2, #(PROT_READ | PROT_WRITE)
    mov     x3, #(MAP_PRIVATE | MAP_ANONYMOUS)
    mov     x4, #-1                 // fd
    mov     x5, #0                  // offset
    bl      sys_mmap

    cmn     x0, #4096
    b.hi    .Ltok_init_error

    // Initialize state
    str     x19, [x0, #TOK_STATE_OFF_CONTENT]
    str     x20, [x0, #TOK_STATE_OFF_LENGTH]
    str     xzr, [x0, #TOK_STATE_OFF_POSITION]
    str     xzr, [x0, #TOK_STATE_OFF_TOKEN_POS]
    str     xzr, [x0, #TOK_STATE_OFF_FLAGS]

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Ltok_init_error:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size fts_tokenize_init, .-fts_tokenize_init

// =============================================================================
// fts_tokenize_free - Free tokenizer state
// =============================================================================
// Input:
//   x0 = tokenizer state pointer
// Output:
//   x0 = 0 on success
// =============================================================================
.global fts_tokenize_free
.type fts_tokenize_free, %function
fts_tokenize_free:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    cbz     x0, .Ltok_free_done

    mov     x1, #TOK_STATE_SIZE
    bl      sys_munmap

.Ltok_free_done:
    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret
.size fts_tokenize_free, .-fts_tokenize_free

// =============================================================================
// fts_tokenize_next - Get next token from document
// =============================================================================
// Input:
//   x0 = tokenizer state pointer
//   x1 = output buffer for normalized token
//   x2 = output buffer size
// Output:
//   x0 = token length on success, 0 if no more tokens, negative errno on error
//   x1 = byte position in document (for positional index)
// =============================================================================
.global fts_tokenize_next
.type fts_tokenize_next, %function
fts_tokenize_next:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                 // State pointer
    mov     x20, x1                 // Output buffer
    mov     x21, x2                 // Buffer size
    mov     x22, #0                 // Token length

    // Load state
    ldr     x23, [x19, #TOK_STATE_OFF_CONTENT]    // Content ptr
    ldr     x24, [x19, #TOK_STATE_OFF_LENGTH]     // Content length
    ldr     x0, [x19, #TOK_STATE_OFF_POSITION]    // Current position

    // Skip non-word characters
.Ltok_skip_loop:
    cmp     x0, x24
    b.ge    .Ltok_no_more

    add     x1, x23, x0             // Current byte ptr
    sub     x2, x24, x0             // Remaining bytes

    // Get character length
    ldrb    w3, [x1]
    stp     x0, x1, [sp, #-16]!
    mov     x0, x3
    bl      utf8_char_len
    mov     x4, x0                  // Char length
    ldp     x0, x1, [sp], #16

    cbz     x4, .Ltok_skip_invalid  // Invalid UTF-8, skip byte

    // Decode codepoint
    stp     x0, x4, [sp, #-16]!
    mov     x0, x1
    sub     x1, x24, x0
    add     x1, x1, x23             // Remaining = length - (ptr - content)
    ldr     x1, [x19, #TOK_STATE_OFF_LENGTH]
    ldr     x2, [x19, #TOK_STATE_OFF_POSITION]
    sub     x1, x1, x2              // Remaining bytes
    bl      utf8_decode
    mov     x5, x0                  // Codepoint
    ldp     x0, x4, [sp], #16

    // Check if word character (letter or digit)
    stp     x0, x4, [sp, #-16]!
    stp     x5, xzr, [sp, #-16]!
    mov     x0, x5
    bl      utf8_is_letter
    cbnz    x0, .Ltok_skip_found_word

    ldp     x5, xzr, [sp]
    mov     x0, x5
    bl      utf8_is_digit
    cbnz    x0, .Ltok_skip_found_word   // FIX: pop x5 via .Ltok_skip_found_word

    // Not a word char, skip
    ldp     x5, xzr, [sp], #16
    ldp     x0, x4, [sp], #16
    add     x0, x0, x4
    b       .Ltok_skip_loop

.Ltok_skip_found_word:
    add     sp, sp, #16             // Pop x5
.Ltok_skip_found_word_pop:
    ldp     x0, x4, [sp], #16
    b       .Ltok_collect_start

.Ltok_skip_invalid:
    add     x0, x0, #1              // Skip one byte
    b       .Ltok_skip_loop

.Ltok_collect_start:
    // x0 = position of token start
    // Save token start position for return
    mov     x6, x0                  // Token start byte position

    // Collect word characters
.Ltok_collect_loop:
    cmp     x0, x24
    b.ge    .Ltok_collect_done
    cmp     x22, x21
    b.ge    .Ltok_collect_done      // Buffer full

    add     x1, x23, x0             // Current byte ptr

    // Get character length
    ldrb    w3, [x1]
    stp     x0, x6, [sp, #-16]!
    mov     x0, x3
    bl      utf8_char_len
    mov     x4, x0                  // Char length
    ldp     x0, x6, [sp], #16

    cbz     x4, .Ltok_collect_done  // Invalid UTF-8, end token

    // Decode codepoint
    stp     x0, x4, [sp, #-16]!
    stp     x6, xzr, [sp, #-16]!
    add     x0, x23, x0
    sub     x1, x24, x0
    add     x1, x1, x23
    ldr     x1, [x19, #TOK_STATE_OFF_LENGTH]
    ldr     x2, [x19, #TOK_STATE_OFF_POSITION]
    ldp     x2, xzr, [sp, #16]      // Get saved position from stack
    sub     x1, x24, x2             // Remaining bytes
    bl      utf8_decode
    mov     x5, x0                  // Codepoint
    mov     x7, x1                  // Bytes consumed
    ldp     x6, xzr, [sp], #16
    ldp     x0, x4, [sp], #16

    // Check if word character
    stp     x0, x4, [sp, #-16]!
    stp     x5, x6, [sp, #-16]!
    stp     x7, xzr, [sp, #-16]!
    mov     x0, x5
    bl      utf8_is_letter
    cbnz    x0, .Ltok_collect_word_char

    ldp     x7, xzr, [sp]
    ldp     x5, x6, [sp, #16]
    mov     x0, x5
    bl      utf8_is_digit
    cbz     x0, .Ltok_collect_not_word

.Ltok_collect_word_char:
    ldp     x7, xzr, [sp], #16
    ldp     x5, x6, [sp], #16
    ldp     x0, x4, [sp], #16

    // Convert to lowercase
    stp     x0, x4, [sp, #-16]!
    stp     x5, x6, [sp, #-16]!
    stp     x7, xzr, [sp, #-16]!
    mov     x0, x5
    bl      utf8_tolower
    mov     x5, x0                  // Lowercase codepoint
    ldp     x7, xzr, [sp], #16
    ldp     x8, x6, [sp], #16       // x8 = original codepoint (unused now)
    ldp     x0, x4, [sp], #16

    // Encode lowercase codepoint to output buffer
    // For simplicity, we re-encode as UTF-8
    cmp     x5, #0x7F
    b.gt    .Ltok_encode_multi

    // ASCII: single byte
    strb    w5, [x20, x22]
    add     x22, x22, #1
    add     x0, x0, x7              // Advance by bytes consumed
    b       .Ltok_collect_loop

.Ltok_encode_multi:
    cmp     x5, #0x7FF
    b.gt    .Ltok_encode_3byte

    // 2-byte encoding: 110xxxxx 10xxxxxx
    cmp     x22, x21
    b.ge    .Ltok_collect_done      // Need 2 bytes
    sub     x8, x21, x22
    cmp     x8, #2
    b.lt    .Ltok_collect_done

    lsr     w8, w5, #6
    orr     w8, w8, #0xC0
    strb    w8, [x20, x22]
    add     x22, x22, #1
    and     w8, w5, #0x3F
    orr     w8, w8, #0x80
    strb    w8, [x20, x22]
    add     x22, x22, #1
    add     x0, x0, x7
    b       .Ltok_collect_loop

.Ltok_encode_3byte:
    ldr     x6, =0xFFFF
    cmp     x5, x6
    b.gt    .Ltok_encode_4byte

    // 3-byte encoding: 1110xxxx 10xxxxxx 10xxxxxx
    sub     x8, x21, x22
    cmp     x8, #3
    b.lt    .Ltok_collect_done

    lsr     w8, w5, #12
    orr     w8, w8, #0xE0
    strb    w8, [x20, x22]
    add     x22, x22, #1
    lsr     w8, w5, #6
    and     w8, w8, #0x3F
    orr     w8, w8, #0x80
    strb    w8, [x20, x22]
    add     x22, x22, #1
    and     w8, w5, #0x3F
    orr     w8, w8, #0x80
    strb    w8, [x20, x22]
    add     x22, x22, #1
    add     x0, x0, x7
    b       .Ltok_collect_loop

.Ltok_encode_4byte:
    // 4-byte encoding: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    sub     x8, x21, x22
    cmp     x8, #4
    b.lt    .Ltok_collect_done

    lsr     w8, w5, #18
    orr     w8, w8, #0xF0
    strb    w8, [x20, x22]
    add     x22, x22, #1
    lsr     w8, w5, #12
    and     w8, w8, #0x3F
    orr     w8, w8, #0x80
    strb    w8, [x20, x22]
    add     x22, x22, #1
    lsr     w8, w5, #6
    and     w8, w8, #0x3F
    orr     w8, w8, #0x80
    strb    w8, [x20, x22]
    add     x22, x22, #1
    and     w8, w5, #0x3F
    orr     w8, w8, #0x80
    strb    w8, [x20, x22]
    add     x22, x22, #1
    add     x0, x0, x7
    b       .Ltok_collect_loop

.Ltok_collect_not_word:
    // End of word
    ldp     x7, xzr, [sp], #16
    ldp     x5, x6, [sp], #16
    ldp     x0, x4, [sp], #16
    // Fall through to done

.Ltok_collect_done:
    // Update state
    str     x0, [x19, #TOK_STATE_OFF_POSITION]

    // Increment token position counter
    ldr     x1, [x19, #TOK_STATE_OFF_TOKEN_POS]
    add     x1, x1, #1
    str     x1, [x19, #TOK_STATE_OFF_TOKEN_POS]

    // Null-terminate if space
    cmp     x22, x21
    b.ge    .Ltok_return
    strb    wzr, [x20, x22]

.Ltok_return:
    mov     x0, x22                 // Return token length
    mov     x1, x6                  // Return byte position

    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret

.Ltok_no_more:
    // Update position to end
    str     x24, [x19, #TOK_STATE_OFF_POSITION]

    mov     x0, #0                  // No more tokens
    mov     x1, #0

    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size fts_tokenize_next, .-fts_tokenize_next

// =============================================================================
// fts_tokenize_get_position - Get current token position (word count)
// =============================================================================
// Input:
//   x0 = tokenizer state pointer
// Output:
//   x0 = current token position
// =============================================================================
.global fts_tokenize_get_position
.type fts_tokenize_get_position, %function
fts_tokenize_get_position:
    ldr     x0, [x0, #TOK_STATE_OFF_TOKEN_POS]
    ret
.size fts_tokenize_get_position, .-fts_tokenize_get_position
