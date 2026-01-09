// =============================================================================
// Omesh - syscall_nums.inc
// Linux aarch64 syscall numbers and system constants
// =============================================================================

// -----------------------------------------------------------------------------
// Syscall Numbers (aarch64 Linux)
// Reference: arch/arm64/include/asm/unistd.h
// -----------------------------------------------------------------------------

.equ SYS_io_setup,          0
.equ SYS_io_destroy,        1
.equ SYS_io_submit,         2
.equ SYS_io_cancel,         3
.equ SYS_io_getevents,      4
.equ SYS_setxattr,          5
.equ SYS_lsetxattr,         6
.equ SYS_fsetxattr,         7
.equ SYS_getxattr,          8
.equ SYS_lgetxattr,         9
.equ SYS_fgetxattr,         10
.equ SYS_listxattr,         11
.equ SYS_llistxattr,        12
.equ SYS_flistxattr,        13
.equ SYS_removexattr,       14
.equ SYS_lremovexattr,      15
.equ SYS_fremovexattr,      16
.equ SYS_getcwd,            17
.equ SYS_lookup_dcookie,    18
.equ SYS_eventfd2,          19
.equ SYS_epoll_create1,     20
.equ SYS_epoll_ctl,         21
.equ SYS_epoll_pwait,       22
.equ SYS_dup,               23
.equ SYS_dup3,              24
.equ SYS_fcntl,             25
.equ SYS_inotify_init1,     26
.equ SYS_inotify_add_watch, 27
.equ SYS_inotify_rm_watch,  28
.equ SYS_ioctl,             29
.equ SYS_ioprio_set,        30
.equ SYS_ioprio_get,        31
.equ SYS_flock,             32
.equ SYS_mknodat,           33
.equ SYS_mkdirat,           34
.equ SYS_unlinkat,          35
.equ SYS_symlinkat,         36
.equ SYS_linkat,            37
.equ SYS_renameat,          38
.equ SYS_umount2,           39
.equ SYS_mount,             40
.equ SYS_pivot_root,        41
.equ SYS_nfsservctl,        42
.equ SYS_statfs,            43
.equ SYS_fstatfs,           44
.equ SYS_truncate,          45
.equ SYS_ftruncate,         46
.equ SYS_fallocate,         47
.equ SYS_faccessat,         48
.equ SYS_chdir,             49
.equ SYS_fchdir,            50
.equ SYS_chroot,            51
.equ SYS_fchmod,            52
.equ SYS_fchmodat,          53
.equ SYS_fchownat,          54
.equ SYS_fchown,            55
.equ SYS_openat,            56
.equ SYS_close,             57
.equ SYS_vhangup,           58
.equ SYS_pipe2,             59
.equ SYS_quotactl,          60
.equ SYS_getdents64,        61
.equ SYS_lseek,             62
.equ SYS_read,              63
.equ SYS_write,             64
.equ SYS_readv,             65
.equ SYS_writev,            66
.equ SYS_pread64,           67
.equ SYS_pwrite64,          68
.equ SYS_preadv,            69
.equ SYS_pwritev,           70
.equ SYS_sendfile,          71
.equ SYS_pselect6,          72
.equ SYS_ppoll,             73
.equ SYS_signalfd4,         74
.equ SYS_vmsplice,          75
.equ SYS_splice,            76
.equ SYS_tee,               77
.equ SYS_readlinkat,        78
.equ SYS_newfstatat,        79
.equ SYS_fstat,             80
.equ SYS_sync,              81
.equ SYS_fsync,             82
.equ SYS_fdatasync,         83
.equ SYS_sync_file_range,   84
.equ SYS_timerfd_create,    85
.equ SYS_timerfd_settime,   86
.equ SYS_timerfd_gettime,   87
.equ SYS_utimensat,         88
.equ SYS_acct,              89
.equ SYS_capget,            90
.equ SYS_capset,            91
.equ SYS_personality,       92
.equ SYS_exit,              93
.equ SYS_exit_group,        94
.equ SYS_waitid,            95
.equ SYS_set_tid_address,   96
.equ SYS_unshare,           97
.equ SYS_futex,             98
.equ SYS_set_robust_list,   99
.equ SYS_get_robust_list,   100
.equ SYS_nanosleep,         101
.equ SYS_getitimer,         102
.equ SYS_setitimer,         103
.equ SYS_kexec_load,        104
.equ SYS_init_module,       105
.equ SYS_delete_module,     106
.equ SYS_timer_create,      107
.equ SYS_timer_gettime,     108
.equ SYS_timer_getoverrun,  109
.equ SYS_timer_settime,     110
.equ SYS_timer_delete,      111
.equ SYS_clock_settime,     112
.equ SYS_clock_gettime,     113
.equ SYS_clock_getres,      114
.equ SYS_clock_nanosleep,   115
.equ SYS_syslog,            116
.equ SYS_ptrace,            117
.equ SYS_sched_setparam,    118
.equ SYS_sched_setscheduler, 119
.equ SYS_sched_getscheduler, 120
.equ SYS_sched_getparam,    121
.equ SYS_sched_setaffinity, 122
.equ SYS_sched_getaffinity, 123
.equ SYS_sched_yield,       124
.equ SYS_sched_get_priority_max, 125
.equ SYS_sched_get_priority_min, 126
.equ SYS_sched_rr_get_interval, 127
.equ SYS_restart_syscall,   128
.equ SYS_kill,              129
.equ SYS_tkill,             130
.equ SYS_tgkill,            131
.equ SYS_sigaltstack,       132
.equ SYS_rt_sigsuspend,     133
.equ SYS_rt_sigaction,      134
.equ SYS_rt_sigprocmask,    135
.equ SYS_rt_sigpending,     136
.equ SYS_rt_sigtimedwait,   137
.equ SYS_rt_sigqueueinfo,   138
.equ SYS_rt_sigreturn,      139
.equ SYS_setpriority,       140
.equ SYS_getpriority,       141
.equ SYS_reboot,            142
.equ SYS_setregid,          143
.equ SYS_setgid,            144
.equ SYS_setreuid,          145
.equ SYS_setuid,            146
.equ SYS_setresuid,         147
.equ SYS_getresuid,         148
.equ SYS_setresgid,         149
.equ SYS_getresgid,         150
.equ SYS_setfsuid,          151
.equ SYS_setfsgid,          152
.equ SYS_times,             153
.equ SYS_setpgid,           154
.equ SYS_getpgid,           155
.equ SYS_getsid,            156
.equ SYS_setsid,            157
.equ SYS_getgroups,         158
.equ SYS_setgroups,         159
.equ SYS_uname,             160
.equ SYS_sethostname,       161
.equ SYS_setdomainname,     162
.equ SYS_getrlimit,         163
.equ SYS_setrlimit,         164
.equ SYS_getrusage,         165
.equ SYS_umask,             166
.equ SYS_prctl,             167
.equ SYS_getcpu,            168
.equ SYS_gettimeofday,      169
.equ SYS_settimeofday,      170
.equ SYS_adjtimex,          171
.equ SYS_getpid,            172
.equ SYS_getppid,           173
.equ SYS_getuid,            174
.equ SYS_geteuid,           175
.equ SYS_getgid,            176
.equ SYS_getegid,           177
.equ SYS_gettid,            178
.equ SYS_sysinfo,           179
.equ SYS_mq_open,           180
.equ SYS_mq_unlink,         181
.equ SYS_mq_timedsend,      182
.equ SYS_mq_timedreceive,   183
.equ SYS_mq_notify,         184
.equ SYS_mq_getsetattr,     185
.equ SYS_msgget,            186
.equ SYS_msgctl,            187
.equ SYS_msgrcv,            188
.equ SYS_msgsnd,            189
.equ SYS_semget,            190
.equ SYS_semctl,            191
.equ SYS_semtimedop,        192
.equ SYS_semop,             193
.equ SYS_shmget,            194
.equ SYS_shmctl,            195
.equ SYS_shmat,             196
.equ SYS_shmdt,             197
.equ SYS_socket,            198
.equ SYS_socketpair,        199
.equ SYS_bind,              200
.equ SYS_listen,            201
.equ SYS_accept,            202
.equ SYS_connect,           203
.equ SYS_getsockname,       204
.equ SYS_getpeername,       205
.equ SYS_sendto,            206
.equ SYS_recvfrom,          207
.equ SYS_setsockopt,        208
.equ SYS_getsockopt,        209
.equ SYS_shutdown,          210
.equ SYS_sendmsg,           211
.equ SYS_recvmsg,           212
.equ SYS_readahead,         213
.equ SYS_brk,               214
.equ SYS_munmap,            215
.equ SYS_mremap,            216
.equ SYS_add_key,           217
.equ SYS_request_key,       218
.equ SYS_keyctl,            219
.equ SYS_clone,             220
.equ SYS_execve,            221
.equ SYS_mmap,              222
.equ SYS_fadvise64,         223
.equ SYS_swapon,            224
.equ SYS_swapoff,           225
.equ SYS_mprotect,          226
.equ SYS_msync,             227
.equ SYS_mlock,             228
.equ SYS_munlock,           229
.equ SYS_mlockall,          230
.equ SYS_munlockall,        231
.equ SYS_mincore,           232
.equ SYS_madvise,           233
.equ SYS_remap_file_pages,  234
.equ SYS_mbind,             235
.equ SYS_get_mempolicy,     236
.equ SYS_set_mempolicy,     237
.equ SYS_migrate_pages,     238
.equ SYS_move_pages,        239
.equ SYS_rt_tgsigqueueinfo, 240
.equ SYS_perf_event_open,   241
.equ SYS_accept4,           242
.equ SYS_recvmmsg,          243
.equ SYS_wait4,             260
.equ SYS_prlimit64,         261
.equ SYS_fanotify_init,     262
.equ SYS_fanotify_mark,     263
.equ SYS_name_to_handle_at, 264
.equ SYS_open_by_handle_at, 265
.equ SYS_clock_adjtime,     266
.equ SYS_syncfs,            267
.equ SYS_setns,             268
.equ SYS_sendmmsg,          269
.equ SYS_process_vm_readv,  270
.equ SYS_process_vm_writev, 271
.equ SYS_kcmp,              272
.equ SYS_finit_module,      273
.equ SYS_sched_setattr,     274
.equ SYS_sched_getattr,     275
.equ SYS_renameat2,         276
.equ SYS_seccomp,           277
.equ SYS_getrandom,         278
.equ SYS_memfd_create,      279
.equ SYS_bpf,               280
.equ SYS_execveat,          281
.equ SYS_userfaultfd,       282
.equ SYS_membarrier,        283
.equ SYS_mlock2,            284
.equ SYS_copy_file_range,   285
.equ SYS_preadv2,           286
.equ SYS_pwritev2,          287
.equ SYS_pkey_mprotect,     288
.equ SYS_pkey_alloc,        289
.equ SYS_pkey_free,         290
.equ SYS_statx,             291
.equ SYS_io_pgetevents,     292
.equ SYS_rseq,              293
.equ SYS_kexec_file_load,   294
.equ SYS_pidfd_send_signal, 424
.equ SYS_io_uring_setup,    425
.equ SYS_io_uring_enter,    426
.equ SYS_io_uring_register, 427
.equ SYS_open_tree,         428
.equ SYS_move_mount,        429
.equ SYS_fsopen,            430
.equ SYS_fsconfig,          431
.equ SYS_fsmount,           432
.equ SYS_fspick,            433
.equ SYS_pidfd_open,        434
.equ SYS_clone3,            435
.equ SYS_close_range,       436
.equ SYS_openat2,           437
.equ SYS_pidfd_getfd,       438
.equ SYS_faccessat2,        439
.equ SYS_process_madvise,   440
.equ SYS_epoll_pwait2,      441
.equ SYS_mount_setattr,     442
.equ SYS_quotactl_fd,       443
.equ SYS_landlock_create_ruleset, 444
.equ SYS_landlock_add_rule, 445
.equ SYS_landlock_restrict_self, 446
.equ SYS_memfd_secret,      447
.equ SYS_process_mrelease,  448
.equ SYS_futex_waitv,       449
.equ SYS_set_mempolicy_home_node, 450

