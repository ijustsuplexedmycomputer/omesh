// =============================================================================
// Omesh - features.s
// HAL feature flags structure and constants
// =============================================================================
//
// This file defines the global feature structure that holds detected hardware
// capabilities. The structure is populated by hal_init() in detect.s.
//
// Structure layout (152 bytes total):
//
//   Offset  Size  Field               Description
//   ──────────────────────────────────────────────────────────────────────────
//   0       8     cpu_implementer     Manufacturer (ARM=0x41, Apple=0x61, etc.)
//   8       8     cpu_variant         CPU variant/revision
//   16      8     cpu_part            CPU part number
//   24      8     cpu_revision        CPU revision
//   32      8     cache_line_size     D-cache line size in bytes
//   40      8     page_size           System page size (typically 4096)
//   48      8     core_count          Number of CPU cores
//   56      8     total_memory        Total physical memory in bytes
//   64      8     available_memory    Available memory in bytes
//   72      8     feature_flags       Bitfield of CPU features
//   80      64    board_model         Board model string (null-terminated)
//   144     8     kernel_version      Packed version (major<<16 | minor<<8 | patch)
//
// =============================================================================

.include "include/syscall_nums.inc"

// -----------------------------------------------------------------------------
// Feature structure offsets
// Use these constants to access fields in the global g_features structure
// -----------------------------------------------------------------------------

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

.equ FEAT_STRUCT_SIZE,          152
.equ FEAT_BOARD_MODEL_LEN,      64

// -----------------------------------------------------------------------------
// CPU Feature flags (bits in feature_flags field)
// Test with: tbnz x0, #FEAT_BIT_xxx, label
// -----------------------------------------------------------------------------

.equ FEAT_BIT_NEON,             0       // NEON/ASIMD SIMD instructions
.equ FEAT_BIT_CRC32,            1       // CRC32 instructions
.equ FEAT_BIT_LSE,              2       // Large System Extensions (atomics)
.equ FEAT_BIT_AES,              3       // AES crypto instructions
.equ FEAT_BIT_SHA1,             4       // SHA-1 crypto instructions
.equ FEAT_BIT_SHA256,           5       // SHA-256 crypto instructions
.equ FEAT_BIT_SHA512,           6       // SHA-512 crypto instructions
.equ FEAT_BIT_SHA3,             7       // SHA-3 crypto instructions
.equ FEAT_BIT_PMULL,            8       // Polynomial multiply (GCM)
.equ FEAT_BIT_FP16,             9       // Half-precision floating point
.equ FEAT_BIT_LSE2,             10      // LSE2 (enhanced atomics)
.equ FEAT_BIT_SVE,              11      // Scalable Vector Extension
.equ FEAT_BIT_SVE2,             12      // SVE2
.equ FEAT_BIT_RNG,              13      // Hardware random number generator
.equ FEAT_BIT_BTI,              14      // Branch Target Identification
.equ FEAT_BIT_MTE,              15      // Memory Tagging Extension
.equ FEAT_BIT_PAUTH,            16      // Pointer Authentication
.equ FEAT_BIT_SM3,              17      // SM3 crypto (Chinese standard)
.equ FEAT_BIT_SM4,              18      // SM4 crypto (Chinese standard)
.equ FEAT_BIT_DOTPROD,          19      // Dot product instructions
.equ FEAT_BIT_RCPC,             20      // Release-consistent PC-relative (LDAPR)
.equ FEAT_BIT_FLAGM,            21      // Flag manipulation instructions
.equ FEAT_BIT_BF16,             22      // BFloat16 support
.equ FEAT_BIT_I8MM,             23      // Int8 matrix multiply

// Feature masks for common combinations
.equ FEAT_MASK_CRYPTO,          ((1 << 3) | (1 << 4) | (1 << 5) | (1 << 8))
.equ FEAT_MASK_SIMD,            ((1 << 0) | (1 << 11) | (1 << 12))

// -----------------------------------------------------------------------------
// CPU Implementer IDs (from MIDR_EL1 bits [31:24])
// -----------------------------------------------------------------------------

.equ CPU_IMPL_ARM,              0x41    // ARM Ltd
.equ CPU_IMPL_BROADCOM,         0x42    // Broadcom (Pi)
.equ CPU_IMPL_CAVIUM,           0x43    // Cavium/Marvell
.equ CPU_IMPL_FUJITSU,          0x46    // Fujitsu
.equ CPU_IMPL_HISI,             0x48    // HiSilicon
.equ CPU_IMPL_INFINEON,         0x49    // Infineon
.equ CPU_IMPL_FREESCALE,        0x4D    // Freescale/NXP
.equ CPU_IMPL_NVIDIA,           0x4E    // NVIDIA
.equ CPU_IMPL_APM,              0x50    // Applied Micro
.equ CPU_IMPL_QUALCOMM,         0x51    // Qualcomm
.equ CPU_IMPL_SAMSUNG,          0x53    // Samsung
.equ CPU_IMPL_INTEL,            0x69    // Intel
.equ CPU_IMPL_AMPERE,           0xC0    // Ampere Computing
.equ CPU_IMPL_APPLE,            0x61    // Apple (Asahi)

