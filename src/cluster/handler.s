// =============================================================================
// Omesh - Message Handlers
// =============================================================================
//
// Handles incoming cluster messages:
// - handler_init: Register handlers with peer layer
// - handle_search: Process search queries from peers
// - handle_results: Process search results from peers
// - handle_index: Process index updates (replication)
//
// CALLING CONVENTION: AAPCS64
//   - Arguments: x0-x7 (x0 = first arg)
//   - Return value: x0
//   - Callee-saved: x19-x28
//   - Caller-saved: x0-x18
//
// ERROR HANDLING:
//   - Returns 0 on success, negative errno on failure
//
// PUBLIC API:
//
//   handler_init() -> 0
//       Initialize and register message handlers.
//       Currently marks as initialized; handlers called directly by router.
//
//   handle_search(conn_ptr, msg_ptr) -> 0 | -errno
//       Process incoming SEARCH message from peer:
//       1. Parse query from MSG_TYPE_SEARCH payload
//       2. Execute local query via fts_query_*
//       3. Build MSG_TYPE_RESULTS response
//       4. Send results back to requesting peer
//
//   handle_results(conn_ptr, msg_ptr) -> 0 | -errno
//       Process incoming RESULTS message from peer:
//       1. Parse results from MSG_TYPE_RESULTS payload
//       2. Find matching pending query by query_id
//       3. Merge results into pending query's result buffer
//       4. If all responses received, trigger completion callback
//
//   handle_index(conn_ptr, msg_ptr) -> 0 | -errno
//       Process incoming INDEX message (replication):
//       1. Parse document from MSG_TYPE_INDEX payload
//       2. If PUT: Add to local store and index
//       3. If DELETE: Mark as deleted in store
//       4. Update ownership table
//
// MESSAGE PAYLOADS (see cluster.inc for offsets):
//
//   MSG_TYPE_SEARCH (0x30):
//     +0 [4] query_id, +4 [4] flags, +8 [4] max_results,
//     +12 [4] query_len, +16 [N] query_str
//
//   MSG_TYPE_RESULTS (0x31):
//     +0 [4] query_id, +4 [4] result_count, +8 [4] total_matches,
//     +12 [N] results[] { doc_id:8, score:4, doc_len:4 }
//
//   MSG_TYPE_INDEX (0x32):
//     +0 [8] doc_id, +8 [4] operation (PUT=1, DELETE=2),
//     +12 [4] doc_len, +16 [N] doc_data
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"
.include "cluster.inc"

.data

// =============================================================================
// Handler State
// =============================================================================

.align 8
handler_initialized:
    .quad   0

// Temporary buffers for message building
.align 8
handler_msg_buf:
    .skip   NET_MAX_MSG_SIZE + MSG_HDR_SIZE

handler_result_buf:
    .skip   RESULT_SIZE * CLUSTER_MAX_RESULTS

handler_query_buf:
    .skip   1024 + 1            // Max query length + null

// =============================================================================
// Pending Distributed Search State
// =============================================================================
// Used to collect search results from peers during distributed queries

.align 4
pending_query_id:
    .word   0                   // Current pending query ID (0 = none)

pending_peers_expected:
    .word   0                   // Number of peers we sent search to

pending_peers_responded:
    .word   0                   // Number of peers that have responded

pending_results_count:
    .word   0                   // Total results collected from peers

.align 8
pending_results_buf:
    .skip   RESULT_SIZE * 64    // Space for 64 results from peers

// Next query ID (increments for each distributed search)
.align 4
next_query_id:
    .word   1

.text

// =============================================================================
// handler_init - Initialize message handlers
// =============================================================================
// Output:
//   x0 = 0 on success, -errno on failure
// Note:
//   In a full implementation, this would register callbacks with the peer
//   layer. For now, we just mark as initialized - handlers are called
//   directly by the router/peer code.
// =============================================================================
.global handler_init
.type handler_init, %function
handler_init:
    adrp    x0, handler_initialized
    add     x0, x0, :lo12:handler_initialized
    mov     x1, #1
    str     x1, [x0]
    mov     x0, #0
    ret
.size handler_init, .-handler_init

// =============================================================================
// handler_is_ready - Check if handlers are initialized
// =============================================================================
// Output:
//   x0 = 1 if ready, 0 if not
// =============================================================================
.global handler_is_ready
.type handler_is_ready, %function
handler_is_ready:
    adrp    x0, handler_initialized
    add     x0, x0, :lo12:handler_initialized
    ldr     x0, [x0]
    ret
