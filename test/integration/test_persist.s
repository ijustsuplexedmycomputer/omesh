// =============================================================================
// Omesh - Index Persistence Integration Test
// =============================================================================
//
// Tests index save/load persistence:
// 1. Initialize FTS index
// 2. Index 3 documents
// 3. Save index to disk
// 4. Close index and clear memory
// 5. Reinitialize and load from disk
// 6. Verify terms can be found via lookup
//
// =============================================================================

.include "syscall_nums.inc"
.include "index.inc"

.data

msg_banner:
    .asciz  "=== Omesh Index Persistence Test ===\n"

msg_init:
    .asciz  "[TEST] Initializing index...\n"

msg_init_ok:
    .asciz  "[TEST] Index initialized OK\n"

msg_indexing:
    .asciz  "[TEST] Indexing documents...\n"

msg_indexed:
    .asciz  "[TEST] Indexed doc "

msg_terms:
    .asciz  " terms\n"

msg_saving:
    .asciz  "[TEST] Saving index...\n"

msg_saved:
    .asciz  "[TEST] Index saved OK\n"

msg_closing:
    .asciz  "[TEST] Closing index...\n"

msg_closed:
    .asciz  "[TEST] Index closed OK\n"

msg_reinit:
    .asciz  "[TEST] Reinitializing index...\n"

msg_loading:
    .asciz  "[TEST] Loading index from disk...\n"

msg_loaded:
    .asciz  "[TEST] Index loaded OK\n"

msg_verifying:
    .asciz  "[TEST] Verifying persisted terms...\n"

msg_lookup:
    .asciz  "[TEST] Looking up term: "

msg_found:
    .asciz  " - FOUND\n"

msg_not_found:
    .asciz  " - NOT FOUND\n"

msg_pass:
    .asciz  "\n=== Persistence test PASSED ===\n"

msg_fail:
    .asciz  "\n=== Persistence test FAILED ===\n"

msg_newline:
    .asciz  "\n"

// Test documents
doc1:
    .asciz  "hello world this is test document one"
doc1_len = . - doc1 - 1

doc2:
    .asciz  "world peace and happiness for everyone"
doc2_len = . - doc2 - 1

doc3:
    .asciz  "hello again world from document three"
doc3_len = . - doc3 - 1

// Test path (current directory)
test_path:
    .asciz  "."

// Terms to verify after load
term_hello:
    .asciz  "hello"
term_hello_len = . - term_hello - 1

term_world:
    .asciz  "world"
term_world_len = . - term_world - 1

term_peace:
    .asciz  "peace"
term_peace_len = . - term_peace - 1

.bss
.align 8
offset_out:
    .skip   8
docfreq_out:
    .skip   8

.text

// =============================================================================
// print_str - Print null-terminated string
// =============================================================================
print_str:
    mov     x2, x0
    mov     x3, #0
.Lps_len:
    ldrb    w4, [x2, x3]
    cbz     w4, .Lps_write
    add     x3, x3, #1
    b       .Lps_len
.Lps_write:
    mov     x1, x2
    mov     x2, x3
    mov     x0, #1          // stdout
    mov     x8, #SYS_write
    svc     #0
    ret

// =============================================================================
// print_dec - Print decimal number
// =============================================================================
print_dec:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    mov     x1, sp
    add     x1, x1, #32
    mov     x2, #0

    cbz     x0, .Lpd_zero

.Lpd_loop:
    cbz     x0, .Lpd_print
    mov     x3, #10
    udiv    x4, x0, x3
    msub    x5, x4, x3, x0
    add     x5, x5, #'0'
    sub     x1, x1, #1
    strb    w5, [x1]
    add     x2, x2, #1
    mov     x0, x4
    b       .Lpd_loop

.Lpd_zero:
    mov     w5, #'0'
    sub     x1, x1, #1
    strb    w5, [x1]
    mov     x2, #1

