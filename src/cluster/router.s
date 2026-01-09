// =============================================================================
// Omesh - Query Router and Result Aggregator
// =============================================================================
//
// Distributed query routing and result aggregation:
// - router_init: Initialize pending query slots
// - router_search: Execute distributed search
// - router_alloc_pending: Allocate pending query slot
// - router_find_pending: Find pending query by ID
// - router_free_pending: Free pending query slot
// - router_merge_results: Merge incoming results
// - router_finalize_query: Finalize and deduplicate results
// - router_check_timeouts: Check for timed-out queries
//
// CALLING CONVENTION: AAPCS64
//   - Arguments: x0-x7 (x0 = first arg)
//   - Return value: x0
//   - Callee-saved: x19-x28
//   - Caller-saved: x0-x18
//
// ERROR HANDLING:
//   - Returns 0 on success, negative errno on failure
//   - -EAGAIN (-11): No available pending query slots
//   - -ENOENT (-2): Query ID not found
//
// PUBLIC API:
//
//   router_init() -> 0
//       Initialize pending query slots and result buffer.
//       Must be called before router_search.
//
//   router_search(query_str, query_len, max_results, callback) -> query_id | -errno
//       Execute distributed search:
//       1. Allocate pending query slot
//       2. Execute local search via fts_query_*
//       3. Broadcast SEARCH message to peers
//       4. Return query_id for tracking
//       callback(query_id, results_ptr, count) called on completion.
//
//   router_alloc_pending() -> slot_ptr | -EAGAIN
//       Allocate a pending query slot from bitmap.
//       NOTE: Allocates from HIGH end (slot 63 first).
//
//   router_find_pending(query_id) -> slot_ptr | -ENOENT
//       Find pending query slot by query ID.
//
//   router_free_pending(slot_ptr) -> 0
//       Free pending query slot, clear bitmap bit.
//
//   router_get_results(query_id, buf, max) -> count | -errno
//       Copy results for query_id into buf.
//
// INTERNAL STATE:
//   g_pending_queries - Array of PQUERY_SIZE * 64 pending query slots
//   g_pending_bitmap  - 64-bit bitmap of allocated slots (1 = in use)
//   g_result_buffer   - Shared buffer for merged results
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"
.include "cluster.inc"
.include "index.inc"

.data
// =============================================================================
// Pending Query State
// =============================================================================

.align 8
.global g_pending_queries
g_pending_queries:
    .skip   PQUERY_SIZE * CLUSTER_MAX_PENDING_QUERIES

// Bitmap of allocated slots (64 bits for 64 slots)
.global g_pending_bitmap
g_pending_bitmap:
    .quad   0

// Result buffer for merged results
.align 8
.global g_result_buffer
g_result_buffer:
    .skip   RESULT_SIZE * CLUSTER_MAX_RESULTS * 4    // Extra space for merging

// Message buffer for search messages
.align 8
router_msg_buf:
    .skip   NET_MAX_MSG_SIZE + MSG_HDR_SIZE

.text

// =============================================================================
// router_init - Initialize router state
// =============================================================================
// Output:
//   x0 = 0
// =============================================================================
.global router_init
.type router_init, %function
router_init:
    // Clear pending bitmap
    adrp    x0, g_pending_bitmap
    add     x0, x0, :lo12:g_pending_bitmap
    str     xzr, [x0]

    // Clear pending query slots
    adrp    x0, g_pending_queries
    add     x0, x0, :lo12:g_pending_queries
    mov     x1, #(PQUERY_SIZE * CLUSTER_MAX_PENDING_QUERIES)
.Lrouter_init_clear:
    cbz     x1, .Lrouter_init_done
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Lrouter_init_clear

.Lrouter_init_done:
    mov     x0, #0
    ret
.size router_init, .-router_init

