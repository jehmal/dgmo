#!/bin/bash
# DGMO Bun/TypeScript Build Script

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Configuration
PROJECT_ROOT="/mnt/c/Users/jehma/Desktop/AI/DGMSTT"
OPENCODE_DIR="$PROJECT_ROOT/opencode/packages/opencode"
BUILD_DIR="$PROJECT_ROOT/distribution/build/bun"

# Clean and create build directory
echo -e "${YELLOW}Cleaning build directory...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Change to opencode directory
cd "$OPENCODE_DIR"

# Build with Bun
echo -e "${GREEN}Building TypeScript with Bun...${NC}"

# Create build configuration
cat > "$BUILD_DIR/build.ts" << 'EOF'
import { build } from "bun";

await build({
  entrypoints: ["./src/index.ts"],
  outdir: "./dist-standalone",
  target: "bun",
  minify: true,
  sourcemap: "none",
  external: ["fsevents", "node-pty", "@napi-rs/*"],
});
EOF

# Run the build
cd "$OPENCODE_DIR"
bun run "$BUILD_DIR/build.ts"

# Copy built files
echo -e "${YELLOW}Copying built files...${NC}"
cp -r "$OPENCODE_DIR/dist-standalone/"* "$BUILD_DIR/"

# Create standalone wrapper
echo -e "${GREEN}Creating standalone wrapper...${NC}"
cat > "$BUILD_DIR/dgmo-cli" << 'EOF'
#!/usr/bin/env bun
process.env.NODE_ENV = "production";
process.env.DGMO_STANDALONE = "true";
import "./index.js";
EOF

chmod +x "$BUILD_DIR/dgmo-cli"

# Get size
SIZE=$(du -sh "$BUILD_DIR" | cut -f1)
echo -e "${GREEN}✓ Bun bundle created successfully!${NC}"
echo -e "Size: ${SIZE}"
echo -e "Location: $BUILD_DIR"