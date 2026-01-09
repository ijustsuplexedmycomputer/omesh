#!/bin/bash
#
# Omesh Installer Script
# Supports: Linux aarch64, Linux x86_64 (via qemu), macOS arm64
#
set -e

OMESH_VERSION="0.3.0"
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="$HOME/.omesh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_banner() {
    echo ""
    echo -e "${CYAN}+===================================================================+${NC}"
    echo -e "${CYAN}|${NC}              OMESH INSTALLER v${OMESH_VERSION}                           ${CYAN}|${NC}"
    echo -e "${CYAN}|${NC}         Distributed Full-Text Search Engine                    ${CYAN}|${NC}"
    echo -e "${CYAN}+===================================================================+${NC}"
    echo ""
}

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect platform
detect_platform() {
    OS=$(uname -s)
    ARCH=$(uname -m)

    log_info "Detected: $OS $ARCH"

    case "$OS" in
        Linux)
            if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
                PLATFORM="linux-arm64"
                log_success "Native aarch64 Linux detected"
            elif [ "$ARCH" = "x86_64" ]; then
                log_warn "x86_64 detected. Omesh is native aarch64 assembly."
                log_warn "Will use qemu-user for emulation."
                PLATFORM="linux-x64-emu"
            else
                log_error "Unsupported architecture: $ARCH"
                exit 1
            fi
            ;;
        Darwin)
            if [ "$ARCH" = "arm64" ]; then
                PLATFORM="macos-arm64"
                log_success "Apple Silicon Mac detected"
            else
                log_error "Intel Macs not supported (need arm64)"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported OS: $OS"
            exit 1
            ;;
    esac

    echo ""
}

# Check/install dependencies
install_deps() {
    log_info "Checking dependencies..."

    case "$PLATFORM" in
        linux-arm64)
            # Native aarch64 Linux - check for assembler
            if ! command -v as &> /dev/null; then
                log_info "Installing binutils..."
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update
                    sudo apt-get install -y binutils make
                elif command -v dnf &> /dev/null; then
                    sudo dnf install -y binutils make
                elif command -v pacman &> /dev/null; then
                    sudo pacman -S --noconfirm binutils make
                else
                    log_error "Please install binutils manually"
                    exit 1
                fi
            fi
            log_success "Dependencies OK"
            ;;

        linux-x64-emu)
            # x86_64 Linux - need cross-compiler and qemu
            NEED_INSTALL=""

            if ! command -v aarch64-linux-gnu-as &> /dev/null; then
                NEED_INSTALL="$NEED_INSTALL binutils-aarch64-linux-gnu"
            fi

            if ! command -v qemu-aarch64 &> /dev/null && ! command -v qemu-aarch64-static &> /dev/null; then
                NEED_INSTALL="$NEED_INSTALL qemu-user qemu-user-binfmt"
            fi

            if [ -n "$NEED_INSTALL" ]; then
                log_info "Installing: $NEED_INSTALL"
                if command -v apt-get &> /dev/null; then
                    sudo apt-get update
                    sudo apt-get install -y $NEED_INSTALL make
                elif command -v dnf &> /dev/null; then
                    sudo dnf install -y $NEED_INSTALL make
                else
                    log_error "Please install aarch64 cross-tools manually:"
                    log_error "  - aarch64-linux-gnu binutils"
                    log_error "  - qemu-user"
                    exit 1
                fi
            fi

            # Enable binfmt_misc for transparent execution
            if [ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
                log_success "qemu-aarch64 binfmt handler active"
            else
                log_warn "qemu binfmt_misc not active. You may need to run:"
                log_warn "  sudo systemctl restart systemd-binfmt"
            fi

            log_success "Dependencies OK"
            ;;

        macos-arm64)
            # macOS with Apple Silicon - native arm64
            # Need Xcode command line tools for 'as' and 'ld'
            if ! command -v as &> /dev/null; then
                log_info "Installing Xcode command line tools..."
                xcode-select --install 2>/dev/null || true
                echo ""
                log_warn "Please wait for Xcode tools installation to complete,"
                log_warn "then re-run this script."
                exit 0
            fi

            # Check for GNU make (macOS has BSD make by default)
            if ! command -v make &> /dev/null; then
                log_error "make not found. Install Xcode command line tools."
                exit 1
            fi

            log_success "Dependencies OK"
            ;;
    esac
    echo ""
}

