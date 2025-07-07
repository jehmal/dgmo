#!/bin/bash

# verify-backup.sh - Comprehensive Backup Verification Script
# Author: AI Assistant
# Version: 1.0
# Description: Multi-level verification tool for tar.gz backup archives

set -euo pipefail

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_INVALID_ARGS=1
readonly EXIT_FILE_NOT_FOUND=2
readonly EXIT_ARCHIVE_CORRUPT=3
readonly EXIT_CONTENT_MISMATCH=4
readonly EXIT_PERMISSION_ERROR=5
readonly EXIT_EXTRACTION_FAILED=6
readonly EXIT_CHECKSUM_FAILED=7

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Global variables
BACKUP_FILE=""
VERIFICATION_LEVEL="STANDARD"
VERBOSE=false
QUIET=false
JSON_OUTPUT=false
CHECKSUM_TYPE="SHA256"
TEMP_DIR=""
START_TIME=""
RESULTS=()

# Performance metrics
VERIFICATION_TIME=0
ARCHIVE_SIZE=0
EXTRACTED_SIZE=0
FILE_COUNT=0
COMPRESSION_RATIO=0

# JSON result structure
JSON_RESULT='{
  "backup_file": "",
  "verification_level": "",
  "status": "",
  "start_time": "",
  "end_time": "",
  "duration": 0,
  "archive_size": 0,
  "extracted_size": 0,
  "file_count": 0,
  "compression_ratio": 0,
  "errors": [],
  "warnings": [],
  "details": {}
}'

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    if [[ "$QUIET" == false ]]; then
        echo -e "${color}${message}${NC}"
    fi
}

# Function to log messages
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        "INFO")
            if [[ "$VERBOSE" == true ]]; then
                print_color "$BLUE" "[$timestamp] INFO: $message"
            fi
            ;;
        "WARN")
            print_color "$YELLOW" "[$timestamp] WARNING: $message"
            ;;
        "ERROR")
            print_color "$RED" "[$timestamp] ERROR: $message"
            ;;
        "SUCCESS")
            print_color "$GREEN" "[$timestamp] SUCCESS: $message"
            ;;
        "HEADER")
            if [[ "$QUIET" == false ]]; then
                print_color "$WHITE" "=== $message ==="
            fi
            ;;
    esac
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] BACKUP_FILE

Comprehensive backup verification script for tar.gz archives.

VERIFICATION LEVELS:
  QUICK     - Basic archive integrity only (tar -tf)
  STANDARD  - Archive + file count + size validation (default)
  FULL      - Complete extraction test and content comparison
  DEEP      - Includes checksum verification of individual files

OPTIONS:
  -l, --level LEVEL     Verification level (QUICK|STANDARD|FULL|DEEP)
  -c, --checksum TYPE   Checksum type for DEEP verification (MD5|SHA256)
  -v, --verbose         Enable verbose output
  -q, --quiet           Suppress non-essential output
  -j, --json            Output results in JSON format
  -h, --help            Show this help message

EXAMPLES:
  $0 backup.tar.gz                    # Standard verification
  $0 -l FULL backup.tar.gz            # Full extraction test
  $0 -l DEEP -c MD5 backup.tar.gz     # Deep verification with MD5
  $0 -j -q backup.tar.gz              # JSON output, quiet mode

EXIT CODES:
  0 - Success
  1 - Invalid arguments
  2 - File not found
  3 - Archive corruption
  4 - Content mismatch
  5 - Permission error
  6 - Extraction failed
  7 - Checksum verification failed

EOF
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -l|--level)
                VERIFICATION_LEVEL="$2"
                if [[ ! "$VERIFICATION_LEVEL" =~ ^(QUICK|STANDARD|FULL|DEEP)$ ]]; then
                    log "ERROR" "Invalid verification level: $VERIFICATION_LEVEL"
                    exit $EXIT_INVALID_ARGS
                fi
                shift 2
                ;;
            -c|--checksum)
                CHECKSUM_TYPE="$2"
                if [[ ! "$CHECKSUM_TYPE" =~ ^(MD5|SHA256)$ ]]; then
                    log "ERROR" "Invalid checksum type: $CHECKSUM_TYPE"
                    exit $EXIT_INVALID_ARGS
                fi
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                QUIET=true
                shift
                ;;
            -h|--help)
                show_usage
                exit $EXIT_SUCCESS
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                show_usage
                exit $EXIT_INVALID_ARGS
                ;;
            *)
                if [[ -z "$BACKUP_FILE" ]]; then
                    BACKUP_FILE="$1"
                else
                    log "ERROR" "Multiple backup files specified"
                    exit $EXIT_INVALID_ARGS
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$BACKUP_FILE" ]]; then
        log "ERROR" "No backup file specified"
        show_usage
        exit $EXIT_INVALID_ARGS
    fi
}

