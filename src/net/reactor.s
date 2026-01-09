// =============================================================================
// Omesh - epoll Event Reactor
// =============================================================================
//
// Event-driven I/O using Linux epoll:
// - reactor_init: Initialize reactor with listening sockets
// - reactor_add: Add fd to epoll
// - reactor_mod: Modify fd events
// - reactor_del: Remove fd from epoll
// - reactor_run: Main event loop
// - reactor_stop: Stop event loop
// - reactor_close: Cleanup resources
//
// =============================================================================

.include "syscall_nums.inc"
.include "net.inc"

// =============================================================================
// Global Data
// =============================================================================

.bss

// Reactor state
.global g_reactor
.align 4
g_reactor:
    .skip   REACTOR_SIZE

// epoll events buffer
.global g_epoll_events
.align 4
g_epoll_events:
    .skip   (EPOLL_EVENT_SIZE * NET_MAX_EVENTS)

.text

// =============================================================================
// reactor_init - Initialize the reactor
// =============================================================================
// Input:
//   x0 = port number (host byte order)
//   x1 = local node ID
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global reactor_init
.type reactor_init, %function
reactor_init:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Save port
    mov     x20, x1                     // Save node ID

    adrp    x21, g_reactor
    add     x21, x21, :lo12:g_reactor

    // Store node ID
    str     x20, [x21, #REACTOR_OFF_NODE_ID]

    // Initialize connection pool
    bl      conn_pool_init

    // Create epoll instance
    mov     x0, #0                      // flags (could use EPOLL_CLOEXEC)
    mov     x8, #SYS_epoll_create1
    svc     #0

    cmp     x0, #0
    b.lt    .Linit_ret
    str     x0, [x21, #REACTOR_OFF_EPOLL_FD]

    // Create listening TCP socket
    mov     x0, x19
    bl      tcp_listen
    cmp     x0, #0
    b.lt    .Linit_close_epoll
    str     x0, [x21, #REACTOR_OFF_TCP_FD]
    mov     x22, x0                     // Save TCP fd

    // Add TCP socket to epoll
    mov     x0, x22
    mov     x1, #EPOLLIN
    mov     x2, x22                     // data = fd
    bl      reactor_add
    cmp     x0, #0
    b.lt    .Linit_close_tcp

    // Create UDP socket
    mov     x0, x19
    bl      udp_bind
    cmp     x0, #0
    b.lt    .Linit_close_tcp
    str     x0, [x21, #REACTOR_OFF_UDP_FD]
    mov     x22, x0                     // Save UDP fd

    // Add UDP socket to epoll
    mov     x0, x22
    mov     x1, #EPOLLIN
    mov     x2, x22
    bl      reactor_add
    cmp     x0, #0
    b.lt    .Linit_close_udp

    // Set up events buffer pointer and max
    adrp    x0, g_epoll_events
    add     x0, x0, :lo12:g_epoll_events
    str     x0, [x21, #REACTOR_OFF_EVENTS]
    mov     x0, #NET_MAX_EVENTS
    str     x0, [x21, #REACTOR_OFF_MAX_EVENTS]

    // Set running flag
    mov     x0, #1
    str     x0, [x21, #REACTOR_OFF_RUNNING]

    // Initialize connection count
    str     xzr, [x21, #REACTOR_OFF_CONN_COUNT]

    mov     x0, #0
    b       .Linit_ret

.Linit_close_udp:
    mov     x22, x0                     // Save error
    ldr     x0, [x21, #REACTOR_OFF_UDP_FD]
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x22
    b       .Linit_close_tcp

.Linit_close_tcp:
    mov     x22, x0                     // Save error
    ldr     x0, [x21, #REACTOR_OFF_TCP_FD]
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x22

.Linit_close_epoll:
    mov     x22, x0                     // Save error
    ldr     x0, [x21, #REACTOR_OFF_EPOLL_FD]
    mov     x8, #SYS_close
    svc     #0
    mov     x0, x22

.Linit_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size reactor_init, .-reactor_init

// =============================================================================
// reactor_add - Add fd to epoll
// =============================================================================
// Input:
//   x0 = fd
//   x1 = events (EPOLLIN, EPOLLOUT, etc.)
//   x2 = user data (usually fd or connection ptr)
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global reactor_add
.type reactor_add, %function
reactor_add:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Build epoll_event struct on stack
    sub     sp, sp, #16
    str     w1, [sp]                    // events
    str     x2, [sp, #4]                // data (u64)

    // epoll_ctl(epfd, EPOLL_CTL_ADD, fd, &event)
    adrp    x4, g_reactor
    add     x4, x4, :lo12:g_reactor
    ldr     x4, [x4, #REACTOR_OFF_EPOLL_FD]
    mov     x1, #EPOLL_CTL_ADD
    mov     x2, x0                      // fd
    mov     x3, sp                      // event
    mov     x0, x4                      // epfd
    mov     x8, #SYS_epoll_ctl
    svc     #0

    add     sp, sp, #16
    ldp     x29, x30, [sp], #32
    ret
.size reactor_add, .-reactor_add

// =============================================================================
// reactor_mod - Modify fd events in epoll
// =============================================================================
// Input:
//   x0 = fd
//   x1 = events
//   x2 = user data
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global reactor_mod
.type reactor_mod, %function
reactor_mod:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    sub     sp, sp, #16
    str     w1, [sp]
    str     x2, [sp, #4]

    adrp    x4, g_reactor
    add     x4, x4, :lo12:g_reactor
    ldr     x4, [x4, #REACTOR_OFF_EPOLL_FD]
    mov     x1, #EPOLL_CTL_MOD
    mov     x2, x0
    mov     x3, sp
    mov     x0, x4
    mov     x8, #SYS_epoll_ctl
    svc     #0

    add     sp, sp, #16
    ldp     x29, x30, [sp], #32
    ret
.size reactor_mod, .-reactor_mod

// =============================================================================
// reactor_del - Remove fd from epoll
// =============================================================================
// Input:
//   x0 = fd
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global reactor_del
.type reactor_del, %function
reactor_del:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x3, g_reactor
    add     x3, x3, :lo12:g_reactor
    ldr     x3, [x3, #REACTOR_OFF_EPOLL_FD]
    mov     x1, #EPOLL_CTL_DEL
    mov     x2, x0                      // fd
    mov     x0, x3                      // epfd
    mov     x3, #0                      // event = NULL
    mov     x8, #SYS_epoll_ctl
    svc     #0

    ldp     x29, x30, [sp], #16
    ret
.size reactor_del, .-reactor_del

// =============================================================================
// reactor_wait - Wait for events (single iteration)
// =============================================================================
// Input:
//   x0 = timeout in milliseconds (-1 for infinite)
// Output:
//   x0 = number of events or -errno
// =============================================================================
.global reactor_wait
.type reactor_wait, %function
reactor_wait:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x4, g_reactor
    add     x4, x4, :lo12:g_reactor
    ldr     x1, [x4, #REACTOR_OFF_EPOLL_FD]
    ldr     x2, [x4, #REACTOR_OFF_EVENTS]
    ldr     x3, [x4, #REACTOR_OFF_MAX_EVENTS]

    // epoll_pwait(epfd, events, maxevents, timeout, sigmask)
    mov     x4, x0                      // timeout
    mov     x0, x1                      // epfd
    mov     x1, x2                      // events
    mov     x2, x3                      // maxevents
    mov     x3, x4                      // timeout
    mov     x4, #0                      // sigmask = NULL
    mov     x8, #SYS_epoll_pwait
    svc     #0

    ldp     x29, x30, [sp], #16
    ret
.size reactor_wait, .-reactor_wait

// =============================================================================
// reactor_get_event - Get event at index
// =============================================================================
// Input:
//   x0 = event index
// Output:
//   x0 = events mask
//   x1 = user data
// =============================================================================
.global reactor_get_event
.type reactor_get_event, %function
reactor_get_event:
    adrp    x2, g_epoll_events
    add     x2, x2, :lo12:g_epoll_events
    mov     x3, #EPOLL_EVENT_SIZE
    mul     x3, x0, x3
    add     x2, x2, x3

    ldr     w0, [x2]                    // events
    ldr     x1, [x2, #4]                // data
    ret
.size reactor_get_event, .-reactor_get_event

// =============================================================================
// reactor_run - Main event loop
// =============================================================================
// Input:
//   x0 = callback function ptr (called for each event)
//        callback(events, data) -> 0 to continue, non-zero to stop
// Output:
//   x0 = 0 or -errno
// =============================================================================
.global reactor_run
.type reactor_run, %function
reactor_run:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x19, x0                     // Callback ptr
    adrp    x20, g_reactor
    add     x20, x20, :lo12:g_reactor

.Lrun_loop:
    // Check running flag
    ldr     x0, [x20, #REACTOR_OFF_RUNNING]
    cbz     x0, .Lrun_stopped

    // Wait for events
    mov     x0, #NET_EPOLL_TIMEOUT
    bl      reactor_wait
    cmp     x0, #0
    b.lt    .Lrun_check_eintr

    mov     x21, x0                     // Event count
    mov     x22, #0                     // Event index

.Lrun_event_loop:
    cmp     x22, x21
    b.hs    .Lrun_loop

    // Get event
    mov     x0, x22
    bl      reactor_get_event
    // x0 = events, x1 = data

    // Call callback if provided
    cbz     x19, .Lrun_next_event
    mov     x2, x0                      // Save events
    mov     x3, x1                      // Save data
    mov     x0, x2
    mov     x1, x3
    blr     x19
    cbnz    x0, .Lrun_callback_stop

.Lrun_next_event:
    add     x22, x22, #1
    b       .Lrun_event_loop

.Lrun_check_eintr:
    mov     x1, #-EINTR
    cmp     x0, x1
    b.eq    .Lrun_loop                  // Interrupted, continue
    b       .Lrun_ret                   // Real error

.Lrun_callback_stop:
    mov     x0, #0

.Lrun_stopped:
    mov     x0, #0

.Lrun_ret:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size reactor_run, .-reactor_run

// =============================================================================
// reactor_stop - Stop the event loop
// =============================================================================
// Input: none
// Output:
//   x0 = 0
// =============================================================================
.global reactor_stop
.type reactor_stop, %function
reactor_stop:
    adrp    x0, g_reactor
    add     x0, x0, :lo12:g_reactor
    str     xzr, [x0, #REACTOR_OFF_RUNNING]
    mov     x0, #0
    ret
.size reactor_stop, .-reactor_stop

// =============================================================================
// reactor_is_running - Check if reactor is running
// =============================================================================
// Input: none
// Output:
//   x0 = 1 if running, 0 if stopped
// =============================================================================
.global reactor_is_running
.type reactor_is_running, %function
reactor_is_running:
    adrp    x0, g_reactor
    add     x0, x0, :lo12:g_reactor
    ldr     x0, [x0, #REACTOR_OFF_RUNNING]
    ret
.size reactor_is_running, .-reactor_is_running

// =============================================================================
// reactor_close - Close reactor and cleanup
// =============================================================================
// Input: none
// Output:
//   x0 = 0
// =============================================================================
.global reactor_close
.type reactor_close, %function
reactor_close:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    adrp    x19, g_reactor
    add     x19, x19, :lo12:g_reactor

    // Stop running
    str     xzr, [x19, #REACTOR_OFF_RUNNING]

    // Close UDP socket
    ldr     x0, [x19, #REACTOR_OFF_UDP_FD]
    cmn     x0, #1
    b.eq    .Lclose_tcp
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #-1
    str     x0, [x19, #REACTOR_OFF_UDP_FD]

.Lclose_tcp:
    // Close TCP socket
    ldr     x0, [x19, #REACTOR_OFF_TCP_FD]
    cmn     x0, #1
    b.eq    .Lclose_epoll
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #-1
    str     x0, [x19, #REACTOR_OFF_TCP_FD]

.Lclose_epoll:
    // Close epoll fd
    ldr     x0, [x19, #REACTOR_OFF_EPOLL_FD]
    cmn     x0, #1
    b.eq    .Lclose_done
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #-1
    str     x0, [x19, #REACTOR_OFF_EPOLL_FD]

.Lclose_done:
    mov     x0, #0
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size reactor_close, .-reactor_close

// =============================================================================
// reactor_get_tcp_fd - Get listening TCP fd
// =============================================================================
// Input: none
// Output:
//   x0 = fd
// =============================================================================
.global reactor_get_tcp_fd
.type reactor_get_tcp_fd, %function
reactor_get_tcp_fd:
    adrp    x0, g_reactor
    add     x0, x0, :lo12:g_reactor
    ldr     x0, [x0, #REACTOR_OFF_TCP_FD]
    ret
.size reactor_get_tcp_fd, .-reactor_get_tcp_fd

// =============================================================================
// reactor_get_udp_fd - Get UDP fd
// =============================================================================
// Input: none
// Output:
//   x0 = fd
// =============================================================================
.global reactor_get_udp_fd
.type reactor_get_udp_fd, %function
reactor_get_udp_fd:
    adrp    x0, g_reactor
    add     x0, x0, :lo12:g_reactor
    ldr     x0, [x0, #REACTOR_OFF_UDP_FD]
    ret
.size reactor_get_udp_fd, .-reactor_get_udp_fd

// =============================================================================
// reactor_get_node_id - Get local node ID
// =============================================================================
// Input: none
// Output:
//   x0 = node ID
// =============================================================================
.global reactor_get_node_id
.type reactor_get_node_id, %function
reactor_get_node_id:
    adrp    x0, g_reactor
    add     x0, x0, :lo12:g_reactor
    ldr     x0, [x0, #REACTOR_OFF_NODE_ID]
    ret
.size reactor_get_node_id, .-reactor_get_node_id
