// =============================================================================
// Omesh - Node State Management
// =============================================================================
//
// Manages local node identity and state:
// - node_init: Initialize node with ID
// - node_get_id: Return node ID
// - node_set_state/get_state: State management
// - node_inc_doc_count/get_doc_count: Document tracking
// - node_inc_peer_count/dec_peer_count: Peer tracking
// - node_generate_query_id: Generate unique query IDs
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
//   node_init(node_id) -> 0 | -errno
//       Initialize node state with given ID.
//       If node_id == 0, generates random ID from /dev/urandom.
//       Sets state to NODE_STATE_INIT.
//
//   node_get_id() -> node_id
//       Return this node's 64-bit unique identifier.
//
//   node_set_state(state) -> 0
//       Set node state (NODE_STATE_INIT/READY/SYNCING).
//
//   node_get_state() -> state
//       Return current node state.
//
//   node_inc_doc_count() -> new_count
//       Atomically increment document count and return new value.
//
//   node_get_doc_count() -> count
//       Return current document count.
//
//   node_inc_peer_count() -> new_count
//       Increment connected peer count.
//
//   node_dec_peer_count() -> new_count
//       Decrement connected peer count.
//
//   node_generate_query_id() -> query_id
//       Generate unique 32-bit query ID (monotonic counter).
//
// INTERNAL STATE:
//   g_node - NODE_SIZE structure containing all node state
//
// =============================================================================

.include "syscall_nums.inc"
.include "cluster.inc"

.data

// =============================================================================
// Global Node State
// =============================================================================

.global g_node
.align 8
g_node:
    .skip   NODE_SIZE

.text

// =============================================================================
// node_init - Initialize node state
// =============================================================================
// Input:
//   x0 = node_id (0 to auto-generate from random)
// Output:
//   x0 = 0 on success, -errno on failure
// =============================================================================
.global node_init
.type node_init, %function
node_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Save node_id

    // Clear entire node structure
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    mov     x1, #NODE_SIZE
.Lnode_clear:
    strb    wzr, [x0], #1
    subs    x1, x1, #1
    b.ne    .Lnode_clear

    // If node_id is 0, generate from random
    cbnz    x19, .Lnode_set_id

    // Read random bytes for node ID
    // getrandom(buf, buflen, flags)
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node        // buf = node struct as temp buffer
    mov     x1, #8                      // buflen = 8 bytes
    mov     x2, #0                      // flags = 0
    mov     x8, #SYS_getrandom
    svc     #0
    cmp     x0, #8
    b.ne    .Lnode_init_random_err

    // Load the random value as node ID
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    ldr     x19, [x0]

    // Ensure non-zero (extremely unlikely but handle it)
    cbnz    x19, .Lnode_set_id
    mov     x19, #1

