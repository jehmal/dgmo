#!/bin/bash

# Checksum Verification Function
# Generate and verify MD5/SHA256 checksums for backup integrity
# Author: DGMSTT System
# Version: 1.0

# Source the utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/backup-verification-utils.sh"

# Function: checksum_verification
# Purpose: Generate and verify checksums for files and directories
# Parameters:
#   $1: source_path - Path to source file/directory
#   $2: backup_path - Path to backup file/directory (optional for generation only)
#   $3: algorithm - Checksum algorithm (md5, sha256, both) [default: sha256]
#   $4: checksum_file - Path to store/read checksums [optional]
#   $5: mode - Operation mode (generate, verify, both) [default: both]
# Returns: Exit code indicating success or failure type

checksum_verification() {
    local source_path="$1"
    local backup_path="$2"
    local algorithm="${3:-sha256}"
    local checksum_file="$4"
    local mode="${5:-both}"
    
    # Validate parameters
    if [[ -z "$source_path" ]]; then
        log_error "Source path is required"
        return $EXIT_INVALID_ARGS
    fi
    
    # Validate algorithm
    case "$algorithm" in
        md5|sha256|both)
            ;;
        *)
            log_error "Invalid algorithm: $algorithm. Supported: md5, sha256, both"
            return $EXIT_INVALID_ARGS
            ;;
    esac
    
    # Validate mode
    case "$mode" in
        generate|verify|both)
            ;;
        *)
            log_error "Invalid mode: $mode. Supported: generate, verify, both"
            return $EXIT_INVALID_ARGS
            ;;
    esac
    
    log_info "Starting checksum verification"
    log_verbose "Source: $source_path"
    log_verbose "Backup: $backup_path"
    log_verbose "Algorithm: $algorithm"
    log_verbose "Mode: $mode"
    
    start_timer "checksum_verification"
    
    # Validate source exists
    if [[ -f "$source_path" ]]; then
        local source_type="file"
    elif [[ -d "$source_path" ]]; then
        local source_type="directory"
    else
        log_error "Source path does not exist: $source_path"
        return $EXIT_FILE_NOT_FOUND
    fi
    
    # Set default checksum file if not provided
    if [[ -z "$checksum_file" ]]; then
        if [[ "$source_type" == "file" ]]; then
            checksum_file="${source_path}.checksums"
        else
            checksum_file="${source_path%/}/checksums.txt"
        fi
    fi
    
    local exit_code=$EXIT_SUCCESS
    
    # Generate checksums
    if [[ "$mode" == "generate" || "$mode" == "both" ]]; then
        log_info "Generating checksums..."
        
        if ! _generate_checksums "$source_path" "$source_type" "$algorithm" "$checksum_file"; then
            exit_code=$EXIT_GENERAL_ERROR
        fi
    fi
    
    # Verify checksums
    if [[ "$mode" == "verify" || "$mode" == "both" ]] && [[ -n "$backup_path" ]]; then
        log_info "Verifying checksums..."
        
        if [[ ! -f "$checksum_file" ]]; then
            log_error "Checksum file not found: $checksum_file"
            return $EXIT_FILE_NOT_FOUND
        fi
        
        if ! _verify_checksums "$backup_path" "$checksum_file" "$algorithm"; then
            exit_code=$EXIT_CHECKSUM_MISMATCH
        fi
    elif [[ "$mode" == "verify" || "$mode" == "both" ]]; then
        log_warn "Backup path not provided, skipping verification"
    fi
    
    local duration=$(end_timer "checksum_verification")
    log_info "Checksum verification completed in ${duration}s"
    
    return $exit_code
}

# Internal function to generate checksums
_generate_checksums() {
    local source_path="$1"
    local source_type="$2"
    local algorithm="$3"
    local checksum_file="$4"
    
    log_verbose "Generating checksums for $source_type: $source_path"
    
    # Create checksum file directory if needed
    local checksum_dir=$(dirname "$checksum_file")
    if [[ ! -d "$checksum_dir" ]]; then
        mkdir -p "$checksum_dir" || {
            log_error "Failed to create checksum directory: $checksum_dir"
            return 1
        }
    fi
    
    # Initialize checksum file
    echo "# Checksums generated on $(date)" > "$checksum_file"
    echo "# Source: $source_path" >> "$checksum_file"
    echo "# Algorithm: $algorithm" >> "$checksum_file"
    echo "" >> "$checksum_file"
    
    if [[ "$source_type" == "file" ]]; then
        _generate_file_checksums "$source_path" "$algorithm" "$checksum_file"
    else
        _generate_directory_checksums "$source_path" "$algorithm" "$checksum_file"
    fi
    
    local result=$?
    
    if [[ $result -eq 0 ]]; then
        log_success "Checksums generated successfully: $checksum_file"
    else
        log_error "Failed to generate checksums"
    fi
    
    return $result
}

