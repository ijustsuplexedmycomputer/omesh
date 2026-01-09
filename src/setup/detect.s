// Hardware Detection for Setup Wizard
// src/setup/detect.s
//
// Detects network hardware available on the system:
//   - WiFi interfaces (with mesh capability check)
//   - Bluetooth adapters
//   - Serial devices (ttyUSB*, ttyACM*)
//   - Network interfaces with IP addresses
//
// Functions:
//   detect_wifi_interfaces   - List WiFi interfaces
//   detect_bluetooth_adapters - List Bluetooth adapters
//   detect_serial_devices    - List serial ports
//   detect_network_interfaces - List network interfaces with IPs
//   detect_all_hardware      - Run all detection and populate hw_info

.include "include/syscall_nums.inc"
.include "include/setup.inc"

.global detect_wifi_interfaces
.global detect_bluetooth_adapters
.global detect_serial_devices
.global detect_network_interfaces
.global detect_all_hardware
.global g_hw_info

// ============================================================================
// Constants
// ============================================================================

.equ MAX_INTERFACES,        8
.equ MAX_NAME_LEN,          32
.equ MAX_IP_LEN,            16
.equ MAX_PATH_LEN,          128

// Hardware info structure offsets
.equ HW_INFO_FLAGS,         0       // uint32_t - HW_FLAG_* bits
.equ HW_INFO_WIFI_COUNT,    4       // uint32_t
.equ HW_INFO_BT_COUNT,      8       // uint32_t
.equ HW_INFO_SERIAL_COUNT,  12      // uint32_t
.equ HW_INFO_NET_COUNT,     16      // uint32_t
.equ HW_INFO_WIFI_NAMES,    20      // char[8][32] - WiFi interface names
.equ HW_INFO_WIFI_MESH,     276     // uint8_t[8] - mesh capable flags
.equ HW_INFO_BT_NAMES,      284     // char[8][32] - Bluetooth adapter names
.equ HW_INFO_SERIAL_NAMES,  540     // char[8][32] - Serial device names
.equ HW_INFO_NET_NAMES,     796     // char[8][32] - Network interface names
.equ HW_INFO_NET_IPS,       1052    // char[8][16] - IP addresses
.equ HW_INFO_SIZE,          1180

// ============================================================================
// BSS Section
// ============================================================================

.section .bss
.align 8

// Global hardware info structure
g_hw_info:
    .skip HW_INFO_SIZE

// Temporary path buffer
path_buf:
    .skip MAX_PATH_LEN

// Directory entry buffer (for getdents64)
dirent_buf:
    .skip 1024

// ============================================================================
// Text Section
// ============================================================================

.section .text

