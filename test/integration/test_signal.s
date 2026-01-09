// =============================================================================
// Omesh - Signal Handling Integration Test
// =============================================================================
//
// Tests graceful shutdown via signal handling:
// 1. Fork a child process
// 2. Child calls signal_init and loops checking signal_shutdown_requested
// 3. Parent sends SIGTERM to child
// 4. Parent waits for child and verifies clean exit (exit code 0)
//
// =============================================================================

.include "syscall_nums.inc"

.data

msg_banner:
    .asciz  "=== Omesh Signal Handling Test ===\n"

msg_fork:
    .asciz  "[TEST] Forking child process...\n"

msg_child_start:
    .asciz  "[CHILD] Starting, calling signal_init...\n"

msg_child_init_ok:
    .asciz  "[CHILD] signal_init OK, entering loop...\n"

msg_child_init_fail:
    .asciz  "[CHILD] signal_init FAILED\n"

msg_child_shutdown:
    .asciz  "[CHILD] Shutdown requested, exiting cleanly\n"

msg_parent_sending:
    .asciz  "[PARENT] Sending SIGTERM to child...\n"

msg_parent_waiting:
    .asciz  "[PARENT] Waiting for child to exit...\n"

msg_pass:
    .asciz  "[PASS] Child exited cleanly with code 0\n"

msg_fail_code:
    .asciz  "[FAIL] Child exited with non-zero code\n"

msg_fail_signal:
    .asciz  "[FAIL] Child was killed by signal\n"

msg_fail_fork:
    .asciz  "[FAIL] Fork failed\n"

msg_exit_code:
    .asciz  "  Exit status: "

msg_newline:
    .asciz  "\n"

msg_summary_pass:
    .asciz  "\n=== Signal test PASSED ===\n"

msg_summary_fail:
    .asciz  "\n=== Signal test FAILED ===\n"

.bss
.align 4
child_pid:
    .skip   4

wait_status:
    .skip   4

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
    add     x1, x1, #32         // Buffer at sp+32
    mov     x2, #0              // Digit count

    // Handle 0 specially
    cbz     x0, .Lpd_zero

.Lpd_loop:
    cbz     x0, .Lpd_print
    mov     x3, #10
    udiv    x4, x0, x3          // x4 = x0 / 10
    msub    x5, x4, x3, x0      // x5 = x0 - (x4 * 10) = remainder
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
    mov     x0, #1              // stdout
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #48
    ret

