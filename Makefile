# =============================================================================
# Omesh - Makefile
# Build system for aarch64 assembly project
# =============================================================================
#
# Targets:
#   make              Build all test binaries
#   make test         Build and run all tests
#   make test-hal     Build and run HAL test only
#   make test-store   Build and run storage test only
#   make test-index   Build and run index test only
#   make test-net     Build and run network test only
#   make test-cluster Build and run cluster test only
#   make clean        Remove build artifacts
#   make qemu-test    Build and run in QEMU (for non-ARM hosts)
#
# Cross-compilation:
#   make CROSS=aarch64-linux-gnu-
#
# =============================================================================

# Toolchain
CROSS ?=
AS = $(CROSS)as
LD = $(CROSS)ld
OBJDUMP = $(CROSS)objdump
OBJCOPY = $(CROSS)objcopy

# Assembler flags
ASFLAGS = -g -march=armv8-a+crc

# Linker flags
LDFLAGS = -static

# Directories
BUILD_DIR = build
SRC_DIR = src
TEST_DIR = test
INC_DIR = include

# Include paths for the assembler
INCLUDES = -I$(INC_DIR) -I.

# =============================================================================
# Source files
# =============================================================================

# HAL sources
HAL_SRCS = $(SRC_DIR)/hal/features.s \
           $(SRC_DIR)/hal/syscall.s \
           $(SRC_DIR)/hal/detect.s

# Storage sources
STORE_SRCS = $(SRC_DIR)/store/docs.s \
             $(SRC_DIR)/store/docidx.s \
             $(SRC_DIR)/store/wal.s

# Index sources
INDEX_SRCS = $(SRC_DIR)/index/tokenizer.s \
             $(SRC_DIR)/index/inverted.s \
             $(SRC_DIR)/index/tfidf.s \
             $(SRC_DIR)/index/query.s \
             $(SRC_DIR)/index/persist.s

# Network sources
NET_SRCS = $(SRC_DIR)/net/socket.s \
           $(SRC_DIR)/net/protocol.s \
           $(SRC_DIR)/net/connection.s \
           $(SRC_DIR)/net/reactor.s \
           $(SRC_DIR)/net/peer.s

# Cluster sources
CLUSTER_SRCS = $(SRC_DIR)/cluster/node.s \
               $(SRC_DIR)/cluster/handler.s \
               $(SRC_DIR)/cluster/replica.s \
               $(SRC_DIR)/cluster/router.s

# Mesh sources
MESH_SRCS = $(SRC_DIR)/mesh/peer_list.s \
            $(SRC_DIR)/mesh/mesh_net.s

# Transport sources
TRANSPORT_SRCS = $(SRC_DIR)/transport/transport.s \
                 $(SRC_DIR)/transport/tcp.s \
                 $(SRC_DIR)/transport/serial.s \
                 $(SRC_DIR)/transport/udp.s \
                 $(SRC_DIR)/transport/lora.s \
                 $(SRC_DIR)/transport/bluetooth.s \
                 $(SRC_DIR)/transport/wifi_mesh.s

# Core sources
CORE_SRCS = $(SRC_DIR)/core/signal.s

# HTTP sources
HTTP_SRCS = $(SRC_DIR)/http/parser.s \
            $(SRC_DIR)/http/json.s \
            $(SRC_DIR)/http/server.s

# CLI sources
CLI_SRCS = $(SRC_DIR)/cli/repl.s

# Setup sources
SETUP_SRCS = $(SRC_DIR)/setup/config.s \
             $(SRC_DIR)/setup/detect.s \
             $(SRC_DIR)/setup/ui.s \
             $(SRC_DIR)/setup/wizard.s

# Test sources
TEST_HAL_SRC = $(TEST_DIR)/unit/test_hal.s
TEST_STORE_SRC = $(TEST_DIR)/unit/test_store.s
TEST_INDEX_SRC = $(TEST_DIR)/unit/test_index.s
TEST_NET_SRC = $(TEST_DIR)/unit/test_net.s
TEST_CLUSTER_SRC = $(TEST_DIR)/unit/test_cluster.s
TEST_BASIC_SRC = $(TEST_DIR)/integration/test_basic.s
TEST_SIGNAL_SRC = $(TEST_DIR)/integration/test_signal.s
TEST_PERSIST_SRC = $(TEST_DIR)/integration/test_persist.s
TEST_HTTP_SRC = $(TEST_DIR)/unit/test_http.s
TEST_JSON_SRC = $(TEST_DIR)/unit/test_json.s
TEST_API_SRC = $(TEST_DIR)/integration/test_api.s
TEST_PEER_LIST_SRC = $(TEST_DIR)/unit/test_peer_list.s
TEST_SERIAL_SRC = $(TEST_DIR)/unit/test_serial.s
TEST_CONFIG_SRC = $(TEST_DIR)/unit/test_config.s
TEST_DETECT_HW_SRC = $(TEST_DIR)/unit/test_detect_hw.s

