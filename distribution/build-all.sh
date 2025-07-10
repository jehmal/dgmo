#!/bin/bash
# DGMO Complete Distribution Build Script
# Builds all components and creates distribution packages

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DIST_DIR="$SCRIPT_DIR/releases"
BUILD_DIR="$SCRIPT_DIR/build"
VERSION="${VERSION:-$(date +%Y%m%d-%H%M%S)}"

# Print banner
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     DGMO Distribution Builder v1.0     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Version: ${VERSION}${NC}"
echo -e "${YELLOW}Build Time: $(date)${NC}"
echo ""

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    local missing=()
    
    # Check Go
    if ! command -v go &> /dev/null; then
        missing+=("Go")
    fi
    
    # Check Bun
    if ! command -v bun &> /dev/null; then
        missing+=("Bun")
    fi
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        missing+=("Python3")
    fi
    
    # Check PyInstaller
    if ! command -v pyinstaller &> /dev/null; then
        echo -e "${YELLOW}Installing PyInstaller...${NC}"
        pip3 install pyinstaller
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo -e "${RED}Missing prerequisites: ${missing[*]}${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ All prerequisites installed${NC}"
}

# Function to build Go binaries
build_go() {
    echo -e "\n${BLUE}Building Go binaries...${NC}"
    "$SCRIPT_DIR/scripts/build-go.sh"
}

# Function to build Bun/TypeScript
build_bun() {
    echo -e "\n${BLUE}Building Bun/TypeScript bundle...${NC}"
    "$SCRIPT_DIR/scripts/build-bun.sh"
}

# Function to build Python bridge
build_python() {
    echo -e "\n${BLUE}Building Python bridge...${NC}"
    "$SCRIPT_DIR/scripts/build-python.sh"
}

# Function to create distribution package
create_package() {
    local platform=$1
    local arch=$2
    
    echo -e "\n${YELLOW}Creating package for $platform/$arch...${NC}"
    
    local pkg_name="dgmo-${VERSION}-${platform}-${arch}"
    local pkg_dir="$DIST_DIR/$pkg_name"
    
    # Create package directory
    rm -rf "$pkg_dir"
    mkdir -p "$pkg_dir/bin"
    
    # Copy Go binary
    local go_binary="dgmo-${platform}-${arch}"
    if [ "$platform" = "windows" ]; then
        go_binary="${go_binary}.exe"
    fi
    
    if [ -f "$BUILD_DIR/go/$go_binary" ]; then
        cp "$BUILD_DIR/go/$go_binary" "$pkg_dir/bin/dgmo-tui"
        if [ "$platform" = "windows" ]; then
            mv "$pkg_dir/bin/dgmo-tui" "$pkg_dir/bin/dgmo-tui.exe"
        fi
    fi
    
    # Copy Bun bundle
    if [ -d "$BUILD_DIR/bun" ]; then
        cp -r "$BUILD_DIR/bun" "$pkg_dir/runtime"
    fi
    
    # Copy Python bridge
    if [ -f "$BUILD_DIR/python/dgm-bridge" ]; then
        cp "$BUILD_DIR/python/dgm-bridge" "$pkg_dir/bin/"
    elif [ -f "$BUILD_DIR/python/dgm-bridge.exe" ]; then
        cp "$BUILD_DIR/python/dgm-bridge.exe" "$pkg_dir/bin/"
    fi
    
    # Create wrapper script
    if [ "$platform" = "windows" ]; then
        cat > "$pkg_dir/dgmo.bat" << 'EOF'
@echo off
setlocal
set DGMO_HOME=%~dp0
set PATH=%DGMO_HOME%\bin;%PATH%
"%DGMO_HOME%\bin\dgmo-tui.exe" %*
EOF
    else
        cat > "$pkg_dir/dgmo" << 'EOF'
#!/bin/sh
DGMO_HOME="$(cd "$(dirname "$0")" && pwd)"
export PATH="$DGMO_HOME/bin:$PATH"
exec "$DGMO_HOME/bin/dgmo-tui" "$@"
EOF
        chmod +x "$pkg_dir/dgmo"
    fi
    
    # Create README
    cat > "$pkg_dir/README.md" << EOF
# DGMO - AI-Powered CLI with Self-Evolution

Version: $VERSION
Platform: $platform/$arch

## Installation

1. Extract this archive to your desired location
2. Add the directory to your PATH
3. Run \`dgmo\` to start

## Components

- \`bin/dgmo-tui\` - Terminal UI (Go binary)
- \`runtime/\` - JavaScript runtime (Bun)
- \`bin/dgm-bridge\` - Python bridge for evolution

## Usage

\`\`\`bash
dgmo              # Start interactive mode
dgmo --help       # Show help
dgmo --version    # Show version
\`\`\`

## Support

Visit: https://dgmo.ai
Issues: https://github.com/sst/dgmo/issues
EOF
    
    # Create archive
    echo -e "${GREEN}Creating archive...${NC}"
    cd "$DIST_DIR"
    
    if [ "$platform" = "windows" ]; then
        # Create ZIP for Windows
        zip -r "${pkg_name}.zip" "$pkg_name"
    else
        # Create tar.gz for Unix
        tar -czf "${pkg_name}.tar.gz" "$pkg_name"
    fi
    
    # Clean up directory
    rm -rf "$pkg_name"
    
    echo -e "${GREEN}✓ Package created: ${pkg_name}${NC}"
}

# Main build process
main() {
    # Check prerequisites
    check_prerequisites
    
    # Clean previous builds
    echo -e "\n${YELLOW}Cleaning previous builds...${NC}"
    rm -rf "$BUILD_DIR" "$DIST_DIR"
    mkdir -p "$BUILD_DIR" "$DIST_DIR"
    
    # Build components
    build_go
    build_bun
    build_python
    
    # Create distribution packages
    echo -e "\n${BLUE}Creating distribution packages...${NC}"
    
    # Linux
    create_package "linux" "amd64"
    create_package "linux" "arm64"
    
    # macOS
    create_package "darwin" "amd64"
    create_package "darwin" "arm64"
    
    # Windows
    create_package "windows" "amd64"
    
    # Create checksums
    echo -e "\n${YELLOW}Creating checksums...${NC}"
    cd "$DIST_DIR"
    sha256sum *.tar.gz *.zip > checksums.sha256
    
    # Summary
    echo -e "\n${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN}Build completed successfully!${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "\nPackages created in: ${DIST_DIR}"
    echo -e "\nFiles:"
    ls -lh "$DIST_DIR"/*.{tar.gz,zip} 2>/dev/null || true
    
    # Calculate total size
    TOTAL_SIZE=$(du -sh "$DIST_DIR" | cut -f1)
    echo -e "\nTotal size: ${TOTAL_SIZE}"
}

# Run main
main "$@"