// -----------------------------------------------------------------------------
// errno values
// Reference: include/uapi/asm-generic/errno-base.h
// -----------------------------------------------------------------------------

.equ EPERM,             1       // Operation not permitted
.equ ENOENT,            2       // No such file or directory
.equ ESRCH,             3       // No such process
.equ EINTR,             4       // Interrupted system call
.equ EIO,               5       // I/O error
.equ ENXIO,             6       // No such device or address
.equ E2BIG,             7       // Argument list too long
.equ ENOEXEC,           8       // Exec format error
.equ EBADF,             9       // Bad file number
.equ ECHILD,            10      // No child processes
.equ EAGAIN,            11      // Try again (also EWOULDBLOCK)
.equ ENOMEM,            12      // Out of memory
.equ EACCES,            13      // Permission denied
.equ EFAULT,            14      // Bad address
.equ ENOTBLK,           15      // Block device required
.equ EBUSY,             16      // Device or resource busy
.equ EEXIST,            17      // File exists
.equ EXDEV,             18      // Cross-device link
.equ ENODEV,            19      // No such device
.equ ENOTDIR,           20      // Not a directory
.equ EISDIR,            21      // Is a directory
.equ EINVAL,            22      // Invalid argument
.equ ENFILE,            23      // File table overflow
.equ EMFILE,            24      // Too many open files
.equ ENOTTY,            25      // Not a typewriter
.equ ETXTBSY,           26      // Text file busy
.equ EFBIG,             27      // File too large
.equ ENOSPC,            28      // No space left on device
.equ ESPIPE,            29      // Illegal seek
.equ EROFS,             30      // Read-only file system
.equ EMLINK,            31      // Too many links
.equ EPIPE,             32      // Broken pipe
.equ EDOM,              33      // Math argument out of domain
.equ ERANGE,            34      // Math result not representable
.equ EDEADLK,           35      // Resource deadlock would occur
.equ ENAMETOOLONG,      36      // File name too long
.equ ENOLCK,            37      // No record locks available
.equ ENOSYS,            38      // Function not implemented
.equ ENOTEMPTY,         39      // Directory not empty
.equ ELOOP,             40      // Too many symbolic links
.equ EWOULDBLOCK,       11      // Same as EAGAIN
.equ ENOMSG,            42      // No message of desired type
.equ EIDRM,             43      // Identifier removed
.equ ENOSTR,            60      // Device not a stream
.equ ENODATA,           61      // No data available
.equ ETIME,             62      // Timer expired
.equ ENOSR,             63      // Out of streams resources
.equ ENONET,            64      // Machine is not on the network
.equ EREMOTE,           66      // Object is remote
.equ ENOLINK,           67      // Link has been severed
.equ EPROTO,            71      // Protocol error
.equ EBADMSG,           74      // Not a data message
.equ EOVERFLOW,         75      // Value too large for data type
.equ EILSEQ,            84      // Illegal byte sequence
.equ EUSERS,            87      // Too many users
.equ ENOTSOCK,          88      // Socket operation on non-socket
.equ EDESTADDRREQ,      89      // Destination address required
.equ EMSGSIZE,          90      // Message too long
.equ EPROTOTYPE,        91      // Protocol wrong type for socket
.equ ENOPROTOOPT,       92      // Protocol not available
.equ EPROTONOSUPPORT,   93      // Protocol not supported
.equ ESOCKTNOSUPPORT,   94      // Socket type not supported
.equ EOPNOTSUPP,        95      // Operation not supported
.equ EPFNOSUPPORT,      96      // Protocol family not supported
.equ EAFNOSUPPORT,      97      // Address family not supported
.equ EADDRINUSE,        98      // Address already in use
.equ EADDRNOTAVAIL,     99      // Cannot assign requested address
.equ ENETDOWN,          100     // Network is down
.equ ENETUNREACH,       101     // Network is unreachable
.equ ENETRESET,         102     // Network connection reset
.equ ECONNABORTED,      103     // Software caused connection abort
.equ ECONNRESET,        104     // Connection reset by peer
.equ ENOBUFS,           105     // No buffer space available
.equ EISCONN,           106     // Socket is already connected
.equ ENOTCONN,          107     // Socket is not connected
.equ ESHUTDOWN,         108     // Cannot send after shutdown
.equ ETOOMANYREFS,      109     // Too many references
.equ ETIMEDOUT,         110     // Connection timed out
.equ ECONNREFUSED,      111     // Connection refused
.equ EHOSTDOWN,         112     // Host is down
.equ EHOSTUNREACH,      113     // No route to host
.equ EALREADY,          114     // Operation already in progress
.equ EINPROGRESS,       115     // Operation now in progress
.equ ESTALE,            116     // Stale file handle
.equ EDQUOT,            122     // Quota exceeded
.equ ECANCELED,         125     // Operation canceled

