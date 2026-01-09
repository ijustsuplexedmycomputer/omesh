// =============================================================================
// Omesh - test_cluster.s
// Distributed coordination layer test program
// =============================================================================
//
// Tests cluster components:
// - Node state management
// - Message handlers
// - Replication manager
// - Query router
//
// =============================================================================

.include "include/syscall_nums.inc"
.include "include/net.inc"
.include "include/cluster.inc"

// Import HAL
.extern hal_init
.extern print_str
.extern print_dec
.extern print_hex
.extern print_newline
.extern print_char

// Import protocol functions
.extern msg_init
.extern msg_set_payload
.extern msg_finalize
.extern msg_validate
.extern msg_get_type
.extern msg_get_length
.extern crc32_calc

// Import node functions
.extern node_init
.extern node_get_id
.extern node_set_state
.extern node_get_state
.extern node_inc_doc_count
.extern node_dec_doc_count
.extern node_get_doc_count
.extern node_inc_peer_count
.extern node_dec_peer_count
.extern node_get_peer_count
.extern node_generate_query_id

// Import handler functions
.extern handler_init
.extern handler_is_ready
.extern build_search_msg
.extern build_index_msg

// Import replica functions
.extern replica_init
.extern replica_record_ownership
.extern replica_find_ownership
.extern replica_get_primary
.extern replica_get_replicas
.extern replica_select_peers
.extern replica_get_ownership_count

// Import router functions
.extern router_init
.extern router_alloc_pending
.extern router_free_pending
.extern router_find_pending
.extern router_get_pending_ptr
.extern router_get_pending_count

.text
.balign 4

// =============================================================================
// _start - Test entry point
// =============================================================================
.global _start
_start:
    mov     x29, sp

    // Initialize HAL first
    bl      hal_init

    // Print header
    adrp    x0, msg_header
    add     x0, x0, :lo12:msg_header
    bl      print_str

    // Initialize test counters
    adrp    x19, test_passed
    add     x19, x19, :lo12:test_passed
    str     xzr, [x19]
    adrp    x20, test_total
    add     x20, x20, :lo12:test_total
    str     xzr, [x20]

    // Run tests
    bl      test_node_init
    bl      test_node_state
    bl      test_node_doc_count
    bl      test_node_peer_count
    bl      test_query_id_gen
    bl      test_handler_init
    bl      test_build_search_msg
    bl      test_build_index_msg
    bl      test_replica_init
    bl      test_replica_ownership
    bl      test_replica_select_peers
    bl      test_router_init
    bl      test_router_pending_alloc
    bl      test_router_pending_find

    // Print summary
    adrp    x0, msg_summary
    add     x0, x0, :lo12:msg_summary
    bl      print_str

    ldr     x0, [x19]
    bl      print_dec

    mov     x0, #'/'
    bl      print_char

    ldr     x0, [x20]
    bl      print_dec

    adrp    x0, msg_tests_passed
    add     x0, x0, :lo12:msg_tests_passed
    bl      print_str
    bl      print_newline

    // Exit with appropriate code
    ldr     x0, [x19]           // passed
    ldr     x1, [x20]           // total
    cmp     x0, x1
    b.eq    .Lexit_success

    mov     x0, #1
    mov     x8, #SYS_exit_group
    svc     #0

.Lexit_success:
    mov     x0, #0
    mov     x8, #SYS_exit_group
    svc     #0

// =============================================================================
// Test helper functions
// =============================================================================

// Print [PASS] or [FAIL] and increment counters
// x0 = 0 for pass, non-zero for fail
// x1 = test name string
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

    cbz     x19, .Ltest_pass

    // FAIL
    adrp    x0, msg_fail
    add     x0, x0, :lo12:msg_fail
    bl      print_str
    b       .Ltest_name

.Ltest_pass:
    // Increment passed
    adrp    x0, test_passed
    add     x0, x0, :lo12:test_passed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_str