# Generate checksums for a single file
_generate_file_checksums() {
    local file_path="$1"
    local algorithm="$2"
    local checksum_file="$3"
    
    local filename=$(basename "$file_path")
    
    if [[ "$algorithm" == "md5" || "$algorithm" == "both" ]]; then
        log_verbose "Generating MD5 checksum for $filename"
        local md5_hash=$(md5sum "$file_path" | cut -d' ' -f1)
        echo "MD5:$md5_hash:$filename" >> "$checksum_file"
    fi
    
    if [[ "$algorithm" == "sha256" || "$algorithm" == "both" ]]; then
        log_verbose "Generating SHA256 checksum for $filename"
        local sha256_hash=$(sha256sum "$file_path" | cut -d' ' -f1)
        echo "SHA256:$sha256_hash:$filename" >> "$checksum_file"
    fi
    
    return 0
}

# Generate checksums for directory contents
_generate_directory_checksums() {
    local dir_path="$1"
    local algorithm="$2"
    local checksum_file="$3"
    
    log_verbose "Finding files in directory: $dir_path"
    
    # Get list of files (excluding directories)
    local file_list=()
    while IFS= read -r -d '' file; do
        file_list+=("$file")
    done < <(find "$dir_path" -type f -print0 | sort -z)
    
    local total_files=${#file_list[@]}
    log_info "Found $total_files files to checksum"
    
    if [[ $total_files -eq 0 ]]; then
        log_warn "No files found in directory: $dir_path"
        return 0
    fi
    
    local current_file=0
    local failed_files=0
    
    for file in "${file_list[@]}"; do
        current_file=$((current_file + 1))
        show_progress "$current_file" "$total_files" "Generating checksums"
        
        # Get relative path
        local rel_path="${file#$dir_path/}"
        
        if [[ "$algorithm" == "md5" || "$algorithm" == "both" ]]; then
            local md5_hash=$(md5sum "$file" 2>/dev/null | cut -d' ' -f1)
            if [[ $? -eq 0 && -n "$md5_hash" ]]; then
                echo "MD5:$md5_hash:$rel_path" >> "$checksum_file"
            else
                log_warn "Failed to generate MD5 for: $rel_path"
                failed_files=$((failed_files + 1))
            fi
        fi
        
        if [[ "$algorithm" == "sha256" || "$algorithm" == "both" ]]; then
            local sha256_hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1)
            if [[ $? -eq 0 && -n "$sha256_hash" ]]; then
                echo "SHA256:$sha256_hash:$rel_path" >> "$checksum_file"
            else
                log_warn "Failed to generate SHA256 for: $rel_path"
                failed_files=$((failed_files + 1))
            fi
        fi
    done
    
    if [[ $failed_files -gt 0 ]]; then
        log_warn "Failed to generate checksums for $failed_files files"
        return 1
    fi
    
    return 0
}