// -----------------------------------------------------------------------------
// File open flags (fcntl.h)
// -----------------------------------------------------------------------------

.equ O_RDONLY,          0x0000
.equ O_WRONLY,          0x0001
.equ O_RDWR,            0x0002
.equ O_ACCMODE,         0x0003
.equ O_CREAT,           0x0040
.equ O_EXCL,            0x0080
.equ O_NOCTTY,          0x0100
.equ O_TRUNC,           0x0200
.equ O_APPEND,          0x0400
.equ O_NONBLOCK,        0x0800
.equ O_DSYNC,           0x1000
.equ O_SYNC,            0x101000
.equ O_DIRECTORY,       0x10000
.equ O_NOFOLLOW,        0x20000
.equ O_CLOEXEC,         0x80000
.equ O_DIRECT,          0x10000
.equ O_LARGEFILE,       0x20000
.equ O_NOATIME,         0x40000
.equ O_PATH,            0x200000
.equ O_TMPFILE,         0x410000

// AT_* constants for *at() syscalls
.equ AT_FDCWD,          -100    // Use current working directory
.equ AT_SYMLINK_NOFOLLOW, 0x100
.equ AT_REMOVEDIR,      0x200
.equ AT_SYMLINK_FOLLOW, 0x400
.equ AT_EMPTY_PATH,     0x1000