// -----------------------------------------------------------------------------
// Common ARM CPU Part Numbers (from MIDR_EL1 bits [15:4])
// -----------------------------------------------------------------------------

// Cortex-A series
.equ CPU_PART_A53,              0xD03   // Cortex-A53 (Pi 3)
.equ CPU_PART_A55,              0xD05   // Cortex-A55
.equ CPU_PART_A57,              0xD07   // Cortex-A57 (Jetson TX1)
.equ CPU_PART_A72,              0xD08   // Cortex-A72 (Pi 4)
.equ CPU_PART_A73,              0xD09   // Cortex-A73
.equ CPU_PART_A75,              0xD0A   // Cortex-A75
.equ CPU_PART_A76,              0xD0B   // Cortex-A76 (Pi 5)
.equ CPU_PART_A77,              0xD0D   // Cortex-A77
.equ CPU_PART_A78,              0xD41   // Cortex-A78
.equ CPU_PART_A710,             0xD47   // Cortex-A710
.equ CPU_PART_A715,             0xD4D   // Cortex-A715
.equ CPU_PART_X1,               0xD44   // Cortex-X1
.equ CPU_PART_X2,               0xD48   // Cortex-X2
.equ CPU_PART_X3,               0xD4E   // Cortex-X3
.equ CPU_PART_X4,               0xD81   // Cortex-X4

// Neoverse (server) series
.equ CPU_PART_N1,               0xD0C   // Neoverse N1 (Graviton2)
.equ CPU_PART_N2,               0xD49   // Neoverse N2 (Graviton3)
.equ CPU_PART_V1,               0xD40   // Neoverse V1
.equ CPU_PART_V2,               0xD4F   // Neoverse V2 (Graviton4)

// NVIDIA
.equ CPU_PART_DENVER,           0x003   // Denver (Jetson TX1/TX2)
.equ CPU_PART_CARMEL,           0x004   // Carmel (Jetson Xavier)

// Apple Silicon (note: different implementer ID)
.equ CPU_PART_APPLE_M1_FIRESTORM, 0x022 // M1 P-core
.equ CPU_PART_APPLE_M1_ICESTORM,  0x021 // M1 E-core
.equ CPU_PART_APPLE_M2_AVALANCHE, 0x032 // M2 P-core
.equ CPU_PART_APPLE_M2_BLIZZARD,  0x031 // M2 E-core

// -----------------------------------------------------------------------------
// Board Type IDs
// Detected from device tree or model string matching
// -----------------------------------------------------------------------------

.equ BOARD_UNKNOWN,             0
.equ BOARD_RPI_3B,              1       // Raspberry Pi 3 Model B
.equ BOARD_RPI_3BP,             2       // Raspberry Pi 3 Model B+
.equ BOARD_RPI_4B,              3       // Raspberry Pi 4 Model B
.equ BOARD_RPI_400,             4       // Raspberry Pi 400
.equ BOARD_RPI_5,               5       // Raspberry Pi 5
.equ BOARD_RPI_ZERO2,           6       // Raspberry Pi Zero 2 W
.equ BOARD_RPI_CM4,             7       // Raspberry Pi Compute Module 4
.equ BOARD_JETSON_NANO,         10      // NVIDIA Jetson Nano
.equ BOARD_JETSON_TX2,          11      // NVIDIA Jetson TX2
.equ BOARD_JETSON_XAVIER,       12      // NVIDIA Jetson Xavier NX
.equ BOARD_JETSON_ORIN,         13      // NVIDIA Jetson Orin
.equ BOARD_AWS_GRAVITON,        20      // AWS Graviton (any generation)
.equ BOARD_AWS_GRAVITON2,       21      // AWS Graviton2
.equ BOARD_AWS_GRAVITON3,       22      // AWS Graviton3
.equ BOARD_AWS_GRAVITON4,       23      // AWS Graviton4
.equ BOARD_AMPERE_ALTRA,        30      // Ampere Altra
.equ BOARD_AMPERE_ALTRA_MAX,    31      // Ampere Altra Max
.equ BOARD_APPLE_M1,            40      // Apple M1 (Asahi Linux)
.equ BOARD_APPLE_M2,            41      // Apple M2 (Asahi Linux)
.equ BOARD_APPLE_M3,            42      // Apple M3 (Asahi Linux)
.equ BOARD_QEMU,                99      // QEMU virtual machine

// -----------------------------------------------------------------------------
// Memory tier thresholds (for adaptive behavior)
// -----------------------------------------------------------------------------

.equ MEM_TIER_MINIMAL,          (512 << 20)     // < 512 MB
.equ MEM_TIER_LOW,              (1 << 30)       // 512 MB - 1 GB
.equ MEM_TIER_MEDIUM,           (4 << 30)       // 1 GB - 4 GB
.equ MEM_TIER_HIGH,             (16 << 30)      // 4 GB - 16 GB
// > 16 GB = TIER_SERVER