.Ltest_name:
    mov     x0, x20
    bl      print_str
    bl      print_newline

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_node_init - Test node initialization
// =============================================================================
test_node_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Initialize with explicit ID
    ldr     x0, =0x123456789ABCDEF0
    bl      node_init
    cmp     x0, #0
    b.ne    .Lnode_init_fail

    // Verify ID
    bl      node_get_id
    ldr     x1, =0x123456789ABCDEF0
    cmp     x0, x1
    b.ne    .Lnode_init_fail

    // Verify initial state
    bl      node_get_state
    cmp     x0, #NODE_STATE_INIT
    b.ne    .Lnode_init_fail

    mov     x0, #0
    b       .Lnode_init_result

.Lnode_init_fail:
    mov     x0, #1

.Lnode_init_result:
    adrp    x1, name_node_init
    add     x1, x1, :lo12:name_node_init
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_node_state - Test node state transitions
// =============================================================================
test_node_state:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Set state to SYNCING
    mov     x0, #NODE_STATE_SYNCING
    bl      node_set_state
    bl      node_get_state
    cmp     x0, #NODE_STATE_SYNCING
    b.ne    .Lnode_state_fail

    // Set state to READY
    mov     x0, #NODE_STATE_READY
    bl      node_set_state
    bl      node_get_state
    cmp     x0, #NODE_STATE_READY
    b.ne    .Lnode_state_fail

    mov     x0, #0
    b       .Lnode_state_result

.Lnode_state_fail:
    mov     x0, #1

.Lnode_state_result:
    adrp    x1, name_node_state
    add     x1, x1, :lo12:name_node_state
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_node_doc_count - Test document count tracking
// =============================================================================
test_node_doc_count:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Re-initialize to reset counters
    mov     x0, #0x1234
    bl      node_init

    // Get initial count (should be 0)
    bl      node_get_doc_count
    cbnz    x0, .Lnode_doc_fail

    // Increment
    bl      node_inc_doc_count
    cmp     x0, #1
    b.ne    .Lnode_doc_fail

    bl      node_inc_doc_count
    cmp     x0, #2
    b.ne    .Lnode_doc_fail

    // Decrement
    bl      node_dec_doc_count
    cmp     x0, #1
    b.ne    .Lnode_doc_fail

    // Verify count
    bl      node_get_doc_count
    cmp     x0, #1
    b.ne    .Lnode_doc_fail

    mov     x0, #0
    b       .Lnode_doc_result

.Lnode_doc_fail:
    mov     x0, #1

.Lnode_doc_result:
    adrp    x1, name_node_doc_count
    add     x1, x1, :lo12:name_node_doc_count
    bl      test_result

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_node_peer_count - Test peer count tracking
// =============================================================================
test_node_peer_count:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Re-initialize
    mov     x0, #0x5678
    bl      node_init

    // Initial peer count should be 0
    bl      node_get_peer_count
    cbnz    x0, .Lnode_peer_fail

    // Increment
    bl      node_inc_peer_count
    cmp     x0, #1
    b.ne    .Lnode_peer_fail

    bl      node_inc_peer_count
    bl      node_inc_peer_count
    bl      node_get_peer_count
    cmp     x0, #3
    b.ne    .Lnode_peer_fail

    // Decrement
    bl      node_dec_peer_count
    cmp     x0, #2
    b.ne    .Lnode_peer_fail

    mov     x0, #0
    b       .Lnode_peer_result

.Lnode_peer_fail:
    mov     x0, #1

.Lnode_peer_result:
    adrp    x1, name_node_peer_count
    add     x1, x1, :lo12:name_node_peer_count
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_query_id_gen - Test query ID generation
// =============================================================================
test_query_id_gen:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Re-initialize
    mov     x0, #0x9ABC
    bl      node_init

    // Generate IDs - should be sequential and non-zero
    bl      node_generate_query_id
    cmp     x0, #0
    b.eq    .Lquery_id_fail
    mov     x19, x0

    bl      node_generate_query_id
    cmp     x0, x19
    b.eq    .Lquery_id_fail              // Should be different
    add     x1, x19, #1
    cmp     x0, x1
    b.ne    .Lquery_id_fail              // Should be sequential

    mov     x0, #0
    b       .Lquery_id_result

