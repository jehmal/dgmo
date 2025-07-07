#!/bin/bash

# Qdrant Backup System Test Suite
# Database Administrator: Comprehensive Testing
# Created: $(date '+%Y-%m-%d')
# Purpose: Test all components of the Qdrant backup automation system

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/qdrant-backup.sh"
RESTORE_SCRIPT="${SCRIPT_DIR}/qdrant-restore.sh"
VERIFY_SCRIPT="${SCRIPT_DIR}/qdrant-verify.sh"
CRON_SCRIPT="${SCRIPT_DIR}/qdrant-cron-setup.sh"
TEST_COLLECTION="TestBackupCollection"
BACKUP_DIR="${HOME}/backups/qdrant"
LOG_DIR="${HOME}/backups/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Test result tracking
test_pass() {
    local test_name="$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_success "✓ $test_name"
}

test_fail() {
    local test_name="$1"
    local error_msg="$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    log_error "✗ $test_name: $error_msg"
}

# Test 1: Check script existence and permissions
test_script_files() {
    log_info "Testing script files..."
    
    local scripts=("$BACKUP_SCRIPT" "$RESTORE_SCRIPT" "$VERIFY_SCRIPT" "$CRON_SCRIPT")
    local all_good=true
    
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            test_fail "Script existence" "$(basename "$script") not found"
            all_good=false
        elif [ ! -x "$script" ]; then
            test_fail "Script permissions" "$(basename "$script") not executable"
            all_good=false
        fi
    done
    
    if [ "$all_good" = true ]; then
        test_pass "All scripts exist and are executable"
    fi
}

# Test 2: Directory structure
test_directory_structure() {
    log_info "Testing directory structure..."
    
    # Create directories if they don't exist
    mkdir -p "$BACKUP_DIR" "$LOG_DIR"
    
    if [ -d "$BACKUP_DIR" ] && [ -w "$BACKUP_DIR" ] && [ -d "$LOG_DIR" ] && [ -w "$LOG_DIR" ]; then
        test_pass "Directory structure is valid"
    else
        test_fail "Directory structure" "Backup or log directories not accessible"
    fi
}

# Test 3: Backup script dry run
test_backup_dry_run() {
    log_info "Testing backup script dry run..."
    
    if "$BACKUP_SCRIPT" --dry-run > /dev/null 2>&1; then
        test_pass "Backup script dry run"
    else
        test_fail "Backup script dry run" "Script failed in dry-run mode"
    fi
}

# Test 4: Verification script
test_verification_script() {
    log_info "Testing verification script..."
    
    if "$VERIFY_SCRIPT" --no-connectivity --quick > /dev/null 2>&1; then
        test_pass "Verification script execution"
    else
        test_fail "Verification script" "Script failed to execute"
    fi
}

# Test 5: Cron setup script
test_cron_setup() {
    log_info "Testing cron setup script..."
    
    if "$CRON_SCRIPT" test > /dev/null 2>&1; then
        test_pass "Cron setup script test"
    else
        test_fail "Cron setup script" "Test mode failed"
    fi
}

# Test 6: Help messages
test_help_messages() {
    log_info "Testing help messages..."
    
    local scripts=("$BACKUP_SCRIPT" "$RESTORE_SCRIPT" "$VERIFY_SCRIPT" "$CRON_SCRIPT")
    local all_good=true
    
    for script in "${scripts[@]}"; do
        if ! "$script" --help > /dev/null 2>&1; then
            test_fail "Help message" "$(basename "$script") --help failed"
            all_good=false
        fi
    done
    
    if [ "$all_good" = true ]; then
        test_pass "All help messages work"
    fi
}

# Test 7: Log file creation
test_log_creation() {
    log_info "Testing log file creation..."
    
    # Run verification to create log
    "$VERIFY_SCRIPT" --no-connectivity --quick > /dev/null 2>&1 || true
    
    if [ -f "${LOG_DIR}/qdrant-verify.log" ]; then
        test_pass "Log file creation"
    else
        test_fail "Log file creation" "Verification log not created"
    fi
}

# Test 8: Restore script list function
test_restore_list() {
    log_info "Testing restore script list function..."
    
    if "$RESTORE_SCRIPT" --list > /dev/null 2>&1; then
        test_pass "Restore script list function"
    else
        test_fail "Restore script list" "List function failed"
    fi
}