# Build from source
build_omesh() {
    log_info "Building Omesh..."

    # Check if we're in the source directory
    if [ ! -f "Makefile" ]; then
        log_error "Makefile not found. Run this from the omesh source directory."
        exit 1
    fi

    # Clean previous build
    make clean 2>/dev/null || true
    mkdir -p build

    # Build based on platform
    case "$PLATFORM" in
        linux-arm64)
            log_info "Building native aarch64..."
            make 2>&1 | tail -5
            ;;

        linux-x64-emu)
            log_info "Building with cross-compiler..."
            # Use cross-compiler prefix
            make AS=aarch64-linux-gnu-as LD=aarch64-linux-gnu-ld 2>&1 | tail -5
            ;;

        macos-arm64)
            log_info "Building for macOS arm64..."
            # Try macOS-specific Makefile first, fall back to main
            if [ -f "Makefile.macos" ]; then
                make -f Makefile.macos 2>&1 | tail -5
            else
                # macOS 'as' is compatible with GNU syntax for basic ARM64
                make 2>&1 | tail -5 || {
                    log_warn "Standard build failed, trying with macOS adjustments..."
                    make PLATFORM=macos 2>&1 | tail -5
                }
            fi
            ;;
    esac

    if [ ! -f "build/omesh" ]; then
        log_error "Build failed - binary not created"
        echo ""
        echo "Try running 'make' manually to see full error output."
        exit 1
    fi

    # Verify binary
    if file build/omesh | grep -q "aarch64\|ARM64\|arm64"; then
        log_success "Build successful (aarch64 binary)"
    else
        log_warn "Binary created but architecture unclear"
    fi
    echo ""
}

# Install binary
install_binary() {
    log_info "Installing to $INSTALL_DIR..."

    # Create directories
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"

    # Copy binary
    cp build/omesh "$INSTALL_DIR/omesh"
    chmod +x "$INSTALL_DIR/omesh"

    # For x86_64, create a wrapper script
    if [ "$PLATFORM" = "linux-x64-emu" ]; then
        QEMU_CMD=""
        if command -v qemu-aarch64-static &> /dev/null; then
            QEMU_CMD="qemu-aarch64-static"
        elif command -v qemu-aarch64 &> /dev/null; then
            QEMU_CMD="qemu-aarch64"
        fi

        if [ -n "$QEMU_CMD" ] && [ ! -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
            # Create wrapper script for explicit qemu execution
            mv "$INSTALL_DIR/omesh" "$INSTALL_DIR/omesh.bin"
            cat > "$INSTALL_DIR/omesh" << EOF
#!/bin/bash
exec $QEMU_CMD "$INSTALL_DIR/omesh.bin" "\$@"
EOF
            chmod +x "$INSTALL_DIR/omesh"
            log_info "Created qemu wrapper script"
        fi
    fi

    log_success "Installed to $INSTALL_DIR/omesh"

    # Check if INSTALL_DIR is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo ""
        log_warn "$INSTALL_DIR is not in your PATH"
        echo "   Add this to your ~/.bashrc or ~/.zshrc:"
        echo ""
        echo "   export PATH=\"$INSTALL_DIR:\$PATH\""
        echo ""
    fi
    echo ""
}

# Verify installation
verify_install() {
    log_info "Verifying installation..."

    if [ -x "$INSTALL_DIR/omesh" ]; then
        # Try to run --help or similar quick command
        if timeout 2 "$INSTALL_DIR/omesh" --help 2>/dev/null | head -1; then
            log_success "Binary runs correctly"
        else
            # May not have --help, try detecting crash
            if timeout 2 "$INSTALL_DIR/omesh" </dev/null 2>&1 | head -3; then
                log_success "Binary starts correctly"
            else
                log_warn "Binary may have issues running"
            fi
        fi
    else
        log_error "Binary not executable"
        exit 1
    fi
    echo ""
}

# Run setup wizard
run_setup() {
    echo ""
    echo -e "${CYAN}+===================================================================+${NC}"
    echo -e "${CYAN}|${NC}              INSTALLATION COMPLETE                              ${CYAN}|${NC}"
    echo -e "${CYAN}+===================================================================+${NC}"
    echo ""
    echo "Omesh has been installed to: $INSTALL_DIR/omesh"
    echo "Config directory created at: $CONFIG_DIR"
    echo ""

    # Check if running interactively
    if [ -t 0 ]; then
        read -p "Run setup wizard now? [Y/n] " -n 1 -r
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            echo ""
            "$INSTALL_DIR/omesh" --setup
        else
            print_usage
        fi
    else
        print_usage
    fi
}

print_usage() {
    echo ""
    echo "Quick Start:"
    echo "  omesh --setup           Run setup wizard"
    echo "  omesh --http 8080       Start HTTP server"
    echo "  omesh                   Start interactive REPL"
    echo ""
    echo "Mesh Networking:"
    echo "  omesh --mesh-port 9000                Start mesh listener"
    echo "  omesh --peer HOST:PORT                Connect to peer"
    echo ""
    echo "Example - Start first node:"
    echo "  omesh --http 8080 --mesh-port 9000"
    echo ""
    echo "Example - Connect second node:"
    echo "  omesh --http 8081 --mesh-port 9001 --peer 192.168.1.10:9000"
    echo ""
}

# Show help
show_help() {
    echo "Omesh Installer"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help      Show this help"
    echo "  -d, --dir DIR   Install to DIR (default: ~/.local/bin)"
    echo "  -n, --no-setup  Skip setup wizard prompt"
    echo ""
    echo "Environment Variables:"
    echo "  INSTALL_DIR     Installation directory"
    echo ""
}

# Parse arguments
SKIP_SETUP=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -n|--no-setup)
            SKIP_SETUP=true
            shift
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Main
main() {
    print_banner
    detect_platform
    install_deps
    build_omesh
    install_binary
    verify_install

    if [ "$SKIP_SETUP" = false ]; then
        run_setup
    else
        print_usage
    fi
}

main
