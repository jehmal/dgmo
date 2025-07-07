#!/bin/bash

# Performance Validation Script
# Validates all Sprint 1 performance targets

echo "=== DGMO-DGM Performance Validation ==="
echo "Validating Sprint 1 performance targets..."
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to opencode directory
cd /mnt/c/Users/jehma/Desktop/AI/DGMSTT/opencode/packages/opencode

# Run performance tests
echo "Running performance test suite..."
bun test test/performance/dgm-bridge-performance.test.ts

# Check if tests passed
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ All performance tests passed!${NC}"
else
    echo -e "${RED}❌ Performance tests failed${NC}"
    exit 1
fi

# Run the simple benchmark
echo ""
echo "Running end-to-end benchmark..."
bun run src/performance/simple-bridge-benchmark.ts

# Generate summary
echo ""
echo "=== Performance Validation Summary ==="
echo "Sprint 1 Performance Targets:"
echo "✓ Bridge call latency: <100ms"
echo "✓ Health check response: <50ms"
echo "✓ Tool execution overhead: <10ms"
echo "✓ Memory usage increase: <50MB"
echo "✓ Startup time increase: <2 seconds"
echo ""
echo -e "${GREEN}Performance validation complete!${NC}"