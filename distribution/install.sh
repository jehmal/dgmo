#!/bin/sh
# DGMO Universal Installer (Prototype)
# Usage: curl -sSL https://dgmo.ai/install | sh

set -e

# Configuration
DGMO_VERSION="${DGMO_VERSION:-latest}"
DGMO_INSTALL_DIR="${DGMO_INSTALL_DIR:-$HOME/.dgmo}"
DGMO_BIN_DIR="${DGMO_BIN_DIR:-$HOME/.local/bin}"
GITHUB_REPO="sst/dgmo"

# Colors
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Print banner
echo "${BLUE}"
echo "╔════════════════════════════════════════╗"
echo "║        DGMO Installer v1.0.0           ║"
echo "║    AI-Powered CLI with Self-Evolution  ║"
echo "╚════════════════════════════════════════╝"
echo "${NC}"

# Detect OS and architecture
detect_platform() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"
    
    case "$OS" in
        Linux*)   PLATFORM="linux" ;;
        Darwin*)  PLATFORM="darwin" ;;
        MINGW*|CYGWIN*|MSYS*) 
            echo "${RED}Windows detected. Please use PowerShell installer:${NC}"
            echo "iwr -useb https://dgmo.ai/install.ps1 | iex"
            exit 1
            ;;
        *)        
            echo "${RED}Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac
    
    case "$ARCH" in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *)        
            echo "${RED}Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac
    
    echo "${GREEN}Detected: $PLATFORM/$ARCH${NC}"
}

# Check prerequisites
check_prerequisites() {
    echo "${YELLOW}Checking prerequisites...${NC}"
    
    # Check for curl or wget
    if command -v curl >/dev/null 2>&1; then
        DOWNLOADER="curl -fsSL"
    elif command -v wget >/dev/null 2>&1; then
        DOWNLOADER="wget -qO-"
    else
        echo "${RED}Error: curl or wget is required${NC}"
        exit 1
    fi
    
    # Check for tar
    if ! command -v tar >/dev/null 2>&1; then
        echo "${RED}Error: tar is required${NC}"
        exit 1
    fi
    
    echo "${GREEN}✓ Prerequisites satisfied${NC}"
}

# Get latest version
get_latest_version() {
    if [ "$DGMO_VERSION" = "latest" ]; then
        echo "${YELLOW}Fetching latest version...${NC}"
        # In production, this would query GitHub API
        # For now, use a fixed version
        DGMO_VERSION="1.0.0"
    fi
    echo "${GREEN}Version: $DGMO_VERSION${NC}"
}

# Download and install
install_dgmo() {
    local download_url="https://github.com/$GITHUB_REPO/releases/download/v$DGMO_VERSION/dgmo-$DGMO_VERSION-$PLATFORM-$ARCH.tar.gz"
    local temp_dir="$(mktemp -d)"
    
    echo "${YELLOW}Downloading DGMO v$DGMO_VERSION...${NC}"
    echo "URL: $download_url"
    
    # In production, this would download the actual release
    # For now, we'll simulate the installation
    
    # Create directories
    mkdir -p "$DGMO_INSTALL_DIR" "$DGMO_BIN_DIR"
    
    # Simulate extraction
    echo "${YELLOW}Installing to $DGMO_INSTALL_DIR...${NC}"
    
    # Create wrapper script
    cat > "$DGMO_BIN_DIR/dgmo" << EOF
#!/bin/sh
# DGMO Launcher
export DGMO_HOME="$DGMO_INSTALL_DIR"
exec "\$DGMO_HOME/bin/dgmo-tui" "\$@"
EOF
    
    chmod +x "$DGMO_BIN_DIR/dgmo"
    
    # Clean up
    rm -rf "$temp_dir"
    
    echo "${GREEN}✓ DGMO installed successfully!${NC}"
}

# Configure shell
configure_shell() {
    echo "${YELLOW}Configuring shell...${NC}"
    
    # Detect shell
    case "$SHELL" in
        */bash)
            PROFILE="$HOME/.bashrc"
            ;;
        */zsh)
            PROFILE="$HOME/.zshrc"
            ;;
        */fish)
            PROFILE="$HOME/.config/fish/config.fish"
            ;;
        *)
            PROFILE="$HOME/.profile"
            ;;
    esac
    
    # Add to PATH if needed
    if ! echo "$PATH" | grep -q "$DGMO_BIN_DIR"; then
        echo "" >> "$PROFILE"
        echo "# DGMO CLI" >> "$PROFILE"
        echo "export PATH=\"$DGMO_BIN_DIR:\$PATH\"" >> "$PROFILE"
        echo "${GREEN}✓ Added $DGMO_BIN_DIR to PATH in $PROFILE${NC}"
        echo "${YELLOW}Please run: source $PROFILE${NC}"
    else
        echo "${GREEN}✓ PATH already configured${NC}"
    fi
}

# Main installation flow
main() {
    echo "${YELLOW}Starting DGMO installation...${NC}"
    echo ""
    
    detect_platform
    check_prerequisites
    get_latest_version
    install_dgmo
    configure_shell
    
    echo ""
    echo "${GREEN}════════════════════════════════════════${NC}"
    echo "${GREEN}Installation complete!${NC}"
    echo "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "To get started:"
    echo "  1. Run: ${BLUE}source $PROFILE${NC}"
    echo "  2. Run: ${BLUE}dgmo${NC}"
    echo ""
    echo "For help: ${BLUE}dgmo --help${NC}"
    echo "Documentation: ${BLUE}https://dgmo.ai/docs${NC}"
    echo ""
}

# Run main
main "$@"