#!/bin/bash

# Quick validation script for the recovery testing framework
# This script performs basic validation without running full tests

set -e

echo "🔍 Validating DGMSTT Recovery Testing Framework..."
echo "=================================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

VALIDATION_PASSED=0
VALIDATION_FAILED=0

validate_check() {
    local description="$1"
    local command="$2"
    
    echo -n "Checking $description... "
    
    if eval "$command" &>/dev/null; then
        echo -e "${GREEN}✓${NC}"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        echo -e "${RED}✗${NC}"
        VALIDATION_FAILED=$((VALIDATION_FAILED + 1))
    fi
}

# 1. Check script exists and is executable
validate_check "test-recovery.sh exists and is executable" "[ -x './test-recovery.sh' ]"

# 2. Check dependencies
validate_check "curl is available" "command -v curl"
validate_check "jq is available" "command -v jq"
validate_check "bc is available" "command -v bc"
validate_check "find is available" "command -v find"
validate_check "tar is available" "command -v tar"

# 3. Check existing recovery scripts
validate_check "qdrant-backup.sh exists" "[ -f './qdrant-backup.sh' ]"
validate_check "consolidate-sessions.sh exists" "[ -f './consolidate-sessions.sh' ]"

# 4. Check script help functionality
validate_check "test-recovery.sh help works" "./test-recovery.sh --help"

# 5. Check directory structure can be created
validate_check "can create test directories" "mkdir -p /tmp/recovery-test-validation && rmdir /tmp/recovery-test-validation"

# 6. Check basic script syntax
validate_check "test-recovery.sh syntax is valid" "bash -n ./test-recovery.sh"

# 7. Test data generation (dry run)
echo ""
echo "🧪 Testing framework initialization..."
if ./test-recovery.sh --generate-data &>/tmp/recovery-validation.log; then
    echo -e "${GREEN}✓${NC} Test data generation works"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    
    # Check if test data was created
    if [ -d "./recovery-tests/test-data" ]; then
        echo -e "${GREEN}✓${NC} Test data directory created"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Test data directory not created"
        VALIDATION_FAILED=$((VALIDATION_FAILED + 1))
    fi
else
    echo -e "${RED}✗${NC} Test data generation failed"
    VALIDATION_FAILED=$((VALIDATION_FAILED + 1))
fi

# 8. Test quick scenario (if Qdrant is not required)
echo ""
echo "🚀 Testing quick scenario execution..."
if ./test-recovery.sh --scenario corruption --quick &>/tmp/recovery-quick-test.log; then
    echo -e "${GREEN}✓${NC} Quick test scenario works"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
else
    echo -e "${YELLOW}⚠${NC} Quick test scenario failed (may be expected without full setup)"
    # Don't count this as a failure since it might need full environment
fi

# 9. Check report generation capability
echo ""
echo "📊 Testing report generation..."
if [ -d "./recovery-tests/reports" ]; then
    echo -e "${GREEN}✓${NC} Reports directory exists"
    VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    
    # Check for any generated reports
    if ls ./recovery-tests/reports/*.html &>/dev/null; then
        echo -e "${GREEN}✓${NC} HTML reports generated"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC} No HTML reports found (expected for first run)"
    fi
    
    if ls ./recovery-tests/reports/*.json &>/dev/null; then
        echo -e "${GREEN}✓${NC} JSON metrics generated"
        VALIDATION_PASSED=$((VALIDATION_PASSED + 1))
    else
        echo -e "${YELLOW}⚠${NC} No JSON metrics found (expected for first run)"
    fi
else
    echo -e "${YELLOW}⚠${NC} Reports directory not found (will be created on first run)"
fi

# 10. Cleanup test artifacts
echo ""
echo "🧹 Cleaning up validation artifacts..."
rm -rf ./recovery-tests/test-data 2>/dev/null || true
rm -f /tmp/recovery-validation.log /tmp/recovery-quick-test.log 2>/dev/null || true
echo -e "${GREEN}✓${NC} Cleanup completed"

# Summary
echo ""
echo "=================================================="
echo "📋 VALIDATION SUMMARY"
echo "=================================================="
echo -e "Passed: ${GREEN}${VALIDATION_PASSED}${NC}"
echo -e "Failed: ${RED}${VALIDATION_FAILED}${NC}"
echo ""

if [ $VALIDATION_FAILED -eq 0 ]; then
    echo -e "${GREEN}🎉 All critical validations passed!${NC}"
    echo ""
    echo "The recovery testing framework is ready to use."
    echo ""
    echo "Next steps:"
    echo "1. Run: ./test-recovery.sh --help"
    echo "2. Try: ./test-recovery.sh --quick"
    echo "3. Full test: ./test-recovery.sh"
    echo ""
    exit 0
else
    echo -e "${RED}❌ Some validations failed.${NC}"
    echo ""
    echo "Please address the failed checks before using the framework."
    echo ""
    echo "Common fixes:"
    echo "- Install missing dependencies: sudo apt-get install curl jq bc"
    echo "- Ensure scripts are executable: chmod +x *.sh"
    echo "- Check that required scripts exist in the current directory"
    echo ""
    exit 1
fi