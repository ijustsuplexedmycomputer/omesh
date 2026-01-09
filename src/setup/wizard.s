// Setup Wizard Logic
// src/setup/wizard.s
//
// Interactive setup wizard with three modes:
//   - Easy: Automatic configuration with smart defaults
//   - Guided: Step-by-step with explanations
//   - Advanced: Full manual configuration
//
// Functions:
//   wizard_run       - Entry point, shows mode selection
//   wizard_easy      - Automatic setup with 4-5 questions
//   wizard_guided    - Step-by-step interactive setup
//   wizard_advanced  - Full configuration options
//   wizard_summary   - Display final configuration
//   wizard_confirm   - Confirm and save configuration

.include "include/syscall_nums.inc"
.include "include/setup.inc"

// External functions - UI
.extern ui_clear
.extern ui_print
.extern ui_println
.extern ui_print_header
.extern ui_print_menu
.extern ui_print_line
.extern ui_prompt_string
.extern ui_prompt_int
.extern ui_prompt_choice
.extern ui_prompt_yesno
.extern ui_bold_on
.extern ui_bold_off
.extern ui_color
.extern ui_color_reset

// External functions - Config
.extern config_init
.extern config_load
.extern config_save
.extern config_set
.extern config_get

// External functions - Hardware detection
.extern detect_all_hardware
.extern g_hw_info

// External functions - HAL
.extern hal_init

.global wizard_run
.global wizard_easy
.global wizard_guided
.global wizard_advanced
.global wizard_summary
.global wizard_confirm

// ============================================================================
// Constants
// ============================================================================

.equ HW_INFO_FLAGS,         0
.equ HW_INFO_WIFI_COUNT,    4
.equ HW_INFO_BT_COUNT,      8
.equ HW_INFO_SERIAL_COUNT,  12
.equ HW_INFO_NET_COUNT,     16
.equ HW_INFO_WIFI_NAMES,    20
.equ HW_INFO_BT_NAMES,      284
.equ HW_INFO_SERIAL_NAMES,  540
.equ HW_INFO_NET_NAMES,     796

.equ MAX_NAME_LEN,          32
.equ INPUT_BUF_SIZE,        128

// ============================================================================
// BSS Section
// ============================================================================

.section .bss
.align 8

// Wizard state
wizard_mode:
    .skip 4

// Temporary buffers
node_name_buf:
    .skip 64

transport_buf:
    .skip 32

port_buf:
    .skip 16

// ============================================================================
// Text Section
// ============================================================================

.section .text

// ----------------------------------------------------------------------------
// wizard_run - Main wizard entry point
// ----------------------------------------------------------------------------
// Outputs:
//   x0 = 0 on success, negative on error/cancel
// ----------------------------------------------------------------------------
.type wizard_run, %function
wizard_run:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    // Initialize HAL
    bl      hal_init

    // Initialize config system
    bl      config_init

    // Detect hardware
    bl      detect_all_hardware
    mov     x19, x0             // Save hw_info pointer

    // Clear screen and show welcome
    bl      ui_clear

    adrp    x0, str_wizard_title
    add     x0, x0, :lo12:str_wizard_title
    bl      ui_print_header

    adrp    x0, str_welcome
    add     x0, x0, :lo12:str_welcome
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Show detected hardware summary
    bl      wizard_show_hardware

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Ask for setup mode
    adrp    x0, str_mode_prompt
    add     x0, x0, :lo12:str_mode_prompt
    adrp    x1, mode_options
    add     x1, x1, :lo12:mode_options
    mov     x2, #3
    bl      ui_prompt_choice

    // Store mode
    adrp    x1, wizard_mode
    add     x1, x1, :lo12:wizard_mode
    str     w0, [x1]

    // Branch to appropriate wizard
    cmp     w0, #0
    b.eq    .Lwizard_easy
    cmp     w0, #1
    b.eq    .Lwizard_guided
    b       .Lwizard_advanced

.Lwizard_easy:
    bl      wizard_easy
    b       .Lwizard_done

.Lwizard_guided:
    bl      wizard_guided
    b       .Lwizard_done

.Lwizard_advanced:
    bl      wizard_advanced

.Lwizard_done:
    // Show summary and confirm
    bl      wizard_summary
    bl      wizard_confirm

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size wizard_run, . - wizard_run