.size handler_is_ready, .-handler_is_ready

// =============================================================================
// Pending Search Management Functions
// =============================================================================
// These functions manage distributed search result collection

// pending_search_start - Start a new pending distributed search
// Input:
//   w0 = number of peers we're sending to
// Output:
//   w0 = query_id assigned to this search
.global pending_search_start
.type pending_search_start, %function
pending_search_start:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     w19, w0                     // peer count

    // Get and increment query ID
    adrp    x0, next_query_id
    add     x0, x0, :lo12:next_query_id
    ldr     w20, [x0]                   // w20 = query_id
    add     w2, w20, #1
    str     w2, [x0]

    // Store query ID
    adrp    x0, pending_query_id
    add     x0, x0, :lo12:pending_query_id
    str     w20, [x0]

    // Store peer count
    adrp    x0, pending_peers_expected
    add     x0, x0, :lo12:pending_peers_expected
    str     w19, [x0]

    // Reset responded count
    adrp    x0, pending_peers_responded
    add     x0, x0, :lo12:pending_peers_responded
    str     wzr, [x0]

    // Reset results count
    adrp    x0, pending_results_count
    add     x0, x0, :lo12:pending_results_count
    str     wzr, [x0]

    mov     w0, w20                     // Return query_id
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size pending_search_start, .-pending_search_start

// pending_search_is_complete - Check if all peers have responded
// Output:
//   w0 = 1 if complete (or no pending search), 0 if still waiting
.global pending_search_is_complete
.type pending_search_is_complete, %function
pending_search_is_complete:
    // Check if there's a pending search
    adrp    x0, pending_query_id
    add     x0, x0, :lo12:pending_query_id
    ldr     w0, [x0]
    cbz     w0, .Lpsc_complete          // No pending search = complete

    // Check responded vs expected
    adrp    x0, pending_peers_expected
    add     x0, x0, :lo12:pending_peers_expected
    ldr     w1, [x0]

    adrp    x0, pending_peers_responded
    add     x0, x0, :lo12:pending_peers_responded
    ldr     w0, [x0]

    cmp     w0, w1
    b.ge    .Lpsc_complete

    mov     w0, #0                      // Not complete
    ret

.Lpsc_complete:
    mov     w0, #1                      // Complete
    ret
.size pending_search_is_complete, .-pending_search_is_complete

// pending_search_get_count - Get number of collected results
// Output:
//   w0 = result count
.global pending_search_get_count
.type pending_search_get_count, %function
pending_search_get_count:
    adrp    x0, pending_results_count
    add     x0, x0, :lo12:pending_results_count
    ldr     w0, [x0]
    ret
.size pending_search_get_count, .-pending_search_get_count

