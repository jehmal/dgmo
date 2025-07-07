#!/bin/bash

# Archive Structure Validation Function
# Validate tar.gz structure and headers for backup integrity
# Author: DGMSTT System
# Version: 1.0

# Source the utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/backup-verification-utils.sh"

# Function: archive_structure_validation
# Purpose: Validate tar.gz archive structure, headers, and integrity
# Parameters:
#   $1: archive_path - Path to the tar.gz archive
#   $2: validation_level - Level of validation (basic, standard, thorough) [default: standard]
#   $3: extract_test - Whether to test extraction (true/false) [default: true]
#   $4: temp_extract_dir - Directory for test extraction [optional]
# Returns: Exit code indicating success or failure type

archive_structure_validation() {
    local archive_path="$1"
    local validation_level="${2:-standard}"
    local extract_test="${3:-true}"
    local temp_extract_dir="$4"
    
    # Validate parameters
    if [[ -z "$archive_path" ]]; then
        log_error "Archive path is required"
        return $EXIT_INVALID_ARGS
    fi
    
    # Validate validation level
    case "$validation_level" in
        basic|standard|thorough)
            ;;
        *)
            log_error "Invalid validation level: $validation_level. Supported: basic, standard, thorough"
            return $EXIT_INVALID_ARGS
            ;;
    esac
    
    log_info "Starting archive structure validation"
    log_verbose "Archive: $archive_path"
    log_verbose "Validation level: $validation_level"
    log_verbose "Extract test: $extract_test"
    
    start_timer "archive_validation"
    
    # Validate archive exists and is readable
    validate_file_exists "$archive_path" "Archive file" || return $?
    
    local exit_code=$EXIT_SUCCESS
    local validation_results=()
    
    # Basic validation - file format and basic integrity
    log_info "Performing basic validation..."
    if ! _validate_archive_format "$archive_path"; then
        validation_results+=("FAILED: Archive format validation")
        exit_code=$EXIT_ARCHIVE_CORRUPTED
    else
        validation_results+=("PASSED: Archive format validation")
    fi
    
    if ! _validate_archive_headers "$archive_path"; then
        validation_results+=("FAILED: Archive header validation")
        exit_code=$EXIT_ARCHIVE_CORRUPTED
    else
        validation_results+=("PASSED: Archive header validation")
    fi
    
    # Standard validation - includes listing and basic structure checks
    if [[ "$validation_level" == "standard" || "$validation_level" == "thorough" ]]; then
        log_info "Performing standard validation..."
        
        if ! _validate_archive_listing "$archive_path"; then
            validation_results+=("FAILED: Archive listing validation")
            exit_code=$EXIT_ARCHIVE_CORRUPTED
        else
            validation_results+=("PASSED: Archive listing validation")
        fi
        
        if ! _validate_archive_structure "$archive_path"; then
            validation_results+=("FAILED: Archive structure validation")
            exit_code=$EXIT_ARCHIVE_CORRUPTED
        else
            validation_results+=("PASSED: Archive structure validation")
        fi
    fi
    
    # Thorough validation - includes extraction test and deep inspection
    if [[ "$validation_level" == "thorough" ]]; then
        log_info "Performing thorough validation..."
        
        if ! _validate_compression_integrity "$archive_path"; then
            validation_results+=("FAILED: Compression integrity validation")
            exit_code=$EXIT_ARCHIVE_CORRUPTED
        else
            validation_results+=("PASSED: Compression integrity validation")
        fi
        
        if ! _validate_archive_metadata "$archive_path"; then
            validation_results+=("FAILED: Archive metadata validation")
            exit_code=$EXIT_ARCHIVE_CORRUPTED
        else
            validation_results+=("PASSED: Archive metadata validation")
        fi
    fi
    
    # Extraction test (if enabled)
    if [[ "$extract_test" == "true" ]]; then
        log_info "Performing extraction test..."
        
        if ! _test_archive_extraction "$archive_path" "$temp_extract_dir"; then
            validation_results+=("FAILED: Archive extraction test")
            exit_code=$EXIT_ARCHIVE_CORRUPTED
        else
            validation_results+=("PASSED: Archive extraction test")
        fi
    fi
    
    # Report results
    log_info "Archive validation results:"
    for result in "${validation_results[@]}"; do
        if [[ "$result" =~ ^PASSED ]]; then
            log_success "  ✓ ${result#PASSED: }"
        else
            log_error "  ✗ ${result#FAILED: }"
        fi
    done
    
    local duration=$(end_timer "archive_validation")
    
    if [[ $exit_code -eq $EXIT_SUCCESS ]]; then
        log_success "Archive validation completed successfully in ${duration}s"
    else
        log_error "Archive validation failed in ${duration}s"
    fi
    
    return $exit_code
}

