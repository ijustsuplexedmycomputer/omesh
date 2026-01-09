#!/bin/bash
#
# Omesh Uninstaller Script
#

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="$HOME/.omesh"
DATA_DIR="$HOME/.omesh/data"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo -e "${CYAN}Omesh Uninstaller${NC}"
echo "================="
echo ""

# Check what's installed
BINARY_EXISTS=false
CONFIG_EXISTS=false
DATA_EXISTS=false

if [ -f "$INSTALL_DIR/omesh" ] || [ -f "$INSTALL_DIR/omesh.bin" ]; then
    BINARY_EXISTS=true
    echo -e "Binary:  ${GREEN}Found${NC} at $INSTALL_DIR/omesh"
else
    echo -e "Binary:  ${YELLOW}Not found${NC}"
fi

if [ -d "$CONFIG_DIR" ]; then
    CONFIG_EXISTS=true
    if [ -f "$CONFIG_DIR/config" ]; then
        echo -e "Config:  ${GREEN}Found${NC} at $CONFIG_DIR/config"
    else
        echo -e "Config:  ${YELLOW}Directory exists but no config file${NC}"
    fi
else
    echo -e "Config:  ${YELLOW}Not found${NC}"
fi

if [ -d "$DATA_DIR" ]; then
    DATA_EXISTS=true
    FILE_COUNT=$(find "$DATA_DIR" -type f 2>/dev/null | wc -l)
    echo -e "Data:    ${GREEN}Found${NC} ($FILE_COUNT files in $DATA_DIR)"
else
    echo -e "Data:    ${YELLOW}Not found${NC}"
fi

echo ""

# Nothing to uninstall
if [ "$BINARY_EXISTS" = false ] && [ "$CONFIG_EXISTS" = false ]; then
    echo "Nothing to uninstall."
    exit 0
fi

# Remove binary
if [ "$BINARY_EXISTS" = true ]; then
    read -p "Remove omesh binary from $INSTALL_DIR? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f "$INSTALL_DIR/omesh"
        rm -f "$INSTALL_DIR/omesh.bin"  # In case wrapper was created
        echo -e "${GREEN}[OK]${NC} Binary removed"
    else
        echo "Skipped binary removal"
    fi
    echo ""
fi

# Remove config (but warn about data)
if [ "$CONFIG_EXISTS" = true ]; then
    if [ "$DATA_EXISTS" = true ]; then
        echo -e "${YELLOW}Warning:${NC} $CONFIG_DIR contains data files."
        read -p "Remove config directory AND all data? [y/N] " -n 1 -r
    else
        read -p "Remove config directory $CONFIG_DIR? [y/N] " -n 1 -r
    fi
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        echo -e "${GREEN}[OK]${NC} Config directory removed"
    else
        # Offer to remove just the config file
        if [ -f "$CONFIG_DIR/config" ]; then
            read -p "Remove just the config file (keep data)? [y/N] " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$CONFIG_DIR/config"
                echo -e "${GREEN}[OK]${NC} Config file removed (data preserved)"
            fi
        fi
    fi
fi

echo ""
echo "Uninstall complete."
echo ""

# Check if PATH still references omesh
if command -v omesh &> /dev/null; then
    WHICH_OMESH=$(which omesh 2>/dev/null)
    if [ -n "$WHICH_OMESH" ]; then
        echo -e "${YELLOW}Note:${NC} 'omesh' still found at: $WHICH_OMESH"
        echo "You may need to remove it manually or update your PATH."
    fi
fi