# =============================================================================
# Object files
# =============================================================================

# HAL objects
HAL_OBJS = $(BUILD_DIR)/features.o \
           $(BUILD_DIR)/syscall.o \
           $(BUILD_DIR)/detect.o

# Storage objects
STORE_OBJS = $(BUILD_DIR)/docs.o \
             $(BUILD_DIR)/docidx.o \
             $(BUILD_DIR)/wal.o

# Index objects
INDEX_OBJS = $(BUILD_DIR)/tokenizer.o \
             $(BUILD_DIR)/inverted.o \
             $(BUILD_DIR)/tfidf.o \
             $(BUILD_DIR)/query.o \
             $(BUILD_DIR)/persist.o

# Network objects
NET_OBJS = $(BUILD_DIR)/socket.o \
           $(BUILD_DIR)/protocol.o \
           $(BUILD_DIR)/connection.o \
           $(BUILD_DIR)/reactor.o \
           $(BUILD_DIR)/peer.o

# Cluster objects
CLUSTER_OBJS = $(BUILD_DIR)/node.o \
               $(BUILD_DIR)/handler.o \
               $(BUILD_DIR)/replica.o \
               $(BUILD_DIR)/router.o

# Mesh objects
MESH_OBJS = $(BUILD_DIR)/peer_list.o \
            $(BUILD_DIR)/mesh_net.o

# Transport objects
TRANSPORT_OBJS = $(BUILD_DIR)/transport.o \
                 $(BUILD_DIR)/tcp_transport.o \
                 $(BUILD_DIR)/serial_transport.o \
                 $(BUILD_DIR)/udp_transport.o \
                 $(BUILD_DIR)/lora_transport.o \
                 $(BUILD_DIR)/bluetooth_transport.o \
                 $(BUILD_DIR)/wifi_mesh_transport.o

# Core objects
CORE_OBJS = $(BUILD_DIR)/signal.o

# HTTP objects (split for testing)
HTTP_PARSER_OBJS = $(BUILD_DIR)/http_parser.o \
                   $(BUILD_DIR)/json.o
HTTP_SERVER_OBJS = $(BUILD_DIR)/http_server.o
HTTP_OBJS = $(HTTP_PARSER_OBJS) $(HTTP_SERVER_OBJS)

# CLI objects
CLI_OBJS = $(BUILD_DIR)/repl.o

# Setup objects
SETUP_OBJS = $(BUILD_DIR)/config.o \
             $(BUILD_DIR)/setup_detect.o \
             $(BUILD_DIR)/setup_ui.o \
             $(BUILD_DIR)/setup_wizard.o

# Test objects
TEST_HAL_OBJ = $(BUILD_DIR)/test_hal.o
TEST_STORE_OBJ = $(BUILD_DIR)/test_store.o
TEST_INDEX_OBJ = $(BUILD_DIR)/test_index.o
TEST_NET_OBJ = $(BUILD_DIR)/test_net.o
TEST_CLUSTER_OBJ = $(BUILD_DIR)/test_cluster.o
TEST_BASIC_OBJ = $(BUILD_DIR)/test_basic.o
TEST_SIGNAL_OBJ = $(BUILD_DIR)/test_signal.o
TEST_PERSIST_OBJ = $(BUILD_DIR)/test_persist.o
TEST_HTTP_OBJ = $(BUILD_DIR)/test_http.o
TEST_JSON_OBJ = $(BUILD_DIR)/test_json.o
TEST_API_OBJ = $(BUILD_DIR)/test_api.o
TEST_PEER_LIST_OBJ = $(BUILD_DIR)/test_peer_list.o
TEST_SERIAL_OBJ = $(BUILD_DIR)/test_serial.o
TEST_CONFIG_OBJ = $(BUILD_DIR)/test_config.o
TEST_DETECT_HW_OBJ = $(BUILD_DIR)/test_detect_hw.o

