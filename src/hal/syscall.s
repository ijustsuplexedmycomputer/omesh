// =============================================================================
// Omesh - syscall.s
// Linux aarch64 syscall wrappers with error handling
// =============================================================================
//
// Calling convention (AAPCS64):
//   - Arguments: x0-x5 (same as kernel syscall convention)
//   - Return: x0 = result on success, negative errno on error
//   - Clobbers: x8 (syscall number), x9-x15 (scratch registers)
//   - Preserved: x19-x28, sp, fp, lr
//
// Error handling:
//   The Linux kernel returns -errno directly in x0 on error for aarch64.
//   We pass this through unchanged, so callers can check with:
//     cmp x0, #0
//     b.lt error_handler
//   Or for specific error comparison:
//     cmn x0, #ENOENT      // Compare Negative: x0 == -ENOENT?
//     b.eq file_not_found
//
// =============================================================================

.include "include/syscall_nums.inc"

.text
.balign 4

// =============================================================================
// File Operations
// =============================================================================

// -----------------------------------------------------------------------------
// sys_read - Read from file descriptor
//
// Input:
//   x0 = file descriptor
//   x1 = buffer pointer
//   x2 = count (max bytes to read)
// Output:
//   x0 = bytes read on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_read
.type sys_read, %function
sys_read:
    mov     x8, #SYS_read
    svc     #0
    ret
.size sys_read, . - sys_read

// -----------------------------------------------------------------------------
// sys_write - Write to file descriptor
//
// Input:
//   x0 = file descriptor
//   x1 = buffer pointer
//   x2 = count (bytes to write)
// Output:
//   x0 = bytes written on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_write
.type sys_write, %function
sys_write:
    mov     x8, #SYS_write
    svc     #0
    ret
.size sys_write, . - sys_write

// -----------------------------------------------------------------------------
// sys_openat - Open file relative to directory fd
//
// Input:
//   x0 = dirfd (use AT_FDCWD for current directory)
//   x1 = pathname (null-terminated string)
//   x2 = flags (O_RDONLY, O_WRONLY, etc.)
//   x3 = mode (permissions if O_CREAT)
// Output:
//   x0 = file descriptor on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_openat
.type sys_openat, %function
sys_openat:
    mov     x8, #SYS_openat
    svc     #0
    ret
.size sys_openat, . - sys_openat

// -----------------------------------------------------------------------------
// sys_open - Open file (convenience wrapper for sys_openat)
//
// Input:
//   x0 = pathname (null-terminated string)
//   x1 = flags
//   x2 = mode
// Output:
//   x0 = file descriptor on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_open
.type sys_open, %function
sys_open:
    mov     x3, x2              // mode -> x3
    mov     x2, x1              // flags -> x2
    mov     x1, x0              // pathname -> x1
    mov     x0, #AT_FDCWD       // dirfd = current directory
    mov     x8, #SYS_openat
    svc     #0
    ret
.size sys_open, . - sys_open

// -----------------------------------------------------------------------------
// sys_close - Close file descriptor
//
// Input:
//   x0 = file descriptor
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_close
.type sys_close, %function
sys_close:
    mov     x8, #SYS_close
    svc     #0
    ret
.size sys_close, . - sys_close

// -----------------------------------------------------------------------------
// sys_lseek - Reposition file offset
//
// Input:
//   x0 = file descriptor
//   x1 = offset
//   x2 = whence (SEEK_SET, SEEK_CUR, SEEK_END)
// Output:
//   x0 = new offset on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_lseek
.type sys_lseek, %function
sys_lseek:
    mov     x8, #SYS_lseek
    svc     #0
    ret
.size sys_lseek, . - sys_lseek

// -----------------------------------------------------------------------------
// sys_fsync - Synchronize file to disk
//
// Input:
//   x0 = file descriptor
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_fsync
.type sys_fsync, %function
sys_fsync:
    mov     x8, #SYS_fsync
    svc     #0
    ret
.size sys_fsync, . - sys_fsync

// -----------------------------------------------------------------------------
// sys_ftruncate - Truncate file to specified length
//
// Input:
//   x0 = file descriptor
//   x1 = length
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_ftruncate
.type sys_ftruncate, %function
sys_ftruncate:
    mov     x8, #SYS_ftruncate
    svc     #0
    ret