// -----------------------------------------------------------------------------
// mmap protection flags
// -----------------------------------------------------------------------------

.equ PROT_NONE,         0x0
.equ PROT_READ,         0x1
.equ PROT_WRITE,        0x2
.equ PROT_EXEC,         0x4

// -----------------------------------------------------------------------------
// mmap flags
// -----------------------------------------------------------------------------

.equ MAP_SHARED,        0x01
.equ MAP_PRIVATE,       0x02
.equ MAP_FIXED,         0x10
.equ MAP_ANONYMOUS,     0x20
.equ MAP_GROWSDOWN,     0x100
.equ MAP_DENYWRITE,     0x800
.equ MAP_EXECUTABLE,    0x1000
.equ MAP_LOCKED,        0x2000
.equ MAP_NORESERVE,     0x4000
.equ MAP_POPULATE,      0x8000
.equ MAP_NONBLOCK,      0x10000
.equ MAP_STACK,         0x20000
.equ MAP_HUGETLB,       0x40000
.equ MAP_SYNC,          0x80000
.equ MAP_FIXED_NOREPLACE, 0x100000

.equ MAP_FAILED,        -1

// -----------------------------------------------------------------------------
// Socket constants
// -----------------------------------------------------------------------------

// Address families
.equ AF_UNSPEC,         0
.equ AF_UNIX,           1
.equ AF_LOCAL,          1
.equ AF_INET,           2
.equ AF_INET6,          10
.equ AF_PACKET,         17