# Main entry point
MAIN_SRC = $(SRC_DIR)/main.s
MAIN_OBJ = $(BUILD_DIR)/main.o

# =============================================================================
# Output binaries
# =============================================================================

OMESH_BIN = $(BUILD_DIR)/omesh
TEST_HAL_BIN = $(BUILD_DIR)/test_hal
TEST_STORE_BIN = $(BUILD_DIR)/test_store
TEST_INDEX_BIN = $(BUILD_DIR)/test_index
TEST_NET_BIN = $(BUILD_DIR)/test_net
TEST_CLUSTER_BIN = $(BUILD_DIR)/test_cluster
TEST_BASIC_BIN = $(BUILD_DIR)/test_basic
TEST_SIGNAL_BIN = $(BUILD_DIR)/test_signal
TEST_PERSIST_BIN = $(BUILD_DIR)/test_persist
TEST_HTTP_BIN = $(BUILD_DIR)/test_http
TEST_JSON_BIN = $(BUILD_DIR)/test_json
TEST_API_BIN = $(BUILD_DIR)/test_api
TEST_PEER_LIST_BIN = $(BUILD_DIR)/test_peer_list
TEST_SERIAL_BIN = $(BUILD_DIR)/test_serial
TEST_CONFIG_BIN = $(BUILD_DIR)/test_config
TEST_DETECT_HW_BIN = $(BUILD_DIR)/test_detect_hw

# =============================================================================
# Default target - build all tests
# =============================================================================
.PHONY: all
all: $(OMESH_BIN) $(TEST_HAL_BIN) $(TEST_STORE_BIN) $(TEST_INDEX_BIN) $(TEST_NET_BIN) $(TEST_CLUSTER_BIN) $(TEST_BASIC_BIN) $(TEST_SIGNAL_BIN) $(TEST_PERSIST_BIN) $(TEST_HTTP_BIN) $(TEST_JSON_BIN) $(TEST_API_BIN) $(TEST_PEER_LIST_BIN) $(TEST_SERIAL_BIN) $(TEST_CONFIG_BIN) $(TEST_DETECT_HW_BIN)