.size sys_ftruncate, . - sys_ftruncate

// =============================================================================
// Memory Operations
// =============================================================================

// -----------------------------------------------------------------------------
// sys_mmap - Map memory
//
// Input:
//   x0 = addr (hint, or NULL for kernel to choose)
//   x1 = length
//   x2 = prot (PROT_READ, PROT_WRITE, PROT_EXEC)
//   x3 = flags (MAP_SHARED, MAP_PRIVATE, MAP_ANONYMOUS, etc.)
//   x4 = fd (file descriptor, or -1 for anonymous)
//   x5 = offset (file offset)
// Output:
//   x0 = mapped address on success, negative errno on error
// Notes:
//   Check for error with: cmp x0, #-4096; b.hi mmap_failed
//   (Addresses are never in the range -4095 to -1)
// -----------------------------------------------------------------------------
.global sys_mmap
.type sys_mmap, %function
sys_mmap:
    mov     x8, #SYS_mmap
    svc     #0
    ret
.size sys_mmap, . - sys_mmap

// -----------------------------------------------------------------------------
// sys_munmap - Unmap memory
//
// Input:
//   x0 = addr (must be page-aligned)
//   x1 = length
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_munmap
.type sys_munmap, %function
sys_munmap:
    mov     x8, #SYS_munmap
    svc     #0
    ret
.size sys_munmap, . - sys_munmap

// -----------------------------------------------------------------------------
// sys_mprotect - Set memory protection
//
// Input:
//   x0 = addr (must be page-aligned)
//   x1 = length
//   x2 = prot (PROT_READ, PROT_WRITE, PROT_EXEC)
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_mprotect
.type sys_mprotect, %function
sys_mprotect:
    mov     x8, #SYS_mprotect
    svc     #0
    ret
.size sys_mprotect, . - sys_mprotect

// -----------------------------------------------------------------------------
// sys_madvise - Give advice about memory usage
//
// Input:
//   x0 = addr
//   x1 = length
//   x2 = advice (MADV_DONTNEED, MADV_WILLNEED, etc.)
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_madvise
.type sys_madvise, %function
sys_madvise:
    mov     x8, #SYS_madvise
    svc     #0
    ret
.size sys_madvise, . - sys_madvise

// -----------------------------------------------------------------------------
// sys_brk - Change data segment size
//
// Input:
//   x0 = new brk address (or 0 to get current brk)
// Output:
//   x0 = current brk address
// Note: Unlike x86, aarch64 brk returns the actual brk, not 0/-1
// -----------------------------------------------------------------------------
.global sys_brk
.type sys_brk, %function
sys_brk:
    mov     x8, #SYS_brk
    svc     #0
    ret
.size sys_brk, . - sys_brk

// =============================================================================
// Process Operations
// =============================================================================

// -----------------------------------------------------------------------------
// sys_exit - Terminate the calling thread
//
// Input:
//   x0 = exit status
// Output:
//   Does not return
// -----------------------------------------------------------------------------
.global sys_exit
.type sys_exit, %function
sys_exit:
    mov     x8, #SYS_exit
    svc     #0
    // Should never reach here
    b       sys_exit
.size sys_exit, . - sys_exit

// -----------------------------------------------------------------------------
// sys_exit_group - Terminate all threads in process
//
// Input:
//   x0 = exit status
// Output:
//   Does not return
// -----------------------------------------------------------------------------
.global sys_exit_group
.type sys_exit_group, %function
sys_exit_group:
    mov     x8, #SYS_exit_group
    svc     #0
    // Should never reach here
    b       sys_exit_group
.size sys_exit_group, . - sys_exit_group

// -----------------------------------------------------------------------------
// sys_getpid - Get process ID
//
// Output:
//   x0 = process ID (always succeeds)
// -----------------------------------------------------------------------------
.global sys_getpid
.type sys_getpid, %function
sys_getpid:
    mov     x8, #SYS_getpid
    svc     #0
    ret
.size sys_getpid, . - sys_getpid

// -----------------------------------------------------------------------------
// sys_gettid - Get thread ID
//
// Output:
//   x0 = thread ID (always succeeds)
// -----------------------------------------------------------------------------
.global sys_gettid
.type sys_gettid, %function
sys_gettid:
    mov     x8, #SYS_gettid
    svc     #0
    ret