# Internal function to verify checksums
_verify_checksums() {
    local backup_path="$1"
    local checksum_file="$2"
    local algorithm="$3"
    
    log_verbose "Verifying checksums against: $backup_path"
    
    # Determine backup type
    if [[ -f "$backup_path" ]]; then
        local backup_type="file"
    elif [[ -d "$backup_path" ]]; then
        local backup_type="directory"
    else
        log_error "Backup path does not exist: $backup_path"
        return 1
    fi
    
    # Read and verify checksums
    local total_checksums=0
    local verified_checksums=0
    local failed_checksums=0
    local missing_files=0
    
    # Count total checksums first
    total_checksums=$(grep -c "^[A-Z0-9]*:" "$checksum_file" 2>/dev/null || echo "0")
    
    if [[ $total_checksums -eq 0 ]]; then
        log_error "No checksums found in file: $checksum_file"
        return 1
    fi
    
    log_info "Verifying $total_checksums checksums"
    
    local current_checksum=0
    
    while IFS=':' read -r hash_type expected_hash file_path; do
        # Skip comments and empty lines
        [[ "$hash_type" =~ ^#.*$ || -z "$hash_type" ]] && continue
        
        current_checksum=$((current_checksum + 1))
        show_progress "$current_checksum" "$total_checksums" "Verifying checksums"
        
        # Skip if algorithm doesn't match
        if [[ "$algorithm" != "both" ]]; then
            case "$algorithm" in
                md5)
                    [[ "$hash_type" != "MD5" ]] && continue
                    ;;
                sha256)
                    [[ "$hash_type" != "SHA256" ]] && continue
                    ;;
            esac
        fi
        
        # Construct full path to file in backup
        local full_backup_path
        if [[ "$backup_type" == "file" ]]; then
            full_backup_path="$backup_path"
        else
            full_backup_path="$backup_path/$file_path"
        fi
        
        # Check if file exists
        if [[ ! -f "$full_backup_path" ]]; then
            log_error "Missing file in backup: $file_path"
            missing_files=$((missing_files + 1))
            continue
        fi
        
        # Calculate actual checksum
        local actual_hash
        case "$hash_type" in
            MD5)
                actual_hash=$(md5sum "$full_backup_path" 2>/dev/null | cut -d' ' -f1)
                ;;
            SHA256)
                actual_hash=$(sha256sum "$full_backup_path" 2>/dev/null | cut -d' ' -f1)
                ;;
            *)
                log_warn "Unknown hash type: $hash_type for file: $file_path"
                continue
                ;;
        esac
        
        if [[ -z "$actual_hash" ]]; then
            log_error "Failed to calculate $hash_type checksum for: $file_path"
            failed_checksums=$((failed_checksums + 1))
            continue
        fi
        
        # Compare checksums
        if [[ "$expected_hash" == "$actual_hash" ]]; then
            log_verbose "✓ $hash_type checksum verified: $file_path"
            verified_checksums=$((verified_checksums + 1))
        else
            log_error "✗ $hash_type checksum mismatch: $file_path"
            log_error "  Expected: $expected_hash"
            log_error "  Actual:   $actual_hash"
            failed_checksums=$((failed_checksums + 1))
        fi
        
    done < "$checksum_file"
    
    # Report results
    log_info "Checksum verification results:"
    log_info "  Total checksums: $total_checksums"
    log_info "  Verified: $verified_checksums"
    log_info "  Failed: $failed_checksums"
    log_info "  Missing files: $missing_files"
    
    if [[ $failed_checksums -gt 0 || $missing_files -gt 0 ]]; then
        log_error "Checksum verification failed"
        return 1
    else
        log_success "All checksums verified successfully"
        return 0
    fi
}

# Command line interface
checksum_verification_cli() {
    local source_path=""
    local backup_path=""
    local algorithm="sha256"
    local checksum_file=""
    local mode="both"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--source)
                source_path="$2"
                shift 2
                ;;
            -b|--backup)
                backup_path="$2"
                shift 2
                ;;
            -a|--algorithm)
                algorithm="$2"
                shift 2
                ;;
            -c|--checksum-file)
                checksum_file="$2"
                shift 2
                ;;
            -m|--mode)
                mode="$2"
                shift 2
                ;;
            -h|--help)
                _show_checksum_help
                return $EXIT_SUCCESS
                ;;
            *)
                if ! parse_common_options "$@"; then
                    _show_checksum_help
                    return $EXIT_SUCCESS
                fi
                shift
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$source_path" ]]; then
        log_error "Source path is required"
        _show_checksum_help
        return $EXIT_INVALID_ARGS
    fi
    
    # Initialize utilities
    init_backup_verification_utils || return $?
    
    # Run checksum verification
    checksum_verification "$source_path" "$backup_path" "$algorithm" "$checksum_file" "$mode"
}

# Show help information
_show_checksum_help() {
    cat << EOF
Checksum Verification Tool

USAGE:
    $0 [OPTIONS]

REQUIRED OPTIONS:
    -s, --source PATH           Source file or directory path

OPTIONAL OPTIONS:
    -b, --backup PATH           Backup file or directory path (required for verification)
    -a, --algorithm ALGO        Checksum algorithm: md5, sha256, both (default: sha256)
    -c, --checksum-file PATH    Path to checksum file (auto-generated if not specified)
    -m, --mode MODE             Operation mode: generate, verify, both (default: both)

COMMON OPTIONS:
    -v, --verbose               Enable verbose output
    -q, --quiet                 Suppress non-error output
    --log-file PATH             Write logs to specified file
    --no-progress               Disable progress indicators
    -h, --help                  Show this help message

EXAMPLES:
    # Generate checksums for a file
    $0 -s /path/to/file.txt -m generate

    # Verify backup against checksums
    $0 -s /path/to/original -b /path/to/backup -m verify

    # Generate and verify with both MD5 and SHA256
    $0 -s /path/to/dir -b /path/to/backup -a both

EXIT CODES:
    0   Success
    1   General error
    2   Checksum mismatch
    9   Invalid arguments
    10  File not found
EOF
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    checksum_verification_cli "$@"
fi