.Lquery_id_fail:
    mov     x0, #1

.Lquery_id_result:
    adrp    x1, name_query_id_gen
    add     x1, x1, :lo12:name_query_id_gen
    bl      test_result

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_handler_init - Test handler initialization
// =============================================================================
test_handler_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      handler_init
    cmp     x0, #0
    b.ne    .Lhandler_init_fail

    bl      handler_is_ready
    cmp     x0, #1
    b.ne    .Lhandler_init_fail

    mov     x0, #0
    b       .Lhandler_init_result

.Lhandler_init_fail:
    mov     x0, #1

.Lhandler_init_result:
    adrp    x1, name_handler_init
    add     x1, x1, :lo12:name_handler_init
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_build_search_msg - Test SEARCH message building
// =============================================================================
test_build_search_msg:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Initialize node for msg building
    mov     x0, #0xDEAD
    bl      node_init

    // Build search message
    adrp    x0, test_msg_buf
    add     x0, x0, :lo12:test_msg_buf
    mov     x1, #42                     // Query ID
    mov     x2, #SEARCH_FLAG_OR         // Flags
    mov     x3, #10                     // Max results
    adrp    x4, test_query_str
    add     x4, x4, :lo12:test_query_str
    mov     x5, #5                      // "hello" length
    bl      build_search_msg

    cmp     x0, #0
    b.lt    .Lbuild_search_fail

    // Verify message type
    adrp    x0, test_msg_buf
    add     x0, x0, :lo12:test_msg_buf
    ldrb    w0, [x0, #MSG_OFF_TYPE]
    cmp     w0, #MSG_TYPE_SEARCH
    b.ne    .Lbuild_search_fail

    // Verify payload
    adrp    x0, test_msg_buf
    add     x0, x0, :lo12:test_msg_buf
    add     x0, x0, #MSG_OFF_PAYLOAD
    ldr     w1, [x0, #SEARCH_OFF_QUERY_ID]
    cmp     w1, #42
    b.ne    .Lbuild_search_fail

    ldr     w1, [x0, #SEARCH_OFF_QUERY_LEN]
    cmp     w1, #5
    b.ne    .Lbuild_search_fail

    mov     x0, #0
    b       .Lbuild_search_result

.Lbuild_search_fail:
    mov     x0, #1

.Lbuild_search_result:
    adrp    x1, name_build_search
    add     x1, x1, :lo12:name_build_search
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_build_index_msg - Test INDEX message building
// =============================================================================
test_build_index_msg:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Build index message
    adrp    x0, test_msg_buf
    add     x0, x0, :lo12:test_msg_buf
    ldr     x1, =0x123456789ABCDEF0     // Doc ID
    mov     x2, #INDEX_OP_PUT           // Operation
    adrp    x3, test_doc_content
    add     x3, x3, :lo12:test_doc_content
    mov     x4, #11                     // "Hello World" length
    bl      build_index_msg

    cmp     x0, #0
    b.lt    .Lbuild_index_fail

    // Verify message type
    adrp    x0, test_msg_buf
    add     x0, x0, :lo12:test_msg_buf
    ldrb    w0, [x0, #MSG_OFF_TYPE]
    cmp     w0, #MSG_TYPE_INDEX
    b.ne    .Lbuild_index_fail

    // Verify payload
    adrp    x0, test_msg_buf
    add     x0, x0, :lo12:test_msg_buf
    add     x0, x0, #MSG_OFF_PAYLOAD
    ldr     x1, [x0, #INDEX_OFF_DOC_ID]
    ldr     x2, =0x123456789ABCDEF0
    cmp     x1, x2
    b.ne    .Lbuild_index_fail

    ldr     w1, [x0, #INDEX_OFF_OPERATION]
    cmp     w1, #INDEX_OP_PUT
    b.ne    .Lbuild_index_fail

    mov     x0, #0
    b       .Lbuild_index_result

.Lbuild_index_fail:
    mov     x0, #1

.Lbuild_index_result:
    adrp    x1, name_build_index
    add     x1, x1, :lo12:name_build_index
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_replica_init - Test replica manager initialization
// =============================================================================
test_replica_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      replica_init

    // Verify ownership count is 0
    bl      replica_get_ownership_count
    cmp     x0, #0
    cset    w0, ne

    adrp    x1, name_replica_init
    add     x1, x1, :lo12:name_replica_init
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_replica_ownership - Test ownership recording
// =============================================================================
test_replica_ownership:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Initialize replica manager
    bl      replica_init

    // Record ownership
    ldr     x0, =0xABCD1234             // Doc ID
    ldr     x1, =0x1111222233334444     // Primary node
    mov     x2, #0b00000101             // Replicas bitmap
    bl      replica_record_ownership
    cmp     x0, #0
    b.ne    .Lownership_fail

    // Verify ownership count
    bl      replica_get_ownership_count
    cmp     x0, #1
    b.ne    .Lownership_fail

    // Get primary
    ldr     x0, =0xABCD1234
    bl      replica_get_primary
    ldr     x1, =0x1111222233334444
    cmp     x0, x1
    b.ne    .Lownership_fail

    // Get replicas
    ldr     x0, =0xABCD1234
    bl      replica_get_replicas
    cmp     x0, #0b00000101
    b.ne    .Lownership_fail

    // Add another and verify count
    ldr     x0, =0xDEADBEEF
    ldr     x1, =0x5555666677778888
    mov     x2, #0b00001010
    bl      replica_record_ownership
    cmp     x0, #0
    b.ne    .Lownership_fail

    bl      replica_get_ownership_count
    cmp     x0, #2
    b.ne    .Lownership_fail

    mov     x0, #0
    b       .Lownership_result

.Lownership_fail:
    mov     x0, #1

.Lownership_result:
    adrp    x1, name_replica_ownership
    add     x1, x1, :lo12:name_replica_ownership
    bl      test_result

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_replica_select_peers - Test peer selection for replication
// =============================================================================
test_replica_select_peers:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Select peers with 4 available
    ldr     x0, =0x12345678             // Doc ID
    mov     x1, #4                      // Peer count
    bl      replica_select_peers

    // Should return non-zero bitmap with at most CLUSTER_REPLICATION_FACTOR bits
    cbz     x0, .Lselect_peers_fail

    // Count bits (should be <= CLUSTER_REPLICATION_FACTOR)
    mov     x1, x0
    mov     x2, #0
.Lcount_bits:
    cbz     x1, .Lcount_done
    and     x3, x1, #1
    add     x2, x2, x3
    lsr     x1, x1, #1
    b       .Lcount_bits

.Lcount_done:
    cmp     x2, #CLUSTER_REPLICATION_FACTOR
    b.hi    .Lselect_peers_fail

    // Test with 0 peers
    ldr     x0, =0x12345678
    mov     x1, #0
    bl      replica_select_peers
    cmp     x0, #0                      // Should return 0
    b.ne    .Lselect_peers_fail

    mov     x0, #0
    b       .Lselect_peers_result

.Lselect_peers_fail:
    mov     x0, #1

.Lselect_peers_result:
    adrp    x1, name_replica_select
    add     x1, x1, :lo12:name_replica_select
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_router_init - Test router initialization
// =============================================================================
test_router_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    bl      router_init

    // Verify no pending queries
    bl      router_get_pending_count
    cmp     x0, #0
    cset    w0, ne

    adrp    x1, name_router_init
    add     x1, x1, :lo12:name_router_init
    bl      test_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// test_router_pending_alloc - Test pending query allocation
// =============================================================================
test_router_pending_alloc:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Initialize router
    bl      router_init

    // Allocate first slot
    bl      router_alloc_pending
    cmp     x0, #0
    b.lt    .Lpending_alloc_fail
    mov     x19, x0                     // Save slot index

    // Verify count
    bl      router_get_pending_count
    cmp     x0, #1
    b.ne    .Lpending_alloc_fail

    // Get slot pointer
    mov     x0, x19
    bl      router_get_pending_ptr
    cbz     x0, .Lpending_alloc_fail

    // Allocate another
    bl      router_alloc_pending
    cmp     x0, #0
    b.lt    .Lpending_alloc_fail
    cmp     x0, x19
    b.eq    .Lpending_alloc_fail        // Should be different

    // Verify count
    bl      router_get_pending_count
    cmp     x0, #2
    b.ne    .Lpending_alloc_fail

    // Free first slot
    mov     x0, x19
    bl      router_free_pending
    cmp     x0, #0
    b.ne    .Lpending_alloc_fail

    // Verify count decreased
    bl      router_get_pending_count
    cmp     x0, #1
    b.ne    .Lpending_alloc_fail

    mov     x0, #0
    b       .Lpending_alloc_result

.Lpending_alloc_fail:
    mov     x0, #1

.Lpending_alloc_result:
    adrp    x1, name_router_alloc
    add     x1, x1, :lo12:name_router_alloc
    bl      test_result

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// test_router_pending_find - Test pending query lookup
// =============================================================================
test_router_pending_find:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Initialize
    bl      router_init

    // Allocate a slot
    bl      router_alloc_pending
    cmp     x0, #0
    b.lt    .Lpending_find_fail
    mov     x19, x0                     // Slot index

    // Get pointer and set query ID
    bl      router_get_pending_ptr
    cbz     x0, .Lpending_find_fail
    mov     x20, x0                     // Slot pointer

    mov     w1, #12345                  // Query ID
    str     w1, [x20, #PQUERY_OFF_ID]
    mov     w1, #PQUERY_STATE_PENDING
    str     w1, [x20, #PQUERY_OFF_STATE]

    // Find by query ID
    mov     w0, #12345
    bl      router_find_pending
    cmp     x0, x19
    b.ne    .Lpending_find_fail

    // Try to find non-existent
    ldr     w0, =99999
    bl      router_find_pending
    cmp     x0, #-1
    b.ne    .Lpending_find_fail

    mov     x0, #0
    b       .Lpending_find_result

.Lpending_find_fail:
    mov     x0, #1

.Lpending_find_result:
    adrp    x1, name_router_find
    add     x1, x1, :lo12:name_router_find
    bl      test_result

    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Data section
// =============================================================================

.section .data
.balign 8

test_passed:
    .quad   0

test_total:
    .quad   0

// Message buffer for testing
test_msg_buf:
    .skip   MSG_HDR_SIZE + 256

.section .rodata
.balign 8

msg_header:
    .asciz "=== Omesh Cluster Tests ===\n"

msg_pass:
    .asciz "[PASS] "

msg_fail:
    .asciz "[FAIL] "

msg_summary:
    .asciz "=== "

msg_tests_passed:
    .asciz " tests passed ===\n"

// Test names
name_node_init:
    .asciz "Node initialization"

name_node_state:
    .asciz "Node state transitions"

name_node_doc_count:
    .asciz "Node document count"

name_node_peer_count:
    .asciz "Node peer count"

name_query_id_gen:
    .asciz "Query ID generation"

name_handler_init:
    .asciz "Handler initialization"

name_build_search:
    .asciz "Build SEARCH message"

name_build_index:
    .asciz "Build INDEX message"

name_replica_init:
    .asciz "Replica manager init"

name_replica_ownership:
    .asciz "Ownership recording"

name_replica_select:
    .asciz "Peer selection"

name_router_init:
    .asciz "Router initialization"

name_router_alloc:
    .asciz "Pending query alloc/free"

name_router_find:
    .asciz "Pending query lookup"

// Test data
test_query_str:
    .asciz "hello"

test_doc_content:
    .asciz "Hello World"

// =============================================================================
// End of test_cluster.s
// =============================================================================
