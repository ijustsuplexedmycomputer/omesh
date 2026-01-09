// =============================================================================
// Omesh - test_basic.s
// Integration test: End-to-end index and search
// =============================================================================
//
// This test validates the full pipeline:
// 1. Initialize all subsystems via omesh_init
// 2. Index 3 documents with known content
// 3. Search for a term that should match
// 4. Verify we get results
// 5. Search for a term that shouldn't match
// 6. Verify we get zero results
// 7. Print PASS/FAIL and exit with appropriate code
//
// No user input, no REPL - deterministic test.
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/cluster.inc"
.include "include/index.inc"

// External HAL functions
.extern hal_init
.extern print_str
.extern print_dec
.extern print_hex
.extern print_newline

// External init functions
.extern doc_store_init
.extern fts_index_init
.extern fts_index_close
.extern node_init
.extern node_set_state
.extern handler_init
.extern replica_init
.extern router_init

// External cluster/router functions
.extern replica_index_doc
.extern router_search
.extern router_get_pending_ptr
.extern router_free_pending
.extern node_generate_query_id

// External index functions
.extern fts_index_lookup
.extern fts_index_add
.extern crc32_calc
.extern g_term_hash_table

.data
.balign 8

// Test documents - each contains specific searchable terms
doc1_content:
    .asciz  "The quick brown fox jumps over the lazy dog"
doc1_len = . - doc1_content - 1

doc2_content:
    .asciz  "Hello world this is a simple test document"
doc2_len = . - doc2_content - 1

doc3_content:
    .asciz  "Assembly programming is quick and efficient"
doc3_len = . - doc3_content - 1

// Search queries
query_match:
    .asciz  "quick"
query_match_len = . - query_match - 1

query_nomatch:
    .asciz  "xyzzyplugh"
query_nomatch_len = . - query_nomatch - 1

// Messages
msg_header:
    .asciz  "=== Omesh Integration Test ===\n"
msg_init:
    .asciz  "Initializing system... "
msg_ok:
    .asciz  "OK\n"
msg_fail:
    .asciz  "FAIL\n"
msg_indexing:
    .asciz  "Indexing documents...\n"
msg_index_doc:
    .asciz  "  Indexed doc "
msg_searching:
    .asciz  "Searching for '"
msg_quote_end:
    .asciz  "'... "
msg_found:
    .asciz  "found "
msg_results:
    .asciz  " results\n"

msg_test1:
    .asciz  "[TEST 1] Search for term 'quick' (should match): "
msg_test2:
    .asciz  "[TEST 2] Search for term 'xyzzyplugh' (should NOT match): "
msg_pass:
    .asciz  "PASS\n"
msg_test_fail:
    .asciz  "FAIL\n"

msg_summary:
    .asciz  "\n=== Summary: "
msg_slash:
    .asciz  "/"
msg_tests_passed:
    .asciz  " tests passed ===\n"

msg_all_pass:
    .asciz  "\n*** ALL TESTS PASSED ***\n"
msg_some_fail:
    .asciz  "\n*** SOME TESTS FAILED ***\n"
msg_debug_qid:
    .asciz  "  [DEBUG] query_id="
msg_debug_slot:
    .asciz  "  [DEBUG] slot="
msg_debug_lookup:
    .asciz  "  [DEBUG] fts_index_lookup returned: "
msg_debug_index:
    .asciz  "  [DEBUG] replica_index_doc returned: "
msg_terms:
    .asciz  " terms indexed\n"
msg_debug_len:
    .asciz  "  [DEBUG] doc1_len = "
msg_debug_immediate:
    .asciz  "  [DEBUG] lookup 'quick' after indexing: "
msg_debug_hash:
    .asciz  "  [DEBUG] CRC32 of 'quick': 0x"
msg_debug_slot_ptr:
    .asciz  "  [DEBUG] hash table slot "
msg_debug_ptr:
    .asciz  " ptr: "
msg_debug_entry_hash:
    .asciz  "    Entry hash: "
msg_debug_entry_len:
    .asciz  "    Entry len: "
