// =============================================================================
// Omesh - test_hal.s
// HAL test program - detects and prints hardware capabilities
// =============================================================================
//
// Build: make test
// Run: ./build/test_hal
//
// Output:
//   === Omesh HAL Detection ===
//   CPU: ARM (0x41) Part 0xD08 Rev 3
//   Features: NEON CRC32 AES SHA1 SHA2 PMULL
//   Cache line: 64 bytes
//   Cores: 4
//   Memory: 3891 MB total, 2847 MB available
//   Board: Raspberry Pi 4 Model B Rev 1.4
//   Kernel: 6.1.21
//   Page size: 4096
//   === Detection complete ===
//
// =============================================================================

.include "include/syscall_nums.inc"

// Import HAL functions
.extern hal_init
.extern g_features
.extern print_str
.extern print_dec
.extern print_hex
.extern print_newline
.extern print_char

// Feature structure offsets (from features.s)
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
.equ FEAT_BIT_DOTPROD,          19

.text
.balign 4

// =============================================================================
// _start - Program entry point
// =============================================================================
.global _start
_start:
    // Set up stack frame
    mov     x29, sp

    // Print header
    adrp    x0, msg_header
    add     x0, x0, :lo12:msg_header
    bl      print_str

    // Initialize HAL
    bl      hal_init
    cmp     x0, #0
    b.lt    init_failed

    // Get feature structure address
    adrp    x19, g_features
    add     x19, x19, :lo12:g_features

    // === Print CPU info ===
    adrp    x0, msg_cpu
    add     x0, x0, :lo12:msg_cpu
    bl      print_str

    // Print implementer name
    ldr     x20, [x19, #FEAT_OFF_IMPLEMENTER]
    bl      print_implementer_name

    // Print " (0x"
    adrp    x0, msg_paren_hex
    add     x0, x0, :lo12:msg_paren_hex
    bl      print_str

    // Print implementer hex
    mov     x0, x20
    bl      print_hex_byte

    // Print ") Part 0x"
    adrp    x0, msg_part
    add     x0, x0, :lo12:msg_part
    bl      print_str

    // Print part number
    ldr     x0, [x19, #FEAT_OFF_PART]
    bl      print_hex_short

    // Print " Rev "
    adrp    x0, msg_rev
    add     x0, x0, :lo12:msg_rev
    bl      print_str

    // Print revision
    ldr     x0, [x19, #FEAT_OFF_REVISION]
    bl      print_dec
    bl      print_newline

    // === Print features ===
    adrp    x0, msg_features
    add     x0, x0, :lo12:msg_features
    bl      print_str

    ldr     x20, [x19, #FEAT_OFF_FLAGS]
    bl      print_feature_flags
    bl      print_newline

    // === Print cache line size ===
    adrp    x0, msg_cache
    add     x0, x0, :lo12:msg_cache
    bl      print_str

    ldr     x0, [x19, #FEAT_OFF_CACHE_LINE]
    bl      print_dec

    adrp    x0, msg_bytes
    add     x0, x0, :lo12:msg_bytes
    bl      print_str
    bl      print_newline

    // === Print core count ===
    adrp    x0, msg_cores
    add     x0, x0, :lo12:msg_cores
    bl      print_str

    ldr     x0, [x19, #FEAT_OFF_CORE_COUNT]
    bl      print_dec
    bl      print_newline

    // === Print memory ===
    adrp    x0, msg_memory
    add     x0, x0, :lo12:msg_memory
    bl      print_str

    // Total memory in MB
    ldr     x0, [x19, #FEAT_OFF_TOTAL_MEM]
    lsr     x0, x0, #20         // Divide by 1MB
    bl      print_dec

    adrp    x0, msg_mb_total
    add     x0, x0, :lo12:msg_mb_total
    bl      print_str

    // Available memory in MB
    ldr     x0, [x19, #FEAT_OFF_AVAIL_MEM]
    lsr     x0, x0, #20         // Divide by 1MB
    bl      print_dec

    adrp    x0, msg_mb_avail
    add     x0, x0, :lo12:msg_mb_avail
    bl      print_str
    bl      print_newline

    // === Print board model ===
    adrp    x0, msg_board
    add     x0, x0, :lo12:msg_board
    bl      print_str

    add     x0, x19, #FEAT_OFF_BOARD_MODEL
    bl      print_str
    bl      print_newline

    // === Print kernel version ===
    adrp    x0, msg_kernel
    add     x0, x0, :lo12:msg_kernel
    bl      print_str

    ldr     x20, [x19, #FEAT_OFF_KERNEL_VER]

    // Major (bits 23:16)
    ubfx    x0, x20, #16, #8
    bl      print_dec
    mov     x0, #'.'
    bl      print_char

    // Minor (bits 15:8)
    ubfx    x0, x20, #8, #8
    bl      print_dec
    mov     x0, #'.'
    bl      print_char

    // Patch (bits 7:0)
    and     x0, x20, #0xFF
    bl      print_dec
    bl      print_newline

    // === Print page size ===
    adrp    x0, msg_pagesize
    add     x0, x0, :lo12:msg_pagesize
    bl      print_str

    ldr     x0, [x19, #FEAT_OFF_PAGE_SIZE]
    bl      print_dec
    bl      print_newline

    // Print footer
    adrp    x0, msg_footer
    add     x0, x0, :lo12:msg_footer
    bl      print_str

    // Exit successfully
    mov     x0, #0
    mov     x8, #SYS_exit_group
    svc     #0

init_failed:
    adrp    x0, msg_init_fail
    add     x0, x0, :lo12:msg_init_fail
    bl      print_str
    mov     x0, #1
    mov     x8, #SYS_exit_group
    svc     #0

// =============================================================================
// print_implementer_name - Print CPU implementer name
//
// Input:
//   x20 = implementer ID
// =============================================================================
print_implementer_name:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    cmp     x20, #0x41          // ARM
    b.ne    .Lcheck_broadcom
    adrp    x0, str_arm
    add     x0, x0, :lo12:str_arm
    b       .Lprint_impl

.Lcheck_broadcom:
    cmp     x20, #0x42          // Broadcom
    b.ne    .Lcheck_nvidia
    adrp    x0, str_broadcom
    add     x0, x0, :lo12:str_broadcom
    b       .Lprint_impl

.Lcheck_nvidia:
    cmp     x20, #0x4E          // NVIDIA
    b.ne    .Lcheck_qualcomm
    adrp    x0, str_nvidia
    add     x0, x0, :lo12:str_nvidia
    b       .Lprint_impl

.Lcheck_qualcomm:
    cmp     x20, #0x51          // Qualcomm
    b.ne    .Lcheck_apple
    adrp    x0, str_qualcomm
    add     x0, x0, :lo12:str_qualcomm
    b       .Lprint_impl

.Lcheck_apple:
    cmp     x20, #0x61          // Apple
    b.ne    .Lcheck_ampere
    adrp    x0, str_apple
    add     x0, x0, :lo12:str_apple
    b       .Lprint_impl

.Lcheck_ampere:
    cmp     x20, #0xC0          // Ampere
    b.ne    .Lunknown_impl
    adrp    x0, str_ampere
    add     x0, x0, :lo12:str_ampere
    b       .Lprint_impl

.Lunknown_impl:
    adrp    x0, str_unknown_impl
    add     x0, x0, :lo12:str_unknown_impl

.Lprint_impl:
    bl      print_str

    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// print_feature_flags - Print enabled CPU features
//
// Input:
//   x20 = feature flags
// =============================================================================
print_feature_flags:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x21, #0             // Feature printed flag

    // Check each feature bit and print if set
    tbnz    x20, #FEAT_BIT_NEON, .Lprint_neon
    b       .Lcheck_crc32
.Lprint_neon:
    adrp    x0, str_neon
    add     x0, x0, :lo12:str_neon
    bl      print_str
    mov     x21, #1

.Lcheck_crc32:
    tbnz    x20, #FEAT_BIT_CRC32, .Lprint_crc32
    b       .Lcheck_lse
.Lprint_crc32:
    cbnz    x21, .Lprint_crc32_space
    b       .Lprint_crc32_str
.Lprint_crc32_space:
    mov     x0, #' '
    bl      print_char
.Lprint_crc32_str:
    adrp    x0, str_crc32
    add     x0, x0, :lo12:str_crc32
    bl      print_str
    mov     x21, #1

.Lcheck_lse:
    tbnz    x20, #FEAT_BIT_LSE, .Lprint_lse
    b       .Lcheck_aes
.Lprint_lse:
    cbnz    x21, .Lprint_lse_space
    b       .Lprint_lse_str
.Lprint_lse_space:
    mov     x0, #' '
    bl      print_char
.Lprint_lse_str:
    adrp    x0, str_lse
    add     x0, x0, :lo12:str_lse
    bl      print_str
    mov     x21, #1

.Lcheck_aes:
    tbnz    x20, #FEAT_BIT_AES, .Lprint_aes
    b       .Lcheck_sha1
.Lprint_aes:
    cbnz    x21, .Lprint_aes_space
    b       .Lprint_aes_str
.Lprint_aes_space:
    mov     x0, #' '
    bl      print_char
.Lprint_aes_str:
    adrp    x0, str_aes
    add     x0, x0, :lo12:str_aes
    bl      print_str
    mov     x21, #1

.Lcheck_sha1:
    tbnz    x20, #FEAT_BIT_SHA1, .Lprint_sha1
    b       .Lcheck_sha256
.Lprint_sha1:
    cbnz    x21, .Lprint_sha1_space
    b       .Lprint_sha1_str
.Lprint_sha1_space:
    mov     x0, #' '
    bl      print_char
.Lprint_sha1_str:
    adrp    x0, str_sha1
    add     x0, x0, :lo12:str_sha1
    bl      print_str
    mov     x21, #1

.Lcheck_sha256:
    tbnz    x20, #FEAT_BIT_SHA256, .Lprint_sha256
    b       .Lcheck_sha512
.Lprint_sha256:
    cbnz    x21, .Lprint_sha256_space
    b       .Lprint_sha256_str
.Lprint_sha256_space:
    mov     x0, #' '
    bl      print_char
.Lprint_sha256_str:
    adrp    x0, str_sha256
    add     x0, x0, :lo12:str_sha256
    bl      print_str
    mov     x21, #1

.Lcheck_sha512:
    tbnz    x20, #FEAT_BIT_SHA512, .Lprint_sha512
    b       .Lcheck_sha3
.Lprint_sha512:
    cbnz    x21, .Lprint_sha512_space
    b       .Lprint_sha512_str
.Lprint_sha512_space:
    mov     x0, #' '
    bl      print_char
.Lprint_sha512_str:
    adrp    x0, str_sha512
    add     x0, x0, :lo12:str_sha512
    bl      print_str
    mov     x21, #1

.Lcheck_sha3:
    tbnz    x20, #FEAT_BIT_SHA3, .Lprint_sha3
    b       .Lcheck_pmull
.Lprint_sha3:
    cbnz    x21, .Lprint_sha3_space
    b       .Lprint_sha3_str
.Lprint_sha3_space:
    mov     x0, #' '
    bl      print_char
.Lprint_sha3_str:
    adrp    x0, str_sha3
    add     x0, x0, :lo12:str_sha3
    bl      print_str
    mov     x21, #1

.Lcheck_pmull:
    tbnz    x20, #FEAT_BIT_PMULL, .Lprint_pmull
    b       .Lcheck_fp16
.Lprint_pmull:
    cbnz    x21, .Lprint_pmull_space
    b       .Lprint_pmull_str
.Lprint_pmull_space:
    mov     x0, #' '
    bl      print_char
.Lprint_pmull_str:
    adrp    x0, str_pmull
    add     x0, x0, :lo12:str_pmull
    bl      print_str
    mov     x21, #1

.Lcheck_fp16:
    tbnz    x20, #FEAT_BIT_FP16, .Lprint_fp16
    b       .Lcheck_sve
.Lprint_fp16:
    cbnz    x21, .Lprint_fp16_space
    b       .Lprint_fp16_str
.Lprint_fp16_space:
    mov     x0, #' '
    bl      print_char
.Lprint_fp16_str:
    adrp    x0, str_fp16
    add     x0, x0, :lo12:str_fp16
    bl      print_str
    mov     x21, #1

.Lcheck_sve:
    tbnz    x20, #FEAT_BIT_SVE, .Lprint_sve
    b       .Lcheck_sve2
.Lprint_sve:
    cbnz    x21, .Lprint_sve_space
    b       .Lprint_sve_str
.Lprint_sve_space:
    mov     x0, #' '
    bl      print_char
.Lprint_sve_str:
    adrp    x0, str_sve
    add     x0, x0, :lo12:str_sve
    bl      print_str
    mov     x21, #1

.Lcheck_sve2:
    tbnz    x20, #FEAT_BIT_SVE2, .Lprint_sve2
    b       .Lcheck_rng
.Lprint_sve2:
    cbnz    x21, .Lprint_sve2_space
    b       .Lprint_sve2_str
.Lprint_sve2_space:
    mov     x0, #' '
    bl      print_char
.Lprint_sve2_str:
    adrp    x0, str_sve2
    add     x0, x0, :lo12:str_sve2
    bl      print_str
    mov     x21, #1

.Lcheck_rng:
    tbnz    x20, #FEAT_BIT_RNG, .Lprint_rng
    b       .Lcheck_bti
.Lprint_rng:
    cbnz    x21, .Lprint_rng_space
    b       .Lprint_rng_str
.Lprint_rng_space:
    mov     x0, #' '
    bl      print_char
.Lprint_rng_str:
    adrp    x0, str_rng
    add     x0, x0, :lo12:str_rng
    bl      print_str
    mov     x21, #1

.Lcheck_bti:
    tbnz    x20, #FEAT_BIT_BTI, .Lprint_bti
    b       .Lcheck_mte
.Lprint_bti:
    cbnz    x21, .Lprint_bti_space
    b       .Lprint_bti_str
.Lprint_bti_space:
    mov     x0, #' '
    bl      print_char
.Lprint_bti_str:
    adrp    x0, str_bti
    add     x0, x0, :lo12:str_bti
    bl      print_str
    mov     x21, #1

.Lcheck_mte:
    tbnz    x20, #FEAT_BIT_MTE, .Lprint_mte
    b       .Lcheck_pauth
.Lprint_mte:
    cbnz    x21, .Lprint_mte_space
    b       .Lprint_mte_str
.Lprint_mte_space:
    mov     x0, #' '
    bl      print_char
.Lprint_mte_str:
    adrp    x0, str_mte
    add     x0, x0, :lo12:str_mte
    bl      print_str
    mov     x21, #1

.Lcheck_pauth:
    tbnz    x20, #FEAT_BIT_PAUTH, .Lprint_pauth
    b       .Lcheck_dotprod
.Lprint_pauth:
    cbnz    x21, .Lprint_pauth_space
    b       .Lprint_pauth_str
.Lprint_pauth_space:
    mov     x0, #' '
    bl      print_char
.Lprint_pauth_str:
    adrp    x0, str_pauth
    add     x0, x0, :lo12:str_pauth
    bl      print_str
    mov     x21, #1

.Lcheck_dotprod:
    tbnz    x20, #FEAT_BIT_DOTPROD, .Lprint_dotprod
    b       .Lfeatures_done
.Lprint_dotprod:
    cbnz    x21, .Lprint_dotprod_space
    b       .Lprint_dotprod_str
.Lprint_dotprod_space:
    mov     x0, #' '
    bl      print_char
.Lprint_dotprod_str:
    adrp    x0, str_dotprod
    add     x0, x0, :lo12:str_dotprod
    bl      print_str

.Lfeatures_done:
    // If no features were printed, print "none"
    cbnz    x21, .Lfeatures_exit
    adrp    x0, str_none
    add     x0, x0, :lo12:str_none
    bl      print_str

.Lfeatures_exit:
    ldp     x29, x30, [sp], #16
    ret

// =============================================================================
// print_hex_byte - Print 8-bit value as 2 hex digits
//
// Input:
//   x0 = value (low byte)
// =============================================================================
print_hex_byte:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    // High nibble
    lsr     x0, x19, #4
    and     x0, x0, #0xF
    bl      nibble_to_hex
    bl      print_char

    // Low nibble
    and     x0, x19, #0xF
    bl      nibble_to_hex
    bl      print_char

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// print_hex_short - Print 16-bit value as hex (without 0x prefix)
//
// Input:
//   x0 = value
// =============================================================================
print_hex_short:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0

    // Check if we need 3 digits (value >= 0x100)
    cmp     x19, #0x100
    b.lt    .Lhex_short_2

    // High nibble (if needed)
    cmp     x19, #0x1000
    b.lt    .Lhex_short_3

    lsr     x0, x19, #12
    and     x0, x0, #0xF
    bl      nibble_to_hex
    bl      print_char

.Lhex_short_3:
    lsr     x0, x19, #8
    and     x0, x0, #0xF
    bl      nibble_to_hex
    bl      print_char

.Lhex_short_2:
    lsr     x0, x19, #4
    and     x0, x0, #0xF
    bl      nibble_to_hex
    bl      print_char

    and     x0, x19, #0xF
    bl      nibble_to_hex
    bl      print_char

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// =============================================================================
// nibble_to_hex - Convert 4-bit value to hex character
//
// Input:
//   x0 = value (0-15)
// Output:
//   x0 = character ('0'-'9' or 'a'-'f')
// =============================================================================
nibble_to_hex:
    cmp     x0, #10
    b.lt    .Lnibble_digit
    add     x0, x0, #('a' - 10)
    ret
.Lnibble_digit:
    add     x0, x0, #'0'
    ret

// =============================================================================
// Data Section
// =============================================================================

.section .rodata
.balign 8

msg_header:
    .asciz "=== Omesh HAL Detection ===\n"

msg_footer:
    .asciz "=== Detection complete ===\n"

msg_init_fail:
    .asciz "ERROR: HAL initialization failed\n"

msg_cpu:
    .asciz "CPU: "

msg_paren_hex:
    .asciz " (0x"

msg_part:
    .asciz ") Part 0x"

msg_rev:
    .asciz " Rev "

msg_features:
    .asciz "Features: "

msg_cache:
    .asciz "Cache line: "

msg_bytes:
    .asciz " bytes"

msg_cores:
    .asciz "Cores: "

msg_memory:
    .asciz "Memory: "

msg_mb_total:
    .asciz " MB total, "

msg_mb_avail:
    .asciz " MB available"

msg_board:
    .asciz "Board: "

msg_kernel:
    .asciz "Kernel: "

msg_pagesize:
    .asciz "Page size: "

// CPU implementer names
str_arm:
    .asciz "ARM"

str_broadcom:
    .asciz "Broadcom"

str_nvidia:
    .asciz "NVIDIA"

str_qualcomm:
    .asciz "Qualcomm"

str_apple:
    .asciz "Apple"

str_ampere:
    .asciz "Ampere"

str_unknown_impl:
    .asciz "Unknown"

// Feature names
str_neon:
    .asciz "NEON"

str_crc32:
    .asciz "CRC32"

str_lse:
    .asciz "LSE"

str_aes:
    .asciz "AES"

str_sha1:
    .asciz "SHA1"

str_sha256:
    .asciz "SHA256"

str_sha512:
    .asciz "SHA512"

str_sha3:
    .asciz "SHA3"

str_pmull:
    .asciz "PMULL"

str_fp16:
    .asciz "FP16"

str_sve:
    .asciz "SVE"

str_sve2:
    .asciz "SVE2"

str_rng:
    .asciz "RNG"

str_bti:
    .asciz "BTI"

str_mte:
    .asciz "MTE"

str_pauth:
    .asciz "PAUTH"

str_dotprod:
    .asciz "DOTPROD"

str_none:
    .asciz "(none)"

// =============================================================================
// End of test_hal.s
// =============================================================================
