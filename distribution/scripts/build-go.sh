#!/bin/bash
# DGMO Go Binary Cross-Platform Build Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ROOT="/mnt/c/Users/jehma/Desktop/AI/DGMSTT"
TUI_DIR="$PROJECT_ROOT/opencode/packages/tui"
BUILD_DIR="$PROJECT_ROOT/distribution/build"
VERSION="${VERSION:-dev}"
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Clean old binaries
echo -e "${YELLOW}Cleaning old TUI binaries...${NC}"
cd "$TUI_DIR"
rm -f dgmo dgmo-* opencode-tui tui *.exe

# Create build directory
mkdir -p "$BUILD_DIR/go"

# Build flags for optimization
LDFLAGS="-s -w -X main.Version=$VERSION -X main.BuildTime=$BUILD_TIME"
TAGS="production"

# Build function
build_platform() {
    local GOOS=$1
    local GOARCH=$2
    local OUTPUT=$3
    
    echo -e "${GREEN}Building for $GOOS/$GOARCH...${NC}"
    
    # Set environment
    export GOOS=$GOOS
    export GOARCH=$GOARCH
    export CGO_ENABLED=0
    
    # Build
    go build -ldflags="$LDFLAGS" -tags="$TAGS" -trimpath -o "$OUTPUT" cmd/dgmo/main.go
    
    # Compress with UPX if available (except macOS)
    if command -v upx &> /dev/null && [ "$GOOS" != "darwin" ]; then
        echo "Compressing with UPX..."
        upx --best --lzma "$OUTPUT" || true
    fi
    
    # Get file size
    SIZE=$(ls -lh "$OUTPUT" | awk '{print $5}')
    echo -e "${GREEN}✓ Built $OUTPUT (${SIZE})${NC}"
}

# Build for all platforms
cd "$TUI_DIR"

# Linux AMD64
build_platform "linux" "amd64" "$BUILD_DIR/go/dgmo-linux-amd64"

# Linux ARM64
build_platform "linux" "arm64" "$BUILD_DIR/go/dgmo-linux-arm64"

# macOS AMD64
build_platform "darwin" "amd64" "$BUILD_DIR/go/dgmo-darwin-amd64"

# macOS ARM64 (Apple Silicon)
build_platform "darwin" "arm64" "$BUILD_DIR/go/dgmo-darwin-arm64"

# Windows AMD64
build_platform "windows" "amd64" "$BUILD_DIR/go/dgmo-windows-amd64.exe"

# Windows ARM64
build_platform "windows" "arm64" "$BUILD_DIR/go/dgmo-windows-arm64.exe"

# Create checksums
cd "$BUILD_DIR/go"
echo -e "${YELLOW}Creating checksums...${NC}"
sha256sum dgmo-* > checksums.sha256

# Summary
echo -e "\n${GREEN}Go binaries built successfully!${NC}"
echo "Location: $BUILD_DIR/go"
ls -lh "$BUILD_DIR/go/"