// =============================================================================
// nanosleep_ms - Sleep for milliseconds
// =============================================================================
// Input: x0 = milliseconds
nanosleep_ms:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp

    // Convert ms to timespec (seconds, nanoseconds)
    mov     x1, #1000
    udiv    x2, x0, x1          // seconds
    msub    x3, x2, x1, x0      // remainder ms
    // 1000000 = 0xF4240, need movz + movk
    movz    x4, #0x4240
    movk    x4, #0xF, lsl #16   // x4 = 1000000
    mul     x3, x3, x4          // nanoseconds

    str     x2, [sp, #16]       // tv_sec
    str     x3, [sp, #24]       // tv_nsec

    add     x0, sp, #16         // req
    mov     x1, #0              // rem (NULL)
    mov     x8, #SYS_nanosleep
    svc     #0

    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// _start - Test entry point
// =============================================================================
.global _start
_start:
    // Set up stack frame
    mov     x29, sp

    // Print banner
    adrp    x0, msg_banner
    add     x0, x0, :lo12:msg_banner
    bl      print_str

    // Print fork message
    adrp    x0, msg_fork
    add     x0, x0, :lo12:msg_fork
    bl      print_str

    // Fork using clone syscall
    // clone(SIGCHLD, 0, 0, 0, 0) is equivalent to fork()
    mov     x0, #SIGCHLD        // flags = SIGCHLD
    mov     x1, #0              // stack = 0 (use parent's)
    mov     x2, #0              // parent_tid
    mov     x3, #0              // tls
    mov     x4, #0              // child_tid
    mov     x8, #SYS_clone
    svc     #0

    cmp     x0, #0
    b.lt    .Lfork_failed
    b.eq    .Lchild_process

    // === Parent process ===
    // Save child PID
    adrp    x1, child_pid
    add     x1, x1, :lo12:child_pid
    str     w0, [x1]

    // Sleep 100ms to let child initialize
    mov     x0, #100
    bl      nanosleep_ms

    // Print sending message
    adrp    x0, msg_parent_sending
    add     x0, x0, :lo12:msg_parent_sending
    bl      print_str

    // Send SIGTERM to child
    adrp    x0, child_pid
    add     x0, x0, :lo12:child_pid
    ldr     w0, [x0]            // pid
    mov     x1, #SIGTERM        // signal
    mov     x8, #SYS_kill
    svc     #0

    // Print waiting message
    adrp    x0, msg_parent_waiting
    add     x0, x0, :lo12:msg_parent_waiting
    bl      print_str

    // Wait for child
    adrp    x0, child_pid
    add     x0, x0, :lo12:child_pid
    ldr     w0, [x0]            // pid
    adrp    x1, wait_status
    add     x1, x1, :lo12:wait_status
    mov     x2, #0              // options
    mov     x3, #0              // rusage
    mov     x8, #SYS_wait4
    svc     #0

    // Check wait status
    // If WIFEXITED (status & 0x7f == 0), exit code is (status >> 8) & 0xff
    // If WIFSIGNALED (status & 0x7f != 0), was killed by signal
    adrp    x0, wait_status
    add     x0, x0, :lo12:wait_status
    ldr     w1, [x0]

    and     w2, w1, #0x7f       // Check if exited normally
    cbnz    w2, .Lchild_signaled

    // Extract exit code
    lsr     w3, w1, #8
    and     w19, w3, #0xff      // Save exit code in callee-saved x19

    // Print exit code
    adrp    x0, msg_exit_code
    add     x0, x0, :lo12:msg_exit_code
    bl      print_str
    mov     x0, x19
    bl      print_dec
    adrp    x0, msg_newline
    add     x0, x0, :lo12:msg_newline
    bl      print_str

    // Check if exit code is 0
    cbnz    w19, .Ltest_fail_code

    // Success!
    adrp    x0, msg_pass
    add     x0, x0, :lo12:msg_pass
    bl      print_str

    adrp    x0, msg_summary_pass
    add     x0, x0, :lo12:msg_summary_pass
    bl      print_str

    mov     x0, #0
    mov     x8, #SYS_exit
    svc     #0

.Lchild_signaled:
    adrp    x0, msg_fail_signal
    add     x0, x0, :lo12:msg_fail_signal
    bl      print_str
    b       .Ltest_fail

.Ltest_fail_code:
    adrp    x0, msg_fail_code
    add     x0, x0, :lo12:msg_fail_code
    bl      print_str
    b       .Ltest_fail

.Lfork_failed:
    adrp    x0, msg_fail_fork
    add     x0, x0, :lo12:msg_fail_fork
    bl      print_str

.Ltest_fail:
    adrp    x0, msg_summary_fail
    add     x0, x0, :lo12:msg_summary_fail
    bl      print_str

    mov     x0, #1
    mov     x8, #SYS_exit
    svc     #0

// =============================================================================
// Child process
// =============================================================================
.Lchild_process:
    // Print start message
    adrp    x0, msg_child_start
    add     x0, x0, :lo12:msg_child_start
    bl      print_str

    // Call signal_init
    bl      signal_init
    cmp     x0, #0
    b.lt    .Lchild_init_fail

    // Print init OK
    adrp    x0, msg_child_init_ok
    add     x0, x0, :lo12:msg_child_init_ok
    bl      print_str

    // Loop checking for shutdown signal
.Lchild_loop:
    bl      signal_shutdown_requested
    cbnz    x0, .Lchild_got_signal

    // Sleep 10ms between checks
    mov     x0, #10
    bl      nanosleep_ms

    b       .Lchild_loop

.Lchild_got_signal:
    // Print shutdown message
    adrp    x0, msg_child_shutdown
    add     x0, x0, :lo12:msg_child_shutdown
    bl      print_str

    // Exit cleanly with code 0
    mov     x0, #0
    mov     x8, #SYS_exit
    svc     #0

.Lchild_init_fail:
    adrp    x0, msg_child_init_fail
    add     x0, x0, :lo12:msg_child_init_fail
    bl      print_str

    mov     x0, #1
    mov     x8, #SYS_exit
    svc     #0