// Socket types
.equ SOCK_STREAM,       1
.equ SOCK_DGRAM,        2
.equ SOCK_RAW,          3
.equ SOCK_SEQPACKET,    5
.equ SOCK_NONBLOCK,     0x800
.equ SOCK_CLOEXEC,      0x80000

// Socket options level
.equ SOL_SOCKET,        1

// Socket options
.equ SO_DEBUG,          1
.equ SO_REUSEADDR,      2
.equ SO_TYPE,           3
.equ SO_ERROR,          4
.equ SO_DONTROUTE,      5
.equ SO_BROADCAST,      6
.equ SO_SNDBUF,         7
.equ SO_RCVBUF,         8
.equ SO_KEEPALIVE,      9
.equ SO_OOBINLINE,      10
.equ SO_LINGER,         13
.equ SO_REUSEPORT,      15
.equ SO_RCVTIMEO,       20
.equ SO_SNDTIMEO,       21

// IP protocol numbers
.equ IPPROTO_IP,        0
.equ IPPROTO_TCP,       6
.equ IPPROTO_UDP,       17

// TCP options
.equ TCP_NODELAY,       1
.equ TCP_MAXSEG,        2
.equ TCP_KEEPIDLE,      4
.equ TCP_KEEPINTVL,     5
.equ TCP_KEEPCNT,       6

