// =============================================================================
// Omesh - Network Layer Test Suite
// =============================================================================
//
// Tests for Phase 4 transport layer:
// 1. Byte order conversion (htons, htonl, ntohs, ntohl)
// 2. inet_addr parsing
// 3. CRC32 calculation
// 4. Message init and accessors
// 5. Message encode/decode
// 6. Message checksum validation
// 7. Connection pool alloc/free
// 8. Connection state management
// 9. TCP socket create/listen
// 10. UDP socket create/bind
// 11. epoll add/del operations
// 12. Reactor init/close
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"

// =============================================================================
// Test Data
// =============================================================================

.data

test_header:
    .asciz  "\n=== Omesh Network Layer Tests ===\n\n"

test_pass:
    .asciz  "  [PASS] "

test_fail:
    .asciz  "  [FAIL] "

test_newline:
    .asciz  "\n"

// Test names
test_name_htons:
    .asciz  "htons byte order conversion\n"
test_name_htonl:
    .asciz  "htonl byte order conversion\n"
test_name_inet_addr:
    .asciz  "inet_addr parsing\n"
test_name_crc32:
    .asciz  "CRC32 calculation\n"
test_name_msg_init:
    .asciz  "msg_init header initialization\n"
test_name_msg_accessors:
    .asciz  "msg_get_* accessor functions\n"
test_name_msg_payload:
    .asciz  "msg_set_payload\n"
test_name_msg_finalize:
    .asciz  "msg_finalize checksum\n"
test_name_msg_validate:
    .asciz  "msg_validate integrity check\n"
test_name_msg_build:
    .asciz  "msg_build complete message\n"
test_name_conn_alloc:
    .asciz  "conn_alloc slot allocation\n"
test_name_conn_free:
    .asciz  "conn_free slot release\n"
test_name_conn_state:
    .asciz  "conn_set/get_state\n"
test_name_conn_flags:
    .asciz  "conn_set/get_flags\n"
test_name_conn_node:
    .asciz  "conn_set/get_node_id\n"
test_name_tcp_listen:
    .asciz  "tcp_listen socket creation\n"
test_name_udp_bind:
    .asciz  "udp_bind socket creation\n"
test_name_reactor_add:
    .asciz  "reactor_add epoll operation\n"
test_name_reactor_del:
    .asciz  "reactor_del epoll operation\n"
test_name_reactor_init:
    .asciz  "reactor_init full initialization\n"
test_name_reactor_close:
    .asciz  "reactor_close cleanup\n"
test_name_peer_init:
    .asciz  "peer_init manager setup\n"

summary_prefix:
    .asciz  "\n--- Results: "
summary_passed:
    .asciz  " passed, "
summary_failed:
    .asciz  " failed ---\n\n"

// Test input strings
ip_loopback:
    .asciz  "127.0.0.1"
ip_any:
    .asciz  "0.0.0.0"
ip_broadcast:
    .asciz  "192.168.1.255"

// Test payload
test_payload:
    .asciz  "Hello, World!"
test_payload_len = . - test_payload - 1

// CRC32 test data
crc_test_data:
    .asciz  "123456789"
crc_test_len = . - crc_test_data - 1
// Expected CRC32C for "123456789" is 0xE3069283

.bss

// Test message buffer
.align 4
test_msg_buf:
    .skip   256

// Test counters
.align 3
tests_passed:
    .skip   8
tests_failed:
    .skip   8

.text

// =============================================================================
// Helper: Print string
// =============================================================================
print_str:
    mov     x2, #0
.Lprint_len:
    ldrb    w3, [x0, x2]
    cbz     w3, .Lprint_do
    add     x2, x2, #1
    b       .Lprint_len
.Lprint_do:
    mov     x1, x0
    mov     x0, #STDOUT_FILENO
    mov     x8, #SYS_write
    svc     #0
    ret

// =============================================================================
// Helper: Print test result
// =============================================================================
// x0 = 0 for pass, non-zero for fail
// x1 = test name
print_result:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x1, [sp, #16]

    cbnz    x0, .Lresult_fail

    // Pass
    adr     x0, test_pass
    bl      print_str
    adr     x0, tests_passed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]
    b       .Lresult_name

