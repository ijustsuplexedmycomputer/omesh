// =============================================================================
// Omesh - detect.s
// Hardware and platform detection
// =============================================================================
//
// Main entry point: hal_init()
// Populates the global g_features structure with detected hardware info.
//
// Detection strategy:
//   1. Try reading aarch64 system registers (fast, accurate)
//   2. Fall back to parsing /proc and /sys files if registers fail/unavailable
//
// All detection functions are idempotent and can be called multiple times.
//
// =============================================================================

.include "include/syscall_nums.inc"

// Import from features.s
.extern g_features
.extern g_hal_initialized
.extern path_cpuinfo
.extern path_meminfo
.extern path_dt_model
.extern path_dt_model_alt
.extern path_cpu_online
.extern str_cpu_implementer
.extern str_cpu_part
.extern str_cpu_variant
.extern str_cpu_revision
.extern str_features
.extern str_memtotal
.extern str_memavailable

// Feature strings
.extern str_feat_neon
.extern str_feat_crc32
.extern str_feat_aes
.extern str_feat_sha1
.extern str_feat_sha2
.extern str_feat_sha512
.extern str_feat_sha3
.extern str_feat_pmull
.extern str_feat_atomics
.extern str_feat_fphp
.extern str_feat_sve
.extern str_feat_sve2
.extern str_feat_bf16
.extern str_feat_i8mm
.extern str_feat_rng
.extern str_feat_bti
.extern str_feat_mte
.extern str_feat_paca
.extern str_feat_sm3
.extern str_feat_sm4
.extern str_feat_dotprod

// Board strings
.extern str_board_rpi3
.extern str_board_rpi4
.extern str_board_rpi5
.extern str_board_rpizero2
.extern str_board_rpi400
.extern str_board_jetson_nano
.extern str_board_jetson_xavier
.extern str_board_jetson_orin
.extern str_board_qemu
.extern str_board_graviton
.extern str_board_ampere
.extern str_board_apple

// Feature offsets
.equ FEAT_OFF_IMPLEMENTER,      0
.equ FEAT_OFF_VARIANT,          8
.equ FEAT_OFF_PART,             16
.equ FEAT_OFF_REVISION,         24
.equ FEAT_OFF_CACHE_LINE,       32
.equ FEAT_OFF_PAGE_SIZE,        40
.equ FEAT_OFF_CORE_COUNT,       48
.equ FEAT_OFF_TOTAL_MEM,        56
.equ FEAT_OFF_AVAIL_MEM,        64
.equ FEAT_OFF_FLAGS,            72
.equ FEAT_OFF_BOARD_MODEL,      80
.equ FEAT_OFF_KERNEL_VER,       144

// Feature bits
.equ FEAT_BIT_NEON,             0
.equ FEAT_BIT_CRC32,            1
.equ FEAT_BIT_LSE,              2
.equ FEAT_BIT_AES,              3
.equ FEAT_BIT_SHA1,             4
.equ FEAT_BIT_SHA256,           5
.equ FEAT_BIT_SHA512,           6
.equ FEAT_BIT_SHA3,             7
.equ FEAT_BIT_PMULL,            8
.equ FEAT_BIT_FP16,             9
.equ FEAT_BIT_LSE2,             10
.equ FEAT_BIT_SVE,              11
.equ FEAT_BIT_SVE2,             12
.equ FEAT_BIT_RNG,              13
.equ FEAT_BIT_BTI,              14
.equ FEAT_BIT_MTE,              15
.equ FEAT_BIT_PAUTH,            16
.equ FEAT_BIT_SM3,              17
.equ FEAT_BIT_SM4,              18
.equ FEAT_BIT_DOTPROD,          19
.equ FEAT_BIT_RCPC,             20
.equ FEAT_BIT_FLAGM,            21
.equ FEAT_BIT_BF16,             22
.equ FEAT_BIT_I8MM,             23

// Board IDs
.equ BOARD_UNKNOWN,             0
.equ BOARD_RPI_3B,              1
.equ BOARD_RPI_4B,              3
.equ BOARD_RPI_5,               5
.equ BOARD_RPI_ZERO2,           6
.equ BOARD_RPI_400,             4
.equ BOARD_JETSON_NANO,         10
.equ BOARD_JETSON_XAVIER,       12
.equ BOARD_JETSON_ORIN,         13
.equ BOARD_QEMU,                99

// Stack buffer size for file reads
.equ FILE_BUF_SIZE,             4096