// -----------------------------------------------------------------------------
// epoll constants
// -----------------------------------------------------------------------------

.equ EPOLL_CTL_ADD,     1
.equ EPOLL_CTL_DEL,     2
.equ EPOLL_CTL_MOD,     3

.equ EPOLLIN,           0x001
.equ EPOLLPRI,          0x002
.equ EPOLLOUT,          0x004
.equ EPOLLERR,          0x008
.equ EPOLLHUP,          0x010
.equ EPOLLRDNORM,       0x040
.equ EPOLLRDBAND,       0x080
.equ EPOLLWRNORM,       0x100
.equ EPOLLWRBAND,       0x200
.equ EPOLLMSG,          0x400
.equ EPOLLRDHUP,        0x2000
.equ EPOLLEXCLUSIVE,    0x10000000
.equ EPOLLWAKEUP,       0x20000000
.equ EPOLLONESHOT,      0x40000000
.equ EPOLLET,           0x80000000

// -----------------------------------------------------------------------------
// Signal numbers
// -----------------------------------------------------------------------------

.equ SIGHUP,            1
.equ SIGINT,            2
.equ SIGQUIT,           3
.equ SIGILL,            4
.equ SIGTRAP,           5
.equ SIGABRT,           6
.equ SIGBUS,            7
.equ SIGFPE,            8
.equ SIGKILL,           9
.equ SIGUSR1,           10
.equ SIGSEGV,           11
.equ SIGUSR2,           12
.equ SIGPIPE,           13
.equ SIGALRM,           14
.equ SIGTERM,           15
.equ SIGSTKFLT,         16
.equ SIGCHLD,           17
.equ SIGCONT,           18
.equ SIGSTOP,           19
.equ SIGTSTP,           20
.equ SIGTTIN,           21
.equ SIGTTOU,           22
.equ SIGURG,            23
.equ SIGXCPU,           24
.equ SIGXFSZ,           25
.equ SIGVTALRM,         26
.equ SIGPROF,           27
.equ SIGWINCH,          28
.equ SIGIO,             29
.equ SIGPWR,            30
.equ SIGSYS,            31

// -----------------------------------------------------------------------------
// Signal action flags (for rt_sigaction)
// -----------------------------------------------------------------------------

