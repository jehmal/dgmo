#!/bin/bash

# Backup Verification Utilities
# Shared functions and utilities for backup integrity checking
# Author: DGMSTT System
# Version: 1.0

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_CHECKSUM_MISMATCH=2
readonly EXIT_ARCHIVE_CORRUPTED=3
readonly EXIT_FILE_COUNT_MISMATCH=4
readonly EXIT_SIZE_MISMATCH=5
readonly EXIT_TIMESTAMP_MISMATCH=6
readonly EXIT_PERMISSION_MISMATCH=7
readonly EXIT_METADATA_MISMATCH=8
readonly EXIT_INVALID_ARGS=9
readonly EXIT_FILE_NOT_FOUND=10

# Global variables
VERBOSE=false
QUIET=false
LOG_FILE=""
TEMP_DIR=""
PROGRESS_ENABLED=true

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$QUIET" != true ]]; then
        echo -e "${BLUE}[INFO]${NC} $message"
    fi
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [INFO] $message" >> "$LOG_FILE"
    fi
}

log_warn() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$QUIET" != true ]]; then
        echo -e "${YELLOW}[WARN]${NC} $message" >&2
    fi
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [WARN] $message" >> "$LOG_FILE"
    fi
}

log_error() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo -e "${RED}[ERROR]${NC} $message" >&2
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [ERROR] $message" >> "$LOG_FILE"
    fi
}

log_success() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$QUIET" != true ]]; then
        echo -e "${GREEN}[SUCCESS]${NC} $message"
    fi
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [SUCCESS] $message" >> "$LOG_FILE"
    fi
}

log_verbose() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$VERBOSE" == true ]]; then
        echo -e "${CYAN}[VERBOSE]${NC} $message"
        
        if [[ -n "$LOG_FILE" ]]; then
            echo "[$timestamp] [VERBOSE] $message" >> "$LOG_FILE"
        fi
    fi
}

# Progress indicator functions
show_progress() {
    local current="$1"
    local total="$2"
    local operation="$3"
    
    if [[ "$PROGRESS_ENABLED" == true && "$QUIET" != true ]]; then
        local percent=$((current * 100 / total))
        local filled=$((percent / 2))
        local empty=$((50 - filled))
        
        printf "\r${BLUE}[PROGRESS]${NC} $operation: ["
        printf "%${filled}s" | tr ' ' '='
        printf "%${empty}s" | tr ' ' '-'
        printf "] %d%% (%d/%d)" "$percent" "$current" "$total"
        
        if [[ "$current" -eq "$total" ]]; then
            echo
        fi
    fi
}

# Utility functions
create_temp_dir() {
    TEMP_DIR=$(mktemp -d -t backup_verification_XXXXXX)
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create temporary directory"
        return $EXIT_GENERAL_ERROR
    fi
    log_verbose "Created temporary directory: $TEMP_DIR"
    return $EXIT_SUCCESS
}

cleanup_temp_dir() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_verbose "Cleaned up temporary directory: $TEMP_DIR"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_temp_dir EXIT

validate_file_exists() {
    local file="$1"
    local description="$2"
    
    if [[ ! -f "$file" ]]; then
        log_error "$description not found: $file"
        return $EXIT_FILE_NOT_FOUND
    fi
    
    if [[ ! -r "$file" ]]; then
        log_error "$description is not readable: $file"
        return $EXIT_GENERAL_ERROR
    fi
    
    return $EXIT_SUCCESS
}

validate_directory_exists() {
    local dir="$1"
    local description="$2"
    
    if [[ ! -d "$dir" ]]; then
        log_error "$description not found: $dir"
        return $EXIT_FILE_NOT_FOUND
    fi
    
    if [[ ! -r "$dir" ]]; then
        log_error "$description is not readable: $dir"
        return $EXIT_GENERAL_ERROR
    fi
    
    return $EXIT_SUCCESS
}

# Format bytes to human readable
format_bytes() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit=0
    local size="$bytes"
    
    while [[ $size -gt 1024 && $unit -lt 4 ]]; do
        size=$((size / 1024))
        unit=$((unit + 1))
    done
    
    echo "${size}${units[$unit]}"
}