# =============================================================================
# Create build directory
# =============================================================================
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# =============================================================================
# HAL object files
# =============================================================================
$(BUILD_DIR)/features.o: $(SRC_DIR)/hal/features.s $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/syscall.o: $(SRC_DIR)/hal/syscall.s $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/detect.o: $(SRC_DIR)/hal/detect.s $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Storage object files
# =============================================================================
$(BUILD_DIR)/docs.o: $(SRC_DIR)/store/docs.s $(INC_DIR)/store.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/docidx.o: $(SRC_DIR)/store/docidx.s $(INC_DIR)/store.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/wal.o: $(SRC_DIR)/store/wal.s $(INC_DIR)/store.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Index object files
# =============================================================================
$(BUILD_DIR)/tokenizer.o: $(SRC_DIR)/index/tokenizer.s $(INC_DIR)/index.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/inverted.o: $(SRC_DIR)/index/inverted.s $(INC_DIR)/index.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/tfidf.o: $(SRC_DIR)/index/tfidf.s $(INC_DIR)/index.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/query.o: $(SRC_DIR)/index/query.s $(INC_DIR)/index.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/persist.o: $(SRC_DIR)/index/persist.s $(INC_DIR)/index.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Network object files
# =============================================================================
$(BUILD_DIR)/socket.o: $(SRC_DIR)/net/socket.s $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/protocol.o: $(SRC_DIR)/net/protocol.s $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/connection.o: $(SRC_DIR)/net/connection.s $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/reactor.o: $(SRC_DIR)/net/reactor.s $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/peer.o: $(SRC_DIR)/net/peer.s $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Cluster object files
# =============================================================================
$(BUILD_DIR)/node.o: $(SRC_DIR)/cluster/node.s $(INC_DIR)/cluster.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/handler.o: $(SRC_DIR)/cluster/handler.s $(INC_DIR)/cluster.inc $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/replica.o: $(SRC_DIR)/cluster/replica.s $(INC_DIR)/cluster.inc $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/router.o: $(SRC_DIR)/cluster/router.s $(INC_DIR)/cluster.inc $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Mesh object files
# =============================================================================
$(BUILD_DIR)/peer_list.o: $(SRC_DIR)/mesh/peer_list.s $(INC_DIR)/mesh.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/mesh_net.o: $(SRC_DIR)/mesh/mesh_net.s $(INC_DIR)/mesh.inc $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Transport object files
# =============================================================================
$(BUILD_DIR)/transport.o: $(SRC_DIR)/transport/transport.s $(INC_DIR)/transport.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/tcp_transport.o: $(SRC_DIR)/transport/tcp.s $(INC_DIR)/transport.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/serial_transport.o: $(SRC_DIR)/transport/serial.s $(INC_DIR)/transport.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/udp_transport.o: $(SRC_DIR)/transport/udp.s $(INC_DIR)/transport.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/lora_transport.o: $(SRC_DIR)/transport/lora.s $(INC_DIR)/transport.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/bluetooth_transport.o: $(SRC_DIR)/transport/bluetooth.s $(INC_DIR)/transport.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/wifi_mesh_transport.o: $(SRC_DIR)/transport/wifi_mesh.s $(INC_DIR)/transport.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# CLI object files
# =============================================================================
$(BUILD_DIR)/repl.o: $(SRC_DIR)/cli/repl.s $(INC_DIR)/cluster.inc $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Setup object files
# =============================================================================
$(BUILD_DIR)/config.o: $(SRC_DIR)/setup/config.s $(INC_DIR)/setup.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/setup_detect.o: $(SRC_DIR)/setup/detect.s $(INC_DIR)/setup.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/setup_ui.o: $(SRC_DIR)/setup/ui.s $(INC_DIR)/setup.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/setup_wizard.o: $(SRC_DIR)/setup/wizard.s $(INC_DIR)/setup.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Core object files
# =============================================================================
$(BUILD_DIR)/signal.o: $(SRC_DIR)/core/signal.s $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# HTTP object files
# =============================================================================
$(BUILD_DIR)/http_parser.o: $(SRC_DIR)/http/parser.s $(INC_DIR)/http.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/json.o: $(SRC_DIR)/http/json.s $(INC_DIR)/json.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/http_server.o: $(SRC_DIR)/http/server.s $(INC_DIR)/http.inc $(INC_DIR)/json.inc $(INC_DIR)/index.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Main entry point
# =============================================================================
$(BUILD_DIR)/main.o: $(SRC_DIR)/main.s $(INC_DIR)/cluster.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Test object files
# =============================================================================
$(BUILD_DIR)/test_hal.o: $(TEST_DIR)/unit/test_hal.s $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_store.o: $(TEST_DIR)/unit/test_store.s $(INC_DIR)/store.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_index.o: $(TEST_DIR)/unit/test_index.s $(INC_DIR)/index.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_net.o: $(TEST_DIR)/unit/test_net.s $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_cluster.o: $(TEST_DIR)/unit/test_cluster.s $(INC_DIR)/cluster.inc $(INC_DIR)/net.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_basic.o: $(TEST_DIR)/integration/test_basic.s $(INC_DIR)/cluster.inc $(INC_DIR)/index.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_signal.o: $(TEST_DIR)/integration/test_signal.s $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_persist.o: $(TEST_DIR)/integration/test_persist.s $(INC_DIR)/index.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_http.o: $(TEST_DIR)/unit/test_http.s $(INC_DIR)/http.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_json.o: $(TEST_DIR)/unit/test_json.s $(INC_DIR)/json.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_api.o: $(TEST_DIR)/integration/test_api.s $(INC_DIR)/http.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_peer_list.o: $(TEST_DIR)/unit/test_peer_list.s $(INC_DIR)/mesh.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_serial.o: $(TEST_DIR)/unit/test_serial.s $(INC_DIR)/transport.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_config.o: $(TEST_DIR)/unit/test_config.s $(INC_DIR)/setup.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

$(BUILD_DIR)/test_detect_hw.o: $(TEST_DIR)/unit/test_detect_hw.s $(INC_DIR)/setup.inc $(INC_DIR)/syscall_nums.inc | $(BUILD_DIR)
	$(AS) $(ASFLAGS) $(INCLUDES) -o $@ $<