.equ SA_NOCLDSTOP,      0x00000001
.equ SA_NOCLDWAIT,      0x00000002
.equ SA_SIGINFO,        0x00000004
.equ SA_ONSTACK,        0x08000000
.equ SA_RESTART,        0x10000000
.equ SA_NODEFER,        0x40000000
.equ SA_RESETHAND,      0x80000000

// Signal handler special values
.equ SIG_DFL,           0
.equ SIG_IGN,           1

// Size of kernel sigset_t on aarch64
.equ SIGSET_SIZE,       8

// -----------------------------------------------------------------------------
// Auxiliary vector types (from elf.h)
// Used with getauxval() to query system info at startup
// -----------------------------------------------------------------------------

.equ AT_NULL,           0       // End of vector
.equ AT_IGNORE,         1       // Entry should be ignored
.equ AT_EXECFD,         2       // File descriptor of program
.equ AT_PHDR,           3       // Program headers for program
.equ AT_PHENT,          4       // Size of program header entry
.equ AT_PHNUM,          5       // Number of program headers
.equ AT_PAGESZ,         6       // System page size
.equ AT_BASE,           7       // Base address of interpreter
.equ AT_FLAGS,          8       // Flags
.equ AT_ENTRY,          9       // Entry point of program
.equ AT_NOTELF,         10      // Program is not ELF
.equ AT_UID,            11      // Real uid
.equ AT_EUID,           12      // Effective uid
.equ AT_GID,            13      // Real gid
.equ AT_EGID,           14      // Effective gid
.equ AT_PLATFORM,       15      // String identifying platform
.equ AT_HWCAP,          16      // Machine-dependent CPU capability hints
.equ AT_CLKTCK,         17      // Frequency of times()
.equ AT_SECURE,         23      // Boolean, was exec setuid-like?
.equ AT_BASE_PLATFORM,  24      // String identifying real platform
.equ AT_RANDOM,         25      // Address of 16 random bytes
.equ AT_HWCAP2,         26      // Extension of AT_HWCAP
.equ AT_EXECFN,         31      // Filename of executable

// aarch64 HWCAP bits (AT_HWCAP)
.equ HWCAP_FP,          (1 << 0)
.equ HWCAP_ASIMD,       (1 << 1)
.equ HWCAP_EVTSTRM,     (1 << 2)
.equ HWCAP_AES,         (1 << 3)
.equ HWCAP_PMULL,       (1 << 4)
.equ HWCAP_SHA1,        (1 << 5)
.equ HWCAP_SHA2,        (1 << 6)
.equ HWCAP_CRC32,       (1 << 7)
.equ HWCAP_ATOMICS,     (1 << 8)
.equ HWCAP_FPHP,        (1 << 9)
.equ HWCAP_ASIMDHP,     (1 << 10)
.equ HWCAP_CPUID,       (1 << 11)
.equ HWCAP_ASIMDRDM,    (1 << 12)
.equ HWCAP_JSCVT,       (1 << 13)
.equ HWCAP_FCMA,        (1 << 14)
.equ HWCAP_LRCPC,       (1 << 15)
.equ HWCAP_DCPOP,       (1 << 16)
.equ HWCAP_SHA3,        (1 << 17)
.equ HWCAP_SM3,         (1 << 18)
.equ HWCAP_SM4,         (1 << 19)
.equ HWCAP_ASIMDDP,     (1 << 20)
.equ HWCAP_SHA512,      (1 << 21)
.equ HWCAP_SVE,         (1 << 22)
.equ HWCAP_ASIMDFHM,    (1 << 23)
.equ HWCAP_DIT,         (1 << 24)
.equ HWCAP_USCAT,       (1 << 25)
.equ HWCAP_ILRCPC,      (1 << 26)
.equ HWCAP_FLAGM,       (1 << 27)
.equ HWCAP_SSBS,        (1 << 28)
.equ HWCAP_SB,          (1 << 29)
.equ HWCAP_PACA,        (1 << 30)
.equ HWCAP_PACG,        (1 << 31)