# Validate archive file format
_validate_archive_format() {
    local archive_path="$1"
    
    log_verbose "Validating archive format..."
    
    # Check file extension
    if [[ ! "$archive_path" =~ \.(tar\.gz|tgz)$ ]]; then
        log_warn "Archive does not have .tar.gz or .tgz extension"
    fi
    
    # Check file magic number
    local file_type=$(file -b "$archive_path" 2>/dev/null)
    if [[ ! "$file_type" =~ gzip ]]; then
        log_error "File is not a gzip archive: $file_type"
        return 1
    fi
    
    # Test gzip integrity
    if ! gzip -t "$archive_path" 2>/dev/null; then
        log_error "Gzip integrity check failed"
        return 1
    fi
    
    log_verbose "Archive format validation passed"
    return 0
}

# Validate archive headers
_validate_archive_headers() {
    local archive_path="$1"
    
    log_verbose "Validating archive headers..."
    
    # Test tar headers without extracting
    if ! tar -tzf "$archive_path" >/dev/null 2>&1; then
        log_error "Tar header validation failed"
        return 1
    fi
    
    # Check for common tar corruption indicators
    local tar_output
    tar_output=$(tar -tzf "$archive_path" 2>&1)
    local tar_exit_code=$?
    
    if [[ $tar_exit_code -ne 0 ]]; then
        log_error "Tar listing failed with exit code: $tar_exit_code"
        log_error "Tar output: $tar_output"
        return 1
    fi
    
    # Check for warning messages that might indicate issues
    if echo "$tar_output" | grep -qi "warning\|error\|corrupt"; then
        log_warn "Tar reported warnings during header validation"
        log_verbose "Tar warnings: $tar_output"
    fi
    
    log_verbose "Archive header validation passed"
    return 0
}

# Validate archive listing
_validate_archive_listing() {
    local archive_path="$1"
    
    log_verbose "Validating archive listing..."
    
    # Get detailed listing
    local listing_output
    listing_output=$(tar -tvzf "$archive_path" 2>&1)
    local listing_exit_code=$?
    
    if [[ $listing_exit_code -ne 0 ]]; then
        log_error "Failed to get archive listing"
        return 1
    fi
    
    # Count entries
    local entry_count=$(echo "$listing_output" | wc -l)
    log_verbose "Archive contains $entry_count entries"
    
    if [[ $entry_count -eq 0 ]]; then
        log_error "Archive appears to be empty"
        return 1
    fi
    
    # Check for suspicious entries
    local suspicious_entries=0
    
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Check for entries with null bytes or control characters
        if echo "$line" | grep -q $'\0\|\x01\|\x02\|\x03\|\x04\|\x05\|\x06\|\x07\|\x08'; then
            log_warn "Suspicious entry with control characters: $line"
            suspicious_entries=$((suspicious_entries + 1))
        fi
        
        # Check for extremely long paths (potential path traversal)
        local path_part=$(echo "$line" | awk '{print $NF}')
        if [[ ${#path_part} -gt 4096 ]]; then
            log_warn "Extremely long path detected: ${path_part:0:100}..."
            suspicious_entries=$((suspicious_entries + 1))
        fi
        
        # Check for path traversal attempts
        if [[ "$path_part" =~ \.\./|\.\.\\ ]]; then
            log_warn "Potential path traversal detected: $path_part"
            suspicious_entries=$((suspicious_entries + 1))
        fi
        
    done <<< "$listing_output"
    
    if [[ $suspicious_entries -gt 0 ]]; then
        log_warn "Found $suspicious_entries suspicious entries in archive"
    fi
    
    log_verbose "Archive listing validation passed"
    return 0
}

# Validate archive structure
_validate_archive_structure() {
    local archive_path="$1"
    
    log_verbose "Validating archive structure..."
    
    # Get archive statistics
    local total_size=0
    local file_count=0
    local dir_count=0
    local symlink_count=0
    local special_count=0
    
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Parse tar listing format: permissions links owner group size date time path
        local permissions=$(echo "$line" | awk '{print $1}')
        local size=$(echo "$line" | awk '{print $5}')
        
        # Count by type
        case "${permissions:0:1}" in
            -)
                file_count=$((file_count + 1))
                if [[ "$size" =~ ^[0-9]+$ ]]; then
                    total_size=$((total_size + size))
                fi
                ;;
            d)
                dir_count=$((dir_count + 1))
                ;;
            l)
                symlink_count=$((symlink_count + 1))
                ;;
            *)
                special_count=$((special_count + 1))
                ;;
        esac
        
    done < <(tar -tvzf "$archive_path" 2>/dev/null)
    
    log_verbose "Archive structure statistics:"
    log_verbose "  Files: $file_count"
    log_verbose "  Directories: $dir_count"
    log_verbose "  Symlinks: $symlink_count"
    log_verbose "  Special files: $special_count"
    log_verbose "  Total content size: $(format_bytes $total_size)"
    
    # Validate structure makes sense
    if [[ $file_count -eq 0 && $dir_count -eq 0 ]]; then
        log_error "Archive contains no files or directories"
        return 1
    fi
    
    # Check for reasonable file to directory ratio
    if [[ $file_count -gt 0 && $dir_count -eq 0 ]]; then
        log_warn "Archive contains files but no directories (unusual structure)"
    fi
    
    log_verbose "Archive structure validation passed"
    return 0
}