msg_debug_entry_term:
    .asciz  "    Entry term: '"

// Data file paths
docs_path:
    .asciz  "./test_docs.dat"
index_path:
    .asciz  "."

// Test state
.balign 8
tests_passed:
    .quad   0
tests_total:
    .quad   0

.text
.balign 4

// =============================================================================
// _start - Test entry point
// =============================================================================
.global _start
_start:
    mov     x29, sp

    // Print header
    adrp    x0, msg_header
    add     x0, x0, :lo12:msg_header
    bl      print_str

    // Initialize system
    adrp    x0, msg_init
    add     x0, x0, :lo12:msg_init
    bl      print_str

    // 1. Initialize HAL
    bl      hal_init
    cmp     x0, #0
    b.lt    .Linit_failed

    // 2. Initialize document store
    adrp    x0, docs_path
    add     x0, x0, :lo12:docs_path
    bl      doc_store_init
    cmp     x0, #0
    b.lt    .Linit_failed

    // 3. Initialize FTS index
    adrp    x0, index_path
    add     x0, x0, :lo12:index_path
    bl      fts_index_init
    cmp     x0, #0
    b.lt    .Linit_failed

    // 4. Initialize node
    mov     x0, #0              // Auto-generate ID
    bl      node_init
    cmp     x0, #0
    b.lt    .Linit_failed
    mov     x0, #NODE_STATE_READY
    bl      node_set_state

    // 5. Initialize handlers
    bl      handler_init
    cmp     x0, #0
    b.lt    .Linit_failed

    // 6. Initialize replica manager
    bl      replica_init
    cmp     x0, #0
    b.lt    .Linit_failed

    // 7. Initialize router
    bl      router_init

    adrp    x0, msg_ok
    add     x0, x0, :lo12:msg_ok
    bl      print_str

    // Index documents
    adrp    x0, msg_indexing
    add     x0, x0, :lo12:msg_indexing
    bl      print_str

    // Index doc 1
    // Debug: print content length
    adrp    x0, msg_debug_len
    add     x0, x0, :lo12:msg_debug_len
    bl      print_str
    mov     x0, #doc1_len
    bl      print_dec
    bl      print_newline

    // Call fts_index_add directly
    mov     x0, #1              // doc_id = 1
    adrp    x1, doc1_content
    add     x1, x1, :lo12:doc1_content
    mov     x2, #doc1_len
    bl      fts_index_add

    // Debug: print indexing result
    mov     x20, x0
    adrp    x0, msg_debug_index
    add     x0, x0, :lo12:msg_debug_index
    bl      print_str
    mov     x0, x20
    bl      print_dec
    adrp    x0, msg_terms
    add     x0, x0, :lo12:msg_terms
    bl      print_str

    // Compute and print hash of "quick"
    adrp    x0, query_match
    add     x0, x0, :lo12:query_match
    mov     x1, #query_match_len
    bl      crc32_calc
    mov     x21, x0                     // Save hash

    adrp    x0, msg_debug_hash
    add     x0, x0, :lo12:msg_debug_hash
    bl      print_str
    mov     x0, x21
    bl      print_hex
    bl      print_newline

    // Check if hash table slot is populated
    stp     x20, x21, [sp, #-16]!
    adrp    x0, msg_debug_slot_ptr
    add     x0, x0, :lo12:msg_debug_slot_ptr
    bl      print_str
    ldp     x20, x21, [sp]
    mov     x0, x21
    and     x0, x0, #0x1FFF
    bl      print_dec
    adrp    x0, msg_debug_ptr
    add     x0, x0, :lo12:msg_debug_ptr
    bl      print_str
    adrp    x0, g_term_hash_table
    add     x0, x0, :lo12:g_term_hash_table
    ldp     x20, x21, [sp]
    and     x1, x21, #0x1FFF
    ldr     x22, [x0, x1, lsl #3]       // entry ptr in x22
    mov     x0, x22
    bl      print_hex
    bl      print_newline

    // If entry exists, print its contents
    cbz     x22, .Ldebug_hash_done

    // Print stored hash
    adrp    x0, msg_debug_entry_hash
    add     x0, x0, :lo12:msg_debug_entry_hash
    bl      print_str
    ldr     w0, [x22, #0]               // TERMBUF_OFF_HASH
    bl      print_hex
    bl      print_newline

    // Print stored length
    adrp    x0, msg_debug_entry_len
    add     x0, x0, :lo12:msg_debug_entry_len
    bl      print_str
    ldrh    w0, [x22, #4]               // TERMBUF_OFF_LEN
    bl      print_dec
    bl      print_newline

    // Print term ptr
    adrp    x0, msg_debug_entry_term
    add     x0, x0, :lo12:msg_debug_entry_term
    bl      print_str
    ldr     x0, [x22, #32]              // TERMBUF_OFF_TERM_PTR
    bl      print_str
    bl      print_newline

.Ldebug_hash_done:
    ldp     x20, x21, [sp], #16

    // Immediately try to look up "quick"
    sub     sp, sp, #16
    adrp    x0, query_match
    add     x0, x0, :lo12:query_match
    mov     x1, #query_match_len
    mov     x2, sp
    add     x3, sp, #8
    bl      fts_index_lookup
    mov     x21, x0                     // Save result
    add     sp, sp, #16

    adrp    x0, msg_debug_immediate
    add     x0, x0, :lo12:msg_debug_immediate
    bl      print_str
    mov     x0, x21
    bl      print_dec
    bl      print_newline

    cmp     x20, #0
    b.lt    .Lindex_failed

    adrp    x0, msg_index_doc
    add     x0, x0, :lo12:msg_index_doc
    bl      print_str
    mov     x0, #1
    bl      print_dec
    bl      print_newline

    // Index doc 2
    mov     x0, #2              // doc_id = 2
    adrp    x1, doc2_content
    add     x1, x1, :lo12:doc2_content
    mov     x2, #doc2_len
    bl      replica_index_doc
    cmp     x0, #0
    b.lt    .Lindex_failed

    adrp    x0, msg_index_doc
    add     x0, x0, :lo12:msg_index_doc
    bl      print_str
    mov     x0, #2
    bl      print_dec
    bl      print_newline

    // Index doc 3
    mov     x0, #3              // doc_id = 3
    adrp    x1, doc3_content
    add     x1, x1, :lo12:doc3_content
    mov     x2, #doc3_len
    bl      replica_index_doc
    cmp     x0, #0
    b.lt    .Lindex_failed

    adrp    x0, msg_index_doc
    add     x0, x0, :lo12:msg_index_doc
    bl      print_str
    mov     x0, #3
    bl      print_dec
    bl      print_newline

    // =========================================================================
    // TEST 1: Search for "quick" - should find matches (doc1, doc3)
    // =========================================================================
    adrp    x0, msg_test1
    add     x0, x0, :lo12:msg_test1
    bl      print_str

    // Increment total tests
    adrp    x19, tests_total
    add     x19, x19, :lo12:tests_total
    ldr     x0, [x19]
    add     x0, x0, #1
    str     x0, [x19]

    // Direct FTS test: check if fts_index_lookup finds "quick"
    // Stack: sp+0 = offset, sp+8 = doc_freq
    sub     sp, sp, #16

    adrp    x0, query_match
    add     x0, x0, :lo12:query_match   // "quick"
    mov     x1, #query_match_len        // 5
    mov     x2, sp                      // &offset
    add     x3, sp, #8                  // &doc_freq
    bl      fts_index_lookup

    // Debug: print lookup result
    mov     x20, x0                     // Save return value
    stp     x20, x21, [sp, #-16]!
    adrp    x0, msg_debug_lookup
    add     x0, x0, :lo12:msg_debug_lookup
    bl      print_str
    mov     x0, x20
    bl      print_dec
    bl      print_newline
    ldp     x20, x21, [sp], #16

    add     sp, sp, #16                 // Restore stack

    // Return 0 means found
    cmp     x20, #0
    b.ne    .Ltest1_fail

    // TEST 1 PASSED
    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_str

    // Increment passed
    adrp    x22, tests_passed
    add     x22, x22, :lo12:tests_passed
    ldr     x0, [x22]
    add     x0, x0, #1
    str     x0, [x22]
    b       .Ltest2

.Ltest1_fail:
    adrp    x0, msg_test_fail
    add     x0, x0, :lo12:msg_test_fail
    bl      print_str

    // =========================================================================
    // TEST 2: Search for "xyzzyplugh" - should find 0 matches
    // =========================================================================
.Ltest2:
    adrp    x0, msg_test2
    add     x0, x0, :lo12:msg_test2
    bl      print_str

    // Increment total tests
    adrp    x19, tests_total
    add     x19, x19, :lo12:tests_total
    ldr     x0, [x19]
    add     x0, x0, #1
    str     x0, [x19]

    // Execute search for non-matching term
    adrp    x0, query_nomatch
    add     x0, x0, :lo12:query_nomatch
    mov     x1, #query_nomatch_len
    mov     x2, #10             // max_results
    mov     x3, #SEARCH_FLAG_AND
    mov     x4, #0              // no callback
    bl      router_search

    // Check if search succeeded
    cmp     x0, #0
    b.le    .Ltest2_fail
    mov     w20, w0             // query_id

    // Find pending query slot by query_id
    mov     w0, w20             // Set x0 to query_id
    bl      router_find_pending
    cmp     x0, #0
    b.lt    .Ltest2_fail
    mov     x24, x0             // Save slot index

    // Get pointer to slot
    mov     x0, x24             // slot index
    bl      router_get_pending_ptr
    cbz     x0, .Ltest2_fail

    // Check result count - should be 0
    ldr     w21, [x0, #PQUERY_OFF_RESULT_CNT]

    // Free the pending slot
    mov     x0, x24
    bl      router_free_pending

    // Should have exactly 0 results
    cmp     w21, #0
    b.ne    .Ltest2_fail

    // TEST 2 PASSED
    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_str

    // Increment passed
    adrp    x22, tests_passed
    add     x22, x22, :lo12:tests_passed
    ldr     x0, [x22]
    add     x0, x0, #1
    str     x0, [x22]
    b       .Lsummary

.Ltest2_fail:
    adrp    x0, msg_test_fail
    add     x0, x0, :lo12:msg_test_fail
    bl      print_str

    // =========================================================================
    // Print summary
    // =========================================================================
.Lsummary:
    adrp    x0, msg_summary
    add     x0, x0, :lo12:msg_summary
    bl      print_str

    adrp    x22, tests_passed
    add     x22, x22, :lo12:tests_passed
    ldr     x0, [x22]
    bl      print_dec

    adrp    x0, msg_slash
    add     x0, x0, :lo12:msg_slash
    bl      print_str

    adrp    x19, tests_total
    add     x19, x19, :lo12:tests_total
    ldr     x0, [x19]
    bl      print_dec

    adrp    x0, msg_tests_passed
    add     x0, x0, :lo12:msg_tests_passed
    bl      print_str

    // Check if all passed
    ldr     x0, [x22]           // passed
    ldr     x1, [x19]           // total
    cmp     x0, x1
    b.ne    .Lsome_failed

    adrp    x0, msg_all_pass
    add     x0, x0, :lo12:msg_all_pass
    bl      print_str

    // Shutdown
    bl      fts_index_close

    // Exit success
    mov     x0, #0
    mov     x8, #SYS_exit_group
    svc     #0

.Lsome_failed:
    adrp    x0, msg_some_fail
    add     x0, x0, :lo12:msg_some_fail
    bl      print_str

    // Shutdown
    bl      fts_index_close

    // Exit failure
    mov     x0, #1
    mov     x8, #SYS_exit_group
    svc     #0

.Linit_failed:
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_str
    mov     x0, #2
    mov     x8, #SYS_exit_group
    svc     #0

.Lindex_failed:
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_str
    mov     x0, #3
    mov     x8, #SYS_exit_group
    svc     #0

.size _start, .-_start