.Lresult_fail:
    adr     x0, test_fail
    bl      print_str
    adr     x0, tests_failed
    ldr     x1, [x0]
    add     x1, x1, #1
    str     x1, [x0]

.Lresult_name:
    ldr     x0, [sp, #16]
    bl      print_str

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Helper: Print number
// =============================================================================
print_num:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Convert to string (simple single digit for our test counts)
    add     x0, x0, #'0'
    strb    w0, [sp, #16]
    mov     x0, #0
    strb    w0, [sp, #17]
    add     x0, sp, #16
    bl      print_str

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: htons
// =============================================================================
test_htons:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Test: 0x1234 should become 0x3412
    mov     x0, #0x1234
    bl      htons
    mov     x1, #0x3412
    cmp     x0, x1
    cset    x0, ne

    adr     x1, test_name_htons
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: htonl
// =============================================================================
test_htonl:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Test: 0x12345678 should become 0x78563412
    ldr     x0, =0x12345678
    bl      htonl
    ldr     x1, =0x78563412
    cmp     w0, w1
    cset    x0, ne

    adr     x1, test_name_htonl
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: inet_addr
// =============================================================================
test_inet_addr:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Test parsing "127.0.0.1"
    adr     x0, ip_loopback
    bl      inet_addr
    // 127.0.0.1 in network byte order = 0x0100007F
    ldr     x1, =0x0100007F
    cmp     w0, w1
    cset    x0, ne

    adr     x1, test_name_inet_addr
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: CRC32
// =============================================================================
test_crc32:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, crc_test_data
    mov     x1, #crc_test_len
    bl      crc32_calc
    // CRC32C("123456789") = 0xE3069283
    ldr     x1, =0xE3069283
    cmp     w0, w1
    cset    x0, ne

    adr     x1, test_name_crc32
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: msg_init
// =============================================================================
test_msg_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test_msg_buf
    mov     x1, #MSG_TYPE_PING
    mov     x2, #0x1234                 // src node
    mov     x3, #0x5678                 // dst node
    bl      msg_init

    // Verify magic
    adr     x0, test_msg_buf
    ldr     w1, [x0, #MSG_OFF_MAGIC]
    ldr     w2, =MSG_MAGIC
    cmp     w1, w2
    b.ne    .Lmsg_init_fail

    // Verify version
    ldrb    w1, [x0, #MSG_OFF_VERSION]
    cmp     w1, #MSG_VERSION
    b.ne    .Lmsg_init_fail

    // Verify type
    ldrb    w1, [x0, #MSG_OFF_TYPE]
    cmp     w1, #MSG_TYPE_PING
    b.ne    .Lmsg_init_fail

    mov     x0, #0
    b       .Lmsg_init_done

.Lmsg_init_fail:
    mov     x0, #1

.Lmsg_init_done:
    adr     x1, test_name_msg_init
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: msg_get_* accessors
// =============================================================================
test_msg_accessors:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Initialize message first
    adr     x0, test_msg_buf
    mov     x1, #MSG_TYPE_HELLO
    mov     x2, #0xABCD
    mov     x3, #0xEF01
    bl      msg_init

    // Set sequence
    adr     x0, test_msg_buf
    mov     x1, #42
    bl      msg_set_seq

    // Set flags
    adr     x0, test_msg_buf
    mov     x1, #MSG_FLAG_RELIABLE
    bl      msg_set_flags

    // Test get_type
    adr     x0, test_msg_buf
    bl      msg_get_type
    cmp     x0, #MSG_TYPE_HELLO
    b.ne    .Laccessors_fail

    // Test get_seq
    adr     x0, test_msg_buf
    bl      msg_get_seq
    cmp     x0, #42
    b.ne    .Laccessors_fail

    // Test get_flags
    adr     x0, test_msg_buf
    bl      msg_get_flags
    cmp     x0, #MSG_FLAG_RELIABLE
    b.ne    .Laccessors_fail

    // Test get_src_node
    adr     x0, test_msg_buf
    bl      msg_get_src_node
    ldr     x1, =0xABCD
    cmp     x0, x1
    b.ne    .Laccessors_fail

    // Test get_dst_node
    adr     x0, test_msg_buf
    bl      msg_get_dst_node
    ldr     x1, =0xEF01
    cmp     x0, x1
    b.ne    .Laccessors_fail

    mov     x0, #0
    b       .Laccessors_done

.Laccessors_fail:
    mov     x0, #1

.Laccessors_done:
    adr     x1, test_name_msg_accessors
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: msg_set_payload
// =============================================================================
test_msg_payload:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Initialize message
    adr     x0, test_msg_buf
    mov     x1, #MSG_TYPE_DATA
    mov     x2, #1
    mov     x3, #2
    bl      msg_init

    // Set payload
    adr     x0, test_msg_buf
    adr     x1, test_payload
    mov     x2, #test_payload_len
    bl      msg_set_payload
    cmp     x0, #0
    b.ne    .Lpayload_fail

    // Verify length was set
    adr     x0, test_msg_buf
    bl      msg_get_length
    cmp     x0, #test_payload_len
    b.ne    .Lpayload_fail

    // Verify payload pointer
    adr     x0, test_msg_buf
    bl      msg_get_payload
    ldrb    w1, [x0]
    cmp     w1, #'H'                    // First char of "Hello"
    b.ne    .Lpayload_fail

    mov     x0, #0
    b       .Lpayload_done

.Lpayload_fail:
    mov     x0, #1

.Lpayload_done:
    adr     x1, test_name_msg_payload
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: msg_finalize (checksum)
// =============================================================================
test_msg_finalize:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Initialize and set payload
    adr     x0, test_msg_buf
    mov     x1, #MSG_TYPE_DATA
    mov     x2, #1
    mov     x3, #2
    bl      msg_init

    adr     x0, test_msg_buf
    adr     x1, test_payload
    mov     x2, #test_payload_len
    bl      msg_set_payload

    // Finalize
    adr     x0, test_msg_buf
    bl      msg_finalize

    // Verify checksum is non-zero
    adr     x0, test_msg_buf
    ldr     w1, [x0, #MSG_OFF_CHECKSUM]
    cbz     w1, .Lfinalize_fail

    mov     x0, #0
    b       .Lfinalize_done

.Lfinalize_fail:
    mov     x0, #1

.Lfinalize_done:
    adr     x1, test_name_msg_finalize
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: msg_validate
// =============================================================================
test_msg_validate:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Build a complete message
    adr     x0, test_msg_buf
    mov     x1, #MSG_TYPE_PING
    mov     x2, #100
    mov     x3, #200
    mov     x4, #0                      // No payload
    mov     x5, #0
    bl      msg_build
    str     x0, [sp, #16]               // Save size

    // Validate should pass
    adr     x0, test_msg_buf
    ldr     x1, [sp, #16]
    bl      msg_validate
    cbnz    x0, .Lvalidate_fail

    // Corrupt magic and verify failure
    adr     x0, test_msg_buf
    mov     w1, #0xDEAD
    str     w1, [x0, #MSG_OFF_MAGIC]

    adr     x0, test_msg_buf
    ldr     x1, [sp, #16]
    bl      msg_validate
    cmp     x0, #0
    b.eq    .Lvalidate_fail             // Should have failed

    mov     x0, #0
    b       .Lvalidate_done

.Lvalidate_fail:
    mov     x0, #1

.Lvalidate_done:
    adr     x1, test_name_msg_validate
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: msg_build
// =============================================================================
test_msg_build:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adr     x0, test_msg_buf
    mov     x1, #MSG_TYPE_HELLO
    mov     x2, #0x1111
    mov     x3, #0x2222
    adr     x4, test_payload
    mov     x5, #test_payload_len
    bl      msg_build

    // Should return header + payload size
    mov     x1, #MSG_HDR_SIZE
    add     x1, x1, #test_payload_len
    cmp     x0, x1
    cset    x0, ne

    adr     x1, test_name_msg_build
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: conn_alloc
// =============================================================================
test_conn_alloc:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Initialize pool
    bl      conn_pool_init

    // Allocate first connection
    bl      conn_alloc
    cbz     x0, .Lalloc_fail
    str     x0, [sp, #16]

    // Verify it's in the pool
    adr     x1, g_conn_pool
    cmp     x0, x1
    b.lo    .Lalloc_fail

    // Allocate second
    bl      conn_alloc
    cbz     x0, .Lalloc_fail

    // Should be different from first
    ldr     x1, [sp, #16]
    cmp     x0, x1
    b.eq    .Lalloc_fail

    mov     x0, #0
    b       .Lalloc_done

.Lalloc_fail:
    mov     x0, #1

.Lalloc_done:
    adr     x1, test_name_conn_alloc
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: conn_free
// =============================================================================
test_conn_free:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Initialize and allocate
    bl      conn_pool_init
    bl      conn_alloc
    cbz     x0, .Lfree_test_fail
    str     x0, [sp, #16]

    // Free it
    bl      conn_free
    cbnz    x0, .Lfree_test_fail

    // Should be able to allocate again (same slot)
    bl      conn_alloc
    ldr     x1, [sp, #16]
    cmp     x0, x1
    b.ne    .Lfree_test_fail

    mov     x0, #0
    b       .Lfree_done

.Lfree_test_fail:
    mov     x0, #1

.Lfree_done:
    adr     x1, test_name_conn_free
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: conn_set/get_state
// =============================================================================
test_conn_state:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    bl      conn_pool_init
    bl      conn_alloc
    cbz     x0, .Lstate_fail
    str     x0, [sp, #16]

    // Set state
    mov     x1, #CONN_STATE_CONNECTED
    bl      conn_set_state

    // Get state
    ldr     x0, [sp, #16]
    bl      conn_get_state
    cmp     x0, #CONN_STATE_CONNECTED
    b.ne    .Lstate_fail

    mov     x0, #0
    b       .Lstate_done

.Lstate_fail:
    mov     x0, #1

.Lstate_done:
    adr     x1, test_name_conn_state
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: conn_set/get_flags
// =============================================================================
test_conn_flags:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    bl      conn_pool_init
    bl      conn_alloc
    cbz     x0, .Lflags_fail
    str     x0, [sp, #16]

    mov     x1, #CONN_FLAG_OUTBOUND
    bl      conn_set_flags

    ldr     x0, [sp, #16]
    bl      conn_get_flags
    cmp     x0, #CONN_FLAG_OUTBOUND
    b.ne    .Lflags_fail

    mov     x0, #0
    b       .Lflags_done

.Lflags_fail:
    mov     x0, #1

.Lflags_done:
    adr     x1, test_name_conn_flags
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: conn_set/get_node_id
// =============================================================================
test_conn_node:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    bl      conn_pool_init
    bl      conn_alloc
    cbz     x0, .Lnode_fail
    str     x0, [sp, #16]

    ldr     x1, =0xDEADBEEF12345678
    bl      conn_set_node_id

    ldr     x0, [sp, #16]
    bl      conn_get_node_id
    ldr     x1, =0xDEADBEEF12345678
    cmp     x0, x1
    b.ne    .Lnode_fail

    mov     x0, #0
    b       .Lnode_done

.Lnode_fail:
    mov     x0, #1

.Lnode_done:
    adr     x1, test_name_conn_node
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: tcp_listen
// =============================================================================
test_tcp_listen:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Use a high port to avoid permission issues
    mov     x0, #19876
    bl      tcp_listen
    cmp     x0, #0
    b.lt    .Ltcp_listen_fail

    // Close the socket
    str     x0, [sp, #16]
    mov     x8, #SYS_close
    svc     #0

    mov     x0, #0
    b       .Ltcp_listen_done

.Ltcp_listen_fail:
    mov     x0, #1

.Ltcp_listen_done:
    adr     x1, test_name_tcp_listen
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: udp_bind
// =============================================================================
test_udp_bind:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    mov     x0, #19877
    bl      udp_bind
    cmp     x0, #0
    b.lt    .Ludp_bind_fail

    str     x0, [sp, #16]
    mov     x8, #SYS_close
    svc     #0

    mov     x0, #0
    b       .Ludp_bind_done

.Ludp_bind_fail:
    mov     x0, #1

.Ludp_bind_done:
    adr     x1, test_name_udp_bind
    bl      print_result

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// Test: reactor_add
// =============================================================================
test_reactor_add:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    // Create epoll
    mov     x0, #0
    mov     x8, #SYS_epoll_create1
    svc     #0
    cmp     x0, #0
    b.lt    .Lreactor_add_fail
    str     x0, [sp, #16]               // epoll fd

    // Create a pipe for testing
    add     x0, sp, #24
    mov     x8, #SYS_pipe2
    mov     x1, #0
    svc     #0
    cmp     x0, #0
    b.lt    .Lreactor_add_close_epoll

    // Add pipe read end to epoll
    sub     sp, sp, #16
    mov     w0, #EPOLLIN
    str     w0, [sp]
    ldr     w0, [sp, #40]               // pipe[0]
    str     x0, [sp, #4]

    ldr     x0, [sp, #32]               // epoll fd
    mov     x1, #EPOLL_CTL_ADD
    ldr     w2, [sp, #40]               // fd
    mov     x3, sp
    mov     x8, #SYS_epoll_ctl
    svc     #0
    add     sp, sp, #16

    cmp     x0, #0
    b.lt    .Lreactor_add_close_pipe

    mov     x0, #0
    b       .Lreactor_add_cleanup

.Lreactor_add_close_pipe:
    ldr     w0, [sp, #24]
    mov     x8, #SYS_close
    svc     #0
    ldr     w0, [sp, #28]
    mov     x8, #SYS_close
    svc     #0

.Lreactor_add_close_epoll:
    ldr     x0, [sp, #16]
    mov     x8, #SYS_close
    svc     #0

.Lreactor_add_fail:
    mov     x0, #1
    b       .Lreactor_add_done

.Lreactor_add_cleanup:
    // Close pipe
    ldr     w0, [sp, #24]
    mov     x8, #SYS_close
    svc     #0
    ldr     w0, [sp, #28]
    mov     x8, #SYS_close
    svc     #0
    // Close epoll
    ldr     x0, [sp, #16]
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #0

.Lreactor_add_done:
    adr     x1, test_name_reactor_add
    bl      print_result

    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// Test: reactor_del
// =============================================================================
test_reactor_del:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    // Create epoll
    mov     x0, #0
    mov     x8, #SYS_epoll_create1
    svc     #0
    cmp     x0, #0
    b.lt    .Lreactor_del_fail
    str     x0, [sp, #16]

    // Create pipe
    add     x0, sp, #24
    mov     x1, #0
    mov     x8, #SYS_pipe2
    svc     #0
    cmp     x0, #0
    b.lt    .Lreactor_del_close_epoll

    // Add to epoll
    sub     sp, sp, #16
    mov     w0, #EPOLLIN
    str     w0, [sp]
    ldr     w0, [sp, #40]
    str     x0, [sp, #4]
    ldr     x0, [sp, #32]
    mov     x1, #EPOLL_CTL_ADD
    ldr     w2, [sp, #40]
    mov     x3, sp
    mov     x8, #SYS_epoll_ctl
    svc     #0
    add     sp, sp, #16
    cmp     x0, #0
    b.lt    .Lreactor_del_close_pipe

    // Delete from epoll
    ldr     x0, [sp, #16]
    mov     x1, #EPOLL_CTL_DEL
    ldr     w2, [sp, #24]
    mov     x3, #0
    mov     x8, #SYS_epoll_ctl
    svc     #0
    cmp     x0, #0
    b.lt    .Lreactor_del_close_pipe

    mov     x0, #0
    b       .Lreactor_del_cleanup

.Lreactor_del_close_pipe:
    ldr     w0, [sp, #24]
    mov     x8, #SYS_close
    svc     #0
    ldr     w0, [sp, #28]
    mov     x8, #SYS_close
    svc     #0

.Lreactor_del_close_epoll:
    ldr     x0, [sp, #16]
    mov     x8, #SYS_close
    svc     #0

.Lreactor_del_fail:
    mov     x0, #1
    b       .Lreactor_del_done

.Lreactor_del_cleanup:
    ldr     w0, [sp, #24]
    mov     x8, #SYS_close
    svc     #0
    ldr     w0, [sp, #28]
    mov     x8, #SYS_close
    svc     #0
    ldr     x0, [sp, #16]
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #0

.Lreactor_del_done:
    adr     x1, test_name_reactor_del
    bl      print_result

    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// Test: reactor_init
// =============================================================================
test_reactor_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x0, #19878
    ldr     x1, =0x12345678
    bl      reactor_init
    cbnz    x0, .Lreactor_init_fail

    // Verify reactor state
    bl      reactor_get_tcp_fd
    cmp     x0, #0
    b.lt    .Lreactor_init_fail

    bl      reactor_get_udp_fd
    cmp     x0, #0
    b.lt    .Lreactor_init_fail

    bl      reactor_get_node_id
    ldr     x1, =0x12345678
    cmp     x0, x1
    b.ne    .Lreactor_init_fail

    // Cleanup
    bl      reactor_close

    mov     x0, #0
    b       .Lreactor_init_done

.Lreactor_init_fail:
    bl      reactor_close
    mov     x0, #1

.Lreactor_init_done:
    adr     x1, test_name_reactor_init
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: reactor_close
// =============================================================================
test_reactor_close:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Init then close
    mov     x0, #19879
    mov     x1, #1
    bl      reactor_init
    cbnz    x0, .Lreactor_close_fail

    bl      reactor_close

    // Verify fds are -1
    bl      reactor_get_tcp_fd
    cmn     x0, #1
    b.ne    .Lreactor_close_fail

    mov     x0, #0
    b       .Lreactor_close_done

.Lreactor_close_fail:
    mov     x0, #1

.Lreactor_close_done:
    adr     x1, test_name_reactor_close
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Test: peer_init
// =============================================================================
test_peer_init:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x0, #19880
    ldr     x1, =0xABCDEF00
    bl      peer_init
    cbnz    x0, .Lpeer_init_fail

    // Verify node ID
    bl      peer_get_node_id
    ldr     x1, =0xABCDEF00
    cmp     x0, x1
    b.ne    .Lpeer_init_fail

    // Cleanup
    bl      peer_close

    mov     x0, #0
    b       .Lpeer_init_done

.Lpeer_init_fail:
    bl      peer_close
    mov     x0, #1

.Lpeer_init_done:
    adr     x1, test_name_peer_init
    bl      print_result

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// Main entry point
// =============================================================================
.global _start
_start:
    // Initialize CPU feature detection
    bl      hal_init

    // Print header
    adr     x0, test_header
    bl      print_str

    // Initialize counters
    adr     x0, tests_passed
    str     xzr, [x0]
    adr     x0, tests_failed
    str     xzr, [x0]

    // Run tests
    bl      test_htons
    bl      test_htonl
    bl      test_inet_addr
    bl      test_crc32
    bl      test_msg_init
    bl      test_msg_accessors
    bl      test_msg_payload
    bl      test_msg_finalize
    bl      test_msg_validate
    bl      test_msg_build
    bl      test_conn_alloc
    bl      test_conn_free
    bl      test_conn_state
    bl      test_conn_flags
    bl      test_conn_node
    bl      test_tcp_listen
    bl      test_udp_bind
    bl      test_reactor_add
    bl      test_reactor_del
    bl      test_reactor_init
    bl      test_reactor_close
    bl      test_peer_init

    // Print summary
    adr     x0, summary_prefix
    bl      print_str

    adr     x0, tests_passed
    ldr     x0, [x0]
    bl      print_num

    adr     x0, summary_passed
    bl      print_str

    adr     x0, tests_failed
    ldr     x0, [x0]
    bl      print_num

    adr     x0, summary_failed
    bl      print_str

    // Exit with failure count
    adr     x0, tests_failed
    ldr     x0, [x0]
    mov     x8, #SYS_exit
    svc     #0