.size sys_gettid, . - sys_gettid

// -----------------------------------------------------------------------------
// sys_getuid - Get user ID
//
// Output:
//   x0 = user ID (always succeeds)
// -----------------------------------------------------------------------------
.global sys_getuid
.type sys_getuid, %function
sys_getuid:
    mov     x8, #SYS_getuid
    svc     #0
    ret
.size sys_getuid, . - sys_getuid

// -----------------------------------------------------------------------------
// sys_nanosleep - High-resolution sleep
//
// Input:
//   x0 = pointer to timespec (seconds, nanoseconds)
//   x1 = pointer to remaining time (or NULL)
// Output:
//   x0 = 0 on success, -EINTR if interrupted (remaining time in x1)
// -----------------------------------------------------------------------------
.global sys_nanosleep
.type sys_nanosleep, %function
sys_nanosleep:
    mov     x8, #SYS_nanosleep
    svc     #0
    ret
.size sys_nanosleep, . - sys_nanosleep

// =============================================================================
// System Information
// =============================================================================

// -----------------------------------------------------------------------------
// sys_uname - Get system information
//
// Input:
//   x0 = pointer to utsname struct (390 bytes)
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_uname
.type sys_uname, %function
sys_uname:
    mov     x8, #SYS_uname
    svc     #0
    ret
.size sys_uname, . - sys_uname

// -----------------------------------------------------------------------------
// sys_sysinfo - Get system statistics
//
// Input:
//   x0 = pointer to sysinfo struct
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_sysinfo
.type sys_sysinfo, %function
sys_sysinfo:
    mov     x8, #SYS_sysinfo
    svc     #0
    ret
.size sys_sysinfo, . - sys_sysinfo

// -----------------------------------------------------------------------------
// sys_getrandom - Get random bytes
//
// Input:
//   x0 = buffer pointer
//   x1 = count (bytes to read)
//   x2 = flags (0 = blocking, GRND_NONBLOCK, GRND_RANDOM)
// Output:
//   x0 = bytes written on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_getrandom
.type sys_getrandom, %function
sys_getrandom:
    mov     x8, #SYS_getrandom
    svc     #0
    ret
.size sys_getrandom, . - sys_getrandom

// getrandom flags
.equ GRND_NONBLOCK, 1
.equ GRND_RANDOM,   2

// =============================================================================
// Time Operations
// =============================================================================

// -----------------------------------------------------------------------------
// sys_clock_gettime - Get time from specified clock
//
// Input:
//   x0 = clock_id (CLOCK_REALTIME, CLOCK_MONOTONIC, etc.)
//   x1 = pointer to timespec struct (16 bytes: seconds, nanoseconds)
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_clock_gettime
.type sys_clock_gettime, %function
sys_clock_gettime:
    mov     x8, #SYS_clock_gettime
    svc     #0
    ret
.size sys_clock_gettime, . - sys_clock_gettime

// =============================================================================
// Socket Operations
// =============================================================================

// -----------------------------------------------------------------------------
// sys_socket - Create socket
//
// Input:
//   x0 = domain (AF_INET, AF_INET6, AF_UNIX)
//   x1 = type (SOCK_STREAM, SOCK_DGRAM)
//   x2 = protocol (usually 0)
// Output:
//   x0 = socket fd on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_socket
.type sys_socket, %function
sys_socket:
    mov     x8, #SYS_socket
    svc     #0
    ret
.size sys_socket, . - sys_socket

// -----------------------------------------------------------------------------
// sys_bind - Bind socket to address
//
// Input:
//   x0 = socket fd
//   x1 = pointer to sockaddr
//   x2 = address length
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_bind
.type sys_bind, %function
sys_bind:
    mov     x8, #SYS_bind
    svc     #0
    ret
.size sys_bind, . - sys_bind

// -----------------------------------------------------------------------------
// sys_listen - Listen for connections
//
// Input:
//   x0 = socket fd
//   x1 = backlog (max pending connections)
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_listen
.type sys_listen, %function
sys_listen:
    mov     x8, #SYS_listen
    svc     #0
    ret
.size sys_listen, . - sys_listen