.Lpd_print:
    mov     x0, #1          // stdout
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// _start - Test entry point
// =============================================================================
.global _start
_start:
    mov     x29, sp

    // Print banner
    adrp    x0, msg_banner
    add     x0, x0, :lo12:msg_banner
    bl      print_str

    // === Phase 1: Initialize ===
    adrp    x0, msg_init
    add     x0, x0, :lo12:msg_init
    bl      print_str

    bl      hal_init
    cmp     x0, #0
    b.lt    .Ltest_fail

    adrp    x0, test_path
    add     x0, x0, :lo12:test_path
    bl      fts_index_init
    cmp     x0, #0
    b.lt    .Ltest_fail

    adrp    x0, msg_init_ok
    add     x0, x0, :lo12:msg_init_ok
    bl      print_str

    // === Phase 2: Index documents ===
    adrp    x0, msg_indexing
    add     x0, x0, :lo12:msg_indexing
    bl      print_str

    // Index doc1
    mov     x0, #1                  // doc_id
    adrp    x1, doc1
    add     x1, x1, :lo12:doc1
    mov     x2, #doc1_len
    bl      fts_index_add
    cmp     x0, #0
    b.lt    .Ltest_fail

    mov     x19, x0                 // Save term count
    adrp    x0, msg_indexed
    add     x0, x0, :lo12:msg_indexed
    bl      print_str
    mov     x0, #1
    bl      print_dec
    adrp    x0, msg_terms
    add     x0, x0, :lo12:msg_terms
    bl      print_str

    // Index doc2
    mov     x0, #2                  // doc_id
    adrp    x1, doc2
    add     x1, x1, :lo12:doc2
    mov     x2, #doc2_len
    bl      fts_index_add
    cmp     x0, #0
    b.lt    .Ltest_fail

    adrp    x0, msg_indexed
    add     x0, x0, :lo12:msg_indexed
    bl      print_str
    mov     x0, #2
    bl      print_dec
    adrp    x0, msg_terms
    add     x0, x0, :lo12:msg_terms
    bl      print_str

    // Index doc3
    mov     x0, #3                  // doc_id
    adrp    x1, doc3
    add     x1, x1, :lo12:doc3
    mov     x2, #doc3_len
    bl      fts_index_add
    cmp     x0, #0
    b.lt    .Ltest_fail

    adrp    x0, msg_indexed
    add     x0, x0, :lo12:msg_indexed
    bl      print_str
    mov     x0, #3
    bl      print_dec
    adrp    x0, msg_terms
    add     x0, x0, :lo12:msg_terms
    bl      print_str

    // === Phase 3: Save index ===
    adrp    x0, msg_saving
    add     x0, x0, :lo12:msg_saving
    bl      print_str

    bl      fts_index_save
    cmp     x0, #0
    b.lt    .Ltest_fail

    adrp    x0, msg_saved
    add     x0, x0, :lo12:msg_saved
    bl      print_str

    // === Phase 4: Close index ===
    adrp    x0, msg_closing
    add     x0, x0, :lo12:msg_closing
    bl      print_str

    bl      fts_index_close

    adrp    x0, msg_closed
    add     x0, x0, :lo12:msg_closed
    bl      print_str

    // === Phase 5: Reinitialize and load ===
    adrp    x0, msg_reinit
    add     x0, x0, :lo12:msg_reinit
    bl      print_str

    adrp    x0, test_path
    add     x0, x0, :lo12:test_path
    bl      fts_index_init
    cmp     x0, #0
    b.lt    .Ltest_fail

    adrp    x0, msg_loading
    add     x0, x0, :lo12:msg_loading
    bl      print_str

    bl      fts_index_load
    // Note: returns term count, not error code (0 = no index, positive = count)

    adrp    x0, msg_loaded
    add     x0, x0, :lo12:msg_loaded
    bl      print_str

    // === Phase 6: Verify terms ===
    adrp    x0, msg_verifying
    add     x0, x0, :lo12:msg_verifying
    bl      print_str

    mov     x20, #0                 // Failed lookups counter

    // Look up "hello"
    adrp    x0, msg_lookup
    add     x0, x0, :lo12:msg_lookup
    bl      print_str
    adrp    x0, term_hello
    add     x0, x0, :lo12:term_hello
    bl      print_str

    adrp    x0, term_hello
    add     x0, x0, :lo12:term_hello
    mov     x1, #term_hello_len
    adrp    x2, offset_out
    add     x2, x2, :lo12:offset_out
    adrp    x3, docfreq_out
    add     x3, x3, :lo12:docfreq_out
    bl      fts_index_lookup
    cmp     x0, #0
    b.ne    .Lhello_not_found

    adrp    x0, msg_found
    add     x0, x0, :lo12:msg_found
    bl      print_str
    b       .Lcheck_world

.Lhello_not_found:
    adrp    x0, msg_not_found
    add     x0, x0, :lo12:msg_not_found
    bl      print_str
    add     x20, x20, #1

.Lcheck_world:
    // Look up "world"
    adrp    x0, msg_lookup
    add     x0, x0, :lo12:msg_lookup
    bl      print_str
    adrp    x0, term_world
    add     x0, x0, :lo12:term_world
    bl      print_str

    adrp    x0, term_world
    add     x0, x0, :lo12:term_world
    mov     x1, #term_world_len
    adrp    x2, offset_out
    add     x2, x2, :lo12:offset_out
    adrp    x3, docfreq_out
    add     x3, x3, :lo12:docfreq_out
    bl      fts_index_lookup
    cmp     x0, #0
    b.ne    .Lworld_not_found

    adrp    x0, msg_found
    add     x0, x0, :lo12:msg_found
    bl      print_str
    b       .Lcheck_peace

.Lworld_not_found:
    adrp    x0, msg_not_found
    add     x0, x0, :lo12:msg_not_found
    bl      print_str
    add     x20, x20, #1

.Lcheck_peace:
    // Look up "peace"
    adrp    x0, msg_lookup
    add     x0, x0, :lo12:msg_lookup
    bl      print_str
    adrp    x0, term_peace
    add     x0, x0, :lo12:term_peace
    bl      print_str

    adrp    x0, term_peace
    add     x0, x0, :lo12:term_peace
    mov     x1, #term_peace_len
    adrp    x2, offset_out
    add     x2, x2, :lo12:offset_out
    adrp    x3, docfreq_out
    add     x3, x3, :lo12:docfreq_out
    bl      fts_index_lookup
    cmp     x0, #0
    b.ne    .Lpeace_not_found

    adrp    x0, msg_found
    add     x0, x0, :lo12:msg_found
    bl      print_str
    b       .Lcheck_results

.Lpeace_not_found:
    adrp    x0, msg_not_found
    add     x0, x0, :lo12:msg_not_found
    bl      print_str
    add     x20, x20, #1

.Lcheck_results:
    // Clean up
    bl      fts_index_close

    // Check if all terms were found
    cbnz    x20, .Ltest_fail

    // SUCCESS
    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_str

    mov     x0, #0
    mov     x8, #SYS_exit
    svc     #0

.Ltest_fail:
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_str

    mov     x0, #1
    mov     x8, #SYS_exit
    svc     #0
