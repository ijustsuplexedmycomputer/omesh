// Hardware Detection Test
// test/unit/test_detect_hw.s
//
// Tests the hardware detection functions for setup wizard

.include "include/syscall_nums.inc"
.include "include/setup.inc"

// External functions
.extern hal_init
.extern detect_all_hardware
.extern detect_wifi_interfaces
.extern detect_bluetooth_adapters
.extern detect_serial_devices
.extern detect_network_interfaces
.extern g_hw_info

// ============================================================================
// Constants
// ============================================================================

.equ MAX_INTERFACES,        8
.equ MAX_NAME_LEN,          32
.equ MAX_IP_LEN,            16

// Hardware info structure offsets (must match detect.s)
.equ HW_INFO_FLAGS,         0
.equ HW_INFO_WIFI_COUNT,    4
.equ HW_INFO_BT_COUNT,      8
.equ HW_INFO_SERIAL_COUNT,  12
.equ HW_INFO_NET_COUNT,     16
.equ HW_INFO_WIFI_NAMES,    20
.equ HW_INFO_WIFI_MESH,     276
.equ HW_INFO_BT_NAMES,      284
.equ HW_INFO_SERIAL_NAMES,  540
.equ HW_INFO_NET_NAMES,     796
.equ HW_INFO_NET_IPS,       1052

// ============================================================================
// Entry Point
// ============================================================================

