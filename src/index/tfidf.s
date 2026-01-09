// =============================================================================
// Omesh - TF-IDF Scoring Implementation
// =============================================================================
//
// This module provides TF-IDF scoring for search result ranking:
// - Fixed-point arithmetic (24.8 format)
// - Log2 computation via lookup table
// - BM25-style length normalization (optional)
//
// Formula: score = tf * log2(N / df)
//   where tf = term frequency in document
//         N  = total documents in corpus
//         df = document frequency (docs containing term)
//
// =============================================================================

.include "syscall_nums.inc"
.include "index.inc"

.text

// =============================================================================
// tfidf_log2_fixed - Calculate log2 in fixed-point (24.8)
// =============================================================================
// Input:
//   x0 = value (positive integer, > 0)
// Output:
//   x0 = log2(value) * 256 (24.8 fixed-point)
// =============================================================================
.global tfidf_log2_fixed
.type tfidf_log2_fixed, %function
tfidf_log2_fixed:
    // Handle edge cases
    cmp     x0, #0
    b.le    .Llog2_zero

    cmp     x0, #1
    b.eq    .Llog2_one

    // Find highest set bit (integer part of log2)
    clz     x1, x0                  // Count leading zeros
    mov     x2, #63
    sub     x2, x2, x1              // Bit position = 63 - clz

    // Integer part: shift left by 8 for fixed-point
    lsl     x3, x2, #8              // int_part * 256

    // Fractional part via lookup table
    // Normalize to range [1, 2) by shifting
    sub     x4, x2, #0              // Shift amount
    cbz     x4, .Llog2_no_shift
    lsr     x5, x0, x4              // Normalize: x0 >> bit_pos
    b       .Llog2_frac
.Llog2_no_shift:
    mov     x5, x0

.Llog2_frac:
    // x5 is now in range [1, 2) represented as integer
    // For simplicity, use linear interpolation between powers of 2
    // frac = (x5 - (1 << bit_pos)) * 256 / (1 << bit_pos)

    // Simplified: if we have remaining bits, interpolate
    mov     x6, #1
    lsl     x6, x6, x2              // 2^bit_pos
    sub     x7, x0, x6              // remainder = x0 - 2^bit_pos

    cbz     x7, .Llog2_exact        // Exact power of 2

    // Approximate fractional part
    // frac_part = (remainder * 256) / 2^bit_pos
    lsl     x7, x7, #8              // remainder * 256
    lsr     x7, x7, x2              // / 2^bit_pos

    add     x0, x3, x7              // int_part + frac_part
    ret

.Llog2_exact:
    mov     x0, x3
    ret

.Llog2_zero:
.Llog2_one:
    mov     x0, #0                  // log2(1) = 0, log2(0) = undefined (return 0)
    ret
.size tfidf_log2_fixed, .-tfidf_log2_fixed

// =============================================================================
// tfidf_calc - Calculate TF-IDF score
// =============================================================================
// Input:
//   x0 = term frequency in document
//   x1 = document frequency (docs containing term)
//   x2 = total documents in corpus
// Output:
//   x0 = TF-IDF score (24.8 fixed-point)
// =============================================================================
.global tfidf_calc
.type tfidf_calc, %function
tfidf_calc:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                 // tf
    mov     x20, x1                 // df
    mov     x21, x2                 // N

    // Handle edge cases
    cbz     x19, .Ltfidf_zero       // tf = 0 -> score = 0
    cbz     x20, .Ltfidf_zero       // df = 0 -> invalid
    cbz     x21, .Ltfidf_zero       // N = 0 -> invalid

    // Calculate TF component with log dampening
    // tf_score = 1 + log2(tf) in fixed-point
    mov     x0, x19
    bl      tfidf_log2_fixed
    add     x19, x0, #TFIDF_SCALE   // 1.0 + log2(tf) in 24.8

    // Calculate IDF: log2(N / df)
    // To avoid division, we compute log2(N) - log2(df)
    mov     x0, x21
    bl      tfidf_log2_fixed
    mov     x22, x0                 // log2(N)

    mov     x0, x20
    bl      tfidf_log2_fixed
    sub     x22, x22, x0            // log2(N) - log2(df) = log2(N/df)

    // IDF should be non-negative
    cmp     x22, #0
    csel    x22, xzr, x22, lt       // if negative, use 0

    // Final score = tf_score * idf
    // Both are in 24.8 format, so multiply and shift right 8
    mul     x0, x19, x22
    lsr     x0, x0, #TFIDF_FRAC_BITS

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