// -----------------------------------------------------------------------------
// sys_accept4 - Accept connection with flags
//
// Input:
//   x0 = socket fd
//   x1 = pointer to sockaddr (or NULL)
//   x2 = pointer to address length (or NULL)
//   x3 = flags (SOCK_NONBLOCK, SOCK_CLOEXEC)
// Output:
//   x0 = new socket fd on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_accept4
.type sys_accept4, %function
sys_accept4:
    mov     x8, #SYS_accept4
    svc     #0
    ret
.size sys_accept4, . - sys_accept4

// -----------------------------------------------------------------------------
// sys_connect - Connect socket to address
//
// Input:
//   x0 = socket fd
//   x1 = pointer to sockaddr
//   x2 = address length
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_connect
.type sys_connect, %function
sys_connect:
    mov     x8, #SYS_connect
    svc     #0
    ret
.size sys_connect, . - sys_connect

// -----------------------------------------------------------------------------
// sys_sendto - Send message to socket
//
// Input:
//   x0 = socket fd
//   x1 = buffer pointer
//   x2 = length
//   x3 = flags
//   x4 = dest address (or NULL for connected socket)
//   x5 = address length
// Output:
//   x0 = bytes sent on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_sendto
.type sys_sendto, %function
sys_sendto:
    mov     x8, #SYS_sendto
    svc     #0
    ret
.size sys_sendto, . - sys_sendto

// -----------------------------------------------------------------------------
// sys_recvfrom - Receive message from socket
//
// Input:
//   x0 = socket fd
//   x1 = buffer pointer
//   x2 = length
//   x3 = flags
//   x4 = source address (or NULL)
//   x5 = pointer to address length (or NULL)
// Output:
//   x0 = bytes received on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_recvfrom
.type sys_recvfrom, %function
sys_recvfrom:
    mov     x8, #SYS_recvfrom
    svc     #0
    ret
.size sys_recvfrom, . - sys_recvfrom

// -----------------------------------------------------------------------------
// sys_setsockopt - Set socket option
//
// Input:
//   x0 = socket fd
//   x1 = level (SOL_SOCKET, IPPROTO_TCP, etc.)
//   x2 = option name
//   x3 = option value pointer
//   x4 = option length
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_setsockopt
.type sys_setsockopt, %function
sys_setsockopt:
    mov     x8, #SYS_setsockopt
    svc     #0
    ret
.size sys_setsockopt, . - sys_setsockopt

// -----------------------------------------------------------------------------
// sys_shutdown - Shut down part of full-duplex connection
//
// Input:
//   x0 = socket fd
//   x1 = how (SHUT_RD=0, SHUT_WR=1, SHUT_RDWR=2)
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_shutdown
.type sys_shutdown, %function
sys_shutdown:
    mov     x8, #SYS_shutdown
    svc     #0
    ret
.size sys_shutdown, . - sys_shutdown

.equ SHUT_RD,   0
.equ SHUT_WR,   1
.equ SHUT_RDWR, 2

// =============================================================================
// Event/Poll Operations
// =============================================================================

// -----------------------------------------------------------------------------
// sys_epoll_create1 - Create epoll instance
//
// Input:
//   x0 = flags (EPOLL_CLOEXEC or 0)
// Output:
//   x0 = epoll fd on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_epoll_create1
.type sys_epoll_create1, %function
sys_epoll_create1:
    mov     x8, #SYS_epoll_create1
    svc     #0
    ret
.size sys_epoll_create1, . - sys_epoll_create1

.equ EPOLL_CLOEXEC, 0x80000

// -----------------------------------------------------------------------------
// sys_epoll_ctl - Control epoll instance
//
// Input:
//   x0 = epoll fd
//   x1 = operation (EPOLL_CTL_ADD, _MOD, _DEL)
//   x2 = target fd
//   x3 = pointer to epoll_event (NULL for DEL)
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_epoll_ctl
.type sys_epoll_ctl, %function
sys_epoll_ctl:
    mov     x8, #SYS_epoll_ctl
    svc     #0
    ret
.size sys_epoll_ctl, . - sys_epoll_ctl

