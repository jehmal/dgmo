#!/bin/bash

#===============================================================================
# BACKUP TESTING UTILITIES
#===============================================================================
# Name: backup-test-utils.sh
# Purpose: Shared utilities and framework for backup system testing
# Author: DGMSTT Testing Framework
# Version: 1.0
#
# This file provides common functions, configurations, and utilities
# used across all backup testing scripts.
#===============================================================================

set -euo pipefail

#===============================================================================
# GLOBAL CONFIGURATION
#===============================================================================

# Test environment configuration
TEST_BASE_DIR="${TEST_BASE_DIR:-/tmp/backup-tests}"
TEST_DATA_DIR="$TEST_BASE_DIR/test-data"
TEST_BACKUP_DIR="$TEST_BASE_DIR/backups"
TEST_LOG_DIR="$TEST_BASE_DIR/logs"
TEST_REPORTS_DIR="$TEST_BASE_DIR/reports"

# Test session configuration
TEST_SESSION_ID="test-$(date +%Y%m%d-%H%M%S)-$$"
TEST_LOG_FILE="$TEST_LOG_DIR/test-$TEST_SESSION_ID.log"

# Colors for output
declare -r RED='\033[0;31m'
declare -r GREEN='\033[0;32m'
declare -r YELLOW='\033[1;33m'
declare -r BLUE='\033[0;34m'
declare -r PURPLE='\033[0;35m'
declare -r CYAN='\033[0;36m'
declare -r WHITE='\033[1;37m'
declare -r NC='\033[0m' # No Color

# Test result tracking
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -g TEST_SKIPPED=0
declare -g TEST_WARNINGS=0

# Performance tracking
declare -g PERF_START_TIME=0
declare -g PERF_END_TIME=0

# Cleanup tracking
declare -ga CLEANUP_FUNCTIONS=()
declare -ga TEMP_FILES=()
declare -ga TEMP_DIRS=()

#===============================================================================
# LOGGING AND OUTPUT FUNCTIONS
#===============================================================================

# Initialize test environment
init_test_environment() {
    local test_name="$1"
    
    # Create test directories
    mkdir -p "$TEST_BASE_DIR" "$TEST_DATA_DIR" "$TEST_BACKUP_DIR" "$TEST_LOG_DIR" "$TEST_REPORTS_DIR"
    
    # Initialize log file
    cat > "$TEST_LOG_FILE" << EOF
===============================================================================
BACKUP TESTING SESSION: $test_name
===============================================================================
Session ID: $TEST_SESSION_ID
Start Time: $(date '+%Y-%m-%d %H:%M:%S')
Test Base Directory: $TEST_BASE_DIR
Log File: $TEST_LOG_FILE
===============================================================================

EOF
    
    log_info "Test environment initialized"
    log_info "Session ID: $TEST_SESSION_ID"
    log_info "Base directory: $TEST_BASE_DIR"
}

# Logging function with levels and timestamps
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$TEST_LOG_FILE"
    
    # Output to console with colors
    case "$level" in
        ERROR)
            echo -e "${RED}❌ ERROR: $message${NC}" >&2
            ;;
        WARN)
            echo -e "${YELLOW}⚠️  WARN: $message${NC}" >&2
            ;;
        INFO)
            echo -e "${BLUE}ℹ️  INFO: $message${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}✅ SUCCESS: $message${NC}"
            ;;
        DEBUG)
            if [[ "${VERBOSE:-false}" == "true" ]]; then
                echo -e "${PURPLE}🔍 DEBUG: $message${NC}"
            fi
            ;;
        PERF)
            echo -e "${CYAN}📊 PERF: $message${NC}"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Convenience logging functions
log_error() { log "ERROR" "$@"; }
log_warn() { log "WARN" "$@"; }
log_info() { log "INFO" "$@"; }
log_success() { log "SUCCESS" "$@"; }
log_debug() { log "DEBUG" "$@"; }
log_perf() { log "PERF" "$@"; }

# Test result functions
test_start() {
    local test_name="$1"
    echo -e "\n${WHITE}🧪 Starting test: $test_name${NC}"
    log_info "TEST START: $test_name"
    PERF_START_TIME=$(date +%s.%N)
}

test_pass() {
    local test_name="$1"
    local duration=""
    if [[ $PERF_START_TIME != 0 ]]; then
        PERF_END_TIME=$(date +%s.%N)
        duration=$(echo "$PERF_END_TIME - $PERF_START_TIME" | bc -l 2>/dev/null || echo "unknown")
        duration=" (${duration}s)"
    fi
    echo -e "${GREEN}✅ PASS: $test_name$duration${NC}"
    log_success "TEST PASS: $test_name$duration"
    ((TEST_PASSED++))
}