// =============================================================================
// router_alloc_pending - Allocate a pending query slot
// =============================================================================
// Output:
//   x0 = slot index (0-63), or -1 if full
// =============================================================================
.global router_alloc_pending
.type router_alloc_pending, %function
router_alloc_pending:
    adrp    x1, g_pending_bitmap
    add     x1, x1, :lo12:g_pending_bitmap
    ldr     x2, [x1]                    // Current bitmap

    // Find first zero bit
    mvn     x3, x2                      // Invert to find zeros
    cbz     x3, .Lalloc_pending_full    // All bits set = full

    // Find lowest set bit in inverted value = lowest free slot
    clz     x0, x3                      // Count leading zeros
    mov     x4, #63
    sub     x0, x4, x0                  // Convert to bit index

    // Check if within limit
    cmp     x0, #CLUSTER_MAX_PENDING_QUERIES
    b.hs    .Lalloc_pending_full

    // Set the bit
    mov     x4, #1
    lsl     x4, x4, x0
    orr     x2, x2, x4
    str     x2, [x1]

    // Initialize the slot
    mov     x4, #PQUERY_SIZE
    mul     x4, x0, x4
    adrp    x5, g_pending_queries
    add     x5, x5, :lo12:g_pending_queries
    add     x5, x5, x4

    // Clear the slot
    mov     x6, #PQUERY_SIZE
.Lalloc_clear_slot:
    cbz     x6, .Lalloc_pending_ret
    strb    wzr, [x5], #1
    sub     x6, x6, #1
    b       .Lalloc_clear_slot

.Lalloc_pending_ret:
    ret

.Lalloc_pending_full:
    mov     x0, #-1
    ret
.size router_alloc_pending, .-router_alloc_pending