// -----------------------------------------------------------------------------
// sys_epoll_pwait - Wait for events on epoll instance
//
// Input:
//   x0 = epoll fd
//   x1 = pointer to events array
//   x2 = max events
//   x3 = timeout in milliseconds (-1 = infinite)
//   x4 = signal mask (or NULL)
// Output:
//   x0 = number of ready fds on success, negative errno on error
// Note: x5 must be set to sizeof(sigset_t) = 8 if using signal mask
// -----------------------------------------------------------------------------
.global sys_epoll_pwait
.type sys_epoll_pwait, %function
sys_epoll_pwait:
    mov     x5, #8              // sizeof(sigset_t)
    mov     x8, #SYS_epoll_pwait
    svc     #0
    ret
.size sys_epoll_pwait, . - sys_epoll_pwait

// =============================================================================
// Directory Operations
// =============================================================================

// -----------------------------------------------------------------------------
// sys_getdents64 - Get directory entries
//
// Input:
//   x0 = directory fd
//   x1 = buffer pointer
//   x2 = buffer size
// Output:
//   x0 = bytes read on success (0 = end), negative errno on error
// -----------------------------------------------------------------------------
.global sys_getdents64
.type sys_getdents64, %function
sys_getdents64:
    mov     x8, #SYS_getdents64
    svc     #0
    ret
.size sys_getdents64, . - sys_getdents64

// -----------------------------------------------------------------------------
// sys_mkdirat - Create directory
//
// Input:
//   x0 = dirfd (AT_FDCWD for cwd)
//   x1 = pathname
//   x2 = mode
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_mkdirat
.type sys_mkdirat, %function
sys_mkdirat:
    mov     x8, #SYS_mkdirat
    svc     #0
    ret
.size sys_mkdirat, . - sys_mkdirat

// -----------------------------------------------------------------------------
// sys_unlinkat - Remove file or directory
//
// Input:
//   x0 = dirfd (AT_FDCWD for cwd)
//   x1 = pathname
//   x2 = flags (AT_REMOVEDIR for directories)
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_unlinkat
.type sys_unlinkat, %function
sys_unlinkat:
    mov     x8, #SYS_unlinkat
    svc     #0
    ret
.size sys_unlinkat, . - sys_unlinkat

// =============================================================================
// Signal Operations
// =============================================================================

// -----------------------------------------------------------------------------
// sys_rt_sigaction - Examine and change signal action
//
// Input:
//   x0 = signal number
//   x1 = pointer to new sigaction (or NULL)
//   x2 = pointer to old sigaction (or NULL)
//   x3 = sizeof(sigset_t) = 8
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_rt_sigaction
.type sys_rt_sigaction, %function
sys_rt_sigaction:
    mov     x3, #8              // sizeof(sigset_t)
    mov     x8, #SYS_rt_sigaction
    svc     #0
    ret
.size sys_rt_sigaction, . - sys_rt_sigaction

// -----------------------------------------------------------------------------
// sys_rt_sigprocmask - Examine and change blocked signals
//
// Input:
//   x0 = how (SIG_BLOCK, SIG_UNBLOCK, SIG_SETMASK)
//   x1 = pointer to new set (or NULL)
//   x2 = pointer to old set (or NULL)
//   x3 = sizeof(sigset_t) = 8
// Output:
//   x0 = 0 on success, negative errno on error
// -----------------------------------------------------------------------------
.global sys_rt_sigprocmask
.type sys_rt_sigprocmask, %function
sys_rt_sigprocmask:
    mov     x3, #8              // sizeof(sigset_t)
    mov     x8, #SYS_rt_sigprocmask
    svc     #0
    ret
.size sys_rt_sigprocmask, . - sys_rt_sigprocmask

.equ SIG_BLOCK,   0
.equ SIG_UNBLOCK, 1
.equ SIG_SETMASK, 2

// =============================================================================
// Helper Functions
// =============================================================================

// -----------------------------------------------------------------------------
// print_str - Write null-terminated string to stdout
//
// Input:
//   x0 = pointer to null-terminated string
// Output:
//   x0 = bytes written or negative errno
// Clobbers: x0-x2, x8, x9
// -----------------------------------------------------------------------------
.global print_str
.type print_str, %function
print_str:
    mov     x9, x0              // Save string pointer

    // Calculate string length
    mov     x1, x0