// ----------------------------------------------------------------------------
// wizard_show_hardware - Display detected hardware summary
// ----------------------------------------------------------------------------
.type wizard_show_hardware, %function
wizard_show_hardware:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    adrp    x19, g_hw_info
    add     x19, x19, :lo12:g_hw_info

    adrp    x0, str_hw_header
    add     x0, x0, :lo12:str_hw_header
    bl      ui_println

    // WiFi
    ldr     w0, [x19, #HW_INFO_WIFI_COUNT]
    cbz     w0, .Lhw_check_bt

    adrp    x0, str_hw_wifi
    add     x0, x0, :lo12:str_hw_wifi
    bl      ui_print

    // Print first WiFi interface name
    add     x0, x19, #HW_INFO_WIFI_NAMES
    bl      ui_println

.Lhw_check_bt:
    // Bluetooth
    ldr     w0, [x19, #HW_INFO_BT_COUNT]
    cbz     w0, .Lhw_check_serial

    adrp    x0, str_hw_bt
    add     x0, x0, :lo12:str_hw_bt
    bl      ui_print

    add     x0, x19, #HW_INFO_BT_NAMES
    bl      ui_println

.Lhw_check_serial:
    // Serial
    ldr     w0, [x19, #HW_INFO_SERIAL_COUNT]
    cbz     w0, .Lhw_check_net

    adrp    x0, str_hw_serial
    add     x0, x0, :lo12:str_hw_serial
    bl      ui_print

    add     x0, x19, #HW_INFO_SERIAL_NAMES
    bl      ui_println

.Lhw_check_net:
    // Network
    ldr     w0, [x19, #HW_INFO_NET_COUNT]
    cbz     w0, .Lhw_done

    adrp    x0, str_hw_net
    add     x0, x0, :lo12:str_hw_net
    bl      ui_print

    add     x0, x19, #HW_INFO_NET_NAMES
    bl      ui_println

.Lhw_done:
    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size wizard_show_hardware, . - wizard_show_hardware

// ----------------------------------------------------------------------------
// wizard_easy - Use-case focused setup with smart presets
// ----------------------------------------------------------------------------
// Asks what the user wants to use Omesh for, applies appropriate presets
// ----------------------------------------------------------------------------
.type wizard_easy, %function
wizard_easy:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    bl      ui_clear

    adrp    x0, str_easy_title
    add     x0, x0, :lo12:str_easy_title
    bl      ui_print_header

    adrp    x0, str_easy_intro_new
    add     x0, x0, :lo12:str_easy_intro_new
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Question 1: What do you want to use Omesh for?
    adrp    x0, str_q_usecase
    add     x0, x0, :lo12:str_q_usecase
    adrp    x1, usecase_options
    add     x1, x1, :lo12:usecase_options
    mov     x2, #5
    bl      ui_prompt_choice

    mov     x19, x0             // Save choice (0-4)

    // Apply preset based on choice
    cmp     x19, #0
    b.eq    .Leasy_personal
    cmp     x19, #1
    b.eq    .Leasy_home
    cmp     x19, #2
    b.eq    .Leasy_bridge
    cmp     x19, #3
    b.eq    .Leasy_community
    b       .Leasy_offgrid

// ============ PERSONAL DEVICE preset ============
.Leasy_personal:
    // Set node_role=personal
    adrp    x0, key_node_role
    add     x0, x0, :lo12:key_node_role
    adrp    x1, val_personal
    add     x1, x1, :lo12:val_personal
    bl      config_set

    // transports=bluetooth,wifi-mesh
    adrp    x0, key_transports
    add     x0, x0, :lo12:key_transports
    adrp    x1, val_trans_personal
    add     x1, x1, :lo12:val_trans_personal
    bl      config_set

    // store_others_data=no
    adrp    x0, key_store_others
    add     x0, x0, :lo12:key_store_others
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // relay_for_others=no
    adrp    x0, key_relay
    add     x0, x0, :lo12:key_relay
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // discoverable=no
    adrp    x0, key_discoverable
    add     x0, x0, :lo12:key_discoverable
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // use_internet=no
    adrp    x0, key_use_internet
    add     x0, x0, :lo12:key_use_internet
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // http_enabled=true
    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set

    // Follow-up: Device name
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    adrp    x0, str_q_device_name
    add     x0, x0, :lo12:str_q_device_name
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    mov     x2, #64
    bl      ui_prompt_string

    cbz     x0, .Leasy_personal_default_name
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    bl      config_set
    b       .Leasy_finalize

.Leasy_personal_default_name:
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, default_personal_name
    add     x1, x1, :lo12:default_personal_name
    bl      config_set
    b       .Leasy_finalize

// ============ HOME NETWORK preset ============
.Leasy_home:
    // Set node_role=home
    adrp    x0, key_node_role
    add     x0, x0, :lo12:key_node_role
    adrp    x1, val_home
    add     x1, x1, :lo12:val_home
    bl      config_set

    // transports=tcp
    adrp    x0, key_transports
    add     x0, x0, :lo12:key_transports
    adrp    x1, val_tcp
    add     x1, x1, :lo12:val_tcp
    bl      config_set

    // store_others_data=replicate
    adrp    x0, key_store_others
    add     x0, x0, :lo12:key_store_others
    adrp    x1, val_replicate
    add     x1, x1, :lo12:val_replicate
    bl      config_set

    // relay_for_others=no
    adrp    x0, key_relay
    add     x0, x0, :lo12:key_relay
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // discoverable=no
    adrp    x0, key_discoverable
    add     x0, x0, :lo12:key_discoverable
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // use_internet=no
    adrp    x0, key_use_internet
    add     x0, x0, :lo12:key_use_internet
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // http_enabled=true
    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set

    // Follow-up: Network name
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    adrp    x0, str_q_network_name
    add     x0, x0, :lo12:str_q_network_name
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    mov     x2, #64
    bl      ui_prompt_string

    cbz     x0, .Leasy_home_default_net
    adrp    x0, key_network_name
    add     x0, x0, :lo12:key_network_name
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    bl      config_set
    b       .Leasy_home_first

.Leasy_home_default_net:
    adrp    x0, key_network_name
    add     x0, x0, :lo12:key_network_name
    adrp    x1, default_network_name
    add     x1, x1, :lo12:default_network_name
    bl      config_set

.Leasy_home_first:
    // Ask: Is this the first device?
    adrp    x0, str_q_first_device
    add     x0, x0, :lo12:str_q_first_device
    mov     x1, #1              // Default yes
    bl      ui_prompt_yesno

    cbnz    x0, .Leasy_home_set_name  // First device, skip peer

    // Not first - ask for existing device
    adrp    x0, str_q_existing_peer
    add     x0, x0, :lo12:str_q_existing_peer
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    mov     x2, #64
    bl      ui_prompt_string

    cbz     x0, .Leasy_home_set_name  // Empty, skip

    adrp    x0, key_trusted_peers
    add     x0, x0, :lo12:key_trusted_peers
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    bl      config_set

.Leasy_home_set_name:
    // Set default node name
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, default_home_name
    add     x1, x1, :lo12:default_home_name
    bl      config_set
    b       .Leasy_finalize

// ============ BRIDGE TO FRIEND preset ============
.Leasy_bridge:
    // Set node_role=bridge
    adrp    x0, key_node_role
    add     x0, x0, :lo12:key_node_role
    adrp    x1, val_bridge
    add     x1, x1, :lo12:val_bridge
    bl      config_set

    // transports=tcp
    adrp    x0, key_transports
    add     x0, x0, :lo12:key_transports
    adrp    x1, val_tcp
    add     x1, x1, :lo12:val_tcp
    bl      config_set

    // store_others_data=no
    adrp    x0, key_store_others
    add     x0, x0, :lo12:key_store_others
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // relay_for_others=yes
    adrp    x0, key_relay
    add     x0, x0, :lo12:key_relay
    adrp    x1, val_yes
    add     x1, x1, :lo12:val_yes
    bl      config_set

    // discoverable=no
    adrp    x0, key_discoverable
    add     x0, x0, :lo12:key_discoverable
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // use_internet=yes
    adrp    x0, key_use_internet
    add     x0, x0, :lo12:key_use_internet
    adrp    x1, val_yes
    add     x1, x1, :lo12:val_yes
    bl      config_set

    // http_enabled=true
    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set

    // Follow-up: Friend's address
    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    adrp    x0, str_q_friend_addr
    add     x0, x0, :lo12:str_q_friend_addr
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    mov     x2, #64
    bl      ui_prompt_string

    cbz     x0, .Leasy_bridge_set_name

    adrp    x0, key_trusted_peers
    add     x0, x0, :lo12:key_trusted_peers
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    bl      config_set

.Leasy_bridge_set_name:
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, default_bridge_name
    add     x1, x1, :lo12:default_bridge_name
    bl      config_set
    b       .Leasy_finalize

// ============ COMMUNITY NODE preset ============
.Leasy_community:
    // Set node_role=community
    adrp    x0, key_node_role
    add     x0, x0, :lo12:key_node_role
    adrp    x1, val_community
    add     x1, x1, :lo12:val_community
    bl      config_set

    // transports=tcp,bluetooth,wifi-mesh
    adrp    x0, key_transports
    add     x0, x0, :lo12:key_transports
    adrp    x1, val_trans_community
    add     x1, x1, :lo12:val_trans_community
    bl      config_set

    // store_others_data=cache
    adrp    x0, key_store_others
    add     x0, x0, :lo12:key_store_others
    adrp    x1, val_cache
    add     x1, x1, :lo12:val_cache
    bl      config_set

    // relay_for_others=yes
    adrp    x0, key_relay
    add     x0, x0, :lo12:key_relay
    adrp    x1, val_yes
    add     x1, x1, :lo12:val_yes
    bl      config_set

    // discoverable=yes
    adrp    x0, key_discoverable
    add     x0, x0, :lo12:key_discoverable
    adrp    x1, val_yes
    add     x1, x1, :lo12:val_yes
    bl      config_set

    // use_internet=backup
    adrp    x0, key_use_internet
    add     x0, x0, :lo12:key_use_internet
    adrp    x1, val_backup
    add     x1, x1, :lo12:val_backup
    bl      config_set

    // http_enabled=true
    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set

    // Set default node name
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, default_community_name
    add     x1, x1, :lo12:default_community_name
    bl      config_set
    b       .Leasy_finalize

// ============ OFF-GRID ONLY preset ============
.Leasy_offgrid:
    // Set node_role=offgrid
    adrp    x0, key_node_role
    add     x0, x0, :lo12:key_node_role
    adrp    x1, val_offgrid
    add     x1, x1, :lo12:val_offgrid
    bl      config_set

    // transports=bluetooth,wifi-mesh
    adrp    x0, key_transports
    add     x0, x0, :lo12:key_transports
    adrp    x1, val_trans_personal
    add     x1, x1, :lo12:val_trans_personal
    bl      config_set

    // store_others_data=no
    adrp    x0, key_store_others
    add     x0, x0, :lo12:key_store_others
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // relay_for_others=yes
    adrp    x0, key_relay
    add     x0, x0, :lo12:key_relay
    adrp    x1, val_yes
    add     x1, x1, :lo12:val_yes
    bl      config_set

    // discoverable=yes
    adrp    x0, key_discoverable
    add     x0, x0, :lo12:key_discoverable
    adrp    x1, val_yes
    add     x1, x1, :lo12:val_yes
    bl      config_set

    // use_internet=no
    adrp    x0, key_use_internet
    add     x0, x0, :lo12:key_use_internet
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

    // http_enabled=true
    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set

    // Set default node name
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, default_offgrid_name
    add     x1, x1, :lo12:default_offgrid_name
    bl      config_set

.Leasy_finalize:
    // Set common defaults
    // wal_enabled=true
    adrp    x0, key_wal_enabled
    add     x0, x0, :lo12:key_wal_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set

    // http_port=8080
    adrp    x0, key_http_port
    add     x0, x0, :lo12:key_http_port
    adrp    x1, val_http_port_default
    add     x1, x1, :lo12:val_http_port_default
    bl      config_set

    // Set remaining defaults
    bl      wizard_set_defaults

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    adrp    x0, str_easy_done
    add     x0, x0, :lo12:str_easy_done
    bl      ui_println

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size wizard_easy, . - wizard_easy

// ----------------------------------------------------------------------------
// wizard_guided - Step-by-step interactive setup
// ----------------------------------------------------------------------------
.type wizard_guided, %function
wizard_guided:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    bl      ui_clear

    adrp    x0, str_guided_title
    add     x0, x0, :lo12:str_guided_title
    bl      ui_print_header

    // Step 1: Node Configuration
    adrp    x0, str_step1_title
    add     x0, x0, :lo12:str_step1_title
    bl      ui_println

    adrp    x0, str_step1_desc
    add     x0, x0, :lo12:str_step1_desc
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Node name
    adrp    x0, str_q_node_name
    add     x0, x0, :lo12:str_q_node_name
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    mov     x2, #64
    bl      ui_prompt_string

    cbz     x0, .Lguided_default_name
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    bl      config_set
    b       .Lguided_step2

.Lguided_default_name:
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, default_node_name
    add     x1, x1, :lo12:default_node_name
    bl      config_set

.Lguided_step2:
    bl      ui_print_line

    // Step 2: Network Configuration
    adrp    x0, str_step2_title
    add     x0, x0, :lo12:str_step2_title
    bl      ui_println

    adrp    x0, str_step2_desc
    add     x0, x0, :lo12:str_step2_desc
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Transport selection
    adrp    x0, str_q_transport_guided
    add     x0, x0, :lo12:str_q_transport_guided
    adrp    x1, transport_options
    add     x1, x1, :lo12:transport_options
    mov     x2, #4
    bl      ui_prompt_choice

    adrp    x1, transport_values
    add     x1, x1, :lo12:transport_values
    ldr     x1, [x1, x0, lsl #3]

    adrp    x0, key_transport
    add     x0, x0, :lo12:key_transport
    bl      config_set

    // Bind port
    adrp    x0, str_q_bind_port
    add     x0, x0, :lo12:str_q_bind_port
    mov     x1, #7777
    bl      ui_prompt_int

    bl      wizard_int_to_str
    mov     x1, x0
    adrp    x0, key_bind_port
    add     x0, x0, :lo12:key_bind_port
    bl      config_set

.Lguided_step3:
    bl      ui_print_line

    // Step 3: Storage Configuration
    adrp    x0, str_step3_title
    add     x0, x0, :lo12:str_step3_title
    bl      ui_println

    adrp    x0, str_step3_desc
    add     x0, x0, :lo12:str_step3_desc
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // WAL enabled
    adrp    x0, str_q_wal_guided
    add     x0, x0, :lo12:str_q_wal_guided
    mov     x1, #1
    bl      ui_prompt_yesno

    cbz     x0, .Lguided_wal_no

    adrp    x0, key_wal_enabled
    add     x0, x0, :lo12:key_wal_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set
    b       .Lguided_step4

.Lguided_wal_no:
    adrp    x0, key_wal_enabled
    add     x0, x0, :lo12:key_wal_enabled
    adrp    x1, val_false
    add     x1, x1, :lo12:val_false
    bl      config_set

.Lguided_step4:
    bl      ui_print_line

    // Step 4: HTTP API Configuration
    adrp    x0, str_step4_title
    add     x0, x0, :lo12:str_step4_title
    bl      ui_println

    adrp    x0, str_step4_desc
    add     x0, x0, :lo12:str_step4_desc
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // HTTP enabled
    adrp    x0, str_q_http_guided
    add     x0, x0, :lo12:str_q_http_guided
    mov     x1, #1
    bl      ui_prompt_yesno

    cbz     x0, .Lguided_http_no

    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set

    // HTTP port
    adrp    x0, str_q_http_port
    add     x0, x0, :lo12:str_q_http_port
    mov     x1, #8080
    bl      ui_prompt_int

    bl      wizard_int_to_str
    mov     x1, x0
    adrp    x0, key_http_port
    add     x0, x0, :lo12:key_http_port
    bl      config_set
    b       .Lguided_step5

.Lguided_http_no:
    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    adrp    x1, val_false
    add     x1, x1, :lo12:val_false
    bl      config_set

.Lguided_step5:
    bl      ui_print_line

    // Step 5: Privacy & Network
    adrp    x0, str_step5_title
    add     x0, x0, :lo12:str_step5_title
    bl      ui_println

    adrp    x0, str_step5_desc
    add     x0, x0, :lo12:str_step5_desc
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Relay for others?
    adrp    x0, str_q_relay_guided
    add     x0, x0, :lo12:str_q_relay_guided
    mov     x1, #1                  // default yes
    bl      ui_prompt_yesno

    cbz     x0, .Lguided_relay_no

    adrp    x0, key_relay
    add     x0, x0, :lo12:key_relay
    adrp    x1, val_yes
    add     x1, x1, :lo12:val_yes
    bl      config_set
    b       .Lguided_discoverable

.Lguided_relay_no:
    adrp    x0, key_relay
    add     x0, x0, :lo12:key_relay
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

.Lguided_discoverable:
    // Discoverable?
    adrp    x0, str_q_discoverable_guided
    add     x0, x0, :lo12:str_q_discoverable_guided
    mov     x1, #1                  // default yes
    bl      ui_prompt_yesno

    cbz     x0, .Lguided_disc_no

    adrp    x0, key_discoverable
    add     x0, x0, :lo12:key_discoverable
    adrp    x1, val_yes
    add     x1, x1, :lo12:val_yes
    bl      config_set
    b       .Lguided_store_others

.Lguided_disc_no:
    adrp    x0, key_discoverable
    add     x0, x0, :lo12:key_discoverable
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set

.Lguided_store_others:
    // Store others' data?
    adrp    x0, str_q_store_others_guided
    add     x0, x0, :lo12:str_q_store_others_guided
    adrp    x1, store_others_options
    add     x1, x1, :lo12:store_others_options
    mov     x2, #3
    bl      ui_prompt_choice

    // Convert choice to value string
    cmp     x0, #0
    b.eq    .Lguided_store_no
    cmp     x0, #1
    b.eq    .Lguided_store_cache

    // Choice 2: replicate
    adrp    x0, key_store_others
    add     x0, x0, :lo12:key_store_others
    adrp    x1, val_replicate
    add     x1, x1, :lo12:val_replicate
    bl      config_set
    b       .Lguided_step6

.Lguided_store_no:
    adrp    x0, key_store_others
    add     x0, x0, :lo12:key_store_others
    adrp    x1, val_no
    add     x1, x1, :lo12:val_no
    bl      config_set
    b       .Lguided_step6

.Lguided_store_cache:
    adrp    x0, key_store_others
    add     x0, x0, :lo12:key_store_others
    adrp    x1, val_cache
    add     x1, x1, :lo12:val_cache
    bl      config_set

.Lguided_step6:
    bl      ui_print_line

    // Step 6: Node Role
    adrp    x0, str_step6_title
    add     x0, x0, :lo12:str_step6_title
    bl      ui_println

    adrp    x0, str_step6_desc
    add     x0, x0, :lo12:str_step6_desc
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Role selection
    adrp    x0, str_q_role_guided
    add     x0, x0, :lo12:str_q_role_guided
    adrp    x1, role_options_guided
    add     x1, x1, :lo12:role_options_guided
    mov     x2, #4
    bl      ui_prompt_choice

    // Convert choice to role value
    cmp     x0, #0
    b.eq    .Lguided_role_personal
    cmp     x0, #1
    b.eq    .Lguided_role_home
    cmp     x0, #2
    b.eq    .Lguided_role_bridge

    // Choice 3: community
    adrp    x0, key_node_role
    add     x0, x0, :lo12:key_node_role
    adrp    x1, val_community
    add     x1, x1, :lo12:val_community
    bl      config_set
    b       .Lguided_done

.Lguided_role_personal:
    adrp    x0, key_node_role
    add     x0, x0, :lo12:key_node_role
    adrp    x1, val_personal
    add     x1, x1, :lo12:val_personal
    bl      config_set
    b       .Lguided_done

.Lguided_role_home:
    adrp    x0, key_node_role
    add     x0, x0, :lo12:key_node_role
    adrp    x1, val_home
    add     x1, x1, :lo12:val_home
    bl      config_set
    b       .Lguided_done

.Lguided_role_bridge:
    adrp    x0, key_node_role
    add     x0, x0, :lo12:key_node_role
    adrp    x1, val_bridge
    add     x1, x1, :lo12:val_bridge
    bl      config_set

.Lguided_done:
    bl      wizard_set_defaults

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    adrp    x0, str_guided_done
    add     x0, x0, :lo12:str_guided_done
    bl      ui_println

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size wizard_guided, . - wizard_guided

// ----------------------------------------------------------------------------
// wizard_advanced - Full manual configuration
// ----------------------------------------------------------------------------
.type wizard_advanced, %function
wizard_advanced:
    stp     x29, x30, [sp, #-32]!
    mov     x29, sp
    str     x19, [sp, #16]

    bl      ui_clear

    adrp    x0, str_advanced_title
    add     x0, x0, :lo12:str_advanced_title
    bl      ui_print_header

    adrp    x0, str_advanced_intro
    add     x0, x0, :lo12:str_advanced_intro
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // All the same questions as guided, plus more
    // Node name
    adrp    x0, str_q_node_name
    add     x0, x0, :lo12:str_q_node_name
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    mov     x2, #64
    bl      ui_prompt_string

    cbz     x0, .Ladv_default_name
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    bl      config_set
    b       .Ladv_transport

.Ladv_default_name:
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    adrp    x1, default_node_name
    add     x1, x1, :lo12:default_node_name
    bl      config_set

.Ladv_transport:
    // Transport
    adrp    x0, str_q_transport
    add     x0, x0, :lo12:str_q_transport
    adrp    x1, transport_options_full
    add     x1, x1, :lo12:transport_options_full
    mov     x2, #6
    bl      ui_prompt_choice

    adrp    x1, transport_values_full
    add     x1, x1, :lo12:transport_values_full
    ldr     x1, [x1, x0, lsl #3]

    adrp    x0, key_transport
    add     x0, x0, :lo12:key_transport
    bl      config_set

    // Bind address
    adrp    x0, str_q_bind_addr
    add     x0, x0, :lo12:str_q_bind_addr
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    mov     x2, #64
    bl      ui_prompt_string

    cbz     x0, .Ladv_default_addr
    adrp    x0, key_bind_addr
    add     x0, x0, :lo12:key_bind_addr
    adrp    x1, node_name_buf
    add     x1, x1, :lo12:node_name_buf
    bl      config_set
    b       .Ladv_bind_port

.Ladv_default_addr:
    adrp    x0, key_bind_addr
    add     x0, x0, :lo12:key_bind_addr
    adrp    x1, default_bind_addr
    add     x1, x1, :lo12:default_bind_addr
    bl      config_set

.Ladv_bind_port:
    // Bind port
    adrp    x0, str_q_bind_port
    add     x0, x0, :lo12:str_q_bind_port
    mov     x1, #7777
    bl      ui_prompt_int

    bl      wizard_int_to_str
    mov     x1, x0
    adrp    x0, key_bind_port
    add     x0, x0, :lo12:key_bind_port
    bl      config_set

    // Replication factor
    adrp    x0, str_q_replication
    add     x0, x0, :lo12:str_q_replication
    mov     x1, #1
    bl      ui_prompt_int

    bl      wizard_int_to_str
    mov     x1, x0
    adrp    x0, key_replication
    add     x0, x0, :lo12:key_replication
    bl      config_set

    // WAL
    adrp    x0, str_q_wal
    add     x0, x0, :lo12:str_q_wal
    mov     x1, #1
    bl      ui_prompt_yesno

    cbz     x0, .Ladv_wal_no
    adrp    x0, key_wal_enabled
    add     x0, x0, :lo12:key_wal_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set
    b       .Ladv_http

.Ladv_wal_no:
    adrp    x0, key_wal_enabled
    add     x0, x0, :lo12:key_wal_enabled
    adrp    x1, val_false
    add     x1, x1, :lo12:val_false
    bl      config_set

.Ladv_http:
    // HTTP
    adrp    x0, str_q_http
    add     x0, x0, :lo12:str_q_http
    mov     x1, #1
    bl      ui_prompt_yesno

    cbz     x0, .Ladv_http_no

    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    adrp    x1, val_true
    add     x1, x1, :lo12:val_true
    bl      config_set

    adrp    x0, str_q_http_port
    add     x0, x0, :lo12:str_q_http_port
    mov     x1, #8080
    bl      ui_prompt_int

    bl      wizard_int_to_str
    mov     x1, x0
    adrp    x0, key_http_port
    add     x0, x0, :lo12:key_http_port
    bl      config_set
    b       .Ladv_done

.Ladv_http_no:
    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    adrp    x1, val_false
    add     x1, x1, :lo12:val_false
    bl      config_set

.Ladv_done:
    bl      wizard_set_defaults

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    adrp    x0, str_advanced_done
    add     x0, x0, :lo12:str_advanced_done
    bl      ui_println

    ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret
.size wizard_advanced, . - wizard_advanced

// ----------------------------------------------------------------------------
// wizard_summary - Display configuration summary
// ----------------------------------------------------------------------------
.type wizard_summary, %function
wizard_summary:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    bl      ui_print_line

    adrp    x0, str_summary_title
    add     x0, x0, :lo12:str_summary_title
    bl      ui_println

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    // Print each config value
    adrp    x0, str_sum_node
    add     x0, x0, :lo12:str_sum_node
    bl      ui_print
    adrp    x0, key_node_name
    add     x0, x0, :lo12:key_node_name
    bl      config_get
    cbz     x0, .Lsum_node_skip
    bl      ui_println
.Lsum_node_skip:

    adrp    x0, str_sum_transport
    add     x0, x0, :lo12:str_sum_transport
    bl      ui_print
    adrp    x0, key_transport
    add     x0, x0, :lo12:key_transport
    bl      config_get
    cbz     x0, .Lsum_trans_skip
    bl      ui_println
.Lsum_trans_skip:

    adrp    x0, str_sum_bind_port
    add     x0, x0, :lo12:str_sum_bind_port
    bl      ui_print
    adrp    x0, key_bind_port
    add     x0, x0, :lo12:key_bind_port
    bl      config_get
    cbz     x0, .Lsum_port_skip
    bl      ui_println
.Lsum_port_skip:

    adrp    x0, str_sum_http
    add     x0, x0, :lo12:str_sum_http
    bl      ui_print
    adrp    x0, key_http_enabled
    add     x0, x0, :lo12:key_http_enabled
    bl      config_get
    cbz     x0, .Lsum_http_skip
    bl      ui_println
.Lsum_http_skip:

    adrp    x0, str_sum_wal
    add     x0, x0, :lo12:str_sum_wal
    bl      ui_print
    adrp    x0, key_wal_enabled
    add     x0, x0, :lo12:key_wal_enabled
    bl      config_get
    cbz     x0, .Lsum_wal_skip
    bl      ui_println
.Lsum_wal_skip:

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    ldp     x29, x30, [sp], #16
    ret
.size wizard_summary, . - wizard_summary

// ----------------------------------------------------------------------------
// wizard_confirm - Confirm and save configuration
// ----------------------------------------------------------------------------
// Outputs:
//   x0 = 0 on success, -1 if cancelled
// ----------------------------------------------------------------------------
.type wizard_confirm, %function
wizard_confirm:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    adrp    x0, str_confirm_prompt
    add     x0, x0, :lo12:str_confirm_prompt
    mov     x1, #1              // Default yes
    bl      ui_prompt_yesno

    cbz     x0, .Lconfirm_cancel

    // Save configuration
    mov     x0, #0              // Use default path
    bl      config_save

    cmp     x0, #0
    b.lt    .Lconfirm_error

    adrp    x0, str_newline
    add     x0, x0, :lo12:str_newline
    bl      ui_print

    adrp    x0, str_saved
    add     x0, x0, :lo12:str_saved
    bl      ui_println

    mov     x0, #0
    b       .Lconfirm_done

.Lconfirm_error:
    adrp    x0, str_save_error
    add     x0, x0, :lo12:str_save_error
    bl      ui_println
    mov     x0, #-1
    b       .Lconfirm_done

.Lconfirm_cancel:
    adrp    x0, str_cancelled
    add     x0, x0, :lo12:str_cancelled
    bl      ui_println
    mov     x0, #-1

.Lconfirm_done:
    ldp     x29, x30, [sp], #16
    ret
.size wizard_confirm, . - wizard_confirm

// ----------------------------------------------------------------------------
// wizard_set_defaults - Set default values for unset config options
// ----------------------------------------------------------------------------
.type wizard_set_defaults, %function
wizard_set_defaults:
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp

    // Set data directory default
    adrp    x0, key_data_dir
    add     x0, x0, :lo12:key_data_dir
    bl      config_get
    cbnz    x0, .Ldefault_cluster

    adrp    x0, key_data_dir
    add     x0, x0, :lo12:key_data_dir
    adrp    x1, default_data_dir
    add     x1, x1, :lo12:default_data_dir
    bl      config_set

.Ldefault_cluster:
    // Set cluster name default
    adrp    x0, key_cluster_name
    add     x0, x0, :lo12:key_cluster_name
    bl      config_get
    cbnz    x0, .Ldefault_replication

    adrp    x0, key_cluster_name
    add     x0, x0, :lo12:key_cluster_name
    adrp    x1, default_cluster_name
    add     x1, x1, :lo12:default_cluster_name
    bl      config_set

.Ldefault_replication:
    // Set replication default
    adrp    x0, key_replication
    add     x0, x0, :lo12:key_replication
    bl      config_get
    cbnz    x0, .Ldefault_done

    adrp    x0, key_replication
    add     x0, x0, :lo12:key_replication
    adrp    x1, default_replication
    add     x1, x1, :lo12:default_replication
    bl      config_set

.Ldefault_done:
    ldp     x29, x30, [sp], #16
    ret
.size wizard_set_defaults, . - wizard_set_defaults

// ----------------------------------------------------------------------------
// wizard_int_to_str - Convert integer to string
// ----------------------------------------------------------------------------
// Inputs:
//   x0 = integer value
// Outputs:
//   x0 = pointer to string (static buffer)
// ----------------------------------------------------------------------------
.type wizard_int_to_str, %function
wizard_int_to_str:
    adrp    x1, port_buf
    add     x1, x1, :lo12:port_buf
    mov     x2, x1
    add     x2, x2, #15         // End of buffer

    // Handle 0
    cbnz    x0, .Lint_convert
    mov     w3, #'0'
    strb    w3, [x1]
    strb    wzr, [x1, #1]
    mov     x0, x1
    ret

.Lint_convert:
    strb    wzr, [x2]           // Null terminate
    mov     x3, x0

.Lint_loop:
    cbz     x3, .Lint_done
    sub     x2, x2, #1
    mov     x4, #10
    udiv    x5, x3, x4
    msub    x6, x5, x4, x3      // x6 = x3 % 10
    add     w6, w6, #'0'
    strb    w6, [x2]
    mov     x3, x5
    b       .Lint_loop

.Lint_done:
    mov     x0, x2
    ret
.size wizard_int_to_str, . - wizard_int_to_str

// ============================================================================
// Read-only Data
// ============================================================================

.section .rodata
.balign 8

// Titles and headers
str_wizard_title:
    .asciz "Omesh Setup Wizard"

str_welcome:
    .asciz "Welcome to Omesh! This wizard will help you configure your node."

str_easy_title:
    .asciz "Easy Setup"

str_easy_intro:
    .asciz "Answering a few quick questions to get you started..."

str_guided_title:
    .asciz "Guided Setup"

str_advanced_title:
    .asciz "Advanced Setup"

str_advanced_intro:
    .asciz "Configure all available options..."

str_summary_title:
    .asciz "Configuration Summary"

// Hardware detection
str_hw_header:
    .asciz "Detected hardware:"

str_hw_wifi:
    .asciz "  WiFi: "

str_hw_bt:
    .asciz "  Bluetooth: "

str_hw_serial:
    .asciz "  Serial: "

str_hw_net:
    .asciz "  Network: "

// Mode selection
str_mode_prompt:
    .asciz "Choose setup mode:"

.balign 8
mode_options:
    .quad str_mode_easy
    .quad str_mode_guided
    .quad str_mode_advanced

str_mode_easy:
    .asciz "Easy - Quick setup with smart defaults (Recommended)"

str_mode_guided:
    .asciz "Guided - Step-by-step with explanations"

str_mode_advanced:
    .asciz "Advanced - Full manual configuration"

// New easy mode intro and use-case question
str_easy_intro_new:
    .asciz "Let's set up your node based on how you'll use it."

str_q_usecase:
    .asciz "What would you like to use Omesh for?"

// Use-case menu options
.balign 8
usecase_options:
    .quad str_usecase_personal
    .quad str_usecase_home
    .quad str_usecase_bridge
    .quad str_usecase_community
    .quad str_usecase_offgrid

str_usecase_personal:
    .asciz "PERSONAL - Just this device, connect to friends when nearby"

str_usecase_home:
    .asciz "HOME NETWORK - A few devices in my house working together"

str_usecase_bridge:
    .asciz "BRIDGE - Connect my network to a friend's network"

str_usecase_community:
    .asciz "COMMUNITY - Help connect my neighborhood mesh"

str_usecase_offgrid:
    .asciz "OFF-GRID - No internet, direct device connections only"

// Follow-up questions for each use case
str_q_device_name:
    .asciz "Give your device a name"

str_q_network_name:
    .asciz "Network name"

str_q_first_device:
    .asciz "Is this the first device on your network?"

str_q_existing_peer:
    .asciz "Enter existing device address (IP:port)"

str_q_friend_addr:
    .asciz "Friend's address (IP:port or hostname:port)"

// New config keys
key_node_role:
    .asciz "node_role"

key_transports:
    .asciz "transports"

key_store_others:
    .asciz "store_others_data"

key_relay:
    .asciz "relay_for_others"

key_discoverable:
    .asciz "discoverable"

key_use_internet:
    .asciz "use_internet"

key_network_name:
    .asciz "network_name"

key_trusted_peers:
    .asciz "trusted_peers"

// Node role values
val_personal:
    .asciz "personal"

val_home:
    .asciz "home"

val_bridge:
    .asciz "bridge"

val_community:
    .asciz "community"

val_offgrid:
    .asciz "offgrid"

// Data handling values
val_no:
    .asciz "no"

val_yes:
    .asciz "yes"

val_cache:
    .asciz "cache"

val_replicate:
    .asciz "replicate"

val_backup:
    .asciz "backup"

// Transport preset values
val_trans_personal:
    .asciz "bluetooth,wifi-mesh"

val_trans_community:
    .asciz "tcp,bluetooth,wifi-mesh"

// Default names for each role
default_personal_name:
    .asciz "my-device"

default_home_name:
    .asciz "home-node"

default_network_name:
    .asciz "home-mesh"

default_bridge_name:
    .asciz "bridge-node"

default_community_name:
    .asciz "community-node"

default_offgrid_name:
    .asciz "offgrid-node"

// Default port string
val_http_port_default:
    .asciz "8080"

// Questions
str_q_node_name:
    .asciz "Node name"

str_q_transport:
    .asciz "Transport type"

str_q_transport_guided:
    .asciz "Select network transport"

str_q_bind_addr:
    .asciz "Bind address"

str_q_bind_port:
    .asciz "Bind port"

str_q_http:
    .asciz "Enable HTTP API?"

str_q_http_guided:
    .asciz "Enable HTTP API for REST access?"

str_q_http_port:
    .asciz "HTTP port"

str_q_wal:
    .asciz "Enable write-ahead log (recommended for durability)?"

str_q_wal_guided:
    .asciz "Enable write-ahead log for crash recovery?"

str_q_replication:
    .asciz "Replication factor"

// Transport options
.balign 8
transport_options:
    .quad str_trans_tcp
    .quad str_trans_udp
    .quad str_trans_serial
    .quad str_trans_bt

str_trans_tcp:
    .asciz "TCP - Standard network (Recommended)"

str_trans_udp:
    .asciz "UDP - Lightweight, connectionless"

str_trans_serial:
    .asciz "Serial - Direct cable connection"

str_trans_bt:
    .asciz "Bluetooth - Short-range wireless"

.balign 8
transport_values:
    .quad val_tcp
    .quad val_udp
    .quad val_serial
    .quad val_bluetooth

val_tcp:
    .asciz "tcp"

val_udp:
    .asciz "udp"

val_serial:
    .asciz "serial"

val_bluetooth:
    .asciz "bluetooth"

// Full transport options (advanced mode)
.balign 8
transport_options_full:
    .quad str_trans_tcp
    .quad str_trans_udp
    .quad str_trans_serial
    .quad str_trans_bt
    .quad str_trans_lora
    .quad str_trans_wifi_mesh

str_trans_lora:
    .asciz "LoRa - Long-range, low-power"

str_trans_wifi_mesh:
    .asciz "WiFi Mesh - Ad-hoc wireless network"

.balign 8
transport_values_full:
    .quad val_tcp
    .quad val_udp
    .quad val_serial
    .quad val_bluetooth
    .quad val_lora
    .quad val_wifi_mesh

val_lora:
    .asciz "lora"

val_wifi_mesh:
    .asciz "wifi-mesh"

// Step descriptions (guided mode)
str_step1_title:
    .asciz "Step 1: Node Identity"

str_step1_desc:
    .asciz "Give your node a unique name to identify it in the mesh."

str_step2_title:
    .asciz "Step 2: Network Transport"

str_step2_desc:
    .asciz "Choose how this node will communicate with peers."

str_step3_title:
    .asciz "Step 3: Storage"

str_step3_desc:
    .asciz "Configure data persistence and recovery options."

str_step4_title:
    .asciz "Step 4: HTTP API"

str_step4_desc:
    .asciz "Enable REST API for external access to the search engine."

str_step5_title:
    .asciz "Step 5: Privacy & Network"

str_step5_desc:
    .asciz "Configure how you share resources with the mesh network."

str_step6_title:
    .asciz "Step 6: Node Role"

str_step6_desc:
    .asciz "Define this node's purpose in the mesh network."

// Privacy questions
str_q_relay_guided:
    .asciz "Relay messages for other nodes? (helps the network)"

str_q_discoverable_guided:
    .asciz "Allow other nodes to discover this node?"

str_q_store_others_guided:
    .asciz "Store data from other nodes?"

str_q_role_guided:
    .asciz "What is this node's primary role?"

// Role options for guided mode
.balign 8
role_options_guided:
    .quad str_role_personal_g
    .quad str_role_home_g
    .quad str_role_bridge_g
    .quad str_role_community_g

str_role_personal_g:
    .asciz "Personal - Single device, minimal sharing"

str_role_home_g:
    .asciz "Home - Part of a home network cluster"

str_role_bridge_g:
    .asciz "Bridge - Connect separate networks"

str_role_community_g:
    .asciz "Community - Public relay for the mesh"

// Store others data options
.balign 8
store_others_options:
    .quad str_store_no
    .quad str_store_cache
    .quad str_store_replicate

str_store_no:
    .asciz "No - Only store my own data"

str_store_cache:
    .asciz "Cache - Temporarily cache passing data"

str_store_replicate:
    .asciz "Replicate - Full backup of others' data"

// Summary labels
str_sum_node:
    .asciz "  Node name:    "

str_sum_transport:
    .asciz "  Transport:    "

str_sum_bind_port:
    .asciz "  Bind port:    "

str_sum_http:
    .asciz "  HTTP enabled: "

str_sum_wal:
    .asciz "  WAL enabled:  "

// Config keys
key_node_name:
    .asciz "node_name"

key_transport:
    .asciz "transport"

key_bind_addr:
    .asciz "bind_addr"

key_bind_port:
    .asciz "bind_port"

key_http_enabled:
    .asciz "http_enabled"

key_http_port:
    .asciz "http_port"

key_wal_enabled:
    .asciz "wal_enabled"

key_data_dir:
    .asciz "data_dir"

key_cluster_name:
    .asciz "cluster_name"

key_replication:
    .asciz "replication"

// Default values
default_node_name:
    .asciz "omesh-node"

default_bind_addr:
    .asciz "0.0.0.0"

default_data_dir:
    .asciz "~/.omesh/data"

default_cluster_name:
    .asciz "default"

default_replication:
    .asciz "1"

val_true:
    .asciz "true"

val_false:
    .asciz "false"

// Completion messages
str_easy_done:
    .asciz "Configuration complete!"

str_guided_done:
    .asciz "Guided setup complete!"

str_advanced_done:
    .asciz "Advanced configuration complete!"

str_confirm_prompt:
    .asciz "Save this configuration?"

str_saved:
    .asciz "Configuration saved to ~/.omesh/config"

str_save_error:
    .asciz "Error: Failed to save configuration"

str_cancelled:
    .asciz "Setup cancelled."

str_newline:
    .asciz "\n"

// ============================================================================
// End of wizard.s
// ============================================================================