test_fail() {
    local test_name="$1"
    local reason="${2:-Unknown failure}"
    local duration=""
    if [[ $PERF_START_TIME != 0 ]]; then
        PERF_END_TIME=$(date +%s.%N)
        duration=$(echo "$PERF_END_TIME - $PERF_START_TIME" | bc -l 2>/dev/null || echo "unknown")
        duration=" (${duration}s)"
    fi
    echo -e "${RED}❌ FAIL: $test_name$duration - $reason${NC}"
    log_error "TEST FAIL: $test_name$duration - $reason"
    ((TEST_FAILED++))
}

test_skip() {
    local test_name="$1"
    local reason="${2:-Skipped}"
    echo -e "${YELLOW}⏭️  SKIP: $test_name - $reason${NC}"
    log_warn "TEST SKIP: $test_name - $reason"
    ((TEST_SKIPPED++))
}

test_warn() {
    local test_name="$1"
    local warning="$2"
    echo -e "${YELLOW}⚠️  WARN: $test_name - $warning${NC}"
    log_warn "TEST WARN: $test_name - $warning"
    ((TEST_WARNINGS++))
}

#===============================================================================
# PERFORMANCE MEASUREMENT FUNCTIONS
#===============================================================================

# Start performance measurement
perf_start() {
    PERF_START_TIME=$(date +%s.%N)
}

# End performance measurement and return duration
perf_end() {
    PERF_END_TIME=$(date +%s.%N)
    if command -v bc >/dev/null 2>&1; then
        echo "$PERF_END_TIME - $PERF_START_TIME" | bc -l
    else
        echo "0"
    fi
}

# Measure command execution time
measure_time() {
    local cmd="$*"
    local start_time=$(date +%s.%N)
    
    if eval "$cmd"; then
        local end_time=$(date +%s.%N)
        if command -v bc >/dev/null 2>&1; then
            echo "$end_time - $start_time" | bc -l
        else
            echo "0"
        fi
        return 0
    else
        local end_time=$(date +%s.%N)
        if command -v bc >/dev/null 2>&1; then
            echo "$end_time - $start_time" | bc -l
        else
            echo "0"
        fi
        return 1
    fi
}

# Convert bytes to human readable format
human_readable_size() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    
    while [[ $bytes -gt 1024 && $unit -lt 4 ]]; do
        bytes=$((bytes / 1024))
        unit=$((unit + 1))
    done
    
    echo "${bytes}${units[$unit]}"
}

#===============================================================================
# TEST DATA GENERATION FUNCTIONS
#===============================================================================

# Create test session data
create_test_session_data() {
    local session_dir="$1"
    local file_count="${2:-10}"
    local size_kb="${3:-100}"
    
    mkdir -p "$session_dir"
    
    for i in $(seq 1 "$file_count"); do
        local session_file="$session_dir/session_${i}.json"
        
        # Create realistic session JSON data
        cat > "$session_file" << EOF
{
  "id": "session_${i}_$(date +%s)",
  "timestamp": "$(date -Iseconds)",
  "messages": [
    {
      "role": "user",
      "content": "Test message $i",
      "timestamp": "$(date -Iseconds)"
    },
    {
      "role": "assistant", 
      "content": "Test response $i with some longer content to make the file larger. $(head -c $((size_kb * 1024)) /dev/zero | tr '\0' 'x')",
      "timestamp": "$(date -Iseconds)"
    }
  ],
  "metadata": {
    "version": "1.0",
    "test_data": true,
    "size_kb": $size_kb
  }
}
EOF
    done
    
    log_debug "Created $file_count test session files in $session_dir"
}

# Create test files of various types and sizes
create_test_files() {
    local target_dir="$1"
    local pattern="${2:-mixed}"
    
    mkdir -p "$target_dir"
    
    case "$pattern" in
        "small")
            # Small files (1-10KB)
            for i in {1..20}; do
                head -c $((RANDOM % 10240 + 1024)) /dev/urandom > "$target_dir/small_$i.dat"
            done
            ;;
        "large")
            # Large files (1-10MB)
            for i in {1..5}; do
                head -c $((RANDOM % 10485760 + 1048576)) /dev/urandom > "$target_dir/large_$i.dat"
            done
            ;;
        "mixed")
            # Mix of file types and sizes
            create_test_files "$target_dir" "small"
            create_test_files "$target_dir" "large"
            
            # Text files
            for i in {1..10}; do
                echo "Test content $i $(date)" > "$target_dir/text_$i.txt"
            done
            
            # JSON files
            for i in {1..5}; do
                echo "{\"test\": $i, \"timestamp\": \"$(date -Iseconds)\"}" > "$target_dir/data_$i.json"
            done
            ;;
        "empty")
            # Empty files
            for i in {1..10}; do
                touch "$target_dir/empty_$i.txt"
            done
            ;;
    esac
    
    log_debug "Created test files with pattern '$pattern' in $target_dir"
}

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================