.Lprint_strlen:
    ldrb    w2, [x1], #1
    cbnz    w2, .Lprint_strlen
    sub     x2, x1, x9
    sub     x2, x2, #1          // Don't count null terminator

    // Write to stdout
    mov     x0, #STDOUT_FILENO
    mov     x1, x9
    mov     x8, #SYS_write
    svc     #0
    ret
.size print_str, . - print_str

// -----------------------------------------------------------------------------
// print_char - Write single character to stdout
//
// Input:
//   x0 = character (in low byte)
// Output:
//   x0 = 1 on success, negative errno on error
// Clobbers: x0-x2, x8
// -----------------------------------------------------------------------------
.global print_char
.type print_char, %function
print_char:
    // Store char on stack
    sub     sp, sp, #16
    strb    w0, [sp]

    mov     x0, #STDOUT_FILENO
    mov     x1, sp
    mov     x2, #1
    mov     x8, #SYS_write
    svc     #0

    add     sp, sp, #16
    ret
.size print_char, . - print_char

// -----------------------------------------------------------------------------
// print_hex - Print 64-bit value as hexadecimal
//
// Input:
//   x0 = value to print
// Output:
//   x0 = bytes written
// Clobbers: x0-x4, x8-x10
// -----------------------------------------------------------------------------
.global print_hex
.type print_hex, %function
print_hex:
    sub     sp, sp, #32
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16

    mov     x9, x0              // Value to print
    add     x10, sp, #16        // End of buffer (before frame)

    // Handle zero case
    cbnz    x9, .Lhex_loop
    mov     w1, #'0'
    strb    w1, [x10, #-1]!
    b       .Lhex_print

.Lhex_loop:
    cbz     x9, .Lhex_print
    and     x1, x9, #0xF        // Get low nibble
    cmp     x1, #10
    b.lt    .Lhex_digit
    add     x1, x1, #('a' - 10)
    b       .Lhex_store
.Lhex_digit:
    add     x1, x1, #'0'
.Lhex_store:
    strb    w1, [x10, #-1]!
    lsr     x9, x9, #4
    b       .Lhex_loop

.Lhex_print:
    // Add "0x" prefix
    mov     w1, #'x'
    strb    w1, [x10, #-1]!
    mov     w1, #'0'
    strb    w1, [x10, #-1]!

    // Calculate length and print
    add     x2, sp, #16
    sub     x2, x2, x10         // Length
    mov     x0, #STDOUT_FILENO
    mov     x1, x10             // Buffer start
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp, #16]
    add     sp, sp, #32
    ret
.size print_hex, . - print_hex

// -----------------------------------------------------------------------------
// print_dec - Print 64-bit unsigned value as decimal
//
// Input:
//   x0 = value to print
// Output:
//   x0 = bytes written
// Clobbers: x0-x5, x8-x11
// -----------------------------------------------------------------------------
.global print_dec
.type print_dec, %function
print_dec:
    sub     sp, sp, #48
    stp     x29, x30, [sp, #32]
    add     x29, sp, #32

    mov     x9, x0              // Value to print
    add     x10, sp, #32        // End of buffer
    mov     x11, #10            // Divisor

    // Handle zero case
    cbnz    x9, .Ldec_loop
    mov     w1, #'0'
    strb    w1, [x10, #-1]!
    b       .Ldec_print

.Ldec_loop:
    cbz     x9, .Ldec_print
    udiv    x4, x9, x11         // x4 = x9 / 10
    msub    x5, x4, x11, x9     // x5 = x9 - (x4 * 10) = remainder
    add     x5, x5, #'0'
    strb    w5, [x10, #-1]!
    mov     x9, x4
    b       .Ldec_loop

.Ldec_print:
    // Calculate length and print
    add     x2, sp, #32
    sub     x2, x2, x10         // Length
    mov     x0, #STDOUT_FILENO
    mov     x1, x10             // Buffer start
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp, #32]
    add     sp, sp, #48
    ret
.size print_dec, . - print_dec

// -----------------------------------------------------------------------------
// print_newline - Print newline character
//
// Output:
//   x0 = 1 on success
// Clobbers: x0-x2, x8
// -----------------------------------------------------------------------------
.global print_newline
.type print_newline, %function
print_newline:
    mov     x0, #'\n'
    b       print_char
.size print_newline, . - print_newline

// =============================================================================
// End of syscall.s
// =============================================================================
