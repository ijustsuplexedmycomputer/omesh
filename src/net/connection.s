// =============================================================================
// Omesh - Connection Management
// =============================================================================
//
// Connection pool and state management:
// - conn_pool_init: Initialize connection pool
// - conn_alloc: Allocate a connection slot
// - conn_free: Free a connection slot
// - conn_send: Send data on connection
// - conn_recv: Receive data from connection
// - conn_flush: Flush send buffer
// - conn_set_state: Update connection state
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"

// =============================================================================
// Global Data
// =============================================================================

.bss

// Connection pool
.global g_conn_pool
.align 4
g_conn_pool:
    .skip   (CONN_SIZE * NET_MAX_CONNECTIONS)

// Bitmap for allocated slots (1 bit per slot)
.global g_conn_bitmap
.align 4
g_conn_bitmap:
    .skip   (NET_MAX_CONNECTIONS / 8)

// Pool state
.global g_conn_count
.align 3
g_conn_count:
    .skip   8

.text

// =============================================================================
// conn_pool_init - Initialize connection pool
// =============================================================================
// Input: none
// Output:
//   x0 = 0
// =============================================================================
.global conn_pool_init
.type conn_pool_init, %function
conn_pool_init:
    // Zero the connection pool
    adrp    x0, g_conn_pool
    add     x0, x0, :lo12:g_conn_pool
    mov     x1, #(CONN_SIZE * NET_MAX_CONNECTIONS)

.Linit_zero_pool:
    cbz     x1, .Linit_zero_bitmap
    str     xzr, [x0], #8
    sub     x1, x1, #8
    b       .Linit_zero_pool

.Linit_zero_bitmap:
    // Zero the bitmap
    adrp    x0, g_conn_bitmap
    add     x0, x0, :lo12:g_conn_bitmap
    mov     x1, #(NET_MAX_CONNECTIONS / 8)

.Linit_zero_bitmap_loop:
    cbz     x1, .Linit_zero_count
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Linit_zero_bitmap_loop

.Linit_zero_count:
    // Zero connection count
    adrp    x0, g_conn_count
    add     x0, x0, :lo12:g_conn_count
    str     xzr, [x0]

    mov     x0, #0
    ret
.size conn_pool_init, .-conn_pool_init

// =============================================================================
// conn_alloc - Allocate a connection slot
// =============================================================================
// Input: none
// Output:
//   x0 = pointer to connection struct or NULL if full
// =============================================================================
.global conn_alloc
.type conn_alloc, %function
conn_alloc:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    adrp    x19, g_conn_bitmap
    add     x19, x19, :lo12:g_conn_bitmap
    mov     x20, #0                     // Slot index