# Validate backup file integrity
validate_backup_integrity() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file does not exist: $backup_file"
        return 1
    fi
    
    # Check if it's a valid tar.gz file
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_error "Backup file is not a valid tar.gz archive: $backup_file"
        return 1
    fi
    
    log_debug "Backup integrity validated: $backup_file"
    return 0
}

# Compare directory contents
compare_directories() {
    local source_dir="$1"
    local extracted_dir="$2"
    
    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory does not exist: $source_dir"
        return 1
    fi
    
    if [[ ! -d "$extracted_dir" ]]; then
        log_error "Extracted directory does not exist: $extracted_dir"
        return 1
    fi
    
    # Compare file counts
    local source_count=$(find "$source_dir" -type f | wc -l)
    local extracted_count=$(find "$extracted_dir" -type f | wc -l)
    
    if [[ $source_count -ne $extracted_count ]]; then
        log_error "File count mismatch: source=$source_count, extracted=$extracted_count"
        return 1
    fi
    
    # Compare file checksums (if available)
    if command -v md5sum >/dev/null 2>&1; then
        local source_checksums=$(find "$source_dir" -type f -exec md5sum {} \; | sort)
        local extracted_checksums=$(find "$extracted_dir" -type f -exec md5sum {} \; | sed "s|$extracted_dir|$source_dir|g" | sort)
        
        if [[ "$source_checksums" != "$extracted_checksums" ]]; then
            log_error "Checksum mismatch between source and extracted directories"
            return 1
        fi
    fi
    
    log_debug "Directory comparison successful: $source_dir vs $extracted_dir"
    return 0
}

#===============================================================================
# CLEANUP FUNCTIONS
#===============================================================================

# Register cleanup function
register_cleanup() {
    CLEANUP_FUNCTIONS+=("$1")
}

# Register temporary file for cleanup
register_temp_file() {
    TEMP_FILES+=("$1")
}

# Register temporary directory for cleanup
register_temp_dir() {
    TEMP_DIRS+=("$1")
}

# Execute all cleanup functions
cleanup_all() {
    log_info "Executing cleanup procedures..."
    
    # Execute registered cleanup functions
    for cleanup_func in "${CLEANUP_FUNCTIONS[@]}"; do
        if declare -f "$cleanup_func" >/dev/null; then
            log_debug "Executing cleanup function: $cleanup_func"
            "$cleanup_func" || log_warn "Cleanup function failed: $cleanup_func"
        fi
    done
    
    # Clean up temporary files
    for temp_file in "${TEMP_FILES[@]}"; do
        if [[ -f "$temp_file" ]]; then
            log_debug "Removing temporary file: $temp_file"
            rm -f "$temp_file" || log_warn "Failed to remove temporary file: $temp_file"
        fi
    done
    
    # Clean up temporary directories
    for temp_dir in "${TEMP_DIRS[@]}"; do
        if [[ -d "$temp_dir" ]]; then
            log_debug "Removing temporary directory: $temp_dir"
            rm -rf "$temp_dir" || log_warn "Failed to remove temporary directory: $temp_dir"
        fi
    done
    
    log_info "Cleanup completed"
}

# Cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    cleanup_all
    exit $exit_code
}

#===============================================================================
# REPORT GENERATION FUNCTIONS
#===============================================================================