# =============================================================================
# Link main binary
# =============================================================================
$(OMESH_BIN): $(HAL_OBJS) $(STORE_OBJS) $(INDEX_OBJS) $(NET_OBJS) $(CLUSTER_OBJS) $(MESH_OBJS) $(TRANSPORT_OBJS) $(CORE_OBJS) $(HTTP_OBJS) $(CLI_OBJS) $(SETUP_OBJS) $(MAIN_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

# =============================================================================
# Link test binaries
# =============================================================================
$(TEST_HAL_BIN): $(HAL_OBJS) $(TEST_HAL_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_STORE_BIN): $(HAL_OBJS) $(STORE_OBJS) $(TEST_STORE_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_INDEX_BIN): $(HAL_OBJS) $(STORE_OBJS) $(INDEX_OBJS) $(TEST_INDEX_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_NET_BIN): $(HAL_OBJS) $(STORE_OBJS) $(NET_OBJS) $(TEST_NET_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_CLUSTER_BIN): $(HAL_OBJS) $(STORE_OBJS) $(INDEX_OBJS) $(NET_OBJS) $(CLUSTER_OBJS) $(MESH_OBJS) $(TEST_CLUSTER_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_BASIC_BIN): $(HAL_OBJS) $(STORE_OBJS) $(INDEX_OBJS) $(NET_OBJS) $(CLUSTER_OBJS) $(MESH_OBJS) $(TEST_BASIC_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_SIGNAL_BIN): $(HAL_OBJS) $(CORE_OBJS) $(TEST_SIGNAL_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_PERSIST_BIN): $(HAL_OBJS) $(STORE_OBJS) $(INDEX_OBJS) $(TEST_PERSIST_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_HTTP_BIN): $(HAL_OBJS) $(HTTP_PARSER_OBJS) $(TEST_HTTP_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_JSON_BIN): $(HAL_OBJS) $(HTTP_PARSER_OBJS) $(TEST_JSON_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_API_BIN): $(HAL_OBJS) $(STORE_OBJS) $(INDEX_OBJS) $(NET_OBJS) $(CLUSTER_OBJS) $(MESH_OBJS) $(CORE_OBJS) $(HTTP_OBJS) $(TEST_API_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_PEER_LIST_BIN): $(HAL_OBJS) $(BUILD_DIR)/peer_list.o $(TEST_PEER_LIST_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_SERIAL_BIN): $(HAL_OBJS) $(BUILD_DIR)/transport.o $(BUILD_DIR)/serial_transport.o $(TEST_SERIAL_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_CONFIG_BIN): $(HAL_OBJS) $(SETUP_OBJS) $(TEST_CONFIG_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

$(TEST_DETECT_HW_BIN): $(HAL_OBJS) $(SETUP_OBJS) $(TEST_DETECT_HW_OBJ)
	$(LD) $(LDFLAGS) -o $@ $^

# =============================================================================
# Test targets
# =============================================================================
.PHONY: test
test: test-hal test-store test-index test-net test-cluster test-basic

.PHONY: test-hal
test-hal: $(TEST_HAL_BIN)
	@echo ""
	@./$(TEST_HAL_BIN)
	@echo ""

.PHONY: test-store
test-store: $(TEST_STORE_BIN)
	@echo ""
	@./$(TEST_STORE_BIN)
	@echo ""

.PHONY: test-index
test-index: $(TEST_INDEX_BIN)
	@echo ""
	@./$(TEST_INDEX_BIN)
	@echo ""

.PHONY: test-net
test-net: $(TEST_NET_BIN)
	@echo ""
	@./$(TEST_NET_BIN)
	@echo ""

.PHONY: test-cluster
test-cluster: $(TEST_CLUSTER_BIN)
	@echo ""
	@./$(TEST_CLUSTER_BIN)
	@echo ""

.PHONY: test-basic
test-basic: $(TEST_BASIC_BIN)
	@echo ""
	@./$(TEST_BASIC_BIN)
	@echo ""

.PHONY: test-signal
test-signal: $(TEST_SIGNAL_BIN)
	@echo ""
	@./$(TEST_SIGNAL_BIN)
	@echo ""

.PHONY: test-persist
test-persist: $(TEST_PERSIST_BIN)
	@echo ""
	@./$(TEST_PERSIST_BIN)
	@echo ""

.PHONY: test-http
test-http: $(TEST_HTTP_BIN)
	@echo ""
	@./$(TEST_HTTP_BIN)
	@echo ""

.PHONY: test-json
test-json: $(TEST_JSON_BIN)
	@echo ""
	@./$(TEST_JSON_BIN)
	@echo ""

.PHONY: test-api
test-api: $(TEST_API_BIN)
	@echo ""
	@./$(TEST_API_BIN)
	@echo ""

.PHONY: test-peer-list
test-peer-list: $(TEST_PEER_LIST_BIN)
	@echo ""
	@./$(TEST_PEER_LIST_BIN)
	@echo ""

.PHONY: test-serial
test-serial: $(TEST_SERIAL_BIN)
	@echo ""
	@./$(TEST_SERIAL_BIN)
	@echo ""

.PHONY: test-config
test-config: $(TEST_CONFIG_BIN)
	@echo ""
	@./$(TEST_CONFIG_BIN)
	@echo ""

.PHONY: test-detect-hw
test-detect-hw: $(TEST_DETECT_HW_BIN)
	@echo ""
	@./$(TEST_DETECT_HW_BIN)
	@echo ""

# =============================================================================
# QEMU test - for non-ARM hosts
# =============================================================================
.PHONY: qemu-test
qemu-test: $(TEST_HAL_BIN) $(TEST_STORE_BIN) $(TEST_INDEX_BIN) $(TEST_NET_BIN) $(TEST_CLUSTER_BIN)
	@echo "=== Running HAL test in QEMU ==="
	@qemu-aarch64 -L /usr/aarch64-linux-gnu ./$(TEST_HAL_BIN)
	@echo ""
	@echo "=== Running Storage test in QEMU ==="
	@qemu-aarch64 -L /usr/aarch64-linux-gnu ./$(TEST_STORE_BIN)
	@echo ""
	@echo "=== Running Index test in QEMU ==="
	@qemu-aarch64 -L /usr/aarch64-linux-gnu ./$(TEST_INDEX_BIN)
	@echo ""
	@echo "=== Running Network test in QEMU ==="
	@qemu-aarch64 -L /usr/aarch64-linux-gnu ./$(TEST_NET_BIN)
	@echo ""
	@echo "=== Running Cluster test in QEMU ==="
	@qemu-aarch64 -L /usr/aarch64-linux-gnu ./$(TEST_CLUSTER_BIN)

# =============================================================================
# Disassembly (useful for debugging)
# =============================================================================
.PHONY: disasm
disasm: $(TEST_HAL_BIN) $(TEST_STORE_BIN)
	$(OBJDUMP) -d $(TEST_HAL_BIN) > $(BUILD_DIR)/test_hal.dis
	$(OBJDUMP) -d $(TEST_STORE_BIN) > $(BUILD_DIR)/test_store.dis

# =============================================================================
# Clean build artifacts
# =============================================================================
.PHONY: clean
clean:
	rm -rf $(BUILD_DIR)

# =============================================================================
# Install to user's local bin
# =============================================================================
.PHONY: install
install: $(TEST_HAL_BIN) $(TEST_STORE_BIN)
	mkdir -p ~/.local/bin
	cp $(TEST_HAL_BIN) ~/.local/bin/omesh_test_hal
	cp $(TEST_STORE_BIN) ~/.local/bin/omesh_test_store

# =============================================================================
# Help
# =============================================================================
.PHONY: help
help:
	@echo "Omesh Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all          Build all test binaries (default)"
	@echo "  test         Build and run all tests"
	@echo "  test-hal     Build and run HAL test only"
	@echo "  test-store   Build and run storage test only"
	@echo "  test-index   Build and run index test only"
	@echo "  test-net     Build and run network test only"
	@echo "  test-cluster Build and run cluster test only"
	@echo "  qemu-test    Build and run in QEMU (for non-ARM hosts)"
	@echo "  disasm       Generate disassembly"
	@echo "  clean        Remove build artifacts"
	@echo "  install      Install to ~/.local/bin"
	@echo "  help         Show this message"
	@echo ""
	@echo "Variables:"
	@echo "  CROSS        Cross-compiler prefix (e.g., aarch64-linux-gnu-)"
	@echo ""
	@echo "Examples:"
	@echo "  make                         # Build all"
	@echo "  make test                    # Run all tests"
	@echo "  make test-store              # Run storage tests only"
	@echo "  make CROSS=aarch64-linux-gnu- test  # Cross-compile and test"

# =============================================================================
# Debug info
# =============================================================================
.PHONY: info
info:
	@echo "Assembler: $(AS)"
	@echo "Linker: $(LD)"
	@echo "Build dir: $(BUILD_DIR)"
	@echo "HAL sources: $(HAL_SRCS)"
	@echo "Store sources: $(STORE_SRCS)"
	@echo "Index sources: $(INDEX_SRCS)"
	@echo "Net sources: $(NET_SRCS)"
	@echo "HAL objects: $(HAL_OBJS)"
	@echo "Store objects: $(STORE_OBJS)"
	@echo "Index objects: $(INDEX_OBJS)"
	@echo "Net objects: $(NET_OBJS)"