// =============================================================================
// router_free_pending - Free a pending query slot
// =============================================================================
// Input:
//   x0 = slot index
// Output:
//   x0 = 0
// =============================================================================
.global router_free_pending
.type router_free_pending, %function
router_free_pending:
    cmp     x0, #CLUSTER_MAX_PENDING_QUERIES
    b.hs    .Lfree_pending_invalid

    // Clear the bit
    adrp    x1, g_pending_bitmap
    add     x1, x1, :lo12:g_pending_bitmap
    ldr     x2, [x1]
    mov     x3, #1
    lsl     x3, x3, x0
    bic     x2, x2, x3
    str     x2, [x1]

    // Clear state in slot
    mov     x3, #PQUERY_SIZE
    mul     x3, x0, x3
    adrp    x4, g_pending_queries
    add     x4, x4, :lo12:g_pending_queries
    add     x4, x4, x3
    mov     w5, #PQUERY_STATE_FREE
    str     w5, [x4, #PQUERY_OFF_STATE]

    mov     x0, #0
    ret

.Lfree_pending_invalid:
    mov     x0, #-22                    // -EINVAL
    ret
.size router_free_pending, .-router_free_pending

// =============================================================================
// router_get_pending_ptr - Get pointer to pending query slot
// =============================================================================
// Input:
//   x0 = slot index
// Output:
//   x0 = pointer to slot, or NULL if invalid
// =============================================================================
.global router_get_pending_ptr
.type router_get_pending_ptr, %function
router_get_pending_ptr:
    cmp     x0, #CLUSTER_MAX_PENDING_QUERIES
    b.hs    .Lget_pending_invalid

    mov     x1, #PQUERY_SIZE
    mul     x0, x0, x1
    adrp    x1, g_pending_queries
    add     x1, x1, :lo12:g_pending_queries
    add     x0, x0, x1
    ret

.Lget_pending_invalid:
    mov     x0, #0
    ret
.size router_get_pending_ptr, .-router_get_pending_ptr

// =============================================================================
// router_find_pending - Find pending query by query ID
// =============================================================================
// Input:
//   x0 = query ID
// Output:
//   x0 = slot index, or -1 if not found
// =============================================================================
.global router_find_pending
.type router_find_pending, %function
router_find_pending:
    cbz     x0, .Lfind_pending_notfound // ID 0 is invalid

    adrp    x1, g_pending_bitmap
    add     x1, x1, :lo12:g_pending_bitmap
    ldr     x2, [x1]
    cbz     x2, .Lfind_pending_notfound // No pending queries

    adrp    x1, g_pending_queries
    add     x1, x1, :lo12:g_pending_queries
    mov     x3, #0                      // Slot index

.Lfind_pending_loop:
    cmp     x3, #CLUSTER_MAX_PENDING_QUERIES
    b.hs    .Lfind_pending_notfound

    // Check if slot is allocated
    mov     x4, #1
    lsl     x4, x4, x3
    tst     x2, x4
    b.eq    .Lfind_pending_next

    // Check query ID
    ldr     w5, [x1, #PQUERY_OFF_ID]
    cmp     w5, w0
    b.eq    .Lfind_pending_found

.Lfind_pending_next:
    add     x1, x1, #PQUERY_SIZE
    add     x3, x3, #1
    b       .Lfind_pending_loop

.Lfind_pending_found:
    mov     x0, x3
    ret

.Lfind_pending_notfound:
    mov     x0, #-1
    ret
.size router_find_pending, .-router_find_pending

// =============================================================================
// router_search - Execute distributed search
// =============================================================================
// Input:
//   x0 = query string pointer
//   x1 = query string length
//   x2 = max results
//   x3 = flags (SEARCH_FLAG_*)
//   x4 = callback function pointer (or NULL)
// Output:
//   x0 = query ID, or -errno on failure
// =============================================================================
.global router_search
.type router_search, %function
router_search:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0                     // Query string
    mov     x20, x1                     // Query length
    mov     x21, x2                     // Max results
    mov     x22, x3                     // Flags
    mov     x23, x4                     // Callback

    // Validate inputs
    cbz     x19, .Lrouter_search_invalid
    cbz     x20, .Lrouter_search_invalid

    // Cap max results
    cmp     x21, #CLUSTER_MAX_RESULTS
    b.ls    .Lrouter_search_alloc
    mov     x21, #CLUSTER_MAX_RESULTS

.Lrouter_search_alloc:
    // Allocate pending query slot
    bl      router_alloc_pending
    cmp     x0, #0
    b.lt    .Lrouter_search_full
    mov     x24, x0                     // Slot index

    // Get pointer to slot
    bl      router_get_pending_ptr
    mov     x25, x0                     // Slot pointer

    // Generate query ID
    bl      node_generate_query_id
    mov     w26, w0                     // Query ID

    // Initialize pending query
    str     w26, [x25, #PQUERY_OFF_ID]
    mov     w0, #PQUERY_STATE_PENDING
    str     w0, [x25, #PQUERY_OFF_STATE]

    // Get peer count for expected responses
    bl      node_get_peer_count
    add     w0, w0, #1                  // +1 for local result
    str     w0, [x25, #PQUERY_OFF_EXPECTED]
    mov     w0, #1                      // We have local result
    str     w0, [x25, #PQUERY_OFF_RECEIVED]

    // Set result tracking
    adrp    x0, g_result_buffer
    add     x0, x0, :lo12:g_result_buffer
    str     x0, [x25, #PQUERY_OFF_RESULTS]
    str     wzr, [x25, #PQUERY_OFF_RESULT_CNT]
    str     w21, [x25, #PQUERY_OFF_MAX_RESULTS]

    // Set timeout (current time + timeout)
    sub     sp, sp, #16
    mov     x0, #1                      // CLOCK_MONOTONIC
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0

    ldr     x0, [sp]                    // seconds
    ldr     x1, [sp, #8]                // nanoseconds
    add     sp, sp, #16

    // Convert to ns and add timeout
    ldr     x2, =1000000000
    mul     x0, x0, x2
    add     x0, x0, x1
    ldr     x1, =(CLUSTER_QUERY_TIMEOUT_MS * 1000000)
    add     x0, x0, x1
    str     x0, [x25, #PQUERY_OFF_TIMEOUT]

    // Store callback
    str     x23, [x25, #PQUERY_OFF_CALLBACK]

    // Execute local FTS search
    // Allocate stack space for doc_id and score outputs
    sub     sp, sp, #32
    // sp+0: doc_id (8 bytes)
    // sp+8: score (8 bytes)
    // sp+16: query context (8 bytes)
    // sp+24: local result count (8 bytes)

    // Initialize query context
    mov     x0, x21                     // max_results
    bl      fts_query_init
    cbz     x0, .Llocal_search_done     // NULL = no context, skip search
    str     x0, [sp, #16]               // Save context

    // Parse query
    mov     x1, x19                     // Query string (null-terminated)
    mov     x2, x22                     // Query type (from flags)
    bl      fts_query_parse
    cmp     x0, #0
    b.le    .Llocal_free_ctx            // No terms = no results

    // Execute search
    ldr     x0, [sp, #16]               // Load context
    bl      fts_query_execute
    str     x0, [sp, #24]               // Save local result count
    cbz     x0, .Llocal_free_ctx        // No results

    // Copy results to g_result_buffer
    adrp    x1, g_result_buffer
    add     x1, x1, :lo12:g_result_buffer
    mov     x2, #0                      // Result index
    ldr     x3, [sp, #24]               // Total results

.Llocal_copy_loop:
    cmp     x2, x3
    b.hs    .Llocal_copy_done

    // Get result at index
    ldr     x0, [sp, #16]               // Context
    mov     x1, x2                      // Index
    add     x4, sp, #0                  // &doc_id
    add     x5, sp, #8                  // &score
    mov     x2, x4
    mov     x3, x5
    bl      fts_query_get_result
    cmp     x0, #0
    b.ne    .Llocal_copy_done           // Error = stop

    // Reload index (was clobbered)
    ldr     x2, [sp, #24]               // Use as temp to restore
    adrp    x1, g_result_buffer
    add     x1, x1, :lo12:g_result_buffer
    ldr     w4, [x25, #PQUERY_OFF_RESULT_CNT]

    // Calculate destination: g_result_buffer + result_cnt * RESULT_SIZE
    mov     x5, #RESULT_SIZE
    mul     x5, x4, x5
    add     x5, x1, x5                  // Destination pointer

    // Copy doc_id (8 bytes)
    ldr     x6, [sp, #0]
    str     x6, [x5, #RESULT_OFF_DOC_ID]

    // Copy score (truncate 8-byte FTS score to 4 bytes)
    ldr     x6, [sp, #8]
    str     w6, [x5, #RESULT_OFF_SCORE]

    // Clear flags
    str     wzr, [x5, #RESULT_OFF_FLAGS]

    // Increment result count
    add     w4, w4, #1
    str     w4, [x25, #PQUERY_OFF_RESULT_CNT]

    // Reload loop counter and continue
    ldr     w2, [x25, #PQUERY_OFF_RESULT_CNT]
    sub     w2, w2, #1                  // Index = count - 1, but we need next
    add     w2, w2, #1                  // Actually we want the original index + 1
    ldr     x3, [sp, #24]               // Reload total
    b       .Llocal_copy_loop

.Llocal_copy_done:
.Llocal_free_ctx:
    // Free query context
    ldr     x0, [sp, #16]
    cbz     x0, .Llocal_search_done
    bl      fts_query_free

.Llocal_search_done:
    add     sp, sp, #32

    // Build SEARCH message
    adrp    x0, router_msg_buf
    add     x0, x0, :lo12:router_msg_buf
    mov     w1, w26                     // Query ID
    mov     w2, w22                     // Flags
    mov     w3, w21                     // Max results
    mov     x4, x19                     // Query string
    mov     x5, x20                     // Query length
    bl      build_search_msg
    cmp     x0, #0
    b.lt    .Lrouter_search_cleanup

    // Broadcast search to all connected mesh peers
    mov     w0, w26             // query_id
    mov     w1, w22             // flags
    mov     w2, w21             // max_results
    mov     x3, x19             // query string
    mov     w4, w20             // query length
    bl      mesh_broadcast_search

    // Return query ID (broadcast result in x0 ignored for now)
    mov     w0, w26
    b       .Lrouter_search_ret

.Lrouter_search_cleanup:
    // Free the slot on error
    mov     x0, x24
    bl      router_free_pending
    mov     x0, #-5                     // -EIO
    b       .Lrouter_search_ret

.Lrouter_search_invalid:
    mov     x0, #-22                    // -EINVAL
    b       .Lrouter_search_ret

.Lrouter_search_full:
    mov     x0, #-11                    // -EAGAIN

.Lrouter_search_ret:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size router_search, .-router_search

// =============================================================================
// router_merge_results - Merge incoming results into pending query
// =============================================================================
// Input:
//   x0 = query ID
//   x1 = results array pointer
//   x2 = result count
// Output:
//   x0 = 0 on success, -errno on failure
// =============================================================================
.global router_merge_results
.type router_merge_results, %function
router_merge_results:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     w19, w0                     // Query ID
    mov     x20, x1                     // Results array
    mov     x21, x2                     // Result count

    // Find pending query
    mov     w0, w19
    bl      router_find_pending
    cmp     x0, #0
    b.lt    .Lmerge_notfound
    mov     x22, x0                     // Slot index

    // Get slot pointer
    bl      router_get_pending_ptr
    cbz     x0, .Lmerge_notfound
    mov     x23, x0                     // Slot pointer

    // Check state
    ldr     w0, [x23, #PQUERY_OFF_STATE]
    cmp     w0, #PQUERY_STATE_FREE
    b.eq    .Lmerge_notfound
    cmp     w0, #PQUERY_STATE_DONE
    b.eq    .Lmerge_done

    // Update state to collecting
    mov     w0, #PQUERY_STATE_COLLECTING
    str     w0, [x23, #PQUERY_OFF_STATE]

    // Get current result count and buffer
    ldr     w24, [x23, #PQUERY_OFF_RESULT_CNT]
    ldr     x0, [x23, #PQUERY_OFF_RESULTS]

    // Copy new results
    mov     x1, x20                     // Source
    mov     x2, x21                     // Count
.Lmerge_copy_loop:
    cbz     x2, .Lmerge_copy_done

    // Check if we have space
    cmp     w24, #(CLUSTER_MAX_RESULTS * 4)
    b.hs    .Lmerge_copy_done           // Buffer full

    // Copy one result entry
    mov     x3, #RESULT_SIZE
    mul     x4, x24, x3
    adrp    x5, g_result_buffer
    add     x5, x5, :lo12:g_result_buffer
    add     x4, x5, x4                  // Destination

    // Copy RESULT_SIZE bytes
    mov     x5, #RESULT_SIZE
.Lmerge_copy_entry:
    cbz     x5, .Lmerge_copy_next
    ldrb    w6, [x1], #1
    strb    w6, [x4], #1
    sub     x5, x5, #1
    b       .Lmerge_copy_entry

.Lmerge_copy_next:
    add     w24, w24, #1
    sub     x2, x2, #1
    b       .Lmerge_copy_loop

.Lmerge_copy_done:
    // Update result count
    str     w24, [x23, #PQUERY_OFF_RESULT_CNT]

    // Increment received count
    ldr     w0, [x23, #PQUERY_OFF_RECEIVED]
    add     w0, w0, #1
    str     w0, [x23, #PQUERY_OFF_RECEIVED]

    // Check if all responses received
    ldr     w1, [x23, #PQUERY_OFF_EXPECTED]
    cmp     w0, w1
    b.lo    .Lmerge_success

    // All received - finalize
    mov     w0, w19
    bl      router_finalize_query

.Lmerge_success:
    mov     x0, #0
    b       .Lmerge_ret

.Lmerge_notfound:
    mov     x0, #-2                     // -ENOENT
    b       .Lmerge_ret

.Lmerge_done:
    mov     x0, #0                      // Already done, ignore

.Lmerge_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size router_merge_results, .-router_merge_results

// =============================================================================
// router_finalize_query - Finalize query and deduplicate results
// =============================================================================
// Input:
//   x0 = query ID
// Output:
//   x0 = final result count, or -errno on failure
// =============================================================================
.global router_finalize_query
.type router_finalize_query, %function
router_finalize_query:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     w19, w0                     // Query ID

    // Find pending query
    bl      router_find_pending
    cmp     x0, #0
    b.lt    .Lfinalize_notfound
    mov     x20, x0                     // Slot index

    // Get slot pointer
    bl      router_get_pending_ptr
    cbz     x0, .Lfinalize_notfound
    mov     x21, x0                     // Slot pointer

    // Mark as done
    mov     w0, #PQUERY_STATE_DONE
    str     w0, [x21, #PQUERY_OFF_STATE]

    // Get result count
    ldr     w22, [x21, #PQUERY_OFF_RESULT_CNT]

    // Sort results by score (descending) using simple bubble sort
    // In production, would use quicksort for large result sets
    cmp     w22, #1
    b.ls    .Lfinalize_sorted           // 0 or 1 element, already sorted

    adrp    x0, g_result_buffer
    add     x0, x0, :lo12:g_result_buffer
    mov     w1, w22                     // Count

.Lsort_outer:
    sub     w1, w1, #1
    cbz     w1, .Lfinalize_sorted

    adrp    x2, g_result_buffer
    add     x2, x2, :lo12:g_result_buffer
    mov     w3, w1                      // Inner loop count
    mov     w4, #0                      // Swapped flag

.Lsort_inner:
    cbz     w3, .Lsort_inner_done

    // Compare scores at x2 and x2+RESULT_SIZE
    ldr     w5, [x2, #RESULT_OFF_SCORE]
    add     x6, x2, #RESULT_SIZE
    ldr     w7, [x6, #RESULT_OFF_SCORE]

    // If current < next, swap (descending order)
    cmp     w5, w7
    b.hs    .Lsort_no_swap

    // Swap entries
    mov     x8, #RESULT_SIZE
.Lsort_swap:
    cbz     x8, .Lsort_swapped
    ldrb    w9, [x2]
    ldrb    w10, [x6]
    strb    w10, [x2], #1
    strb    w9, [x6], #1
    sub     x8, x8, #1
    b       .Lsort_swap

.Lsort_swapped:
    sub     x2, x2, #RESULT_SIZE        // Reset x2 to start of entry
    sub     x6, x6, #RESULT_SIZE
    mov     w4, #1                      // Mark swapped

.Lsort_no_swap:
    add     x2, x2, #RESULT_SIZE
    sub     w3, w3, #1
    b       .Lsort_inner

.Lsort_inner_done:
    cbz     w4, .Lfinalize_sorted       // No swaps = sorted
    b       .Lsort_outer

.Lfinalize_sorted:
    // Deduplicate by doc_id (keep first = highest score)
    cmp     w22, #1
    b.ls    .Lfinalize_deduped

    adrp    x0, g_result_buffer
    add     x0, x0, :lo12:g_result_buffer
    mov     w1, #1                      // Write position (keep first)
    mov     w2, #1                      // Read position

.Ldedup_loop:
    cmp     w2, w22
    b.hs    .Ldedup_done

    // Get doc_id at read position
    mov     x3, #RESULT_SIZE
    mul     x3, x2, x3
    adrp    x4, g_result_buffer
    add     x4, x4, :lo12:g_result_buffer
    add     x4, x4, x3
    ldr     x5, [x4, #RESULT_OFF_DOC_ID]

    // Check against all previous entries
    mov     w6, #0                      // Check position
    mov     w7, #0                      // Duplicate flag

.Ldedup_check:
    cmp     w6, w1
    b.hs    .Ldedup_check_done

    mov     x3, #RESULT_SIZE
    mul     x3, x6, x3
    adrp    x8, g_result_buffer
    add     x8, x8, :lo12:g_result_buffer
    add     x8, x8, x3
    ldr     x9, [x8, #RESULT_OFF_DOC_ID]

    cmp     x5, x9
    b.ne    .Ldedup_check_next
    mov     w7, #1                      // Found duplicate
    b       .Ldedup_check_done

.Ldedup_check_next:
    add     w6, w6, #1
    b       .Ldedup_check

.Ldedup_check_done:
    cbnz    w7, .Ldedup_skip            // Skip duplicate

    // Keep this entry - copy to write position if different
    cmp     w1, w2
    b.eq    .Ldedup_keep_same

    // Copy entry
    mov     x3, #RESULT_SIZE
    mul     x3, x1, x3
    adrp    x6, g_result_buffer
    add     x6, x6, :lo12:g_result_buffer
    add     x6, x6, x3                  // Destination

    mov     x7, #RESULT_SIZE
.Ldedup_copy:
    cbz     x7, .Ldedup_keep_done
    ldrb    w8, [x4], #1
    strb    w8, [x6], #1
    sub     x7, x7, #1
    b       .Ldedup_copy

.Ldedup_keep_done:
.Ldedup_keep_same:
    add     w1, w1, #1                  // Advance write position

.Ldedup_skip:
    add     w2, w2, #1
    b       .Ldedup_loop

.Ldedup_done:
    mov     w22, w1                     // Update count after dedup

.Lfinalize_deduped:
    // Cap at max_results
    ldr     w0, [x21, #PQUERY_OFF_MAX_RESULTS]
    cmp     w22, w0
    b.ls    .Lfinalize_capped
    mov     w22, w0

.Lfinalize_capped:
    // Update final count
    str     w22, [x21, #PQUERY_OFF_RESULT_CNT]

    // Call callback if set
    ldr     x0, [x21, #PQUERY_OFF_CALLBACK]
    cbz     x0, .Lfinalize_no_callback

    // Callback(query_id, result_count, results_ptr)
    mov     w0, w19                     // Query ID
    mov     w1, w22                     // Count
    adrp    x2, g_result_buffer
    add     x2, x2, :lo12:g_result_buffer // Results
    ldr     x3, [x21, #PQUERY_OFF_CALLBACK]
    blr     x3

.Lfinalize_no_callback:
    mov     w0, w22                     // Return count
    b       .Lfinalize_ret

.Lfinalize_notfound:
    mov     x0, #-2                     // -ENOENT

.Lfinalize_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size router_finalize_query, .-router_finalize_query

// =============================================================================
// router_get_results - Get results for a query
// =============================================================================
// Input:
//   x0 = query ID
//   x1 = output buffer
//   x2 = max entries to copy
// Output:
//   x0 = entries copied, or -errno on failure
// =============================================================================
.global router_get_results
.type router_get_results, %function
router_get_results:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     w19, w0                     // Query ID
    mov     x20, x1                     // Output buffer
    mov     x21, x2                     // Max entries

    // Find pending query
    mov     w0, w19
    bl      router_find_pending
    cmp     x0, #0
    b.lt    .Lget_results_notfound

    // Get slot pointer
    bl      router_get_pending_ptr
    cbz     x0, .Lget_results_notfound
    mov     x22, x0

    // Get result count
    ldr     w0, [x22, #PQUERY_OFF_RESULT_CNT]

    // Cap at requested max
    cmp     w0, w21
    b.ls    .Lget_results_copy
    mov     w0, w21

.Lget_results_copy:
    // Copy results
    mov     w19, w0                     // Count to copy
    adrp    x1, g_result_buffer
    add     x1, x1, :lo12:g_result_buffer
    mov     x2, x20                     // Destination

    mov     w3, w19                     // Loop counter
.Lget_results_loop:
    cbz     w3, .Lget_results_done

    mov     x4, #RESULT_SIZE
.Lget_results_entry:
    cbz     x4, .Lget_results_next
    ldrb    w5, [x1], #1
    strb    w5, [x2], #1
    sub     x4, x4, #1
    b       .Lget_results_entry

.Lget_results_next:
    sub     w3, w3, #1
    b       .Lget_results_loop

.Lget_results_done:
    mov     w0, w19
    b       .Lget_results_ret

.Lget_results_notfound:
    mov     x0, #-2                     // -ENOENT

.Lget_results_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size router_get_results, .-router_get_results

// =============================================================================
// router_check_timeouts - Check for timed-out queries
// =============================================================================
// Output:
//   x0 = number of queries finalized due to timeout
// =============================================================================
.global router_check_timeouts
.type router_check_timeouts, %function
router_check_timeouts:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    // Get current time
    sub     sp, sp, #16
    mov     x0, #1                      // CLOCK_MONOTONIC
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0

    ldr     x19, [sp]                   // seconds
    ldr     x0, [sp, #8]                // nanoseconds
    add     sp, sp, #16

    // Convert to ns
    ldr     x1, =1000000000
    mul     x19, x19, x1
    add     x19, x19, x0                // Current time in ns

    // Check pending bitmap
    adrp    x0, g_pending_bitmap
    add     x0, x0, :lo12:g_pending_bitmap
    ldr     x20, [x0]
    cbz     x20, .Ltimeout_done         // No pending queries

    mov     x21, #0                     // Slot index
    mov     x22, #0                     // Timeout count

.Ltimeout_loop:
    cmp     x21, #CLUSTER_MAX_PENDING_QUERIES
    b.hs    .Ltimeout_done

    // Check if slot is allocated
    mov     x0, #1
    lsl     x0, x0, x21
    tst     x20, x0
    b.eq    .Ltimeout_next

    // Get slot pointer
    mov     x0, x21
    bl      router_get_pending_ptr
    cbz     x0, .Ltimeout_next

    // Check state
    ldr     w1, [x0, #PQUERY_OFF_STATE]
    cmp     w1, #PQUERY_STATE_FREE
    b.eq    .Ltimeout_next
    cmp     w1, #PQUERY_STATE_DONE
    b.eq    .Ltimeout_next

    // Check timeout
    ldr     x1, [x0, #PQUERY_OFF_TIMEOUT]
    cmp     x19, x1
    b.lo    .Ltimeout_next              // Not timed out

    // Timed out - finalize
    ldr     w0, [x0, #PQUERY_OFF_ID]
    bl      router_finalize_query
    add     x22, x22, #1

.Ltimeout_next:
    add     x21, x21, #1
    b       .Ltimeout_loop

.Ltimeout_done:
    mov     x0, x22
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size router_check_timeouts, .-router_check_timeouts

// =============================================================================
// router_get_pending_count - Get count of pending queries
// =============================================================================
// Output:
//   x0 = count of pending queries
// =============================================================================
.global router_get_pending_count
.type router_get_pending_count, %function
router_get_pending_count:
    adrp    x0, g_pending_bitmap
    add     x0, x0, :lo12:g_pending_bitmap
    ldr     x0, [x0]

    // Count set bits (population count)
    mov     x1, #0
.Lpopcount_loop:
    cbz     x0, .Lpopcount_done
    and     x2, x0, #1
    add     x1, x1, x2
    lsr     x0, x0, #1
    b       .Lpopcount_loop

.Lpopcount_done:
    mov     x0, x1
    ret
.size router_get_pending_count, .-router_get_pending_count