// pending_search_get_result - Get a collected result by index
// Input:
//   w0 = index
//   x1 = pointer to store doc_id (8 bytes)
//   x2 = pointer to store score (4 bytes)
// Output:
//   w0 = 0 on success, -1 if index out of range
.global pending_search_get_result
.type pending_search_get_result, %function
pending_search_get_result:
    // Check bounds
    adrp    x3, pending_results_count
    add     x3, x3, :lo12:pending_results_count
    ldr     w3, [x3]
    cmp     w0, w3
    b.ge    .Lpsgr_error

    // Calculate offset into results buffer
    mov     w4, #RESULT_SIZE
    mul     w4, w0, w4

    adrp    x3, pending_results_buf
    add     x3, x3, :lo12:pending_results_buf
    add     x3, x3, x4

    // Load doc_id and score
    ldr     x4, [x3, #RESULT_OFF_DOC_ID]
    str     x4, [x1]
    ldr     w4, [x3, #RESULT_OFF_SCORE]
    str     w4, [x2]

    mov     w0, #0
    ret

.Lpsgr_error:
    mov     w0, #-1
    ret
.size pending_search_get_result, .-pending_search_get_result

// pending_search_clear - Clear pending search state
.global pending_search_clear
.type pending_search_clear, %function
pending_search_clear:
    adrp    x0, pending_query_id
    add     x0, x0, :lo12:pending_query_id
    str     wzr, [x0]

    adrp    x0, pending_peers_expected
    add     x0, x0, :lo12:pending_peers_expected
    str     wzr, [x0]

    adrp    x0, pending_peers_responded
    add     x0, x0, :lo12:pending_peers_responded
    str     wzr, [x0]

    adrp    x0, pending_results_count
    add     x0, x0, :lo12:pending_results_count
    str     wzr, [x0]

    ret
.size pending_search_clear, .-pending_search_clear

// =============================================================================
// handle_search - Handle incoming search request
// =============================================================================
// Input:
//   x0 = connection fd
//   x1 = message buffer pointer (validated message)
// Output:
//   x0 = 0 on success, -errno on failure
//
// Parses SEARCH payload, executes local search, sends RESULTS response.
// =============================================================================
.global handle_search
.type handle_search, %function
handle_search:
    stp     x29, x30, [sp, #-96]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]
    stp     x27, x28, [sp, #80]

    mov     x19, x0                     // Connection fd
    mov     x20, x1                     // Message buffer

    // Get payload pointer
    add     x21, x20, #MSG_OFF_PAYLOAD  // Payload start

    // Parse search payload
    ldr     w22, [x21, #SEARCH_OFF_QUERY_ID]    // Query ID
    ldr     w23, [x21, #SEARCH_OFF_FLAGS]       // Flags
    ldr     w24, [x21, #SEARCH_OFF_MAX_RESULTS] // Max results
    ldr     w25, [x21, #SEARCH_OFF_QUERY_LEN]   // Query length

    // Validate query length
    cmp     w25, #0
    b.eq    .Lhandle_search_empty
    cmp     w25, #1024                  // Reasonable max query length
    b.hi    .Lhandle_search_invalid

    // Get query string pointer
    add     x26, x21, #SEARCH_OFF_QUERY_STR

    // Cap max results
    cmp     w24, #CLUSTER_MAX_RESULTS
    b.ls    .Lhandle_search_exec
    mov     w24, #CLUSTER_MAX_RESULTS

.Lhandle_search_exec:
    // Execute local FTS search
    // Allocate stack space for local variables
    sub     sp, sp, #32
    // sp+0:  query context pointer
    // sp+8:  result count
    // sp+16: doc_id temp
    // sp+24: score temp

    // Initialize FTS query context
    mov     x0, x24                     // max_results
    bl      fts_query_init
    cbz     x0, .Lhandle_search_init_failed
    str     x0, [sp, #0]                // Save context

    // Parse query string (need to ensure null-termination)
    // The query string at x26 has length w25
    // For safety, copy to a temp buffer and null-terminate
    adrp    x0, handler_query_buf
    add     x0, x0, :lo12:handler_query_buf
    mov     x1, x26                     // source
    mov     w2, w25                     // length
.Lhandle_search_copy:
    cbz     w2, .Lhandle_search_copy_done
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     w2, w2, #1
    b       .Lhandle_search_copy
.Lhandle_search_copy_done:
    strb    wzr, [x0]                   // Null terminate

    // Parse query
    ldr     x0, [sp, #0]                // context
    adrp    x1, handler_query_buf
    add     x1, x1, :lo12:handler_query_buf
    mov     w2, w23                     // flags (query type)
    bl      fts_query_parse
    cmp     x0, #0
    b.le    .Lhandle_search_free_ctx    // No terms or error

    // Execute query
    ldr     x0, [sp, #0]
    bl      fts_query_execute
    str     x0, [sp, #8]                // Save result count
    cbz     x0, .Lhandle_search_free_ctx

    // Build RESULTS response with actual results
    // Call node_get_id first, before setting up other registers
    bl      node_get_id
    mov     x2, x0                      // x2 = source node ID

    // Now set up msg_init parameters
    adrp    x0, handler_msg_buf
    add     x0, x0, :lo12:handler_msg_buf
    mov     x1, #MSG_TYPE_RESULTS
    ldr     x3, [x20, #MSG_OFF_SRC_NODE] // x3 = destination (requester)
    bl      msg_init

    // Build results payload header
    adrp    x0, handler_msg_buf
    add     x0, x0, :lo12:handler_msg_buf
    add     x0, x0, #MSG_OFF_PAYLOAD

    str     w22, [x0, #RESULTS_OFF_QUERY_ID]
    ldr     w1, [sp, #8]
    str     w1, [x0, #RESULTS_OFF_COUNT]
    str     w1, [x0, #RESULTS_OFF_TOTAL]
    str     wzr, [x0, #RESULTS_OFF_RESERVED]

    // Copy result entries
    add     x27, x0, #RESULTS_OFF_ENTRIES  // Result entry pointer
    mov     w28, #0                     // Index

.Lhandle_search_copy_results:
    ldr     w1, [sp, #8]                // result count
    cmp     w28, w1
    b.ge    .Lhandle_search_finalize

    // Get result at index
    ldr     x0, [sp, #0]                // context
    mov     w1, w28                     // index
    add     x2, sp, #16                 // &doc_id
    add     x3, sp, #24                 // &score
    bl      fts_query_get_result
    cbnz    x0, .Lhandle_search_finalize  // Error

    // Copy to result buffer
    ldr     x0, [sp, #16]               // doc_id
    str     x0, [x27, #RESULT_OFF_DOC_ID]
    ldr     w0, [sp, #24]               // score (truncate to 32-bit)
    str     w0, [x27, #RESULT_OFF_SCORE]
    str     wzr, [x27, #RESULT_OFF_FLAGS]

    add     x27, x27, #RESULT_SIZE
    add     w28, w28, #1
    b       .Lhandle_search_copy_results

.Lhandle_search_finalize:
    // Calculate payload length: header + count * RESULT_SIZE
    ldr     w0, [sp, #8]
    mov     w1, #RESULT_SIZE
    mul     w0, w0, w1
    add     w0, w0, #RESULTS_HDR_SIZE

    adrp    x1, handler_msg_buf
    add     x1, x1, :lo12:handler_msg_buf
    str     w0, [x1, #MSG_OFF_LENGTH]

    // Free context
    ldr     x0, [sp, #0]
    bl      fts_query_free
    add     sp, sp, #32
    b       .Lhandle_search_send

.Lhandle_search_free_ctx:
    // Free context and return empty results
    ldr     x0, [sp, #0]
    bl      fts_query_free
    // Fall through

.Lhandle_search_init_failed:
    // Stack was allocated but no context to free
    add     sp, sp, #32

.Lhandle_search_no_results:
    // Build empty RESULTS response
    // Call node_get_id first, before setting up other registers
    bl      node_get_id
    mov     x2, x0                      // x2 = source node ID

    // Now set up msg_init parameters
    adrp    x0, handler_msg_buf
    add     x0, x0, :lo12:handler_msg_buf
    mov     x1, #MSG_TYPE_RESULTS
    ldr     x3, [x20, #MSG_OFF_SRC_NODE] // x3 = destination (requester)
    bl      msg_init

    adrp    x0, handler_msg_buf
    add     x0, x0, :lo12:handler_msg_buf
    add     x0, x0, #MSG_OFF_PAYLOAD
    str     w22, [x0, #RESULTS_OFF_QUERY_ID]
    str     wzr, [x0, #RESULTS_OFF_COUNT]
    str     wzr, [x0, #RESULTS_OFF_TOTAL]
    str     wzr, [x0, #RESULTS_OFF_RESERVED]

    adrp    x0, handler_msg_buf
    add     x0, x0, :lo12:handler_msg_buf
    mov     w1, #RESULTS_HDR_SIZE
    str     w1, [x0, #MSG_OFF_LENGTH]

.Lhandle_search_send:
    // Set x0 to message buffer for msg_finalize
    adrp    x0, handler_msg_buf
    add     x0, x0, :lo12:handler_msg_buf

    // Finalize message (calculate checksum)
    bl      msg_finalize

    // Send response (use write syscall for connected socket)
    mov     x0, x19                     // fd
    adrp    x1, handler_msg_buf
    add     x1, x1, :lo12:handler_msg_buf // buffer
    ldr     w2, [x1, #MSG_OFF_LENGTH]
    add     x2, x2, #MSG_HDR_SIZE       // total size
    mov     x8, #SYS_write
    svc     #0

    cmp     x0, #0
    b.lt    .Lhandle_search_ret         // Return error

    mov     x0, #0                      // Success
    b       .Lhandle_search_ret

.Lhandle_search_empty:
.Lhandle_search_invalid:
    mov     x0, #-22                    // -EINVAL

.Lhandle_search_ret:
    ldp     x27, x28, [sp, #80]
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #96
    ret
.size handle_search, .-handle_search

// =============================================================================
// handle_results - Handle incoming search results
// =============================================================================
// Input:
//   x0 = connection fd
//   x1 = message buffer pointer (validated message)
// Output:
//   x0 = 0 on success, -errno on failure
//
// Parses RESULTS payload, merges into pending query, triggers callback
// when all responses received.
// =============================================================================
.global handle_results
.type handle_results, %function
handle_results:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0                     // Connection fd
    mov     x20, x1                     // Message buffer

    // Get payload pointer
    add     x21, x20, #MSG_OFF_PAYLOAD

    // Parse results header
    ldr     w22, [x21, #RESULTS_OFF_QUERY_ID]   // Query ID
    ldr     w23, [x21, #RESULTS_OFF_COUNT]      // Result count
    ldr     w24, [x21, #RESULTS_OFF_TOTAL]      // Total matches

    // Validate result count against payload size
    ldr     w0, [x20, #MSG_OFF_LENGTH]
    sub     w0, w0, #RESULTS_HDR_SIZE   // Payload minus header
    mov     w1, #RESULT_SIZE
    udiv    w0, w0, w1                  // Max entries that fit
    cmp     w23, w0
    b.hi    .Lhandle_results_invalid

    // Check if this matches our pending query
    adrp    x0, pending_query_id
    add     x0, x0, :lo12:pending_query_id
    ldr     w0, [x0]
    cmp     w0, w22
    b.ne    .Lhandle_results_wrong_query

    // Copy results to pending buffer
    // Get current count and calculate destination
    adrp    x0, pending_results_count
    add     x0, x0, :lo12:pending_results_count
    ldr     w25, [x0]                   // Current count

    // Check if we have space (max 64 results)
    add     w26, w25, w23               // New total
    cmp     w26, #64
    b.hi    .Lhandle_results_full

    // Calculate destination pointer
    adrp    x0, pending_results_buf
    add     x0, x0, :lo12:pending_results_buf
    mov     w1, #RESULT_SIZE
    mul     w1, w25, w1
    add     x0, x0, x1                  // x0 = dest ptr

    // Source pointer (after results header)
    add     x1, x21, #RESULTS_OFF_ENTRIES

    // Copy w23 results (each RESULT_SIZE bytes)
    mov     w2, w23                     // count
    cbz     w2, .Lhandle_results_copy_done

.Lhandle_results_copy_loop:
    // Copy one result entry (16 bytes)
    ldr     x3, [x1, #RESULT_OFF_DOC_ID]
    str     x3, [x0, #RESULT_OFF_DOC_ID]
    ldr     w3, [x1, #RESULT_OFF_SCORE]
    str     w3, [x0, #RESULT_OFF_SCORE]
    ldr     w3, [x1, #RESULT_OFF_FLAGS]
    str     w3, [x0, #RESULT_OFF_FLAGS]

    add     x0, x0, #RESULT_SIZE
    add     x1, x1, #RESULT_SIZE
    sub     w2, w2, #1
    cbnz    w2, .Lhandle_results_copy_loop

.Lhandle_results_copy_done:
    // Update pending_results_count
    adrp    x0, pending_results_count
    add     x0, x0, :lo12:pending_results_count
    str     w26, [x0]

.Lhandle_results_full:
    // Increment peers responded count
    adrp    x0, pending_peers_responded
    add     x0, x0, :lo12:pending_peers_responded
    ldr     w1, [x0]
    add     w1, w1, #1
    str     w1, [x0]

    mov     x0, #0
    b       .Lhandle_results_ret

.Lhandle_results_wrong_query:
    // Query ID doesn't match - ignore silently
    mov     x0, #0
    b       .Lhandle_results_ret

.Lhandle_results_invalid:
    mov     x0, #-22                    // -EINVAL

.Lhandle_results_ret:
    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size handle_results, .-handle_results

// =============================================================================
// handle_index - Handle incoming index update
// =============================================================================
// Input:
//   x0 = connection fd
//   x1 = message buffer pointer (validated message)
// Output:
//   x0 = 0 on success, -errno on failure
//
// Parses INDEX payload, applies PUT/DELETE to local store and index.
// =============================================================================
.global handle_index
.type handle_index, %function
handle_index:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // Connection fd
    mov     x20, x1                     // Message buffer

    // Get payload pointer
    add     x21, x20, #MSG_OFF_PAYLOAD

    // Parse index header
    ldr     x22, [x21, #INDEX_OFF_DOC_ID]       // Document ID
    ldr     w23, [x21, #INDEX_OFF_OPERATION]    // Operation
    ldr     w24, [x21, #INDEX_OFF_DOC_LEN]      // Document length

    // Validate operation
    cmp     w23, #INDEX_OP_PUT
    b.eq    .Lhandle_index_put
    cmp     w23, #INDEX_OP_DELETE
    b.eq    .Lhandle_index_delete

    // Unknown operation
    mov     x0, #-22                    // -EINVAL
    b       .Lhandle_index_ret

.Lhandle_index_put:
    // Validate document length against payload
    ldr     w0, [x20, #MSG_OFF_LENGTH]
    sub     w0, w0, #INDEX_HDR_SIZE
    cmp     w24, w0
    b.hi    .Lhandle_index_invalid

    // Index document for full-text search
    // fts_index_add(doc_id, content, len)
    mov     x0, x22                     // doc_id
    add     x1, x21, #INDEX_OFF_DOC_DATA // content pointer
    mov     w2, w24                     // length
    bl      fts_index_add
    cmp     x0, #0
    b.lt    .Lhandle_index_ret          // Error from fts_index_add

    // Record ownership (sender is primary, we are replica)
    // replica_record_ownership(doc_id, primary_node_id, replica_bitmap)
    mov     x0, x22                     // doc_id
    ldr     x1, [x20, #MSG_OFF_SRC_NODE] // primary = sender
    mov     x2, #0                      // No further replicas
    bl      replica_record_ownership

    // Update local document count
    bl      node_inc_doc_count

    mov     x0, #0
    b       .Lhandle_index_ret

.Lhandle_index_delete:
    // In full implementation:
    // 1. Call doc_store_delete(doc_id)
    // 2. Call fts_index_remove(doc_id)
    // 3. Call replica_remove_ownership(doc_id)

    // Update local document count
    bl      node_dec_doc_count

    mov     x0, #0
    b       .Lhandle_index_ret

.Lhandle_index_invalid:
    mov     x0, #-22                    // -EINVAL

.Lhandle_index_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size handle_index, .-handle_index

// =============================================================================
// handler_dispatch - Dispatch message to appropriate handler
// =============================================================================
// Input:
//   x0 = connection fd
//   x1 = message buffer pointer (validated message)
// Output:
//   x0 = 0 on success, -errno on failure
// =============================================================================
.global handler_dispatch
.type handler_dispatch, %function
handler_dispatch:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // fd
    mov     x20, x1                     // msg

    // Get message type
    ldrb    w0, [x20, #MSG_OFF_TYPE]

    // Dispatch based on type
    cmp     w0, #MSG_TYPE_SEARCH
    b.eq    .Ldispatch_search

    cmp     w0, #MSG_TYPE_RESULTS
    b.eq    .Ldispatch_results

    cmp     w0, #MSG_TYPE_INDEX
    b.eq    .Ldispatch_index

    // Unknown type - not an error, just ignore
    mov     x0, #0
    b       .Ldispatch_ret

.Ldispatch_search:
    mov     x0, x19
    mov     x1, x20
    bl      handle_search
    b       .Ldispatch_ret

.Ldispatch_results:
    mov     x0, x19
    mov     x1, x20
    bl      handle_results
    b       .Ldispatch_ret

.Ldispatch_index:
    mov     x0, x19
    mov     x1, x20
    bl      handle_index

.Ldispatch_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size handler_dispatch, .-handler_dispatch

// =============================================================================
// build_search_msg - Build a SEARCH message
// =============================================================================
// Input:
//   x0 = output buffer
//   x1 = query_id
//   x2 = flags
//   x3 = max_results
//   x4 = query string pointer
//   x5 = query string length
// Output:
//   x0 = total message size, or -errno on failure
// =============================================================================
.global build_search_msg
.type build_search_msg, %function
build_search_msg:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // Buffer
    mov     w20, w1                     // Query ID
    mov     w21, w2                     // Flags
    mov     w22, w3                     // Max results
    mov     x23, x4                     // Query string
    mov     x24, x5                     // Query length

    // Validate query length
    cmp     x24, #0
    b.eq    .Lbuild_search_invalid
    ldr     x0, =NET_MAX_MSG_SIZE
    sub     x0, x0, #SEARCH_HDR_SIZE
    cmp     x24, x0
    b.hi    .Lbuild_search_invalid

    // Initialize header
    mov     x0, x19
    mov     x1, #MSG_TYPE_SEARCH
    bl      node_get_id
    mov     x2, x0                      // src = our node
    mov     x3, #0                      // dst = broadcast (0)
    mov     x0, x19
    bl      msg_init

    // Build payload
    add     x0, x19, #MSG_OFF_PAYLOAD
    str     w20, [x0, #SEARCH_OFF_QUERY_ID]
    str     w21, [x0, #SEARCH_OFF_FLAGS]
    str     w22, [x0, #SEARCH_OFF_MAX_RESULTS]
    str     w24, [x0, #SEARCH_OFF_QUERY_LEN]

    // Copy query string
    add     x0, x0, #SEARCH_OFF_QUERY_STR
    mov     x1, x23
    mov     x2, x24
.Lbuild_search_copy:
    cbz     x2, .Lbuild_search_finalize
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     x2, x2, #1
    b       .Lbuild_search_copy

.Lbuild_search_finalize:
    // Set payload length
    add     x0, x24, #SEARCH_HDR_SIZE
    str     w0, [x19, #MSG_OFF_LENGTH]

    // Finalize (checksum)
    mov     x0, x19
    bl      msg_finalize

    // Return total size
    ldr     w0, [x19, #MSG_OFF_LENGTH]
    add     x0, x0, #MSG_HDR_SIZE
    b       .Lbuild_search_ret

.Lbuild_search_invalid:
    mov     x0, #-22                    // -EINVAL

.Lbuild_search_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size build_search_msg, .-build_search_msg

// =============================================================================
// build_index_msg - Build an INDEX message
// =============================================================================
// Input:
//   x0 = output buffer
//   x1 = document ID
//   x2 = operation (INDEX_OP_PUT or INDEX_OP_DELETE)
//   x3 = document data pointer (NULL for DELETE)
//   x4 = document length (0 for DELETE)
// Output:
//   x0 = total message size, or -errno on failure
// =============================================================================
.global build_index_msg
.type build_index_msg, %function
build_index_msg:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0                     // Buffer
    mov     x20, x1                     // Doc ID
    mov     w21, w2                     // Operation
    mov     x22, x3                     // Data
    mov     x23, x4                     // Length

    // Validate operation
    cmp     w21, #INDEX_OP_PUT
    b.eq    .Lbuild_index_validate
    cmp     w21, #INDEX_OP_DELETE
    b.ne    .Lbuild_index_invalid

.Lbuild_index_validate:
    // Validate data length for PUT
    cmp     w21, #INDEX_OP_PUT
    b.ne    .Lbuild_index_header

    ldr     x0, =NET_MAX_MSG_SIZE
    sub     x0, x0, #INDEX_HDR_SIZE
    cmp     x23, x0
    b.hi    .Lbuild_index_invalid

.Lbuild_index_header:
    // Initialize header
    mov     x0, x19
    mov     x1, #MSG_TYPE_INDEX
    bl      node_get_id
    mov     x2, x0                      // src = our node
    mov     x3, #0                      // dst = broadcast (0)
    mov     x0, x19
    bl      msg_init

    // Build payload
    add     x0, x19, #MSG_OFF_PAYLOAD
    str     x20, [x0, #INDEX_OFF_DOC_ID]
    str     w21, [x0, #INDEX_OFF_OPERATION]
    str     w23, [x0, #INDEX_OFF_DOC_LEN]

    // Copy document data for PUT
    cmp     w21, #INDEX_OP_PUT
    b.ne    .Lbuild_index_finalize
    cbz     x23, .Lbuild_index_finalize

    add     x0, x0, #INDEX_OFF_DOC_DATA
    mov     x1, x22
    mov     x2, x23
.Lbuild_index_copy:
    cbz     x2, .Lbuild_index_finalize
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    sub     x2, x2, #1
    b       .Lbuild_index_copy

.Lbuild_index_finalize:
    // Set payload length
    add     x0, x23, #INDEX_HDR_SIZE
    str     w0, [x19, #MSG_OFF_LENGTH]

    // Finalize (checksum)
    mov     x0, x19
    bl      msg_finalize

    // Return total size
    ldr     w0, [x19, #MSG_OFF_LENGTH]
    add     x0, x0, #MSG_HDR_SIZE
    b       .Lbuild_index_ret

.Lbuild_index_invalid:
    mov     x0, #-22                    // -EINVAL

.Lbuild_index_ret:
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size build_index_msg, .-build_index_msg