.Ltfidf_zero:
    mov     x0, #0
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size tfidf_calc, .-tfidf_calc

// =============================================================================
// tfidf_normalize_score - Normalize score for document length (BM25-style)
// =============================================================================
// Input:
//   x0 = raw TF-IDF score (24.8 fixed-point)
//   x1 = document length (token count)
//   x2 = average document length (16.16 fixed-point)
// Output:
//   x0 = normalized score (24.8 fixed-point)
//
// Formula: score / (k1 * (1 - b + b * (doc_len / avg_len)))
//   where k1 = 1.2, b = 0.75 (BM25 parameters)
// =============================================================================
.global tfidf_normalize_score
.type tfidf_normalize_score, %function
tfidf_normalize_score:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                 // raw score
    mov     x3, x1                  // doc_len
    mov     x4, x2                  // avg_len (16.16)

    // Handle edge cases
    cbz     x19, .Lnorm_zero
    cbz     x4, .Lnorm_passthrough  // No avg_len, skip normalization

    // Calculate doc_len / avg_len (result in 24.8)
    // doc_len is integer, avg_len is 16.16
    // (doc_len << 24) / avg_len gives 24.8 result
    lsl     x5, x3, #24
    udiv    x5, x5, x4              // length ratio in 24.8

    // Calculate: 1 - b + b * (doc_len / avg_len)
    // b = 0.75 = 192/256, (1-b) = 0.25 = 64/256
    // All in 24.8: 64 + (192 * ratio) >> 8

    mov     x6, #BM25_B             // 192 = 0.75 * 256
    mul     x6, x6, x5              // b * ratio (in 24.16)
    lsr     x6, x6, #8              // back to 24.8

    mov     x7, #(TFIDF_SCALE - BM25_B)  // 64 = 0.25 * 256
    add     x6, x6, x7              // (1-b) + b * ratio

    // Multiply by k1 = 1.2 = 307/256
    mov     x7, #BM25_K1            // 307
    mul     x6, x6, x7
    lsr     x6, x6, #8              // k1 * (1-b + b*ratio)

    // Avoid division by zero
    cmp     x6, #1
    csel    x6, x6, x7, gt          // Use k1 if denominator too small
    mov     x7, #1
    csel    x6, x7, x6, lt

    // Final: score / denominator
    // score is 24.8, denominator is 24.8
    // (score << 8) / denominator gives 24.8 result
    lsl     x0, x19, #8
    udiv    x0, x0, x6

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lnorm_zero:
    mov     x0, #0
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

.Lnorm_passthrough:
    mov     x0, x19
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size tfidf_normalize_score, .-tfidf_normalize_score

// =============================================================================
// tfidf_combine_scores - Combine multiple term scores
// =============================================================================
// Input:
//   x0 = scores array pointer (24.8 fixed-point values)
//   x1 = score count
// Output:
//   x0 = combined score (sum, 24.8 fixed-point)
// =============================================================================
.global tfidf_combine_scores
.type tfidf_combine_scores, %function
tfidf_combine_scores:
    cbz     x1, .Lcombine_empty

    mov     x2, #0                  // Accumulator

.Lcombine_loop:
    ldr     x3, [x0], #8            // Load score
    add     x2, x2, x3              // Add to accumulator
    subs    x1, x1, #1
    b.ne    .Lcombine_loop

    mov     x0, x2
    ret

.Lcombine_empty:
    mov     x0, #0
    ret
.size tfidf_combine_scores, .-tfidf_combine_scores

// =============================================================================
// tfidf_score_to_int - Convert fixed-point score to integer for display
// =============================================================================
// Input:
//   x0 = score (24.8 fixed-point)
// Output:
//   x0 = integer part
//   x1 = fractional part (0-255)
// =============================================================================
.global tfidf_score_to_int
.type tfidf_score_to_int, %function
tfidf_score_to_int:
    and     x1, x0, #0xFF           // Fractional part
    lsr     x0, x0, #8              // Integer part
    ret
.size tfidf_score_to_int, .-tfidf_score_to_int