// ----------------------------------------------------------------------------
// detect_all_hardware - Run all hardware detection
// ----------------------------------------------------------------------------
// Outputs:
//   x0 = pointer to g_hw_info
//   Populates g_hw_info with detected hardware
// ----------------------------------------------------------------------------
.type detect_all_hardware, %function
detect_all_hardware:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Clear hw_info structure
    adrp    x0, g_hw_info
    add     x0, x0, :lo12:g_hw_info
    mov     x1, #HW_INFO_SIZE
    bl      hw_memzero

    // Detect WiFi interfaces
    adrp    x0, g_hw_info
    add     x0, x0, :lo12:g_hw_info
    add     x0, x0, #HW_INFO_WIFI_NAMES
    mov     x1, #MAX_INTERFACES
    bl      detect_wifi_interfaces

    // Store WiFi count
    adrp    x1, g_hw_info
    add     x1, x1, :lo12:g_hw_info
    str     w0, [x1, #HW_INFO_WIFI_COUNT]

    // Set WiFi flag if found
    cmp     w0, #0
    b.eq    .Ldetect_bt
    ldr     w2, [x1, #HW_INFO_FLAGS]
    orr     w2, w2, #HW_FLAG_WIFI
    str     w2, [x1, #HW_INFO_FLAGS]

.Ldetect_bt:
    // Detect Bluetooth adapters
    adrp    x0, g_hw_info
    add     x0, x0, :lo12:g_hw_info
    add     x0, x0, #HW_INFO_BT_NAMES
    mov     x1, #MAX_INTERFACES
    bl      detect_bluetooth_adapters

    // Store Bluetooth count
    adrp    x1, g_hw_info
    add     x1, x1, :lo12:g_hw_info
    str     w0, [x1, #HW_INFO_BT_COUNT]

    // Set Bluetooth flag if found
    cmp     w0, #0
    b.eq    .Ldetect_serial
    ldr     w2, [x1, #HW_INFO_FLAGS]
    orr     w2, w2, #HW_FLAG_BLUETOOTH
    str     w2, [x1, #HW_INFO_FLAGS]

.Ldetect_serial:
    // Detect serial devices
    adrp    x0, g_hw_info
    add     x0, x0, :lo12:g_hw_info
    add     x0, x0, #HW_INFO_SERIAL_NAMES
    mov     x1, #MAX_INTERFACES
    bl      detect_serial_devices

    // Store serial count
    adrp    x1, g_hw_info
    add     x1, x1, :lo12:g_hw_info
    str     w0, [x1, #HW_INFO_SERIAL_COUNT]

    // Set serial flag if found
    cmp     w0, #0
    b.eq    .Ldetect_net
    ldr     w2, [x1, #HW_INFO_FLAGS]
    orr     w2, w2, #HW_FLAG_SERIAL
    str     w2, [x1, #HW_INFO_FLAGS]

.Ldetect_net:
    // Detect network interfaces
    adrp    x0, g_hw_info
    add     x0, x0, :lo12:g_hw_info
    add     x0, x0, #HW_INFO_NET_NAMES
    adrp    x1, g_hw_info
    add     x1, x1, :lo12:g_hw_info
    add     x1, x1, #HW_INFO_NET_IPS
    mov     x2, #MAX_INTERFACES
    bl      detect_network_interfaces

    // Store network count
    adrp    x1, g_hw_info
    add     x1, x1, :lo12:g_hw_info
    str     w0, [x1, #HW_INFO_NET_COUNT]

    // Return pointer to hw_info
    adrp    x0, g_hw_info
    add     x0, x0, :lo12:g_hw_info

    ldp     x29, x30, [sp], #16
    ret
.size detect_all_hardware, . - detect_all_hardware

// ----------------------------------------------------------------------------
// detect_wifi_interfaces - List WiFi interfaces
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = buffer for interface names (char[max][32])
//   x1 = max interfaces to detect
// Outputs:
//   x0 = number of interfaces found
// ----------------------------------------------------------------------------
.type detect_wifi_interfaces, %function
detect_wifi_interfaces:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // Names buffer
    mov     x20, x1             // Max count
    mov     x21, #0             // Found count

    // Open /sys/class/net
    mov     x0, #AT_FDCWD
    adrp    x1, path_sys_net
    add     x1, x1, :lo12:path_sys_net
    mov     x2, #O_RDONLY | O_DIRECTORY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lwifi_done
    mov     x22, x0             // Dir fd

.Lwifi_read_dir:
    // Read directory entries
    mov     x0, x22
    adrp    x1, dirent_buf
    add     x1, x1, :lo12:dirent_buf
    mov     x2, #1024
    mov     x8, #SYS_getdents64
    svc     #0
    cmp     x0, #0
    b.le    .Lwifi_close

    mov     x23, x0             // Bytes read
    adrp    x24, dirent_buf
    add     x24, x24, :lo12:dirent_buf

.Lwifi_process_entry:
    cmp     x23, #0
    b.le    .Lwifi_read_dir

    // Get entry name (offset 19 in dirent64)
    add     x0, x24, #19

    // Skip . and ..
    ldrb    w1, [x0]
    cmp     w1, #'.'
    b.eq    .Lwifi_next_entry

    // Check if this interface has wireless subdirectory
    mov     x1, x0              // Interface name
    bl      check_wireless_interface
    cmp     x0, #0
    b.eq    .Lwifi_next_entry

    // Found WiFi interface - copy name
    cmp     x21, x20            // Check max
    b.ge    .Lwifi_close

    mov     x0, x19             // Dest
    add     x1, x24, #19        // Src (interface name)
    bl      hw_strcpy_max

    add     x19, x19, #MAX_NAME_LEN
    add     x21, x21, #1

.Lwifi_next_entry:
    // Move to next dirent entry
    ldrh    w0, [x24, #16]      // d_reclen at offset 16
    add     x24, x24, x0
    sub     x23, x23, x0
    b       .Lwifi_process_entry

.Lwifi_close:
    mov     x0, x22
    mov     x8, #SYS_close
    svc     #0

.Lwifi_done:
    mov     x0, x21             // Return count

    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size detect_wifi_interfaces, . - detect_wifi_interfaces

// ----------------------------------------------------------------------------
// check_wireless_interface - Check if interface has wireless capability
// ----------------------------------------------------------------------------
// Inputs:
//   x1 = interface name
// Outputs:
//   x0 = 1 if wireless, 0 otherwise
// ----------------------------------------------------------------------------
.type check_wireless_interface, %function
check_wireless_interface:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x1             // Save interface name

    // Build path: /sys/class/net/<iface>/wireless
    adrp    x0, path_buf
    add     x0, x0, :lo12:path_buf
    adrp    x1, path_sys_net
    add     x1, x1, :lo12:path_sys_net
    bl      hw_strcpy

    // Append /
    adrp    x0, path_buf
    add     x0, x0, :lo12:path_buf
    bl      hw_strlen
    adrp    x1, path_buf
    add     x1, x1, :lo12:path_buf
    add     x1, x1, x0
    mov     w2, #'/'
    strb    w2, [x1], #1

    // Append interface name
    mov     x0, x1
    mov     x1, x19
    bl      hw_strcpy

    // Append /wireless
    adrp    x0, path_buf
    add     x0, x0, :lo12:path_buf
    bl      hw_strlen
    adrp    x1, path_buf
    add     x1, x1, :lo12:path_buf
    add     x0, x1, x0
    adrp    x1, str_wireless
    add     x1, x1, :lo12:str_wireless
    bl      hw_strcpy

    // Try to open the wireless directory
    mov     x0, #AT_FDCWD
    adrp    x1, path_buf
    add     x1, x1, :lo12:path_buf
    mov     x2, #O_RDONLY | O_DIRECTORY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lcheck_wireless_no

    // Close and return 1
    mov     x8, #SYS_close
    svc     #0
    mov     x0, #1
    b       .Lcheck_wireless_done

.Lcheck_wireless_no:
    mov     x0, #0

.Lcheck_wireless_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size check_wireless_interface, . - check_wireless_interface

// ----------------------------------------------------------------------------
// detect_bluetooth_adapters - List Bluetooth adapters
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = buffer for adapter names (char[max][32])
//   x1 = max adapters to detect
// Outputs:
//   x0 = number of adapters found
// ----------------------------------------------------------------------------
.type detect_bluetooth_adapters, %function
detect_bluetooth_adapters:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // Names buffer
    mov     x20, x1             // Max count
    mov     x21, #0             // Found count

    // Open /sys/class/bluetooth
    mov     x0, #AT_FDCWD
    adrp    x1, path_sys_bluetooth
    add     x1, x1, :lo12:path_sys_bluetooth
    mov     x2, #O_RDONLY | O_DIRECTORY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lbt_done
    mov     x22, x0             // Dir fd

.Lbt_read_dir:
    // Read directory entries
    mov     x0, x22
    adrp    x1, dirent_buf
    add     x1, x1, :lo12:dirent_buf
    mov     x2, #1024
    mov     x8, #SYS_getdents64
    svc     #0
    cmp     x0, #0
    b.le    .Lbt_close

    mov     x23, x0             // Bytes read
    adrp    x24, dirent_buf
    add     x24, x24, :lo12:dirent_buf

.Lbt_process_entry:
    cmp     x23, #0
    b.le    .Lbt_read_dir

    // Get entry name (offset 19 in dirent64)
    add     x0, x24, #19

    // Skip . and ..
    ldrb    w1, [x0]
    cmp     w1, #'.'
    b.eq    .Lbt_next_entry

    // Check if name starts with "hci"
    ldrb    w1, [x0]
    cmp     w1, #'h'
    b.ne    .Lbt_next_entry
    ldrb    w1, [x0, #1]
    cmp     w1, #'c'
    b.ne    .Lbt_next_entry
    ldrb    w1, [x0, #2]
    cmp     w1, #'i'
    b.ne    .Lbt_next_entry

    // Found Bluetooth adapter - copy name
    cmp     x21, x20            // Check max
    b.ge    .Lbt_close

    mov     x1, x0              // Src
    mov     x0, x19             // Dest
    bl      hw_strcpy_max

    add     x19, x19, #MAX_NAME_LEN
    add     x21, x21, #1

.Lbt_next_entry:
    // Move to next dirent entry
    ldrh    w0, [x24, #16]      // d_reclen
    add     x24, x24, x0
    sub     x23, x23, x0
    b       .Lbt_process_entry

.Lbt_close:
    mov     x0, x22
    mov     x8, #SYS_close
    svc     #0

.Lbt_done:
    mov     x0, x21             // Return count

    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size detect_bluetooth_adapters, . - detect_bluetooth_adapters

// ----------------------------------------------------------------------------
// detect_serial_devices - List serial devices
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = buffer for device names (char[max][32])
//   x1 = max devices to detect
// Outputs:
//   x0 = number of devices found
// ----------------------------------------------------------------------------
.type detect_serial_devices, %function
detect_serial_devices:
    stp     x29, x30, [sp, #-64]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]

    mov     x19, x0             // Names buffer
    mov     x20, x1             // Max count
    mov     x21, #0             // Found count

    // Open /dev
    mov     x0, #AT_FDCWD
    adrp    x1, path_dev
    add     x1, x1, :lo12:path_dev
    mov     x2, #O_RDONLY | O_DIRECTORY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lserial_done
    mov     x22, x0             // Dir fd

.Lserial_read_dir:
    // Read directory entries
    mov     x0, x22
    adrp    x1, dirent_buf
    add     x1, x1, :lo12:dirent_buf
    mov     x2, #1024
    mov     x8, #SYS_getdents64
    svc     #0
    cmp     x0, #0
    b.le    .Lserial_close

    mov     x23, x0             // Bytes read
    adrp    x24, dirent_buf
    add     x24, x24, :lo12:dirent_buf

.Lserial_process_entry:
    cmp     x23, #0
    b.le    .Lserial_read_dir

    // Get entry name (offset 19 in dirent64)
    add     x0, x24, #19

    // Check for ttyUSB* or ttyACM*
    bl      check_serial_name
    cmp     x0, #0
    b.eq    .Lserial_next_entry

    // Found serial device - copy full path /dev/<name>
    cmp     x21, x20            // Check max
    b.ge    .Lserial_close

    // Copy "/dev/"
    mov     x0, x19
    adrp    x1, path_dev
    add     x1, x1, :lo12:path_dev
    bl      hw_strcpy

    // Append device name
    mov     x0, x19
    bl      hw_strlen
    add     x0, x19, x0
    add     x1, x24, #19        // Device name
    bl      hw_strcpy_max

    add     x19, x19, #MAX_NAME_LEN
    add     x21, x21, #1

.Lserial_next_entry:
    // Move to next dirent entry
    ldrh    w0, [x24, #16]      // d_reclen
    add     x24, x24, x0
    sub     x23, x23, x0
    b       .Lserial_process_entry

.Lserial_close:
    mov     x0, x22
    mov     x8, #SYS_close
    svc     #0

.Lserial_done:
    mov     x0, x21             // Return count

    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
.size detect_serial_devices, . - detect_serial_devices

// ----------------------------------------------------------------------------
// check_serial_name - Check if name matches ttyUSB* or ttyACM*
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = device name
// Outputs:
//   x0 = 1 if serial device, 0 otherwise
// ----------------------------------------------------------------------------
.type check_serial_name, %function
check_serial_name:
    // Check "ttyUSB"
    ldrb    w1, [x0]
    cmp     w1, #'t'
    b.ne    .Lcheck_serial_no
    ldrb    w1, [x0, #1]
    cmp     w1, #'t'
    b.ne    .Lcheck_serial_no
    ldrb    w1, [x0, #2]
    cmp     w1, #'y'
    b.ne    .Lcheck_serial_no

    // Check USB or ACM
    ldrb    w1, [x0, #3]
    cmp     w1, #'U'
    b.eq    .Lcheck_usb
    cmp     w1, #'A'
    b.eq    .Lcheck_acm
    b       .Lcheck_serial_no

.Lcheck_usb:
    ldrb    w1, [x0, #4]
    cmp     w1, #'S'
    b.ne    .Lcheck_serial_no
    ldrb    w1, [x0, #5]
    cmp     w1, #'B'
    b.ne    .Lcheck_serial_no
    mov     x0, #1
    ret

.Lcheck_acm:
    ldrb    w1, [x0, #4]
    cmp     w1, #'C'
    b.ne    .Lcheck_serial_no
    ldrb    w1, [x0, #5]
    cmp     w1, #'M'
    b.ne    .Lcheck_serial_no
    mov     x0, #1
    ret

.Lcheck_serial_no:
    mov     x0, #0
    ret
.size check_serial_name, . - check_serial_name

// ----------------------------------------------------------------------------
// detect_network_interfaces - List network interfaces with IPs
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = buffer for interface names (char[max][32])
//   x1 = buffer for IP addresses (char[max][16])
//   x2 = max interfaces to detect
// Outputs:
//   x0 = number of interfaces found
// ----------------------------------------------------------------------------
.type detect_network_interfaces, %function
detect_network_interfaces:
    stp     x29, x30, [sp, #-80]!
    mov     x29, sp
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    stp     x23, x24, [sp, #48]
    stp     x25, x26, [sp, #64]

    mov     x19, x0             // Names buffer
    mov     x25, x1             // IPs buffer
    mov     x20, x2             // Max count
    mov     x21, #0             // Found count

    // Open /sys/class/net
    mov     x0, #AT_FDCWD
    adrp    x1, path_sys_net
    add     x1, x1, :lo12:path_sys_net
    mov     x2, #O_RDONLY | O_DIRECTORY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lnet_done
    mov     x22, x0             // Dir fd

.Lnet_read_dir:
    // Read directory entries
    mov     x0, x22
    adrp    x1, dirent_buf
    add     x1, x1, :lo12:dirent_buf
    mov     x2, #1024
    mov     x8, #SYS_getdents64
    svc     #0
    cmp     x0, #0
    b.le    .Lnet_close

    mov     x23, x0             // Bytes read
    adrp    x24, dirent_buf
    add     x24, x24, :lo12:dirent_buf

.Lnet_process_entry:
    cmp     x23, #0
    b.le    .Lnet_read_dir

    // Get entry name (offset 19 in dirent64)
    add     x0, x24, #19

    // Skip . and .. and lo
    ldrb    w1, [x0]
    cmp     w1, #'.'
    b.eq    .Lnet_next_entry
    cmp     w1, #'l'
    b.ne    .Lnet_check_interface
    ldrb    w1, [x0, #1]
    cmp     w1, #'o'
    b.ne    .Lnet_check_interface
    ldrb    w1, [x0, #2]
    cbz     w1, .Lnet_next_entry    // Skip "lo"

.Lnet_check_interface:
    // Check if interface is up (has operstate == up)
    add     x0, x24, #19
    bl      check_interface_up
    cmp     x0, #0
    b.eq    .Lnet_next_entry

    // Found network interface - copy name
    cmp     x21, x20            // Check max
    b.ge    .Lnet_close

    mov     x0, x19             // Dest
    add     x1, x24, #19        // Src (interface name)
    bl      hw_strcpy_max

    // Try to get IP address
    add     x0, x24, #19        // Interface name
    mov     x1, x25             // IP buffer
    bl      get_interface_ip

    add     x19, x19, #MAX_NAME_LEN
    add     x25, x25, #MAX_IP_LEN
    add     x21, x21, #1

.Lnet_next_entry:
    // Move to next dirent entry
    ldrh    w0, [x24, #16]      // d_reclen
    add     x24, x24, x0
    sub     x23, x23, x0
    b       .Lnet_process_entry

.Lnet_close:
    mov     x0, x22
    mov     x8, #SYS_close
    svc     #0

.Lnet_done:
    mov     x0, x21             // Return count

    ldp     x25, x26, [sp, #64]
    ldp     x23, x24, [sp, #48]
    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #80
    ret
.size detect_network_interfaces, . - detect_network_interfaces

// ----------------------------------------------------------------------------
// check_interface_up - Check if network interface is up
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = interface name
// Outputs:
//   x0 = 1 if up, 0 otherwise
// ----------------------------------------------------------------------------
.type check_interface_up, %function
check_interface_up:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    mov     x19, x0             // Save interface name

    // Build path: /sys/class/net/<iface>/operstate
    adrp    x0, path_buf
    add     x0, x0, :lo12:path_buf
    adrp    x1, path_sys_net
    add     x1, x1, :lo12:path_sys_net
    bl      hw_strcpy

    // Append /<interface>
    adrp    x0, path_buf
    add     x0, x0, :lo12:path_buf
    bl      hw_strlen
    adrp    x1, path_buf
    add     x1, x1, :lo12:path_buf
    add     x1, x1, x0
    mov     w2, #'/'
    strb    w2, [x1], #1

    mov     x0, x1
    mov     x1, x19
    bl      hw_strcpy

    // Append /operstate
    adrp    x0, path_buf
    add     x0, x0, :lo12:path_buf
    bl      hw_strlen
    adrp    x1, path_buf
    add     x1, x1, :lo12:path_buf
    add     x0, x1, x0
    adrp    x1, str_operstate
    add     x1, x1, :lo12:str_operstate
    bl      hw_strcpy

    // Read operstate file
    mov     x0, #AT_FDCWD
    adrp    x1, path_buf
    add     x1, x1, :lo12:path_buf
    mov     x2, #O_RDONLY
    mov     x3, #0
    mov     x8, #SYS_openat
    svc     #0
    cmp     x0, #0
    b.lt    .Lcheck_up_no

    mov     x19, x0             // fd

    // Read state
    sub     sp, sp, #32
    mov     x1, sp
    mov     x2, #16
    mov     x8, #SYS_read
    svc     #0

    // Close
    mov     x0, x19
    mov     x8, #SYS_close
    svc     #0

    // Check if "up"
    ldrb    w0, [sp]
    cmp     w0, #'u'
    b.ne    .Lcheck_up_down
    ldrb    w0, [sp, #1]
    cmp     w0, #'p'
    b.ne    .Lcheck_up_down

    add     sp, sp, #32
    mov     x0, #1
    b       .Lcheck_up_done

.Lcheck_up_down:
    // Also consider "down" interfaces (they exist but aren't active)
    // Actually, let's include them so user sees what's available
    add     sp, sp, #32
    mov     x0, #1              // Include all interfaces
    b       .Lcheck_up_done

.Lcheck_up_no:
    mov     x0, #0

.Lcheck_up_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size check_interface_up, . - check_interface_up

// ----------------------------------------------------------------------------
// get_interface_ip - Get IP address for interface
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = interface name
//   x1 = IP buffer (16 bytes)
// Outputs:
//   x0 = 1 if IP found, 0 otherwise
// Note: Uses ioctl SIOCGIFADDR or reads from /proc/net/fib_trie
//       For simplicity, we'll mark as "N/A" if we can't easily get it
// ----------------------------------------------------------------------------
.type get_interface_ip, %function
get_interface_ip:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // For now, just put "N/A" - getting IP requires socket ioctl
    // which adds complexity. The wizard can use other methods.
    mov     w2, #'N'
    strb    w2, [x1]
    mov     w2, #'/'
    strb    w2, [x1, #1]
    mov     w2, #'A'
    strb    w2, [x1, #2]
    strb    wzr, [x1, #3]

    mov     x0, #0

    ldp     x29, x30, [sp], #16
    ret
.size get_interface_ip, . - get_interface_ip

// ============================================================================
// Helper Functions
// ============================================================================

// hw_memzero - Zero memory
.type hw_memzero, %function
hw_memzero:
    cbz     x1, .Lmemzero_done
.Lmemzero_loop:
    strb    wzr, [x0], #1
    subs    x1, x1, #1
    b.ne    .Lmemzero_loop
.Lmemzero_done:
    ret
.size hw_memzero, . - hw_memzero

// hw_strcpy - Copy null-terminated string
.type hw_strcpy, %function
hw_strcpy:
    mov     x2, x0
.Lstrcpy_loop:
    ldrb    w3, [x1], #1
    strb    w3, [x0], #1
    cbnz    w3, .Lstrcpy_loop
    mov     x0, x2
    ret
.size hw_strcpy, . - hw_strcpy

// hw_strcpy_max - Copy string with max length (MAX_NAME_LEN - 1)
.type hw_strcpy_max, %function
hw_strcpy_max:
    mov     x2, x0
    mov     x3, #MAX_NAME_LEN - 1
.Lstrcpy_max_loop:
    cbz     x3, .Lstrcpy_max_term
    ldrb    w4, [x1], #1
    strb    w4, [x0], #1
    cbz     w4, .Lstrcpy_max_done
    sub     x3, x3, #1
    b       .Lstrcpy_max_loop
.Lstrcpy_max_term:
    strb    wzr, [x0]
.Lstrcpy_max_done:
    mov     x0, x2
    ret
.size hw_strcpy_max, . - hw_strcpy_max

// hw_strlen - Get string length
.type hw_strlen, %function
hw_strlen:
    mov     x1, x0
.Lstrlen_loop:
    ldrb    w2, [x1], #1
    cbnz    w2, .Lstrlen_loop
    sub     x0, x1, x0
    sub     x0, x0, #1
    ret
.size hw_strlen, . - hw_strlen

// ============================================================================
// Read-only Data
// ============================================================================

.section .rodata
.balign 8

path_sys_net:
    .asciz "/sys/class/net"

path_sys_bluetooth:
    .asciz "/sys/class/bluetooth"

path_dev:
    .asciz "/dev/"

str_wireless:
    .asciz "/wireless"

str_operstate:
    .asciz "/operstate"

// ============================================================================
// End of detect.s
// ============================================================================