# Test 9: File permissions and ownership
test_file_permissions() {
    log_info "Testing file permissions..."
    
    local all_good=true
    
    # Check backup directory permissions
    if [ ! -w "$BACKUP_DIR" ]; then
        test_fail "File permissions" "Backup directory not writable"
        all_good=false
    fi
    
    # Check log directory permissions
    if [ ! -w "$LOG_DIR" ]; then
        test_fail "File permissions" "Log directory not writable"
        all_good=false
    fi
    
    if [ "$all_good" = true ]; then
        test_pass "File permissions are correct"
    fi
}

# Test 10: Script argument parsing
test_argument_parsing() {
    log_info "Testing argument parsing..."
    
    local all_good=true
    
    # Test invalid arguments
    if "$BACKUP_SCRIPT" --invalid-arg > /dev/null 2>&1; then
        test_fail "Argument parsing" "Backup script accepted invalid argument"
        all_good=false
    fi
    
    if "$RESTORE_SCRIPT" --invalid-arg > /dev/null 2>&1; then
        test_fail "Argument parsing" "Restore script accepted invalid argument"
        all_good=false
    fi
    
    if [ "$all_good" = true ]; then
        test_pass "Argument parsing works correctly"
    fi
}

# Test 11: Configuration validation
test_configuration() {
    log_info "Testing configuration validation..."
    
    # Test with custom backup directory
    local temp_backup_dir="/tmp/test-qdrant-backup-$$"
    mkdir -p "$temp_backup_dir"
    
    if BACKUP_DIR="$temp_backup_dir" "$VERIFY_SCRIPT" --no-connectivity --quick > /dev/null 2>&1; then
        test_pass "Custom configuration handling"
    else
        test_fail "Configuration" "Custom backup directory not handled"
    fi
    
    # Cleanup
    rm -rf "$temp_backup_dir"
}

# Test 12: Error handling
test_error_handling() {
    log_info "Testing error handling..."
    
    # Test with non-existent backup directory
    local fake_dir="/non/existent/directory"
    
    if ! BACKUP_DIR="$fake_dir" "$VERIFY_SCRIPT" --no-connectivity --quick > /dev/null 2>&1; then
        test_pass "Error handling for invalid directories"
    else
        test_fail "Error handling" "Script should fail with invalid directory"
    fi
}

# Generate test report
generate_test_report() {
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo ""
    echo "========================================"
    echo "QDRANT BACKUP SYSTEM TEST REPORT"
    echo "========================================"
    echo "Test completed: $end_time"
    echo "Total tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo "Result: ALL TESTS PASSED ✓"
        echo ""
        log_success "Qdrant backup system is ready for production use!"
        echo ""
        echo "Next steps:"
        echo "1. Install cron jobs: ./qdrant-cron-setup.sh install"
        echo "2. Test first backup: ./qdrant-backup.sh"
        echo "3. Verify backups: ./qdrant-verify.sh"
        echo "4. Test restore: ./qdrant-restore.sh --list"
    else
        echo "Result: SOME TESTS FAILED ✗"
        echo ""
        log_error "Please fix the failed tests before using the backup system"
    fi
    
    echo "========================================"
}

# Main test function
main() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "========================================"
    echo "QDRANT BACKUP SYSTEM TEST SUITE"
    echo "========================================"
    echo "Started: $start_time"
    echo "Testing directory: $SCRIPT_DIR"
    echo ""
    
    # Run all tests
    test_script_files
    test_directory_structure
    test_backup_dry_run
    test_verification_script
    test_cron_setup
    test_help_messages
    test_log_creation
    test_restore_list
    test_file_permissions
    test_argument_parsing
    test_configuration
    test_error_handling
    
    # Generate report
    generate_test_report
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Script usage
usage() {
    echo "Usage: $0"
    echo ""
    echo "Comprehensive test suite for Qdrant backup automation system"
    echo ""
    echo "This script tests:"
    echo "  - Script file existence and permissions"
    echo "  - Directory structure and permissions"
    echo "  - Backup script functionality"
    echo "  - Restore script functionality"
    echo "  - Verification script functionality"
    echo "  - Cron setup script functionality"
    echo "  - Error handling and edge cases"
    echo ""
    echo "No arguments required - just run the script"
}

# Handle help argument
if [[ $# -gt 0 ]] && [[ "$1" == "-h" || "$1" == "--help" ]]; then
    usage
    exit 0
fi

# Run main function
main "$@"