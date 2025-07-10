#!/bin/bash

echo "Testing dgmo evolve --generate command..."
echo "========================================"
echo ""

# Create a temporary file to capture output
OUTPUT_FILE=$(mktemp)
ERROR_FILE=$(mktemp)

# Run the actual dgmo evolve --generate command
echo "1. Running: dgmo evolve --generate"
echo ""

# Execute the command and capture output
if dgmo evolve --generate > "$OUTPUT_FILE" 2> "$ERROR_FILE"; then
    EXIT_CODE=0
    echo "   ✓ Command executed successfully (exit code: 0)"
else
    EXIT_CODE=$?
    echo "   ✗ Command failed (exit code: $EXIT_CODE)"
fi

echo ""
echo "2. Command Output:"
echo "   --------------"
if [ -s "$OUTPUT_FILE" ]; then
    # Show first 20 lines of output
    head -n 20 "$OUTPUT_FILE" | sed 's/^/   /'
    LINES=$(wc -l < "$OUTPUT_FILE")
    if [ "$LINES" -gt 20 ]; then
        echo "   ... ($(($LINES - 20)) more lines)"
    fi
else
    echo "   (No standard output)"
fi

echo ""
echo "3. Error Output:"
echo "   ------------"
if [ -s "$ERROR_FILE" ]; then
    cat "$ERROR_FILE" | sed 's/^/   /'
else
    echo "   (No error output)"
fi

echo ""
echo "4. Analysis:"
echo "   ---------"

# Check for performance-related output
if grep -qi "performance\|metrics\|collecting" "$OUTPUT_FILE" "$ERROR_FILE" 2>/dev/null; then
    echo "   ✓ Performance data collection: DETECTED"
else
    echo "   ✗ Performance data collection: NOT DETECTED"
fi

# Check for generation-related output
if grep -qi "generat\|improvement\|optimiz" "$OUTPUT_FILE" "$ERROR_FILE" 2>/dev/null; then
    echo "   ✓ Improvement generation: DETECTED"
else
    echo "   ✗ Improvement generation: NOT DETECTED"
fi

# Check if evolution data was created/updated
if [ -f "dgm/evolution-data.json" ]; then
    echo "   ✓ Evolution data file: EXISTS"
    MODIFIED=$(stat -c %Y "dgm/evolution-data.json" 2>/dev/null || stat -f %m "dgm/evolution-data.json" 2>/dev/null)
    CURRENT=$(date +%s)
    if [ -n "$MODIFIED" ] && [ $((CURRENT - MODIFIED)) -lt 60 ]; then
        echo "   ✓ Evolution data: RECENTLY MODIFIED"
    fi
else
    echo "   ✗ Evolution data file: NOT FOUND"
fi

echo ""
echo "5. Summary:"
echo "   --------"
if [ $EXIT_CODE -eq 0 ]; then
    echo "   ✅ Test PASSED - Command executed successfully"
else
    echo "   ❌ Test FAILED - Command exited with code $EXIT_CODE"
fi

# Cleanup
rm -f "$OUTPUT_FILE" "$ERROR_FILE"

exit $EXIT_CODE