// -----------------------------------------------------------------------------
// Cache line size defaults (if detection fails)
// -----------------------------------------------------------------------------

.equ CACHE_LINE_DEFAULT,        64              // Safe default
.equ CACHE_LINE_MIN,            16              // Minimum supported
.equ CACHE_LINE_MAX,            256             // Maximum expected

// -----------------------------------------------------------------------------
// BSS Section - Global feature structure
// -----------------------------------------------------------------------------

.section .bss
.balign 8

// Global feature structure, populated by hal_init()
.global g_features
g_features:
    .skip FEAT_STRUCT_SIZE

// Initialization flag - set to 1 after hal_init() completes
.global g_hal_initialized
g_hal_initialized:
    .skip 8

// -----------------------------------------------------------------------------
// Read-only data - String constants for detection
// -----------------------------------------------------------------------------

.section .rodata
.balign 8

// Paths for detection
.global path_cpuinfo
path_cpuinfo:
    .asciz "/proc/cpuinfo"

.global path_meminfo
path_meminfo:
    .asciz "/proc/meminfo"

.global path_dt_model
path_dt_model:
    .asciz "/proc/device-tree/model"

.global path_dt_model_alt
path_dt_model_alt:
    .asciz "/sys/firmware/devicetree/base/model"

.global path_cpu_online
path_cpu_online:
    .asciz "/sys/devices/system/cpu/online"

// Search strings for /proc/cpuinfo parsing
.global str_cpu_implementer
str_cpu_implementer:
    .asciz "CPU implementer"

.global str_cpu_part
str_cpu_part:
    .asciz "CPU part"

.global str_cpu_variant
str_cpu_variant:
    .asciz "CPU variant"

.global str_cpu_revision
str_cpu_revision:
    .asciz "CPU revision"

.global str_features
str_features:
    .asciz "Features"

// Search strings for /proc/meminfo parsing
.global str_memtotal
str_memtotal:
    .asciz "MemTotal:"

.global str_memavailable
str_memavailable:
    .asciz "MemAvailable:"

// Feature name strings for /proc/cpuinfo Features line
.global str_feat_neon
str_feat_neon:
    .asciz "asimd"

.global str_feat_crc32
str_feat_crc32:
    .asciz "crc32"

.global str_feat_aes
str_feat_aes:
    .asciz "aes"

.global str_feat_sha1
str_feat_sha1:
    .asciz "sha1"

.global str_feat_sha2
str_feat_sha2:
    .asciz "sha2"

.global str_feat_sha512
str_feat_sha512:
    .asciz "sha512"

.global str_feat_sha3
str_feat_sha3:
    .asciz "sha3"

.global str_feat_pmull
str_feat_pmull:
    .asciz "pmull"

.global str_feat_atomics
str_feat_atomics:
    .asciz "atomics"

.global str_feat_fphp
str_feat_fphp:
    .asciz "fphp"

.global str_feat_sve
str_feat_sve:
    .asciz "sve"

.global str_feat_sve2
str_feat_sve2:
    .asciz "sve2"

.global str_feat_bf16
str_feat_bf16:
    .asciz "bf16"

.global str_feat_i8mm
str_feat_i8mm:
    .asciz "i8mm"

.global str_feat_rng
str_feat_rng:
    .asciz "rng"

.global str_feat_bti
str_feat_bti:
    .asciz "bti"

.global str_feat_mte
str_feat_mte:
    .asciz "mte"

.global str_feat_paca
str_feat_paca:
    .asciz "paca"

.global str_feat_sm3
str_feat_sm3:
    .asciz "sm3"

.global str_feat_sm4
str_feat_sm4:
    .asciz "sm4"

.global str_feat_dotprod
str_feat_dotprod:
    .asciz "asimddp"

// Board model match strings
.global str_board_rpi3
str_board_rpi3:
    .asciz "Raspberry Pi 3"

.global str_board_rpi4
str_board_rpi4:
    .asciz "Raspberry Pi 4"

.global str_board_rpi5
str_board_rpi5:
    .asciz "Raspberry Pi 5"

.global str_board_rpizero2
str_board_rpizero2:
    .asciz "Raspberry Pi Zero 2"

.global str_board_rpi400
str_board_rpi400:
    .asciz "Raspberry Pi 400"

.global str_board_jetson_nano
str_board_jetson_nano:
    .asciz "Jetson Nano"

.global str_board_jetson_xavier
str_board_jetson_xavier:
    .asciz "Jetson Xavier"

.global str_board_jetson_orin
str_board_jetson_orin:
    .asciz "Jetson Orin"

.global str_board_qemu
str_board_qemu:
    .asciz "QEMU"

.global str_board_graviton
str_board_graviton:
    .asciz "Graviton"

.global str_board_ampere
str_board_ampere:
    .asciz "Ampere"

.global str_board_apple
str_board_apple:
    .asciz "Apple"

// =============================================================================
// End of features.s
// =============================================================================
