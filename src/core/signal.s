// =============================================================================
// Omesh - Signal Handler Module
// =============================================================================
//
// Signal handling for graceful shutdown:
// - signal_init: Install handlers for SIGTERM, SIGINT, SIGHUP
// - signal_shutdown_requested: Returns 1 if shutdown signal received
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
//   signal_init() -> 0 | -errno
//       Install signal handlers for graceful shutdown.
//       Handles: SIGTERM, SIGINT, SIGHUP
//
//   signal_shutdown_requested() -> 0 | 1
//       Returns 1 if a shutdown signal has been received.
//       Non-destructive: can be called multiple times.
//
//   signal_get_signum() -> signum
//       Returns the signal number that triggered shutdown (0 if none).
//
// =============================================================================

.include "syscall_nums.inc"

// -----------------------------------------------------------------------------
// sigaction structure for aarch64 Linux
// The kernel's struct sigaction is:
//   sa_handler:  8 bytes (function pointer)
//   sa_flags:    8 bytes (unsigned long)
//   sa_mask:     128 bytes (sigset_t = 1024 bits / 8)
// Total: 144 bytes minimum
// -----------------------------------------------------------------------------
.equ SIGACT_OFF_HANDLER,    0       // void (*sa_handler)(int)
.equ SIGACT_OFF_FLAGS,      8       // unsigned long sa_flags
.equ SIGACT_OFF_MASK,       16      // sigset_t sa_mask (128 bytes!)
.equ SIGACT_SIZE,           152     // 144 + padding for alignment

.data

// -----------------------------------------------------------------------------
// Global shutdown flag (accessed from signal handler and main loop)
// -----------------------------------------------------------------------------
.align 8
.global g_shutdown_requested
g_shutdown_requested:
    .quad   0

// Signal number that triggered shutdown
.align 4
.global g_shutdown_signal
g_shutdown_signal:
    .word   0

// sigaction structures (need to be in .data for read/write)
// Must be large enough for kernel's sigaction struct (144+ bytes)
.align 8
sigaction_shutdown:
    .skip   SIGACT_SIZE             // Full sigaction struct

sigaction_old:
    .skip   SIGACT_SIZE             // For storing old handler

.text

// =============================================================================
// signal_handler - Internal signal handler for shutdown signals
// =============================================================================
// Input:
//   x0 = signal number
// Note:
//   This is called directly by the kernel. Must be async-signal-safe.
//   Only sets global flags - no syscalls or complex operations.
// =============================================================================
.type signal_handler, %function
signal_handler:
    // Set shutdown flag to 1
    adrp    x1, g_shutdown_requested
    add     x1, x1, :lo12:g_shutdown_requested
    mov     x2, #1
    str     x2, [x1]

    // Store signal number
    adrp    x1, g_shutdown_signal
    add     x1, x1, :lo12:g_shutdown_signal
    str     w0, [x1]

    ret
.size signal_handler, .-signal_handler

// =============================================================================
// install_handler - Install handler for a single signal
// =============================================================================
// Input:
//   x0 = signal number
// Output:
//   x0 = 0 on success, -errno on failure
// =============================================================================
.type install_handler, %function
install_handler:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0                 // Save signal number

    // Clear sigaction structure first
    adrp    x1, sigaction_shutdown
    add     x1, x1, :lo12:sigaction_shutdown
    mov     x2, #SIGACT_SIZE
.Lclear_sigact:
    cbz     x2, .Lclear_sigact_done
    strb    wzr, [x1], #1
    sub     x2, x2, #1
    b       .Lclear_sigact
.Lclear_sigact_done:

    // Set up sigaction structure
    adrp    x1, sigaction_shutdown
    add     x1, x1, :lo12:sigaction_shutdown

    // Store handler address
    adrp    x2, signal_handler
    add     x2, x2, :lo12:signal_handler
    str     x2, [x1, #SIGACT_OFF_HANDLER]

    // sa_flags = 0 (no SA_RESTART - let syscalls return EINTR)
    str     xzr, [x1, #SIGACT_OFF_FLAGS]

    // Call rt_sigaction(signum, &act, &oldact, sigsetsize)
    mov     x0, x19                 // signum
    // x1 already points to sigaction_shutdown
    adrp    x2, sigaction_old
    add     x2, x2, :lo12:sigaction_old
    mov     x3, #SIGSET_SIZE        // sigsetsize (must match kernel's sigset_t size)
    mov     x8, #SYS_rt_sigaction
    svc     #0

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size install_handler, .-install_handler

// =============================================================================
// signal_init - Install signal handlers for graceful shutdown
// =============================================================================
// Output:
//   x0 = 0 on success, -errno on failure
// =============================================================================
.global signal_init
.type signal_init, %function
signal_init:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Clear shutdown flag
    adrp    x0, g_shutdown_requested
    add     x0, x0, :lo12:g_shutdown_requested
    str     xzr, [x0]

    adrp    x0, g_shutdown_signal
    add     x0, x0, :lo12:g_shutdown_signal
    str     wzr, [x0]

    // Install SIGTERM handler
    mov     x0, #SIGTERM
    bl      install_handler
    cmp     x0, #0
    b.lt    .Lsig_init_fail

    // Install SIGINT handler
    mov     x0, #SIGINT
    bl      install_handler
    cmp     x0, #0
    b.lt    .Lsig_init_fail

    // Install SIGHUP handler
    mov     x0, #SIGHUP
    bl      install_handler
    cmp     x0, #0
    b.lt    .Lsig_init_fail

    mov     x0, #0
    b       .Lsig_init_done

.Lsig_init_fail:
    mov     x19, x0                 // Save error

    mov     x0, x19

.Lsig_init_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size signal_init, .-signal_init

// =============================================================================
// signal_shutdown_requested - Check if shutdown has been requested
// =============================================================================
// Output:
//   x0 = 1 if shutdown requested, 0 otherwise
// =============================================================================
.global signal_shutdown_requested
.type signal_shutdown_requested, %function
signal_shutdown_requested:
    adrp    x0, g_shutdown_requested
    add     x0, x0, :lo12:g_shutdown_requested
    ldr     x0, [x0]
    ret
.size signal_shutdown_requested, .-signal_shutdown_requested

// =============================================================================
// signal_get_signum - Get the signal that triggered shutdown
// =============================================================================
// Output:
//   x0 = signal number (0 if no shutdown signal received)
// =============================================================================
.global signal_get_signum
.type signal_get_signum, %function
signal_get_signum:
    adrp    x0, g_shutdown_signal
    add     x0, x0, :lo12:g_shutdown_signal
    ldr     w0, [x0]
    ret
.size signal_get_signum, .-signal_get_signum
