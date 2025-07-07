#!/bin/bash

# Run DGM Bridge Performance Benchmark
# This script runs the TypeScript-Python bridge performance benchmarks

echo "=== DGM Bridge Performance Benchmark ==="
echo "Starting benchmark suite..."
echo ""

# Change to the opencode directory
cd /mnt/c/Users/jehma/Desktop/AI/DGMSTT/opencode/packages/opencode

# Ensure Python server is available
echo "Checking Python environment..."
if ! command -v python3 &> /dev/null; then
    echo "❌ Python3 not found. Please install Python 3.x"
    exit 1
fi

# Check if the Python module exists
if ! python3 -c "import dgm.bridge.stdio_server" 2>/dev/null; then
    echo "⚠️  Warning: dgm.bridge.stdio_server module not found"
    echo "The benchmark will likely fail. Ensure the Python module is in PYTHONPATH"
fi

# Run the benchmark
echo "Running performance benchmarks..."
echo ""

# Use bun to run the TypeScript benchmark
bun run src/performance/bridge-benchmark.ts

echo ""
echo "Benchmark complete!"