# Generate test summary report
generate_test_report() {
    local test_name="$1"
    local report_file="$TEST_REPORTS_DIR/${test_name}-report-$TEST_SESSION_ID.txt"
    
    cat > "$report_file" << EOF
===============================================================================
BACKUP TESTING REPORT: $test_name
===============================================================================
Session ID: $TEST_SESSION_ID
Test Date: $(date '+%Y-%m-%d %H:%M:%S')
Test Duration: $(perf_end)s

SUMMARY:
--------
Tests Passed: $TEST_PASSED
Tests Failed: $TEST_FAILED
Tests Skipped: $TEST_SKIPPED
Warnings: $TEST_WARNINGS
Total Tests: $((TEST_PASSED + TEST_FAILED + TEST_SKIPPED))

SUCCESS RATE: $(( TEST_PASSED * 100 / (TEST_PASSED + TEST_FAILED + TEST_SKIPPED) ))%

ENVIRONMENT:
-----------
Test Base Directory: $TEST_BASE_DIR
Log File: $TEST_LOG_FILE
Report File: $report_file

SYSTEM INFO:
-----------
OS: $(uname -s)
Kernel: $(uname -r)
Architecture: $(uname -m)
Available Disk Space: $(df -h "$TEST_BASE_DIR" | awk 'NR==2 {print $4}')

EOF
    
    # Append detailed log if verbose
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "" >> "$report_file"
        echo "DETAILED LOG:" >> "$report_file"
        echo "=============" >> "$report_file"
        cat "$TEST_LOG_FILE" >> "$report_file"
    fi
    
    log_info "Test report generated: $report_file"
    echo -e "\n${CYAN}📋 Test report: $report_file${NC}"
}

# Generate performance report
generate_performance_report() {
    local test_name="$1"
    local metrics_file="$2"
    local report_file="$TEST_REPORTS_DIR/${test_name}-performance-$TEST_SESSION_ID.txt"
    
    if [[ -f "$metrics_file" ]]; then
        cat > "$report_file" << EOF
===============================================================================
PERFORMANCE REPORT: $test_name
===============================================================================
Session ID: $TEST_SESSION_ID
Test Date: $(date '+%Y-%m-%d %H:%M:%S')

PERFORMANCE METRICS:
===================
EOF
        cat "$metrics_file" >> "$report_file"
        
        log_info "Performance report generated: $report_file"
        echo -e "\n${CYAN}📊 Performance report: $report_file${NC}"
    else
        log_warn "No metrics file found for performance report: $metrics_file"
    fi
}

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check required dependencies
check_dependencies() {
    local deps=("$@")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing[*]}"
        return 1
    fi
    
    log_debug "All dependencies satisfied: ${deps[*]}"
    return 0
}

# Wait for condition with timeout
wait_for_condition() {
    local condition="$1"
    local timeout="${2:-30}"
    local interval="${3:-1}"
    local elapsed=0
    
    while [[ $elapsed -lt $timeout ]]; do
        if eval "$condition"; then
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    
    log_error "Timeout waiting for condition: $condition"
    return 1
}

# Create test backup using the main backup script
create_test_backup() {
    local source_dir="$1"
    local backup_file="$2"
    local backup_script="${3:-/mnt/c/Users/jehma/Desktop/AI/DGMSTT/session-backup.sh}"
    
    if [[ ! -f "$backup_script" ]]; then
        log_error "Backup script not found: $backup_script"
        return 1
    fi
    
    # Temporarily modify backup script configuration for testing
    local temp_script="/tmp/test-backup-$$.sh"
    register_temp_file "$temp_script"
    
    # Copy and modify the backup script for testing
    sed -e "s|DEFAULT_SESSION_DIRS=.*|DEFAULT_SESSION_DIRS=(\"$source_dir\")|" \
        -e "s|BACKUP_DIR=.*|BACKUP_DIR=\"$(dirname "$backup_file")\"|" \
        -e "s|PROGRESS_ENABLED=.*|PROGRESS_ENABLED=false|" \
        -e "s|VERBOSE=.*|VERBOSE=false|" \
        "$backup_script" > "$temp_script"
    
    chmod +x "$temp_script"
    
    # Execute the modified backup script
    if "$temp_script"; then
        log_debug "Test backup created successfully"
        return 0
    else
        log_error "Test backup creation failed"
        return 1
    fi
}

#===============================================================================
# INITIALIZATION
#===============================================================================

# Set up trap for cleanup on exit
trap cleanup_on_exit EXIT INT TERM

# Export functions for use in other scripts
export -f log log_error log_warn log_info log_success log_debug log_perf
export -f test_start test_pass test_fail test_skip test_warn
export -f perf_start perf_end measure_time human_readable_size
export -f create_test_session_data create_test_files
export -f validate_backup_integrity compare_directories
export -f register_cleanup register_temp_file register_temp_dir cleanup_all
export -f generate_test_report generate_performance_report
export -f command_exists check_dependencies wait_for_condition create_test_backup

# Export variables
export TEST_BASE_DIR TEST_DATA_DIR TEST_BACKUP_DIR TEST_LOG_DIR TEST_REPORTS_DIR
export TEST_SESSION_ID TEST_LOG_FILE
export RED GREEN YELLOW BLUE PURPLE CYAN WHITE NC

log_debug "Backup testing utilities loaded successfully"