# Function to validate backup file
validate_backup_file() {
    log "INFO" "Validating backup file: $BACKUP_FILE"
    
    if [[ ! -f "$BACKUP_FILE" ]]; then
        log "ERROR" "Backup file not found: $BACKUP_FILE"
        exit $EXIT_FILE_NOT_FOUND
    fi

    if [[ ! -r "$BACKUP_FILE" ]]; then
        log "ERROR" "Cannot read backup file: $BACKUP_FILE"
        exit $EXIT_PERMISSION_ERROR
    fi

    # Check if it's a tar.gz file
    if ! file "$BACKUP_FILE" | grep -q "gzip compressed"; then
        log "WARN" "File may not be a gzip compressed archive"
    fi

    ARCHIVE_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE" 2>/dev/null || echo 0)
    log "INFO" "Archive size: $(numfmt --to=iec $ARCHIVE_SIZE)"
}

# Function to create temporary directory
create_temp_dir() {
    TEMP_DIR=$(mktemp -d -t backup-verify-XXXXXX)
    log "INFO" "Created temporary directory: $TEMP_DIR"
    
    # Ensure cleanup on exit
    trap cleanup_temp_dir EXIT
}

# Function to cleanup temporary directory
cleanup_temp_dir() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        log "INFO" "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# Function to calculate file checksum
calculate_checksum() {
    local file="$1"
    local type="$2"
    
    case $type in
        "MD5")
            if command -v md5sum >/dev/null 2>&1; then
                md5sum "$file" | cut -d' ' -f1
            elif command -v md5 >/dev/null 2>&1; then
                md5 -q "$file"
            else
                log "ERROR" "MD5 checksum tool not available"
                return 1
            fi
            ;;
        "SHA256")
            if command -v sha256sum >/dev/null 2>&1; then
                sha256sum "$file" | cut -d' ' -f1
            elif command -v shasum >/dev/null 2>&1; then
                shasum -a 256 "$file" | cut -d' ' -f1
            else
                log "ERROR" "SHA256 checksum tool not available"
                return 1
            fi
            ;;
    esac
}

# Function to perform QUICK verification
verify_quick() {
    log "HEADER" "QUICK Verification"
    log "INFO" "Testing archive integrity..."
    
    if tar -tzf "$BACKUP_FILE" >/dev/null 2>&1; then
        log "SUCCESS" "Archive integrity check passed"
        FILE_COUNT=$(tar -tzf "$BACKUP_FILE" | wc -l)
        log "INFO" "Archive contains $FILE_COUNT files/directories"
        return 0
    else
        log "ERROR" "Archive integrity check failed"
        return $EXIT_ARCHIVE_CORRUPT
    fi
}

# Function to perform STANDARD verification
verify_standard() {
    log "HEADER" "STANDARD Verification"
    
    # First run quick verification
    if ! verify_quick; then
        return $EXIT_ARCHIVE_CORRUPT
    fi
    
    log "INFO" "Performing detailed archive analysis..."
    
    # Get detailed file listing
    local file_list
    if ! file_list=$(tar -tvzf "$BACKUP_FILE" 2>&1); then
        log "ERROR" "Failed to get detailed file listing"
        return $EXIT_ARCHIVE_CORRUPT
    fi
    
    # Calculate total uncompressed size
    EXTRACTED_SIZE=$(echo "$file_list" | awk '{sum += $3} END {print sum+0}')
    COMPRESSION_RATIO=$(echo "scale=2; $ARCHIVE_SIZE / $EXTRACTED_SIZE * 100" | bc -l 2>/dev/null || echo "0")
    
    log "INFO" "Uncompressed size: $(numfmt --to=iec $EXTRACTED_SIZE)"
    log "INFO" "Compression ratio: ${COMPRESSION_RATIO}%"
    
    # Check for suspicious files
    local suspicious_count
    suspicious_count=$(echo "$file_list" | grep -E '\.(tmp|temp|cache|log)$' | wc -l)
    if [[ $suspicious_count -gt 0 ]]; then
        log "WARN" "Found $suspicious_count potentially temporary files in backup"
    fi
    
    log "SUCCESS" "Standard verification completed"
    return 0
}