# Validate compression integrity
_validate_compression_integrity() {
    local archive_path="$1"
    
    log_verbose "Validating compression integrity..."
    
    # Test decompression without extraction
    if ! gunzip -t "$archive_path" 2>/dev/null; then
        log_error "Gzip decompression test failed"
        return 1
    fi
    
    # Compare compressed vs uncompressed sizes
    local compressed_size=$(stat -c%s "$archive_path" 2>/dev/null || echo "0")
    local uncompressed_size=$(gunzip -l "$archive_path" 2>/dev/null | tail -n1 | awk '{print $2}' || echo "0")
    
    if [[ "$compressed_size" -eq 0 || "$uncompressed_size" -eq 0 ]]; then
        log_warn "Could not determine archive sizes for compression ratio check"
    else
        local compression_ratio=$((compressed_size * 100 / uncompressed_size))
        log_verbose "Compression ratio: ${compression_ratio}% ($(format_bytes $compressed_size) / $(format_bytes $uncompressed_size))"
        
        # Sanity check compression ratio
        if [[ $compression_ratio -gt 100 ]]; then
            log_error "Invalid compression ratio: compressed size larger than uncompressed"
            return 1
        fi
        
        if [[ $compression_ratio -gt 95 ]]; then
            log_warn "Very low compression ratio (${compression_ratio}%) - possible compression issue"
        fi
    fi
    
    log_verbose "Compression integrity validation passed"
    return 0
}