# Calculate percentage difference
calculate_percentage_diff() {
    local val1="$1"
    local val2="$2"
    
    if [[ "$val1" -eq 0 && "$val2" -eq 0 ]]; then
        echo "0"
        return
    fi
    
    if [[ "$val1" -eq 0 ]]; then
        echo "100"
        return
    fi
    
    local diff=$((val1 > val2 ? val1 - val2 : val2 - val1))
    local percent=$((diff * 100 / val1))
    echo "$percent"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate required commands
validate_dependencies() {
    local missing_commands=()
    
    # Check for required commands
    local required_commands=("tar" "gzip" "md5sum" "sha256sum" "find" "stat" "wc")
    
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing_commands[*]}"
        log_error "Please install the missing commands and try again"
        return $EXIT_GENERAL_ERROR
    fi
    
    return $EXIT_SUCCESS
}

# Parse common command line options
parse_common_options() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --log-file)
                LOG_FILE="$2"
                shift 2
                ;;
            --no-progress)
                PROGRESS_ENABLED=false
                shift
                ;;
            -h|--help)
                return 1  # Signal to show help
                ;;
            *)
                # Unknown option, let calling function handle it
                break
                ;;
        esac
    done
    
    return 0
}

# Initialize logging
init_logging() {
    if [[ -n "$LOG_FILE" ]]; then
        # Create log file directory if it doesn't exist
        local log_dir=$(dirname "$LOG_FILE")
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" || {
                log_error "Failed to create log directory: $log_dir"
                return $EXIT_GENERAL_ERROR
            }
        fi
        
        # Initialize log file
        echo "=== Backup Verification Log - $(date) ===" > "$LOG_FILE"
        log_verbose "Logging initialized to: $LOG_FILE"
    fi
    
    return $EXIT_SUCCESS
}

# Performance timing functions
declare -A TIMERS

start_timer() {
    local name="$1"
    TIMERS["$name"]=$(date +%s.%N)
}

end_timer() {
    local name="$1"
    local start_time="${TIMERS[$name]}"
    
    if [[ -z "$start_time" ]]; then
        log_warn "Timer '$name' was not started"
        return
    fi
    
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")
    
    log_verbose "Timer '$name': ${duration}s"
    echo "$duration"
}

# Memory usage monitoring
get_memory_usage() {
    local pid=${1:-$$}
    if [[ -f "/proc/$pid/status" ]]; then
        grep "VmRSS" "/proc/$pid/status" | awk '{print $2}'
    else
        echo "0"
    fi
}

# Disk space checking
check_disk_space() {
    local path="$1"
    local required_space="$2"  # in bytes
    
    local available_space=$(df --output=avail "$path" | tail -n1)
    available_space=$((available_space * 1024))  # Convert from KB to bytes
    
    if [[ "$available_space" -lt "$required_space" ]]; then
        log_error "Insufficient disk space. Required: $(format_bytes $required_space), Available: $(format_bytes $available_space)"
        return $EXIT_GENERAL_ERROR
    fi
    
    return $EXIT_SUCCESS
}

# Signal handling
setup_signal_handlers() {
    trap 'log_warn "Received SIGINT, cleaning up..."; cleanup_temp_dir; exit 130' INT
    trap 'log_warn "Received SIGTERM, cleaning up..."; cleanup_temp_dir; exit 143' TERM
}

# Initialize the utilities
init_backup_verification_utils() {
    setup_signal_handlers
    validate_dependencies || return $?
    create_temp_dir || return $?
    init_logging || return $?
    
    log_verbose "Backup verification utilities initialized"
    return $EXIT_SUCCESS
}

# Export functions for use in other scripts
export -f log_info log_warn log_error log_success log_verbose
export -f show_progress create_temp_dir cleanup_temp_dir
export -f validate_file_exists validate_directory_exists
export -f format_bytes calculate_percentage_diff command_exists
export -f start_timer end_timer get_memory_usage check_disk_space
export -f parse_common_options init_logging init_backup_verification_utils