.text
.balign 4

// =============================================================================
// hal_init - Initialize HAL and detect hardware
//
// Output:
//   x0 = 0 on success, negative errno on error
// Clobbers: all caller-saved registers
//
// This is the main entry point. Call once at program startup.
// =============================================================================
.global hal_init
.type hal_init, %function
hal_init:
    // Check if already initialized
    adrp    x0, g_hal_initialized
    add     x0, x0, :lo12:g_hal_initialized
    ldr     x1, [x0]
    cbnz    x1, .Lhal_already_init

    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Zero the feature structure
    adrp    x0, g_features
    add     x0, x0, :lo12:g_features
    mov     x1, #152            // FEAT_STRUCT_SIZE
    bl      memzero

    // Run all detection functions
    bl      detect_page_size
    bl      detect_cache_info
    bl      detect_cpu_info
    bl      detect_cpu_features
    bl      detect_memory
    bl      detect_cores
    bl      detect_board
    bl      detect_kernel

    // Mark as initialized
    adrp    x0, g_hal_initialized
    add     x0, x0, :lo12:g_hal_initialized
    mov     x1, #1
    str     x1, [x0]

    mov     x0, #0
    ldp     x29, x30, [sp], #16
    ret

.Lhal_already_init:
    mov     x0, #0
    ret
.size hal_init, . - hal_init

// =============================================================================
// detect_page_size - Get system page size
//
// Uses getauxval(AT_PAGESZ) equivalent by reading from /proc/self/auxv
// Falls back to 4096 if detection fails.
// =============================================================================
.type detect_page_size, %function
detect_page_size:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Try reading /proc/self/auxv
    adrp    x1, path_auxv
    add     x1, x1, :lo12:path_auxv
    mov     x0, #AT_FDCWD
    mov     x2, #O_RDONLY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lpage_default

    mov     x19, x0             // Save fd

    // Read auxv entries (16 bytes each: type, value)
    sub     sp, sp, #256
    mov     x1, sp
    mov     x2, #256
    mov     x8, #SYS_read
    svc     #0
    cmp     x0, #0
    b.le    .Lpage_close

    mov     x20, x0             // Bytes read
    mov     x1, sp