// aarch64 HWCAP2 bits (AT_HWCAP2)
.equ HWCAP2_DCPODP,     (1 << 0)
.equ HWCAP2_SVE2,       (1 << 1)
.equ HWCAP2_SVEAES,     (1 << 2)
.equ HWCAP2_SVEPMULL,   (1 << 3)
.equ HWCAP2_SVEBITPERM, (1 << 4)
.equ HWCAP2_SVESHA3,    (1 << 5)
.equ HWCAP2_SVESM4,     (1 << 6)
.equ HWCAP2_FLAGM2,     (1 << 7)
.equ HWCAP2_FRINT,      (1 << 8)
.equ HWCAP2_SVEI8MM,    (1 << 9)
.equ HWCAP2_SVEF32MM,   (1 << 10)
.equ HWCAP2_SVEF64MM,   (1 << 11)
.equ HWCAP2_SVEBF16,    (1 << 12)
.equ HWCAP2_I8MM,       (1 << 13)
.equ HWCAP2_BF16,       (1 << 14)
.equ HWCAP2_DGH,        (1 << 15)
.equ HWCAP2_RNG,        (1 << 16)
.equ HWCAP2_BTI,        (1 << 17)
.equ HWCAP2_MTE,        (1 << 18)
.equ HWCAP2_ECV,        (1 << 19)
.equ HWCAP2_AFP,        (1 << 20)
.equ HWCAP2_RPRES,      (1 << 21)
.equ HWCAP2_MTE3,       (1 << 22)
.equ HWCAP2_SME,        (1 << 23)
.equ HWCAP2_SME_I16I64, (1 << 24)
.equ HWCAP2_SME_F64F64, (1 << 25)
.equ HWCAP2_SME_I8I32,  (1 << 26)
.equ HWCAP2_SME_F16F32, (1 << 27)
.equ HWCAP2_SME_B16F32, (1 << 28)
.equ HWCAP2_SME_F32F32, (1 << 29)
.equ HWCAP2_SME_FA64,   (1 << 30)

// -----------------------------------------------------------------------------
// Standard file descriptors
// -----------------------------------------------------------------------------

.equ STDIN_FILENO,      0
.equ STDOUT_FILENO,     1
.equ STDERR_FILENO,     2

// -----------------------------------------------------------------------------
// utsname structure offsets (for uname syscall)
// Each field is 65 bytes (including null terminator)
// -----------------------------------------------------------------------------

.equ UTSNAME_SYSNAME,   0       // OS name (e.g., "Linux")
.equ UTSNAME_NODENAME,  65      // Network node hostname
.equ UTSNAME_RELEASE,   130     // OS release (e.g., "6.1.21")
.equ UTSNAME_VERSION,   195     // OS version
.equ UTSNAME_MACHINE,   260     // Hardware identifier
.equ UTSNAME_DOMAINNAME, 325    // NIS domain name
.equ UTSNAME_SIZE,      390     // Total size of utsname struct

// -----------------------------------------------------------------------------
// Seek constants (lseek)
// -----------------------------------------------------------------------------

.equ SEEK_SET,          0       // Seek from beginning
.equ SEEK_CUR,          1       // Seek from current position
.equ SEEK_END,          2       // Seek from end

// -----------------------------------------------------------------------------
// Clock IDs (for clock_gettime etc.)
// -----------------------------------------------------------------------------

.equ CLOCK_REALTIME,            0
.equ CLOCK_MONOTONIC,           1
.equ CLOCK_PROCESS_CPUTIME_ID,  2
.equ CLOCK_THREAD_CPUTIME_ID,   3
.equ CLOCK_MONOTONIC_RAW,       4
.equ CLOCK_REALTIME_COARSE,     5
.equ CLOCK_MONOTONIC_COARSE,    6
.equ CLOCK_BOOTTIME,            7

// =============================================================================
// End of syscall_nums.inc
// =============================================================================