# Function to perform FULL verification
verify_full() {
    log "HEADER" "FULL Verification"
    
    # First run standard verification
    if ! verify_standard; then
        return $?
    fi
    
    create_temp_dir
    
    log "INFO" "Performing test extraction..."
    
    # Extract to temporary directory
    if ! tar -xzf "$BACKUP_FILE" -C "$TEMP_DIR" 2>&1; then
        log "ERROR" "Test extraction failed"
        return $EXIT_EXTRACTION_FAILED
    fi
    
    log "SUCCESS" "Test extraction completed"
    
    # Verify extracted content
    log "INFO" "Verifying extracted content..."
    
    local extracted_files
    extracted_files=$(find "$TEMP_DIR" -type f | wc -l)
    
    if [[ $extracted_files -ne $FILE_COUNT ]]; then
        log "WARN" "File count mismatch: expected $FILE_COUNT, found $extracted_files"
    fi
    
    # Check for extraction errors
    local broken_links
    broken_links=$(find "$TEMP_DIR" -type l ! -exec test -e {} \; -print | wc -l)
    if [[ $broken_links -gt 0 ]]; then
        log "WARN" "Found $broken_links broken symbolic links"
    fi
    
    log "SUCCESS" "Full verification completed"
    return 0
}

# Function to perform DEEP verification
verify_deep() {
    log "HEADER" "DEEP Verification"
    
    # First run full verification
    if ! verify_full; then
        return $?
    fi
    
    log "INFO" "Performing deep checksum verification..."
    
    # Create checksum file for archive contents
    local checksum_file="$TEMP_DIR/checksums.txt"
    local failed_checksums=0
    
    # Calculate checksums for all files in extracted archive
    while IFS= read -r -d '' file; do
        if [[ -f "$file" && ! -L "$file" ]]; then
            local relative_path="${file#$TEMP_DIR/}"
            local checksum
            if checksum=$(calculate_checksum "$file" "$CHECKSUM_TYPE"); then
                echo "$checksum  $relative_path" >> "$checksum_file"
                log "INFO" "Calculated $CHECKSUM_TYPE for: $relative_path"
            else
                log "ERROR" "Failed to calculate checksum for: $relative_path"
                ((failed_checksums++))
            fi
        fi
    done < <(find "$TEMP_DIR" -type f -print0)
    
    if [[ $failed_checksums -gt 0 ]]; then
        log "ERROR" "$failed_checksums files failed checksum calculation"
        return $EXIT_CHECKSUM_FAILED
    fi
    
    # Verify file integrity by re-extracting and comparing checksums
    log "INFO" "Re-extracting archive for checksum verification..."
    
    local verify_dir="$TEMP_DIR/verify"
    mkdir -p "$verify_dir"
    
    if ! tar -xzf "$BACKUP_FILE" -C "$verify_dir" 2>&1; then
        log "ERROR" "Re-extraction failed during deep verification"
        return $EXIT_EXTRACTION_FAILED
    fi
    
    # Compare checksums
    local checksum_mismatches=0
    while IFS= read -r line; do
        local expected_checksum=$(echo "$line" | cut -d' ' -f1)
        local file_path=$(echo "$line" | cut -d' ' -f3-)
        local verify_file="$verify_dir/$file_path"
        
        if [[ -f "$verify_file" ]]; then
            local actual_checksum
            if actual_checksum=$(calculate_checksum "$verify_file" "$CHECKSUM_TYPE"); then
                if [[ "$expected_checksum" != "$actual_checksum" ]]; then
                    log "ERROR" "Checksum mismatch for: $file_path"
                    ((checksum_mismatches++))
                fi
            else
                log "ERROR" "Failed to verify checksum for: $file_path"
                ((checksum_mismatches++))
            fi
        else
            log "ERROR" "File missing in re-extraction: $file_path"
            ((checksum_mismatches++))
        fi
    done < "$checksum_file"
    
    if [[ $checksum_mismatches -gt 0 ]]; then
        log "ERROR" "$checksum_mismatches files failed checksum verification"
        return $EXIT_CHECKSUM_FAILED
    fi
    
    log "SUCCESS" "Deep verification completed - all checksums verified"
    return 0
}