.Lnode_set_id:
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    str     x19, [x0, #NODE_OFF_ID]

    // Set initial state to INIT
    mov     w1, #NODE_STATE_INIT
    str     w1, [x0, #NODE_OFF_STATE]

    // Clear flags
    str     wzr, [x0, #NODE_OFF_FLAGS]

    // Clear counts
    str     xzr, [x0, #NODE_OFF_DOC_COUNT]
    str     wzr, [x0, #NODE_OFF_PEER_COUNT]
    str     wzr, [x0, #NODE_OFF_REPLICA_OF]
    str     wzr, [x0, #NODE_OFF_QUERY_SEQ]

    // Set last sync to 0
    str     xzr, [x0, #NODE_OFF_LAST_SYNC]

    mov     x0, #0
    b       .Lnode_init_ret

.Lnode_init_random_err:
    mov     x0, #-5                     // -EIO

.Lnode_init_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size node_init, .-node_init

// =============================================================================
// node_get_id - Get this node's ID
// =============================================================================
// Output:
//   x0 = node ID
// =============================================================================
.global node_get_id
.type node_get_id, %function
node_get_id:
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    ldr     x0, [x0, #NODE_OFF_ID]
    ret
.size node_get_id, .-node_get_id

// =============================================================================
// node_set_state - Set node state
// =============================================================================
// Input:
//   x0 = new state (NODE_STATE_*)
// Output:
//   x0 = 0
// =============================================================================
.global node_set_state
.type node_set_state, %function
node_set_state:
    adrp    x1, g_node
    add     x1, x1, :lo12:g_node
    str     w0, [x1, #NODE_OFF_STATE]
    mov     x0, #0
    ret
.size node_set_state, .-node_set_state

// =============================================================================
// node_get_state - Get node state
// =============================================================================
// Output:
//   x0 = current state
// =============================================================================
.global node_get_state
.type node_get_state, %function
node_get_state:
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    ldr     w0, [x0, #NODE_OFF_STATE]
    ret
.size node_get_state, .-node_get_state

// =============================================================================
// node_set_flags - Set node flags
// =============================================================================
// Input:
//   x0 = flags
// Output:
//   x0 = 0
// =============================================================================
.global node_set_flags
.type node_set_flags, %function
node_set_flags:
    adrp    x1, g_node
    add     x1, x1, :lo12:g_node
    str     w0, [x1, #NODE_OFF_FLAGS]
    mov     x0, #0
    ret
.size node_set_flags, .-node_set_flags

// =============================================================================
// node_get_flags - Get node flags
// =============================================================================
// Output:
//   x0 = flags
// =============================================================================
.global node_get_flags
.type node_get_flags, %function
node_get_flags:
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    ldr     w0, [x0, #NODE_OFF_FLAGS]
    ret
.size node_get_flags, .-node_get_flags

// =============================================================================
// node_inc_doc_count - Increment document count
// =============================================================================
// Output:
//   x0 = new document count
// =============================================================================
.global node_inc_doc_count
.type node_inc_doc_count, %function
node_inc_doc_count:
    adrp    x1, g_node
    add     x1, x1, :lo12:g_node
    ldr     x0, [x1, #NODE_OFF_DOC_COUNT]
    add     x0, x0, #1
    str     x0, [x1, #NODE_OFF_DOC_COUNT]
    ret
.size node_inc_doc_count, .-node_inc_doc_count

// =============================================================================
// node_dec_doc_count - Decrement document count
// =============================================================================
// Output:
//   x0 = new document count
// =============================================================================
.global node_dec_doc_count
.type node_dec_doc_count, %function
node_dec_doc_count:
    adrp    x1, g_node
    add     x1, x1, :lo12:g_node
    ldr     x0, [x1, #NODE_OFF_DOC_COUNT]
    cbz     x0, .Ldec_doc_skip          // Don't go negative
    sub     x0, x0, #1
    str     x0, [x1, #NODE_OFF_DOC_COUNT]
.Ldec_doc_skip:
    ret
.size node_dec_doc_count, .-node_dec_doc_count

// =============================================================================
// node_get_doc_count - Get document count
// =============================================================================
// Output:
//   x0 = document count
// =============================================================================
.global node_get_doc_count
.type node_get_doc_count, %function
node_get_doc_count:
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    ldr     x0, [x0, #NODE_OFF_DOC_COUNT]
    ret
.size node_get_doc_count, .-node_get_doc_count

// =============================================================================
// node_inc_peer_count - Increment peer count
// =============================================================================
// Output:
//   x0 = new peer count
// =============================================================================
.global node_inc_peer_count
.type node_inc_peer_count, %function
node_inc_peer_count:
    adrp    x1, g_node
    add     x1, x1, :lo12:g_node
    ldr     w0, [x1, #NODE_OFF_PEER_COUNT]
    add     w0, w0, #1
    str     w0, [x1, #NODE_OFF_PEER_COUNT]
    ret
.size node_inc_peer_count, .-node_inc_peer_count

// =============================================================================
// node_dec_peer_count - Decrement peer count
// =============================================================================
// Output:
//   x0 = new peer count
// =============================================================================
.global node_dec_peer_count
.type node_dec_peer_count, %function
node_dec_peer_count:
    adrp    x1, g_node
    add     x1, x1, :lo12:g_node
    ldr     w0, [x1, #NODE_OFF_PEER_COUNT]
    cbz     w0, .Ldec_peer_skip         // Don't go negative
    sub     w0, w0, #1
    str     w0, [x1, #NODE_OFF_PEER_COUNT]
.Ldec_peer_skip:
    ret
.size node_dec_peer_count, .-node_dec_peer_count

// =============================================================================
// node_get_peer_count - Get peer count
// =============================================================================
// Output:
//   x0 = peer count
// =============================================================================
.global node_get_peer_count
.type node_get_peer_count, %function
node_get_peer_count:
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    ldr     w0, [x0, #NODE_OFF_PEER_COUNT]
    ret
.size node_get_peer_count, .-node_get_peer_count

// =============================================================================
// node_inc_replica_count - Increment replica-of count
// =============================================================================
// Output:
//   x0 = new replica count
// =============================================================================
.global node_inc_replica_count
.type node_inc_replica_count, %function
node_inc_replica_count:
    adrp    x1, g_node
    add     x1, x1, :lo12:g_node
    ldr     w0, [x1, #NODE_OFF_REPLICA_OF]
    add     w0, w0, #1
    str     w0, [x1, #NODE_OFF_REPLICA_OF]
    ret
.size node_inc_replica_count, .-node_inc_replica_count

// =============================================================================
// node_get_replica_count - Get replica-of count
// =============================================================================
// Output:
//   x0 = replica count
// =============================================================================
.global node_get_replica_count
.type node_get_replica_count, %function
node_get_replica_count:
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    ldr     w0, [x0, #NODE_OFF_REPLICA_OF]
    ret
.size node_get_replica_count, .-node_get_replica_count

// =============================================================================
// node_generate_query_id - Generate unique query ID
// =============================================================================
// Output:
//   x0 = new query ID (never 0)
// =============================================================================
.global node_generate_query_id
.type node_generate_query_id, %function
node_generate_query_id:
    adrp    x1, g_node
    add     x1, x1, :lo12:g_node
    ldr     w0, [x1, #NODE_OFF_QUERY_SEQ]
    add     w0, w0, #1
    // Handle wraparound - skip 0
    cbnz    w0, .Lquery_id_store
    mov     w0, #1
.Lquery_id_store:
    str     w0, [x1, #NODE_OFF_QUERY_SEQ]
    ret
.size node_generate_query_id, .-node_generate_query_id

// =============================================================================
// node_update_sync_time - Update last sync timestamp
// =============================================================================
// Input:
//   x0 = timestamp (0 to use current time)
// Output:
//   x0 = 0 on success, -errno on failure
// =============================================================================
.global node_update_sync_time
.type node_update_sync_time, %function
node_update_sync_time:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    // If timestamp provided, use it
    cbnz    x19, .Lsync_store

    // Get current time
    sub     sp, sp, #16
    mov     x0, #1                      // CLOCK_MONOTONIC
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0
    cmp     x0, #0
    b.lt    .Lsync_time_err

    // Convert to nanoseconds
    ldr     x19, [sp]                   // seconds
    ldr     x1, [sp, #8]                // nanoseconds
    ldr     x2, =1000000000
    mul     x19, x19, x2
    add     x19, x19, x1
    add     sp, sp, #16

.Lsync_store:
    adrp    x1, g_node
    add     x1, x1, :lo12:g_node
    str     x19, [x1, #NODE_OFF_LAST_SYNC]
    mov     x0, #0
    b       .Lsync_ret

.Lsync_time_err:
    add     sp, sp, #16
    // x0 already has error

.Lsync_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size node_update_sync_time, .-node_update_sync_time

// =============================================================================
// node_get_sync_time - Get last sync timestamp
// =============================================================================
// Output:
//   x0 = last sync timestamp (ns)
// =============================================================================
.global node_get_sync_time
.type node_get_sync_time, %function
node_get_sync_time:
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    ldr     x0, [x0, #NODE_OFF_LAST_SYNC]
    ret
.size node_get_sync_time, .-node_get_sync_time

// =============================================================================
// node_get_ptr - Get pointer to node structure
// =============================================================================
// Output:
//   x0 = pointer to g_node
// =============================================================================
.global node_get_ptr
.type node_get_ptr, %function
node_get_ptr:
    adrp    x0, g_node
    add     x0, x0, :lo12:g_node
    ret
.size node_get_ptr, .-node_get_ptr