.Lalloc_search:
    cmp     x20, #NET_MAX_CONNECTIONS
    b.hs    .Lalloc_full

    // Check bit in bitmap
    lsr     x1, x20, #3                 // Byte index
    and     x2, x20, #7                 // Bit index
    ldrb    w3, [x19, x1]
    mov     w4, #1
    lsl     w4, w4, w2
    tst     w3, w4
    b.ne    .Lalloc_next                // Bit set = slot in use

    // Found free slot - set bit
    orr     w3, w3, w4
    strb    w3, [x19, x1]

    // Increment count
    adrp    x1, g_conn_count
    add     x1, x1, :lo12:g_conn_count
    ldr     x2, [x1]
    add     x2, x2, #1
    str     x2, [x1]

    // Calculate connection pointer
    adrp    x0, g_conn_pool
    add     x0, x0, :lo12:g_conn_pool
    mov     x1, #CONN_SIZE
    mul     x1, x20, x1
    add     x0, x0, x1

    // Initialize connection state
    mov     x1, #-1
    str     x1, [x0, #CONN_OFF_TCP_FD]  // fd = -1
    str     x1, [x0, #CONN_OFF_UDP_FD]  // fd = -1
    str     wzr, [x0, #CONN_OFF_STATE]
    str     wzr, [x0, #CONN_OFF_FLAGS]
    str     xzr, [x0, #CONN_OFF_NODE_ID]
    str     xzr, [x0, #CONN_OFF_RECV_BUF]
    str     xzr, [x0, #CONN_OFF_RECV_LEN]
    str     xzr, [x0, #CONN_OFF_SEND_BUF]
    str     xzr, [x0, #CONN_OFF_SEND_LEN]
    str     xzr, [x0, #CONN_OFF_LAST_ACTIVE]
    str     xzr, [x0, #CONN_OFF_ADDR]

    b       .Lalloc_ret

.Lalloc_next:
    add     x20, x20, #1
    b       .Lalloc_search

.Lalloc_full:
    mov     x0, #0                      // NULL

.Lalloc_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size conn_alloc, .-conn_alloc

// =============================================================================
// conn_free - Free a connection slot
// =============================================================================
// Input:
//   x0 = pointer to connection struct
// Output:
//   x0 = 0 or -EINVAL
// =============================================================================
.global conn_free
.type conn_free, %function
conn_free:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save conn ptr

    // Validate pointer is in pool
    adrp    x1, g_conn_pool
    add     x1, x1, :lo12:g_conn_pool
    sub     x2, x0, x1
    cmp     x2, #0
    b.lt    .Lfree_invalid

    ldr     x3, =(CONN_SIZE * NET_MAX_CONNECTIONS)
    cmp     x2, x3
    b.hs    .Lfree_invalid

    // Check alignment
    mov     x3, #CONN_SIZE
    udiv    x4, x2, x3
    mul     x5, x4, x3
    cmp     x2, x5
    b.ne    .Lfree_invalid

    mov     x20, x4                     // Slot index

    // Close TCP socket if open
    ldr     x0, [x19, #CONN_OFF_TCP_FD]
    cmn     x0, #1
    b.eq    .Lfree_check_udp
    mov     x8, #SYS_close
    svc     #0

.Lfree_check_udp:
    // Close UDP socket if open
    ldr     x0, [x19, #CONN_OFF_UDP_FD]
    cmn     x0, #1
    b.eq    .Lfree_clear_bit
    mov     x8, #SYS_close
    svc     #0

.Lfree_clear_bit:
    // Clear bit in bitmap
    adrp    x0, g_conn_bitmap
    add     x0, x0, :lo12:g_conn_bitmap
    lsr     x1, x20, #3                 // Byte index
    and     x2, x20, #7                 // Bit index
    ldrb    w3, [x0, x1]
    mov     w4, #1
    lsl     w4, w4, w2
    bic     w3, w3, w4
    strb    w3, [x0, x1]

    // Decrement count
    adrp    x0, g_conn_count
    add     x0, x0, :lo12:g_conn_count
    ldr     x1, [x0]
    sub     x1, x1, #1
    str     x1, [x0]

    // Zero the connection struct
    mov     x0, x19
    mov     x1, #CONN_SIZE

.Lfree_zero:
    cbz     x1, .Lfree_done
    strb    wzr, [x0], #1
    sub     x1, x1, #1
    b       .Lfree_zero

.Lfree_done:
    mov     x0, #0
    b       .Lfree_ret

.Lfree_invalid:
    mov     x0, #-EINVAL

.Lfree_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size conn_free, .-conn_free

// =============================================================================
// conn_set_tcp_fd - Set TCP socket fd
// =============================================================================
// Input:
//   x0 = connection pointer
//   x1 = fd
// Output:
//   x0 = 0
// =============================================================================
.global conn_set_tcp_fd
.type conn_set_tcp_fd, %function
conn_set_tcp_fd:
    str     x1, [x0, #CONN_OFF_TCP_FD]
    mov     x0, #0
    ret
.size conn_set_tcp_fd, .-conn_set_tcp_fd

// =============================================================================
// conn_get_tcp_fd - Get TCP socket fd
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = fd
// =============================================================================
.global conn_get_tcp_fd
.type conn_get_tcp_fd, %function
conn_get_tcp_fd:
    ldr     x0, [x0, #CONN_OFF_TCP_FD]
    ret
.size conn_get_tcp_fd, .-conn_get_tcp_fd

// =============================================================================
// conn_set_state - Set connection state
// =============================================================================
// Input:
//   x0 = connection pointer
//   x1 = new state
// Output:
//   x0 = 0
// =============================================================================
.global conn_set_state
.type conn_set_state, %function
conn_set_state:
    str     w1, [x0, #CONN_OFF_STATE]
    mov     x0, #0
    ret
.size conn_set_state, .-conn_set_state

// =============================================================================
// conn_get_state - Get connection state
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = state
// =============================================================================
.global conn_get_state
.type conn_get_state, %function
conn_get_state:
    ldr     w0, [x0, #CONN_OFF_STATE]
    ret
.size conn_get_state, .-conn_get_state

// =============================================================================
// conn_set_flags - Set connection flags
// =============================================================================
// Input:
//   x0 = connection pointer
//   x1 = flags
// Output:
//   x0 = 0
// =============================================================================
.global conn_set_flags
.type conn_set_flags, %function
conn_set_flags:
    str     w1, [x0, #CONN_OFF_FLAGS]
    mov     x0, #0
    ret
.size conn_set_flags, .-conn_set_flags

// =============================================================================
// conn_get_flags - Get connection flags
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = flags
// =============================================================================
.global conn_get_flags
.type conn_get_flags, %function
conn_get_flags:
    ldr     w0, [x0, #CONN_OFF_FLAGS]
    ret
.size conn_get_flags, .-conn_get_flags

// =============================================================================
// conn_set_node_id - Set remote node ID
// =============================================================================
// Input:
//   x0 = connection pointer
//   x1 = node ID
// Output:
//   x0 = 0
// =============================================================================
.global conn_set_node_id
.type conn_set_node_id, %function
conn_set_node_id:
    str     x1, [x0, #CONN_OFF_NODE_ID]
    mov     x0, #0
    ret
.size conn_set_node_id, .-conn_set_node_id

// =============================================================================
// conn_get_node_id - Get remote node ID
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = node ID
// =============================================================================
.global conn_get_node_id
.type conn_get_node_id, %function
conn_get_node_id:
    ldr     x0, [x0, #CONN_OFF_NODE_ID]
    ret
.size conn_get_node_id, .-conn_get_node_id

// =============================================================================
// conn_send - Send data on connection
// =============================================================================
// Input:
//   x0 = connection pointer
//   x1 = data pointer
//   x2 = length
// Output:
//   x0 = bytes sent or -errno
// =============================================================================
.global conn_send
.type conn_send, %function
conn_send:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0                     // Save conn ptr
    mov     x20, x2                     // Save length

    // Get TCP fd
    ldr     x0, [x19, #CONN_OFF_TCP_FD]
    cmn     x0, #1
    b.eq    .Lsend_not_connected

    // sendto(fd, buf, len, 0, NULL, 0)
    // x0 = fd (already set)
    // x1 = buf (already set)
    // x2 = len (already set)
    mov     x3, #0                      // flags
    mov     x4, #0                      // addr = NULL
    mov     x5, #0                      // addrlen = 0
    mov     x8, #SYS_sendto
    svc     #0

    b       .Lsend_ret

.Lsend_not_connected:
    mov     x0, #-ENOTCONN

.Lsend_ret:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size conn_send, .-conn_send

// =============================================================================
// conn_recv - Receive data from connection
// =============================================================================
// Input:
//   x0 = connection pointer
//   x1 = buffer pointer
//   x2 = buffer size
// Output:
//   x0 = bytes received or -errno
// =============================================================================
.global conn_recv
.type conn_recv, %function
conn_recv:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                     // Save conn ptr

    // Get TCP fd
    ldr     x0, [x19, #CONN_OFF_TCP_FD]
    cmn     x0, #1
    b.eq    .Lrecv_not_connected

    // recvfrom(fd, buf, len, 0, NULL, NULL)
    // x0 = fd (already set)
    // x1 = buf (already set)
    // x2 = len (already set)
    mov     x3, #0                      // flags
    mov     x4, #0                      // addr = NULL
    mov     x5, #0                      // addrlen = NULL
    mov     x8, #SYS_recvfrom
    svc     #0

    b       .Lrecv_ret

.Lrecv_not_connected:
    mov     x0, #-ENOTCONN

.Lrecv_ret:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size conn_recv, .-conn_recv

// =============================================================================
// conn_get_by_fd - Find connection by TCP fd
// =============================================================================
// Input:
//   x0 = fd to search for
// Output:
//   x0 = connection pointer or NULL
// =============================================================================
.global conn_get_by_fd
.type conn_get_by_fd, %function
conn_get_by_fd:
    adrp    x1, g_conn_pool
    add     x1, x1, :lo12:g_conn_pool
    mov     x2, #0                      // Index

.Lget_by_fd_loop:
    cmp     x2, #NET_MAX_CONNECTIONS
    b.hs    .Lget_by_fd_not_found

    // Check TCP fd
    ldr     x3, [x1, #CONN_OFF_TCP_FD]
    cmp     x3, x0
    b.eq    .Lget_by_fd_found

    add     x1, x1, #CONN_SIZE
    add     x2, x2, #1
    b       .Lget_by_fd_loop

.Lget_by_fd_found:
    mov     x0, x1
    ret

.Lget_by_fd_not_found:
    mov     x0, #0
    ret
.size conn_get_by_fd, .-conn_get_by_fd

// =============================================================================
// conn_get_by_node - Find connection by node ID
// =============================================================================
// Input:
//   x0 = node ID to search for
// Output:
//   x0 = connection pointer or NULL
// =============================================================================
.global conn_get_by_node
.type conn_get_by_node, %function
conn_get_by_node:
    adrp    x1, g_conn_pool
    add     x1, x1, :lo12:g_conn_pool
    mov     x2, #0                      // Index

.Lget_by_node_loop:
    cmp     x2, #NET_MAX_CONNECTIONS
    b.hs    .Lget_by_node_not_found

    // Check state first (must be connected)
    ldr     w3, [x1, #CONN_OFF_STATE]
    cmp     w3, #CONN_STATE_CONNECTED
    b.ne    .Lget_by_node_next

    // Check node ID
    ldr     x3, [x1, #CONN_OFF_NODE_ID]
    cmp     x3, x0
    b.eq    .Lget_by_node_found

.Lget_by_node_next:
    add     x1, x1, #CONN_SIZE
    add     x2, x2, #1
    b       .Lget_by_node_loop

.Lget_by_node_found:
    mov     x0, x1
    ret

.Lget_by_node_not_found:
    mov     x0, #0
    ret
.size conn_get_by_node, .-conn_get_by_node

// =============================================================================
// conn_count - Get number of active connections
// =============================================================================
// Input: none
// Output:
//   x0 = connection count
// =============================================================================
.global conn_count
.type conn_count, %function
conn_count:
    adrp    x0, g_conn_count
    add     x0, x0, :lo12:g_conn_count
    ldr     x0, [x0]
    ret
.size conn_count, .-conn_count

// =============================================================================
// conn_update_activity - Update last activity timestamp
// =============================================================================
// Input:
//   x0 = connection pointer
// Output:
//   x0 = 0
// =============================================================================
.global conn_update_activity
.type conn_update_activity, %function
conn_update_activity:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    // Get current time
    sub     sp, sp, #16
    mov     x0, #CLOCK_MONOTONIC
    mov     x1, sp
    mov     x8, #SYS_clock_gettime
    svc     #0

    // Load seconds and store as last activity
    ldr     x0, [sp]
    str     x0, [x19, #CONN_OFF_LAST_ACTIVE]

    add     sp, sp, #16
    mov     x0, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size conn_update_activity, .-conn_update_activity