# Validate archive metadata
_validate_archive_metadata() {
    local archive_path="$1"
    
    log_verbose "Validating archive metadata..."
    
    # Check for consistent timestamps
    local timestamps=()
    local invalid_timestamps=0
    
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        # Extract timestamp (format varies, but typically: YYYY-MM-DD HH:MM)
        local timestamp=$(echo "$line" | awk '{print $(NF-2), $(NF-1)}')
        
        # Basic timestamp validation
        if [[ ! "$timestamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}$ ]]; then
            invalid_timestamps=$((invalid_timestamps + 1))
        fi
        
    done < <(tar -tvzf "$archive_path" 2>/dev/null | head -100)  # Sample first 100 entries
    
    if [[ $invalid_timestamps -gt 0 ]]; then
        log_warn "Found $invalid_timestamps entries with invalid timestamps"
    fi
    
    # Check for reasonable file permissions
    local suspicious_permissions=0
    
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue
        
        local permissions=$(echo "$line" | awk '{print $1}')
        
        # Check for overly permissive permissions
        if [[ "$permissions" =~ rwxrwxrwx ]]; then
            suspicious_permissions=$((suspicious_permissions + 1))
        fi
        
        # Check for setuid/setgid files
        if [[ "$permissions" =~ [st] ]]; then
            log_verbose "Found setuid/setgid file: $(echo "$line" | awk '{print $NF}')"
        fi
        
    done < <(tar -tvzf "$archive_path" 2>/dev/null | head -100)  # Sample first 100 entries
    
    if [[ $suspicious_permissions -gt 0 ]]; then
        log_warn "Found $suspicious_permissions files with overly permissive permissions"
    fi
    
    log_verbose "Archive metadata validation passed"
    return 0
}

# Test archive extraction
_test_archive_extraction() {
    local archive_path="$1"
    local temp_extract_dir="$2"
    
    log_verbose "Testing archive extraction..."
    
    # Create temporary extraction directory if not provided
    local extract_dir="$temp_extract_dir"
    local cleanup_extract_dir=false
    
    if [[ -z "$extract_dir" ]]; then
        extract_dir="$TEMP_DIR/extract_test"
        cleanup_extract_dir=true
    fi
    
    # Create extraction directory
    if ! mkdir -p "$extract_dir"; then
        log_error "Failed to create extraction directory: $extract_dir"
        return 1
    fi
    
    # Check available disk space
    local archive_size=$(stat -c%s "$archive_path" 2>/dev/null || echo "0")
    local estimated_extracted_size=$((archive_size * 3))  # Conservative estimate
    
    if ! check_disk_space "$extract_dir" "$estimated_extracted_size"; then
        log_error "Insufficient disk space for extraction test"
        return 1
    fi
    
    # Perform test extraction
    log_verbose "Extracting archive to: $extract_dir"
    
    local extract_output
    extract_output=$(tar -xzf "$archive_path" -C "$extract_dir" 2>&1)
    local extract_exit_code=$?
    
    if [[ $extract_exit_code -ne 0 ]]; then
        log_error "Archive extraction failed with exit code: $extract_exit_code"
        log_error "Extract output: $extract_output"
        
        # Cleanup on failure
        if [[ "$cleanup_extract_dir" == true ]]; then
            rm -rf "$extract_dir" 2>/dev/null
        fi
        
        return 1
    fi
    
    # Verify extraction results
    local extracted_files=$(find "$extract_dir" -type f | wc -l)
    local extracted_dirs=$(find "$extract_dir" -type d | wc -l)
    
    log_verbose "Extraction successful: $extracted_files files, $extracted_dirs directories"
    
    # Quick integrity check on extracted files
    local sample_files=()
    while IFS= read -r -d '' file; do
        sample_files+=("$file")
        [[ ${#sample_files[@]} -ge 10 ]] && break  # Sample up to 10 files
    done < <(find "$extract_dir" -type f -print0)
    
    local corrupted_files=0
    for file in "${sample_files[@]}"; do
        if [[ ! -r "$file" ]]; then
            log_warn "Extracted file is not readable: ${file#$extract_dir/}"
            corrupted_files=$((corrupted_files + 1))
        fi
    done
    
    if [[ $corrupted_files -gt 0 ]]; then
        log_warn "Found $corrupted_files potentially corrupted extracted files"
    fi
    
    # Cleanup extraction directory if we created it
    if [[ "$cleanup_extract_dir" == true ]]; then
        rm -rf "$extract_dir" 2>/dev/null
        log_verbose "Cleaned up extraction test directory"
    fi
    
    log_verbose "Archive extraction test passed"
    return 0
}

# Command line interface
archive_structure_validation_cli() {
    local archive_path=""
    local validation_level="standard"
    local extract_test="true"
    local temp_extract_dir=""
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--archive)
                archive_path="$2"
                shift 2
                ;;
            -l|--level)
                validation_level="$2"
                shift 2
                ;;
            --no-extract-test)
                extract_test="false"
                shift
                ;;
            --extract-dir)
                temp_extract_dir="$2"
                shift 2
                ;;
            -h|--help)
                _show_archive_help
                return $EXIT_SUCCESS
                ;;
            *)
                if ! parse_common_options "$@"; then
                    _show_archive_help
                    return $EXIT_SUCCESS
                fi
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$archive_path" ]]; then
        log_error "Archive path is required"
        _show_archive_help
        return $EXIT_INVALID_ARGS
    fi
    
    # Initialize utilities
    init_backup_verification_utils || return $?
    
    # Run archive validation
    archive_structure_validation "$archive_path" "$validation_level" "$extract_test" "$temp_extract_dir"
}

# Show help information
_show_archive_help() {
    cat << EOF
Archive Structure Validation Tool

USAGE:
    $0 [OPTIONS]

REQUIRED OPTIONS:
    -a, --archive PATH          Path to tar.gz archive file

OPTIONAL OPTIONS:
    -l, --level LEVEL           Validation level: basic, standard, thorough (default: standard)
    --no-extract-test           Skip extraction test
    --extract-dir PATH          Directory for extraction test (temporary if not specified)

COMMON OPTIONS:
    -v, --verbose               Enable verbose output
    -q, --quiet                 Suppress non-error output
    --log-file PATH             Write logs to specified file
    --no-progress               Disable progress indicators
    -h, --help                  Show this help message

VALIDATION LEVELS:
    basic       - File format and header validation only
    standard    - Basic + listing and structure validation
    thorough    - Standard + compression integrity and metadata validation

EXAMPLES:
    # Basic validation
    $0 -a /path/to/backup.tar.gz -l basic

    # Standard validation with extraction test
    $0 -a /path/to/backup.tar.gz

    # Thorough validation without extraction test
    $0 -a /path/to/backup.tar.gz -l thorough --no-extract-test

EXIT CODES:
    0   Success
    1   General error
    3   Archive corrupted
    9   Invalid arguments
    10  File not found
EOF
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    archive_structure_validation_cli "$@"
fi