.section .text
.global _start
_start:
    // Initialize HAL
    bl      hal_init

    // Print header
    adrp    x0, str_header
    add     x0, x0, :lo12:str_header
    bl      print_string

    // Run all hardware detection
    bl      detect_all_hardware
    mov     x19, x0             // Save hw_info pointer

    // Print results header
    adrp    x0, str_results
    add     x0, x0, :lo12:str_results
    bl      print_string

    // Print WiFi interfaces
    adrp    x0, str_wifi_header
    add     x0, x0, :lo12:str_wifi_header
    bl      print_string

    ldr     w0, [x19, #HW_INFO_WIFI_COUNT]
    bl      print_count

    ldr     w20, [x19, #HW_INFO_WIFI_COUNT]
    cbz     w20, .Lprint_bt
    add     x21, x19, #HW_INFO_WIFI_NAMES
    mov     x22, #0

.Lprint_wifi_loop:
    cmp     x22, x20
    b.ge    .Lprint_bt

    adrp    x0, str_indent
    add     x0, x0, :lo12:str_indent
    bl      print_string

    mov     x0, x21
    bl      print_string

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      print_string

    add     x21, x21, #MAX_NAME_LEN
    add     x22, x22, #1
    b       .Lprint_wifi_loop

.Lprint_bt:
    // Print Bluetooth adapters
    adrp    x0, str_bt_header
    add     x0, x0, :lo12:str_bt_header
    bl      print_string

    ldr     w0, [x19, #HW_INFO_BT_COUNT]
    bl      print_count

    ldr     w20, [x19, #HW_INFO_BT_COUNT]
    cbz     w20, .Lprint_serial
    add     x21, x19, #HW_INFO_BT_NAMES
    mov     x22, #0

.Lprint_bt_loop:
    cmp     x22, x20
    b.ge    .Lprint_serial

    adrp    x0, str_indent
    add     x0, x0, :lo12:str_indent
    bl      print_string

    mov     x0, x21
    bl      print_string

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      print_string

    add     x21, x21, #MAX_NAME_LEN
    add     x22, x22, #1
    b       .Lprint_bt_loop

.Lprint_serial:
    // Print Serial devices
    adrp    x0, str_serial_header
    add     x0, x0, :lo12:str_serial_header
    bl      print_string

    ldr     w0, [x19, #HW_INFO_SERIAL_COUNT]
    bl      print_count

    ldr     w20, [x19, #HW_INFO_SERIAL_COUNT]
    cbz     w20, .Lprint_net
    add     x21, x19, #HW_INFO_SERIAL_NAMES
    mov     x22, #0

.Lprint_serial_loop:
    cmp     x22, x20
    b.ge    .Lprint_net

    adrp    x0, str_indent
    add     x0, x0, :lo12:str_indent
    bl      print_string

    mov     x0, x21
    bl      print_string

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      print_string

    add     x21, x21, #MAX_NAME_LEN
    add     x22, x22, #1
    b       .Lprint_serial_loop

.Lprint_net:
    // Print Network interfaces
    adrp    x0, str_net_header
    add     x0, x0, :lo12:str_net_header
    bl      print_string

    ldr     w0, [x19, #HW_INFO_NET_COUNT]
    bl      print_count

    ldr     w20, [x19, #HW_INFO_NET_COUNT]
    cbz     w20, .Lprint_flags
    add     x21, x19, #HW_INFO_NET_NAMES
    add     x23, x19, #HW_INFO_NET_IPS
    mov     x22, #0

.Lprint_net_loop:
    cmp     x22, x20
    b.ge    .Lprint_flags

    adrp    x0, str_indent
    add     x0, x0, :lo12:str_indent
    bl      print_string

    mov     x0, x21
    bl      print_string

    adrp    x0, str_ip_sep
    add     x0, x0, :lo12:str_ip_sep
    bl      print_string

    mov     x0, x23
    bl      print_string

    adrp    x0, str_ip_end
    add     x0, x0, :lo12:str_ip_end
    bl      print_string

    add     x21, x21, #MAX_NAME_LEN
    add     x23, x23, #MAX_IP_LEN
    add     x22, x22, #1
    b       .Lprint_net_loop

.Lprint_flags:
    // Print hardware flags
    adrp    x0, str_flags_header
    add     x0, x0, :lo12:str_flags_header
    bl      print_string

    ldr     w20, [x19, #HW_INFO_FLAGS]
    mov     x0, x20
    bl      print_hex

    adrp    x0, str_flags_detail
    add     x0, x0, :lo12:str_flags_detail
    bl      print_string

    // Check individual flags
    tst     w20, #HW_FLAG_WIFI
    b.eq    .Lcheck_bt_flag
    adrp    x0, str_flag_wifi
    add     x0, x0, :lo12:str_flag_wifi
    bl      print_string

.Lcheck_bt_flag:
    tst     w20, #HW_FLAG_BLUETOOTH
    b.eq    .Lcheck_serial_flag
    adrp    x0, str_flag_bt
    add     x0, x0, :lo12:str_flag_bt
    bl      print_string

.Lcheck_serial_flag:
    tst     w20, #HW_FLAG_SERIAL
    b.eq    .Lcheck_lora_flag
    adrp    x0, str_flag_serial
    add     x0, x0, :lo12:str_flag_serial
    bl      print_string

.Lcheck_lora_flag:
    tst     w20, #HW_FLAG_LORA
    b.eq    .Lprint_done
    adrp    x0, str_flag_lora
    add     x0, x0, :lo12:str_flag_lora
    bl      print_string

.Lprint_done:
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      print_string

    // Print success
    adrp    x0, str_success
    add     x0, x0, :lo12:str_success
    bl      print_string

    // Exit
    mov     x0, #0
    mov     x8, #SYS_exit
    svc     #0

// ============================================================================
// Helper Functions
// ============================================================================

// print_string - Print null-terminated string
// Input: x0 = string pointer
print_string:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    mov     x1, x0
    bl      strlen
    mov     x2, x0              // len
    mov     x0, #1              // stdout
    mov     x8, #SYS_write
    svc     #0

    ldp     x29, x30, [sp], #16
    ret

// strlen - Get string length
strlen:
    mov     x1, x0
.Lstrlen_loop:
    ldrb    w2, [x1], #1
    cbnz    w2, .Lstrlen_loop
    sub     x0, x1, x0
    sub     x0, x0, #1
    ret

// print_count - Print count and newline
// Input: w0 = count
print_count:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     w19, w0

    // Simple single digit print (0-9)
    cmp     w19, #10
    b.ge    .Lprint_count_multi

    add     w19, w19, #'0'
    strb    w19, [sp, #24]
    mov     w0, #'\n'
    strb    w0, [sp, #25]

    mov     x0, #1
    add     x1, sp, #24
    mov     x2, #2
    mov     x8, #SYS_write
    svc     #0
    b       .Lprint_count_done

.Lprint_count_multi:
    // For multi-digit, just print the value in decimal
    mov     w0, w19
    bl      print_decimal
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      print_string

.Lprint_count_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

// print_decimal - Print decimal number
// Input: w0 = number
print_decimal:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    mov     w1, w0
    add     x2, sp, #40         // End of buffer
    mov     w3, #0
    strb    w3, [x2]            // Null terminator

.Lprint_dec_loop:
    sub     x2, x2, #1
    mov     w3, #10
    udiv    w4, w1, w3
    msub    w5, w4, w3, w1      // w5 = w1 % 10
    add     w5, w5, #'0'
    strb    w5, [x2]
    mov     w1, w4
    cbnz    w1, .Lprint_dec_loop

    mov     x0, x2
    bl      print_string

    ldp     x29, x30, [sp], #48
    ret

// print_hex - Print hex value (0x...)
// Input: x0 = value
print_hex:
    stp     x29, x30, [sp, #-48]!
    mov     x29, sp

    mov     x1, x0

    // Print "0x"
    adrp    x0, str_hex_prefix
    add     x0, x0, :lo12:str_hex_prefix
    bl      print_string

    // Print hex digits
    add     x2, sp, #32
    mov     x3, #0
    strb    w3, [x2]
    mov     x4, #0              // digit count

.Lprint_hex_loop:
    and     x3, x1, #0xF
    cmp     x3, #10
    b.lt    .Lprint_hex_digit
    add     x3, x3, #('a' - 10)
    b       .Lprint_hex_store
.Lprint_hex_digit:
    add     x3, x3, #'0'
.Lprint_hex_store:
    sub     x2, x2, #1
    strb    w3, [x2]
    lsr     x1, x1, #4
    add     x4, x4, #1
    cbnz    x1, .Lprint_hex_loop

    // Ensure at least one digit
    cbz     x4, .Lprint_hex_zero

    mov     x0, x2
    bl      print_string
    b       .Lprint_hex_done

.Lprint_hex_zero:
    adrp    x0, str_zero
    add     x0, x0, :lo12:str_zero
    bl      print_string

.Lprint_hex_done:
    ldp     x29, x30, [sp], #48
    ret

// ============================================================================
// Data Section
// ============================================================================

.section .rodata
.balign 8

str_header:
    .asciz "=== Hardware Detection Test ===\n\n"

str_results:
    .asciz "Detected Hardware:\n"

str_wifi_header:
    .asciz "  WiFi interfaces: "

str_bt_header:
    .asciz "  Bluetooth adapters: "

str_serial_header:
    .asciz "  Serial devices: "

str_net_header:
    .asciz "  Network interfaces: "

str_flags_header:
    .asciz "\nHardware flags: "

str_flags_detail:
    .asciz " ("

str_flag_wifi:
    .asciz "WiFi "

str_flag_bt:
    .asciz "Bluetooth "

str_flag_serial:
    .asciz "Serial "

str_flag_lora:
    .asciz "LoRa "

str_indent:
    .asciz "    - "

str_ip_sep:
    .asciz " ("

str_ip_end:
    .asciz ")\n"

str_newline:
    .asciz "\n"

str_hex_prefix:
    .asciz "0x"

str_zero:
    .asciz "0"

str_success:
    .asciz "\nHardware detection: PASSED\n"

// ============================================================================
// End of test_detect_hw.s
// ============================================================================