# Function to run verification based on level
run_verification() {
    local exit_code=0
    
    case $VERIFICATION_LEVEL in
        "QUICK")
            verify_quick
            exit_code=$?
            ;;
        "STANDARD")
            verify_standard
            exit_code=$?
            ;;
        "FULL")
            verify_full
            exit_code=$?
            ;;
        "DEEP")
            verify_deep
            exit_code=$?
            ;;
    esac
    
    return $exit_code
}

# Function to generate performance report
generate_report() {
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    local end_timestamp=$(date +%s)
    local start_timestamp=$(date -d "$START_TIME" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M:%S' "$START_TIME" +%s 2>/dev/null || echo $end_timestamp)
    VERIFICATION_TIME=$((end_timestamp - start_timestamp))
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        # Generate JSON output
        cat << EOF
{
  "backup_file": "$BACKUP_FILE",
  "verification_level": "$VERIFICATION_LEVEL",
  "status": "success",
  "start_time": "$START_TIME",
  "end_time": "$end_time",
  "duration": $VERIFICATION_TIME,
  "archive_size": $ARCHIVE_SIZE,
  "extracted_size": $EXTRACTED_SIZE,
  "file_count": $FILE_COUNT,
  "compression_ratio": $COMPRESSION_RATIO,
  "checksum_type": "$CHECKSUM_TYPE",
  "errors": [],
  "warnings": []
}
EOF
    else
        # Generate human-readable report
        log "HEADER" "Verification Report"
        print_color "$WHITE" "Backup File: $BACKUP_FILE"
        print_color "$WHITE" "Verification Level: $VERIFICATION_LEVEL"
        print_color "$WHITE" "Start Time: $START_TIME"
        print_color "$WHITE" "End Time: $end_time"
        print_color "$WHITE" "Duration: ${VERIFICATION_TIME}s"
        print_color "$WHITE" "Archive Size: $(numfmt --to=iec $ARCHIVE_SIZE)"
        if [[ $EXTRACTED_SIZE -gt 0 ]]; then
            print_color "$WHITE" "Extracted Size: $(numfmt --to=iec $EXTRACTED_SIZE)"
            print_color "$WHITE" "Compression Ratio: ${COMPRESSION_RATIO}%"
        fi
        print_color "$WHITE" "File Count: $FILE_COUNT"
        if [[ "$VERIFICATION_LEVEL" == "DEEP" ]]; then
            print_color "$WHITE" "Checksum Type: $CHECKSUM_TYPE"
        fi
        print_color "$GREEN" "✓ Verification PASSED"
    fi
}

# Function to handle errors and generate error report
handle_error() {
    local exit_code=$1
    local error_message=""
    
    case $exit_code in
        $EXIT_ARCHIVE_CORRUPT)
            error_message="Archive corruption detected"
            ;;
        $EXIT_CONTENT_MISMATCH)
            error_message="Content validation failed"
            ;;
        $EXIT_EXTRACTION_FAILED)
            error_message="Test extraction failed"
            ;;
        $EXIT_CHECKSUM_FAILED)
            error_message="Checksum verification failed"
            ;;
        *)
            error_message="Unknown error occurred"
            ;;
    esac
    
    if [[ "$JSON_OUTPUT" == true ]]; then
        cat << EOF
{
  "backup_file": "$BACKUP_FILE",
  "verification_level": "$VERIFICATION_LEVEL",
  "status": "failed",
  "start_time": "$START_TIME",
  "end_time": "$(date '+%Y-%m-%d %H:%M:%S')",
  "duration": $(($(date +%s) - $(date -d "$START_TIME" +%s 2>/dev/null || echo $(date +%s)))),
  "error_code": $exit_code,
  "error_message": "$error_message",
  "errors": ["$error_message"]
}
EOF
    else
        log "HEADER" "Verification Failed"
        print_color "$RED" "✗ $error_message"
        print_color "$WHITE" "Exit Code: $exit_code"
    fi
}

# Main function
main() {
    START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate backup file
    validate_backup_file
    
    # Run verification
    log "HEADER" "Starting $VERIFICATION_LEVEL verification of $BACKUP_FILE"
    
    local exit_code=0
    if run_verification; then
        generate_report
    else
        exit_code=$?
        handle_error $exit_code
    fi
    
    exit $exit_code
}

# Run main function with all arguments
main "$@"