.Lpage_scan:
    cmp     x20, #16
    b.lt    .Lpage_close
    ldr     x2, [x1]            // Type
    ldr     x3, [x1, #8]        // Value
    cbz     x2, .Lpage_close    // AT_NULL = end
    cmp     x2, #AT_PAGESZ
    b.ne    .Lpage_next
    // Found page size
    adrp    x4, g_features
    add     x4, x4, :lo12:g_features
    str     x3, [x4, #FEAT_OFF_PAGE_SIZE]
    b       .Lpage_close

.Lpage_next:
    add     x1, x1, #16
    sub     x20, x20, #16
    b       .Lpage_scan

.Lpage_close:
    add     sp, sp, #256
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0

    // Check if we got a value
    adrp    x0, g_features
    add     x0, x0, :lo12:g_features
    ldr     x1, [x0, #FEAT_OFF_PAGE_SIZE]
    cbnz    x1, .Lpage_done

.Lpage_default:
    // Default to 4096
    adrp    x0, g_features
    add     x0, x0, :lo12:g_features
    mov     x1, #4096
    str     x1, [x0, #FEAT_OFF_PAGE_SIZE]

.Lpage_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size detect_page_size, . - detect_page_size

// =============================================================================
// detect_cache_info - Get cache line size from CTR_EL0
//
// CTR_EL0 is readable from userspace on aarch64.
// DminLine (bits 19:16) gives log2 of minimum D-cache line size in words.
// =============================================================================
.type detect_cache_info, %function
detect_cache_info:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Read Cache Type Register (always accessible from EL0)
    mrs     x0, ctr_el0

    // Extract DminLine (bits 19:16)
    // Line size = 4 << DminLine (in bytes)
    ubfx    x1, x0, #16, #4     // Extract 4 bits at position 16
    mov     x2, #4
    lsl     x2, x2, x1          // 4 << DminLine

    // Store cache line size
    adrp    x0, g_features
    add     x0, x0, :lo12:g_features
    str     x2, [x0, #FEAT_OFF_CACHE_LINE]

    ldp     x29, x30, [sp], #16
    ret
.size detect_cache_info, . - detect_cache_info

// =============================================================================
// detect_cpu_info - Get CPU implementer, part, variant, revision
//
// Tries to read MIDR_EL1 but this may be trapped.
// Falls back to parsing /proc/cpuinfo.
// =============================================================================
.type detect_cpu_info, %function
detect_cpu_info:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Parse /proc/cpuinfo for CPU info
    // (MIDR_EL1 is often trapped in userspace)
    bl      parse_cpuinfo_cpu

    ldp     x29, x30, [sp], #16
    ret
.size detect_cpu_info, . - detect_cpu_info

// =============================================================================
// detect_cpu_features - Detect CPU feature flags
//
// Uses HWCAP from /proc/self/auxv or parses /proc/cpuinfo Features line.
// =============================================================================
.type detect_cpu_features, %function
detect_cpu_features:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Try HWCAP from auxv first
    bl      read_hwcap

    // Also parse /proc/cpuinfo for features not in HWCAP
    bl      parse_cpuinfo_features

    ldp     x29, x30, [sp], #16
    ret
.size detect_cpu_features, . - detect_cpu_features

// =============================================================================
// read_hwcap - Read HWCAP/HWCAP2 from /proc/self/auxv
// =============================================================================
.type read_hwcap, %function
read_hwcap:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]

    mov     x21, #0             // HWCAP
    mov     x22, #0             // HWCAP2

    // Open /proc/self/auxv
    adrp    x1, path_auxv
    add     x1, x1, :lo12:path_auxv
    mov     x0, #AT_FDCWD
    mov     x2, #O_RDONLY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lhwcap_done

    mov     x19, x0             // Save fd

    // Read auxv
    sub     sp, sp, #512
    mov     x1, sp
    mov     x2, #512
    mov     x8, #SYS_read
    svc     #0
    cmp     x0, #0
    b.le    .Lhwcap_close

    mov     x20, x0             // Bytes read
    mov     x1, sp

.Lhwcap_scan:
    cmp     x20, #16
    b.lt    .Lhwcap_close
    ldr     x2, [x1]            // Type
    ldr     x3, [x1, #8]        // Value
    cbz     x2, .Lhwcap_close   // AT_NULL

    cmp     x2, #AT_HWCAP
    b.ne    .Lhwcap_check2
    mov     x21, x3
    b       .Lhwcap_next

.Lhwcap_check2:
    cmp     x2, #AT_HWCAP2
    b.ne    .Lhwcap_next
    mov     x22, x3

.Lhwcap_next:
    add     x1, x1, #16
    sub     x20, x20, #16
    b       .Lhwcap_scan

.Lhwcap_close:
    add     sp, sp, #512
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0

    // Convert HWCAP bits to our feature flags
    adrp    x0, g_features
    add     x0, x0, :lo12:g_features
    ldr     x1, [x0, #FEAT_OFF_FLAGS]

    // HWCAP_ASIMD (bit 1) -> FEAT_BIT_NEON (bit 0)
    tst     x21, #HWCAP_ASIMD
    b.eq    .Lhwcap_crc
    orr     x1, x1, #(1 << FEAT_BIT_NEON)

.Lhwcap_crc:
    tst     x21, #HWCAP_CRC32
    b.eq    .Lhwcap_aes
    orr     x1, x1, #(1 << FEAT_BIT_CRC32)

.Lhwcap_aes:
    tst     x21, #HWCAP_AES
    b.eq    .Lhwcap_sha1
    orr     x1, x1, #(1 << FEAT_BIT_AES)

.Lhwcap_sha1:
    tst     x21, #HWCAP_SHA1
    b.eq    .Lhwcap_sha2
    orr     x1, x1, #(1 << FEAT_BIT_SHA1)

.Lhwcap_sha2:
    tst     x21, #HWCAP_SHA2
    b.eq    .Lhwcap_pmull
    orr     x1, x1, #(1 << FEAT_BIT_SHA256)

.Lhwcap_pmull:
    tst     x21, #HWCAP_PMULL
    b.eq    .Lhwcap_atomics
    orr     x1, x1, #(1 << FEAT_BIT_PMULL)

.Lhwcap_atomics:
    tst     x21, #HWCAP_ATOMICS
    b.eq    .Lhwcap_fphp
    orr     x1, x1, #(1 << FEAT_BIT_LSE)

.Lhwcap_fphp:
    tst     x21, #HWCAP_FPHP
    b.eq    .Lhwcap_sha512
    orr     x1, x1, #(1 << FEAT_BIT_FP16)

.Lhwcap_sha512:
    tst     x21, #HWCAP_SHA512
    b.eq    .Lhwcap_sha3
    orr     x1, x1, #(1 << FEAT_BIT_SHA512)

.Lhwcap_sha3:
    tst     x21, #HWCAP_SHA3
    b.eq    .Lhwcap_sve
    orr     x1, x1, #(1 << FEAT_BIT_SHA3)

.Lhwcap_sve:
    tst     x21, #HWCAP_SVE
    b.eq    .Lhwcap_dotprod
    orr     x1, x1, #(1 << FEAT_BIT_SVE)

.Lhwcap_dotprod:
    tst     x21, #HWCAP_ASIMDDP
    b.eq    .Lhwcap_paca
    orr     x1, x1, #(1 << FEAT_BIT_DOTPROD)

.Lhwcap_paca:
    tst     x21, #HWCAP_PACA
    b.eq    .Lhwcap2_sve2
    orr     x1, x1, #(1 << FEAT_BIT_PAUTH)

    // HWCAP2 checks
.Lhwcap2_sve2:
    tst     x22, #HWCAP2_SVE2
    b.eq    .Lhwcap2_rng
    orr     x1, x1, #(1 << FEAT_BIT_SVE2)

.Lhwcap2_rng:
    tst     x22, #HWCAP2_RNG
    b.eq    .Lhwcap2_bti
    orr     x1, x1, #(1 << FEAT_BIT_RNG)

.Lhwcap2_bti:
    tst     x22, #HWCAP2_BTI
    b.eq    .Lhwcap2_mte
    orr     x1, x1, #(1 << FEAT_BIT_BTI)

.Lhwcap2_mte:
    tst     x22, #HWCAP2_MTE
    b.eq    .Lhwcap2_bf16
    orr     x1, x1, #(1 << FEAT_BIT_MTE)

.Lhwcap2_bf16:
    tst     x22, #HWCAP2_BF16
    b.eq    .Lhwcap2_i8mm
    orr     x1, x1, #(1 << FEAT_BIT_BF16)

.Lhwcap2_i8mm:
    tst     x22, #HWCAP2_I8MM
    b.eq    .Lhwcap_store
    orr     x1, x1, #(1 << FEAT_BIT_I8MM)

.Lhwcap_store:
    str     x1, [x0, #FEAT_OFF_FLAGS]

.Lhwcap_done:
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret
.size read_hwcap, . - read_hwcap

// =============================================================================
// detect_memory - Get total and available memory from /proc/meminfo
// =============================================================================
.type detect_memory, %function
detect_memory:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Open /proc/meminfo
    adrp    x1, path_meminfo
    add     x1, x1, :lo12:path_meminfo
    mov     x0, #AT_FDCWD
    mov     x2, #O_RDONLY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lmem_done

    mov     x19, x0             // Save fd

    // Read file content
    sub     sp, sp, #FILE_BUF_SIZE
    mov     x1, sp
    mov     x2, #FILE_BUF_SIZE - 1
    mov     x8, #SYS_read
    svc     #0
    cmp     x0, #0
    b.le    .Lmem_close

    // Null-terminate
    add     x1, sp, x0
    strb    wzr, [x1]

    // Parse MemTotal
    mov     x0, sp
    adrp    x1, str_memtotal
    add     x1, x1, :lo12:str_memtotal
    bl      find_line_value
    cmp     x0, #0
    b.le    .Lmem_avail

    // MemTotal is in kB, convert to bytes
    lsl     x0, x0, #10
    adrp    x1, g_features
    add     x1, x1, :lo12:g_features
    str     x0, [x1, #FEAT_OFF_TOTAL_MEM]

.Lmem_avail:
    // Parse MemAvailable
    mov     x0, sp
    adrp    x1, str_memavailable
    add     x1, x1, :lo12:str_memavailable
    bl      find_line_value
    cmp     x0, #0
    b.le    .Lmem_close

    // MemAvailable is in kB, convert to bytes
    lsl     x0, x0, #10
    adrp    x1, g_features
    add     x1, x1, :lo12:g_features
    str     x0, [x1, #FEAT_OFF_AVAIL_MEM]

.Lmem_close:
    add     sp, sp, #FILE_BUF_SIZE
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0

.Lmem_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size detect_memory, . - detect_memory

// =============================================================================
// detect_cores - Count CPU cores
// =============================================================================
.type detect_cores, %function
detect_cores:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Read /sys/devices/system/cpu/online
    // Format: "0-3" or "0,2-3" etc.
    adrp    x1, path_cpu_online
    add     x1, x1, :lo12:path_cpu_online
    mov     x0, #AT_FDCWD
    mov     x2, #O_RDONLY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lcores_default

    mov     x19, x0             // Save fd

    sub     sp, sp, #64
    mov     x1, sp
    mov     x2, #63
    mov     x8, #SYS_read
    svc     #0
    cmp     x0, #0
    b.le    .Lcores_close_default

    // Null-terminate
    add     x1, sp, x0
    strb    wzr, [x1]

    // Parse the range string to count cores
    mov     x0, sp
    bl      count_cpu_range
    mov     x20, x0

    add     sp, sp, #64
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0

    // Store core count
    adrp    x0, g_features
    add     x0, x0, :lo12:g_features
    str     x20, [x0, #FEAT_OFF_CORE_COUNT]
    b       .Lcores_done

.Lcores_close_default:
    add     sp, sp, #64
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0

.Lcores_default:
    // Default to 1 core
    adrp    x0, g_features
    add     x0, x0, :lo12:g_features
    mov     x1, #1
    str     x1, [x0, #FEAT_OFF_CORE_COUNT]

.Lcores_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size detect_cores, . - detect_cores

// =============================================================================
// detect_board - Identify board from device tree model
// =============================================================================
.type detect_board, %function
detect_board:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Try /proc/device-tree/model first
    adrp    x1, path_dt_model
    add     x1, x1, :lo12:path_dt_model
    mov     x0, #AT_FDCWD
    mov     x2, #O_RDONLY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.ge    .Lboard_read

    // Try alternate path
    adrp    x1, path_dt_model_alt
    add     x1, x1, :lo12:path_dt_model_alt
    mov     x0, #AT_FDCWD
    mov     x2, #O_RDONLY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lboard_unknown

.Lboard_read:
    mov     x19, x0             // Save fd

    // Read into board_model field directly
    adrp    x1, g_features
    add     x1, x1, :lo12:g_features
    add     x1, x1, #FEAT_OFF_BOARD_MODEL
    mov     x2, #63             // Leave room for null
    mov     x8, #SYS_read
    svc     #0

    // Null-terminate
    adrp    x1, g_features
    add     x1, x1, :lo12:g_features
    add     x1, x1, #FEAT_OFF_BOARD_MODEL
    cmp     x0, #0
    b.le    .Lboard_close
    add     x2, x1, x0
    strb    wzr, [x2]

.Lboard_close:
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0
    b       .Lboard_done

.Lboard_unknown:
    // Set "Unknown" as board model
    adrp    x0, g_features
    add     x0, x0, :lo12:g_features
    add     x0, x0, #FEAT_OFF_BOARD_MODEL
    adrp    x1, str_unknown
    add     x1, x1, :lo12:str_unknown
    bl      strcpy_simple

.Lboard_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size detect_board, . - detect_board

// =============================================================================
// detect_kernel - Get kernel version using uname syscall
// =============================================================================
.type detect_kernel, %function
detect_kernel:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Allocate space for utsname struct (390 bytes)
    sub     sp, sp, #400

    mov     x0, sp
    mov     x8, #SYS_uname
    svc     #0
    cmp     x0, #0
    b.lt    .Lkernel_done

    // Parse release string (at offset 130)
    // Format: "6.1.21-v8+" or similar
    add     x0, sp, #130        // UTSNAME_RELEASE
    bl      parse_kernel_version

    // Store packed version (major<<16 | minor<<8 | patch)
    adrp    x1, g_features
    add     x1, x1, :lo12:g_features
    str     x0, [x1, #FEAT_OFF_KERNEL_VER]

.Lkernel_done:
    add     sp, sp, #400
    ldp     x29, x30, [sp], #16
    ret
.size detect_kernel, . - detect_kernel

// =============================================================================
// Helper Functions
// =============================================================================

// -----------------------------------------------------------------------------
// parse_cpuinfo_cpu - Parse CPU info from /proc/cpuinfo
// -----------------------------------------------------------------------------
.type parse_cpuinfo_cpu, %function
parse_cpuinfo_cpu:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    // Open /proc/cpuinfo
    adrp    x1, path_cpuinfo
    add     x1, x1, :lo12:path_cpuinfo
    mov     x0, #AT_FDCWD
    mov     x2, #O_RDONLY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lcpu_info_done

    mov     x19, x0             // Save fd

    // Read file
    sub     sp, sp, #FILE_BUF_SIZE
    mov     x1, sp
    mov     x2, #FILE_BUF_SIZE - 1
    mov     x8, #SYS_read
    svc     #0
    cmp     x0, #0
    b.le    .Lcpu_info_close

    // Null-terminate
    add     x1, sp, x0
    strb    wzr, [x1]

    // Parse "CPU implementer" line (hex value)
    mov     x0, sp
    adrp    x1, str_cpu_implementer
    add     x1, x1, :lo12:str_cpu_implementer
    bl      find_line_hex
    adrp    x1, g_features
    add     x1, x1, :lo12:g_features
    str     x0, [x1, #FEAT_OFF_IMPLEMENTER]

    // Parse "CPU part" line (hex value)
    mov     x0, sp
    adrp    x1, str_cpu_part
    add     x1, x1, :lo12:str_cpu_part
    bl      find_line_hex
    adrp    x1, g_features
    add     x1, x1, :lo12:g_features
    str     x0, [x1, #FEAT_OFF_PART]

    // Parse "CPU variant" line (hex value)
    mov     x0, sp
    adrp    x1, str_cpu_variant
    add     x1, x1, :lo12:str_cpu_variant
    bl      find_line_hex
    adrp    x1, g_features
    add     x1, x1, :lo12:g_features
    str     x0, [x1, #FEAT_OFF_VARIANT]

    // Parse "CPU revision" line (decimal value)
    mov     x0, sp
    adrp    x1, str_cpu_revision
    add     x1, x1, :lo12:str_cpu_revision
    bl      find_line_value
    adrp    x1, g_features
    add     x1, x1, :lo12:g_features
    str     x0, [x1, #FEAT_OFF_REVISION]

.Lcpu_info_close:
    add     sp, sp, #FILE_BUF_SIZE
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0

.Lcpu_info_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size parse_cpuinfo_cpu, . - parse_cpuinfo_cpu

// -----------------------------------------------------------------------------
// parse_cpuinfo_features - Parse Features line from /proc/cpuinfo
// This is a backup for features not in HWCAP
// -----------------------------------------------------------------------------
.type parse_cpuinfo_features, %function
parse_cpuinfo_features:
    // For now, rely on HWCAP which is more reliable
    // This function can be expanded later if needed
    ret
.size parse_cpuinfo_features, . - parse_cpuinfo_features

// -----------------------------------------------------------------------------
// find_line_value - Find "key: value" and parse decimal value
//
// Input:
//   x0 = buffer pointer
//   x1 = key string to find
// Output:
//   x0 = parsed value, or 0 if not found
// -----------------------------------------------------------------------------
.type find_line_value, %function
find_line_value:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // Buffer
    mov     x20, x1             // Key

    // Find key in buffer
    bl      strstr_simple
    cbz     x0, .Lfind_val_notfound

    // Skip past the key and find ':'
.Lfind_colon:
    ldrb    w1, [x0], #1
    cbz     w1, .Lfind_val_notfound
    cmp     w1, #':'
    b.ne    .Lfind_colon

    // Skip whitespace
.Lfind_val_skip:
    ldrb    w1, [x0]
    cmp     w1, #' '
    b.eq    .Lfind_val_skipnext
    cmp     w1, #'\t'
    b.ne    .Lfind_val_parse
.Lfind_val_skipnext:
    add     x0, x0, #1
    b       .Lfind_val_skip

.Lfind_val_parse:
    bl      parse_decimal
    b       .Lfind_val_done

.Lfind_val_notfound:
    mov     x0, #0

.Lfind_val_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size find_line_value, . - find_line_value

// -----------------------------------------------------------------------------
// find_line_hex - Find "key: 0xvalue" and parse hex value
//
// Input:
//   x0 = buffer pointer
//   x1 = key string to find
// Output:
//   x0 = parsed value, or 0 if not found
// -----------------------------------------------------------------------------
.type find_line_hex, %function
find_line_hex:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // Buffer
    mov     x20, x1             // Key

    // Find key in buffer
    bl      strstr_simple
    cbz     x0, .Lfind_hex_notfound

    // Skip past the key and find ':'
.Lfind_hex_colon:
    ldrb    w1, [x0], #1
    cbz     w1, .Lfind_hex_notfound
    cmp     w1, #':'
    b.ne    .Lfind_hex_colon

    // Skip whitespace
.Lfind_hex_skip:
    ldrb    w1, [x0]
    cmp     w1, #' '
    b.eq    .Lfind_hex_skipnext
    cmp     w1, #'\t'
    b.ne    .Lfind_hex_parse
.Lfind_hex_skipnext:
    add     x0, x0, #1
    b       .Lfind_hex_skip

.Lfind_hex_parse:
    bl      parse_hex
    b       .Lfind_hex_done

.Lfind_hex_notfound:
    mov     x0, #0

.Lfind_hex_done:
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size find_line_hex, . - find_line_hex

// -----------------------------------------------------------------------------
// parse_decimal - Parse decimal number from string
//
// Input:
//   x0 = string pointer
// Output:
//   x0 = parsed value
// -----------------------------------------------------------------------------
.type parse_decimal, %function
parse_decimal:
    mov     x1, #0              // Result
    mov     x2, #10             // Multiplier

.Lparse_dec_loop:
    ldrb    w3, [x0], #1
    sub     w4, w3, #'0'
    cmp     w4, #9
    b.hi    .Lparse_dec_done
    madd    x1, x1, x2, x4
    b       .Lparse_dec_loop

.Lparse_dec_done:
    mov     x0, x1
    ret
.size parse_decimal, . - parse_decimal

// -----------------------------------------------------------------------------
// parse_hex - Parse hex number from string (with optional 0x prefix)
//
// Input:
//   x0 = string pointer
// Output:
//   x0 = parsed value
// -----------------------------------------------------------------------------
.type parse_hex, %function
parse_hex:
    mov     x1, #0              // Result

    // Check for 0x prefix
    ldrb    w2, [x0]
    cmp     w2, #'0'
    b.ne    .Lparse_hex_loop
    ldrb    w2, [x0, #1]
    cmp     w2, #'x'
    b.eq    .Lparse_hex_skip
    cmp     w2, #'X'
    b.ne    .Lparse_hex_loop

.Lparse_hex_skip:
    add     x0, x0, #2

.Lparse_hex_loop:
    ldrb    w2, [x0], #1

    // Check 0-9
    sub     w3, w2, #'0'
    cmp     w3, #9
    b.hi    .Lparse_hex_alpha
    lsl     x1, x1, #4
    add     x1, x1, x3
    b       .Lparse_hex_loop

.Lparse_hex_alpha:
    // Check a-f
    sub     w3, w2, #'a'
    cmp     w3, #5
    b.hi    .Lparse_hex_upper
    lsl     x1, x1, #4
    add     x1, x1, x3
    add     x1, x1, #10
    b       .Lparse_hex_loop

.Lparse_hex_upper:
    // Check A-F
    sub     w3, w2, #'A'
    cmp     w3, #5
    b.hi    .Lparse_hex_done
    lsl     x1, x1, #4
    add     x1, x1, x3
    add     x1, x1, #10
    b       .Lparse_hex_loop

.Lparse_hex_done:
    mov     x0, x1
    ret
.size parse_hex, . - parse_hex

// -----------------------------------------------------------------------------
// parse_kernel_version - Parse "M.m.p" version string
//
// Input:
//   x0 = version string pointer
// Output:
//   x0 = packed version (major<<16 | minor<<8 | patch)
// -----------------------------------------------------------------------------
.type parse_kernel_version, %function
parse_kernel_version:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // Save string ptr

    // Parse major
    bl      parse_decimal
    mov     x20, x0
    lsl     x20, x20, #16       // major << 16

    // Find '.'
    mov     x0, x19
.Lkver_dot1:
    ldrb    w1, [x0], #1
    cbz     w1, .Lkver_done
    cmp     w1, #'.'
    b.ne    .Lkver_dot1

    // Parse minor
    bl      parse_decimal
    lsl     x0, x0, #8          // minor << 8
    orr     x20, x20, x0

    // Find second '.'
    mov     x0, x19
    mov     x1, #0              // dot count
.Lkver_dot2:
    ldrb    w2, [x0], #1
    cbz     w2, .Lkver_done
    cmp     w2, #'.'
    b.ne    .Lkver_dot2
    add     x1, x1, #1
    cmp     x1, #2
    b.lt    .Lkver_dot2

    // Parse patch
    bl      parse_decimal
    orr     x20, x20, x0

.Lkver_done:
    mov     x0, x20
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size parse_kernel_version, . - parse_kernel_version

// -----------------------------------------------------------------------------
// count_cpu_range - Count CPUs from range string like "0-3" or "0,2-3"
//
// Input:
//   x0 = range string
// Output:
//   x0 = total CPU count
// -----------------------------------------------------------------------------
.type count_cpu_range, %function
count_cpu_range:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]

    mov     x19, x0             // String ptr
    mov     x20, #0             // Total count

.Lcpu_range_loop:
    // Parse first number
    mov     x0, x19
    bl      parse_decimal
    mov     x1, x0              // Start

    // Find next char
.Lcpu_range_find:
    ldrb    w2, [x19], #1
    cmp     w2, #'-'
    b.eq    .Lcpu_range_dash
    cmp     w2, #','
    b.eq    .Lcpu_range_single
    cbz     w2, .Lcpu_range_single
    cmp     w2, #'\n'
    b.eq    .Lcpu_range_single
    b       .Lcpu_range_find

.Lcpu_range_dash:
    // Range: parse end number
    mov     x0, x19
    bl      parse_decimal
    sub     x0, x0, x1          // end - start
    add     x0, x0, #1          // + 1
    add     x20, x20, x0

    // Skip to next segment
.Lcpu_range_skip:
    ldrb    w2, [x19], #1
    cbz     w2, .Lcpu_range_done
    cmp     w2, #'\n'
    b.eq    .Lcpu_range_done
    cmp     w2, #','
    b.ne    .Lcpu_range_skip
    b       .Lcpu_range_loop

.Lcpu_range_single:
    // Single CPU
    add     x20, x20, #1
    sub     x19, x19, #1        // Back up
    ldrb    w2, [x19]
    cbz     w2, .Lcpu_range_done
    cmp     w2, #'\n'
    b.eq    .Lcpu_range_done
    add     x19, x19, #1
    cmp     w2, #','
    b.eq    .Lcpu_range_loop
    b       .Lcpu_range_done

.Lcpu_range_done:
    mov     x0, x20
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size count_cpu_range, . - count_cpu_range

// -----------------------------------------------------------------------------
// strstr_simple - Find substring in string
//
// Input:
//   x0 = haystack
//   x1 = needle
// Output:
//   x0 = pointer to match, or NULL
// -----------------------------------------------------------------------------
.type strstr_simple, %function
strstr_simple:
    mov     x2, x0              // Save haystack start
    mov     x3, x1              // Save needle start

.Lstrstr_outer:
    ldrb    w4, [x0]
    cbz     w4, .Lstrstr_notfound

    mov     x5, x0              // Potential match start
    mov     x1, x3              // Reset needle

.Lstrstr_inner:
    ldrb    w6, [x1]
    cbz     w6, .Lstrstr_found  // End of needle = match
    ldrb    w7, [x5]
    cbz     w7, .Lstrstr_notfound
    cmp     w6, w7
    b.ne    .Lstrstr_next
    add     x1, x1, #1
    add     x5, x5, #1
    b       .Lstrstr_inner

.Lstrstr_next:
    add     x0, x0, #1
    b       .Lstrstr_outer

.Lstrstr_found:
    // x0 still points to match start
    ret

.Lstrstr_notfound:
    mov     x0, #0
    ret
.size strstr_simple, . - strstr_simple

// -----------------------------------------------------------------------------
// strcpy_simple - Copy string
//
// Input:
//   x0 = dest
//   x1 = src
// Output:
//   x0 = dest
// -----------------------------------------------------------------------------
.type strcpy_simple, %function
strcpy_simple:
    mov     x2, x0              // Save dest

.Lstrcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    cbnz    w3, .Lstrcpy_loop

    mov     x0, x2
    ret
.size strcpy_simple, . - strcpy_simple

// -----------------------------------------------------------------------------
// memzero - Zero memory region
//
// Input:
//   x0 = address
//   x1 = size
// -----------------------------------------------------------------------------
.type memzero, %function
memzero:
    cbz     x1, .Lmemzero_done

.Lmemzero_loop:
    strb    wzr, [x0], #1
    subs    x1, x1, #1
    b.ne    .Lmemzero_loop

.Lmemzero_done:
    ret
.size memzero, . - memzero

// =============================================================================
// Data Section
// =============================================================================

.section .rodata
.balign 8

path_auxv:
    .asciz "/proc/self/auxv"

str_unknown:
    .asciz "Unknown"

// =============================================================================
// End of detect.s
// =============================================================================
