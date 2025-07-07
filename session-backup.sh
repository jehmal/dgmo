#!/bin/bash

#===============================================================================
# SESSION BACKUP SCRIPT
#===============================================================================
# Name: session-backup.sh
# Purpose: Automated backup of OpenCode session data with compression and retention
# Author: Auto-generated for DGMSTT project
# Version: 1.0
# 
# Features:
# - Automatic session directory detection
# - Pre-flight checks (disk space, permissions, dependencies)
# - Compressed backups with timestamp naming
# - Integrity verification
# - 30-day retention policy
# - Comprehensive logging with rotation
# - Email notifications on failures
# - Lock file protection
# - Progress indicators
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

#===============================================================================
# CONFIGURATION
#===============================================================================

# Default paths - will be auto-detected if they exist
DEFAULT_SESSION_DIRS=(
    "$HOME/.opencode/sessions"
    "$HOME/.config/opencode/sessions"
    "/tmp/opencode-sessions"
    "$HOME/Library/Application Support/opencode/sessions"  # macOS
)

# Backup configuration
BACKUP_BASE_DIR="$HOME/backups"
BACKUP_DIR="$BACKUP_BASE_DIR/sessions"
LOG_DIR="$BACKUP_BASE_DIR/logs"
LOG_FILE="$LOG_DIR/session-backup.log"
LOCK_FILE="/tmp/session-backup.lock"

# Retention and size limits
RETENTION_DAYS=30
MIN_FREE_SPACE_MB=1024  # Minimum 1GB free space required
MAX_LOG_SIZE_MB=10
MAX_LOG_FILES=5

# Email configuration (set EMAIL_ON_FAILURE=true to enable)
EMAIL_ON_FAILURE=false
EMAIL_RECIPIENT=""
EMAIL_SUBJECT="Session Backup Failure"

# Progress and timing
PROGRESS_ENABLED=true
VERBOSE=false

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# Get current timestamp
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Get timestamp for filenames
file_timestamp() {
    date '+%Y-%m-%d_%H-%M-%S'
}

# Logging function with levels
log() {
    local level="$1"
    shift
    local message="$*"
    local ts=$(timestamp)
    
    # Ensure log directory exists
    mkdir -p "$LOG_DIR"
    
    # Write to log file
    echo "[$ts] [$level] $message" >> "$LOG_FILE"
    
    # Also output to console based on level
    case "$level" in
        ERROR)
            echo "❌ ERROR: $message" >&2
            ;;
        WARN)
            echo "⚠️  WARN: $message" >&2
            ;;
        INFO)
            if [[ "$VERBOSE" == "true" ]]; then
                echo "ℹ️  INFO: $message"
            fi
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Progress indicator
show_progress() {
    if [[ "$PROGRESS_ENABLED" == "true" ]]; then
        echo -n "."
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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Send email notification on failure
send_failure_notification() {
    local error_message="$1"
    
    if [[ "$EMAIL_ON_FAILURE" == "true" && -n "$EMAIL_RECIPIENT" ]]; then
        if command_exists mail; then
            echo "Session backup failed at $(timestamp): $error_message" | \
                mail -s "$EMAIL_SUBJECT" "$EMAIL_RECIPIENT"
            log "INFO" "Failure notification sent to $EMAIL_RECIPIENT"
        else
            log "WARN" "Email notification requested but 'mail' command not available"
        fi
    fi
}

#===============================================================================
# PRE-FLIGHT CHECKS
#===============================================================================

# Check for required dependencies
check_dependencies() {
    log "INFO" "Checking dependencies..."
    
    local missing_deps=()
    
    for cmd in tar gzip find du df; do
        if ! command_exists "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        local deps_str=$(IFS=', '; echo "${missing_deps[*]}")
        log "ERROR" "Missing required dependencies: $deps_str"
        return 1
    fi
    
    log "INFO" "All dependencies satisfied"
    return 0
}

# Find actual session directories
find_session_directories() {
    log "INFO" "Detecting session directories..."
    
    local found_dirs=()
    
    for dir in "${DEFAULT_SESSION_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            # Check if directory has content
            if [[ -n "$(find "$dir" -type f -name "*.json" 2>/dev/null | head -1)" ]]; then
                found_dirs+=("$dir")
                log "INFO" "Found session directory: $dir"
            else
                log "INFO" "Directory exists but appears empty: $dir"
            fi
        fi
    done
    
    # Also search for any opencode-related session directories
    local search_dirs=("$HOME" "/tmp")
    for search_dir in "${search_dirs[@]}"; do
        if [[ -d "$search_dir" ]]; then
            while IFS= read -r -d '' dir; do
                if [[ ! " ${found_dirs[*]} " =~ " ${dir} " ]]; then
                    found_dirs+=("$dir")
                    log "INFO" "Auto-detected session directory: $dir"
                fi
            done < <(find "$search_dir" -maxdepth 3 -type d -name "*session*" -path "*opencode*" -print0 2>/dev/null || true)
        fi
    done
    
    if [[ ${#found_dirs[@]} -eq 0 ]]; then
        log "WARN" "No session directories found"
        return 1
    fi
    
    # Export found directories for use by other functions
    SESSION_DIRS=("${found_dirs[@]}")
    return 0
}

# Check available disk space
check_disk_space() {
    log "INFO" "Checking disk space..."
    
    # Get available space in MB for backup directory
    local backup_parent=$(dirname "$BACKUP_DIR")
    mkdir -p "$backup_parent"
    
    local available_mb
    if command_exists df; then
        available_mb=$(df -m "$backup_parent" | awk 'NR==2 {print $4}')
    else
        log "ERROR" "Cannot check disk space - df command not available"
        return 1
    fi
    
    if [[ $available_mb -lt $MIN_FREE_SPACE_MB ]]; then
        log "ERROR" "Insufficient disk space. Available: ${available_mb}MB, Required: ${MIN_FREE_SPACE_MB}MB"
        return 1
    fi
    
    log "INFO" "Disk space check passed. Available: ${available_mb}MB"
    return 0
}

# Check permissions
check_permissions() {
    log "INFO" "Checking permissions..."
    
    # Check source directories are readable
    for dir in "${SESSION_DIRS[@]}"; do
        if [[ ! -r "$dir" ]]; then
            log "ERROR" "Cannot read source directory: $dir"
            return 1
        fi
    done
    
    # Check/create backup directory with write permissions
    if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
        log "ERROR" "Cannot create backup directory: $BACKUP_DIR"
        return 1
    fi
    
    if [[ ! -w "$BACKUP_DIR" ]]; then
        log "ERROR" "Cannot write to backup directory: $BACKUP_DIR"
        return 1
    fi
    
    # Check/create log directory
    if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
        log "ERROR" "Cannot create log directory: $LOG_DIR"
        return 1
    fi
    
    log "INFO" "Permission checks passed"
    return 0
}

#===============================================================================
# LOCK FILE MANAGEMENT
#===============================================================================

# Create lock file to prevent concurrent runs
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
        
        # Check if the process is still running
        if kill -0 "$lock_pid" 2>/dev/null; then
            log "ERROR" "Another backup process is running (PID: $lock_pid)"
            return 1
        else
            log "WARN" "Stale lock file found, removing..."
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    log "INFO" "Lock acquired (PID: $$)"
    return 0
}

# Remove lock file
release_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log "INFO" "Lock released"
    fi
}

#===============================================================================
# LOG ROTATION
#===============================================================================

# Rotate log files when they get too large
rotate_logs() {
    if [[ ! -f "$LOG_FILE" ]]; then
        return 0
    fi
    
    local log_size_mb
    log_size_mb=$(du -m "$LOG_FILE" 2>/dev/null | cut -f1 || echo "0")
    
    if [[ $log_size_mb -gt $MAX_LOG_SIZE_MB ]]; then
        log "INFO" "Rotating log file (size: ${log_size_mb}MB)"
        
        # Rotate existing logs
        for i in $(seq $((MAX_LOG_FILES - 1)) -1 1); do
            local old_log="${LOG_FILE}.$i"
            local new_log="${LOG_FILE}.$((i + 1))"
            
            if [[ -f "$old_log" ]]; then
                if [[ $i -eq $((MAX_LOG_FILES - 1)) ]]; then
                    rm -f "$old_log"  # Remove oldest log
                else
                    mv "$old_log" "$new_log"
                fi
            fi
        done
        
        # Move current log to .1
        mv "$LOG_FILE" "${LOG_FILE}.1"
        
        # Start fresh log
        touch "$LOG_FILE"
        log "INFO" "Log rotation completed"
    fi
}

#===============================================================================
# BACKUP OPERATIONS
#===============================================================================

# Calculate total size of source directories
calculate_source_size() {
    local total_size=0
    
    for dir in "${SESSION_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            local dir_size
            dir_size=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo "0")
            total_size=$((total_size + dir_size))
        fi
    done
    
    echo "$total_size"
}

# Create compressed backup
create_backup() {
    local backup_file="$1"
    local temp_backup="${backup_file}.tmp"
    
    log "INFO" "Creating backup: $(basename "$backup_file")"
    
    # Calculate source size for progress reporting
    local source_size
    source_size=$(calculate_source_size)
    local source_size_hr
    source_size_hr=$(human_readable_size "$source_size")
    
    log "INFO" "Source data size: $source_size_hr"
    
    # Create temporary backup file
    if [[ "$PROGRESS_ENABLED" == "true" ]]; then
        echo -n "Creating backup"
    fi
    
    # Build tar command with all session directories
    local tar_args=("czf" "$temp_backup")
    
    for dir in "${SESSION_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            tar_args+=("-C" "$(dirname "$dir")" "$(basename "$dir")")
        fi
    done
    
    # Execute backup with progress
    if tar "${tar_args[@]}" 2>/dev/null; then
        if [[ "$PROGRESS_ENABLED" == "true" ]]; then
            echo " ✅"
        fi
        
        # Move temp file to final location
        mv "$temp_backup" "$backup_file"
        
        # Get backup file size
        local backup_size
        backup_size=$(du -sb "$backup_file" 2>/dev/null | cut -f1 || echo "0")
        local backup_size_hr
        backup_size_hr=$(human_readable_size "$backup_size")
        
        # Calculate compression ratio
        local compression_ratio=0
        if [[ $source_size -gt 0 ]]; then
            compression_ratio=$(( (source_size - backup_size) * 100 / source_size ))
        fi
        
        log "INFO" "Backup created successfully"
        log "INFO" "Backup size: $backup_size_hr (${compression_ratio}% compression)"
        
        return 0
    else
        if [[ "$PROGRESS_ENABLED" == "true" ]]; then
            echo " ❌"
        fi
        
        # Clean up temp file
        rm -f "$temp_backup"
        
        log "ERROR" "Failed to create backup archive"
        return 1
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"
    
    log "INFO" "Verifying backup integrity..."
    
    if [[ "$PROGRESS_ENABLED" == "true" ]]; then
        echo -n "Verifying backup"
    fi
    
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        if [[ "$PROGRESS_ENABLED" == "true" ]]; then
            echo " ✅"
        fi
        log "INFO" "Backup integrity verified"
        return 0
    else
        if [[ "$PROGRESS_ENABLED" == "true" ]]; then
            echo " ❌"
        fi
        log "ERROR" "Backup integrity check failed"
        return 1
    fi
}

#===============================================================================
# CLEANUP OPERATIONS
#===============================================================================

# Clean up old backups based on retention policy
cleanup_old_backups() {
    log "INFO" "Cleaning up backups older than $RETENTION_DAYS days..."
    
    local deleted_count=0
    local total_size_freed=0
    
    # Find and remove old backup files
    while IFS= read -r -d '' backup_file; do
        local file_size
        file_size=$(du -sb "$backup_file" 2>/dev/null | cut -f1 || echo "0")
        
        if rm -f "$backup_file"; then
            deleted_count=$((deleted_count + 1))
            total_size_freed=$((total_size_freed + file_size))
            log "INFO" "Deleted old backup: $(basename "$backup_file")"
        else
            log "WARN" "Failed to delete old backup: $(basename "$backup_file")"
        fi
    done < <(find "$BACKUP_DIR" -name "sessions_*.tar.gz" -type f -mtime +$RETENTION_DAYS -print0 2>/dev/null || true)
    
    if [[ $deleted_count -gt 0 ]]; then
        local size_freed_hr
        size_freed_hr=$(human_readable_size "$total_size_freed")
        log "INFO" "Cleanup completed: $deleted_count files removed, $size_freed_hr freed"
    else
        log "INFO" "No old backups to clean up"
    fi
}

#===============================================================================
# MAIN EXECUTION
#===============================================================================

# Cleanup function for script exit
cleanup_on_exit() {
    local exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log "ERROR" "Script exited with error code: $exit_code"
        send_failure_notification "Script exited with error code: $exit_code"
    fi
    
    release_lock
    exit $exit_code
}

# Main backup function
main() {
    local start_time
    start_time=$(date +%s)
    
    log "INFO" "=== Session Backup Started ==="
    log "INFO" "Script version: 1.0"
    log "INFO" "Start time: $(timestamp)"
    
    # Set up cleanup on exit
    trap cleanup_on_exit EXIT INT TERM
    
    # Rotate logs if needed
    rotate_logs
    
    # Acquire lock
    if ! acquire_lock; then
        log "ERROR" "Failed to acquire lock"
        exit 1
    fi
    
    # Pre-flight checks
    if ! check_dependencies; then
        log "ERROR" "Dependency check failed"
        exit 1
    fi
    
    if ! find_session_directories; then
        log "WARN" "No session directories found - nothing to backup"
        exit 0
    fi
    
    if ! check_disk_space; then
        log "ERROR" "Disk space check failed"
        exit 1
    fi
    
    if ! check_permissions; then
        log "ERROR" "Permission check failed"
        exit 1
    fi
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Generate backup filename
    local backup_filename="sessions_$(file_timestamp).tar.gz"
    local backup_path="$BACKUP_DIR/$backup_filename"
    
    # Create backup
    if ! create_backup "$backup_path"; then
        log "ERROR" "Backup creation failed"
        send_failure_notification "Backup creation failed"
        exit 1
    fi
    
    # Verify backup
    if ! verify_backup "$backup_path"; then
        log "ERROR" "Backup verification failed"
        send_failure_notification "Backup verification failed"
        # Remove corrupted backup
        rm -f "$backup_path"
        exit 1
    fi
    
    # Clean up old backups
    cleanup_old_backups
    
    # Calculate execution time
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "INFO" "=== Session Backup Completed Successfully ==="
    log "INFO" "Backup file: $backup_filename"
    log "INFO" "Execution time: ${duration} seconds"
    log "INFO" "End time: $(timestamp)"
    
    echo "✅ Backup completed successfully: $backup_filename"
}

#===============================================================================
# COMMAND LINE INTERFACE
#===============================================================================

# Show usage information
show_usage() {
    cat << EOF
Session Backup Script v1.0

USAGE:
    $0 [OPTIONS]

OPTIONS:
    -v, --verbose       Enable verbose output
    -q, --quiet         Disable progress indicators
    -h, --help          Show this help message
    --dry-run           Show what would be backed up without creating backup
    --list-sessions     List detected session directories and exit
    --cleanup-only      Only perform cleanup of old backups
    --verify FILE       Verify integrity of specific backup file

CONFIGURATION:
    Edit the script to modify:
    - Backup location: $BACKUP_DIR
    - Retention period: $RETENTION_DAYS days
    - Email notifications: Set EMAIL_ON_FAILURE=true

EXAMPLES:
    $0                  # Run normal backup
    $0 --verbose        # Run with detailed output
    $0 --list-sessions  # Show detected session directories
    $0 --cleanup-only   # Only clean up old backups

EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                PROGRESS_ENABLED=false
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            --dry-run)
                echo "Dry run mode - detecting session directories:"
                if find_session_directories; then
                    for dir in "${SESSION_DIRS[@]}"; do
                        local size
                        size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown")
                        echo "  📁 $dir ($size)"
                    done
                else
                    echo "  No session directories found"
                fi
                exit 0
                ;;
            --list-sessions)
                echo "Detected session directories:"
                if find_session_directories; then
                    for dir in "${SESSION_DIRS[@]}"; do
                        local size file_count
                        size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown")
                        file_count=$(find "$dir" -type f -name "*.json" 2>/dev/null | wc -l || echo "0")
                        echo "  📁 $dir ($size, $file_count JSON files)"
                    done
                else
                    echo "  No session directories found"
                fi
                exit 0
                ;;
            --cleanup-only)
                echo "Performing cleanup only..."
                cleanup_old_backups
                exit 0
                ;;
            --verify)
                shift
                if [[ $# -eq 0 ]]; then
                    echo "Error: --verify requires a backup file path"
                    exit 1
                fi
                local verify_file="$1"
                if [[ ! -f "$verify_file" ]]; then
                    echo "Error: Backup file not found: $verify_file"
                    exit 1
                fi
                echo "Verifying backup: $verify_file"
                if verify_backup "$verify_file"; then
                    echo "✅ Backup verification successful"
                    exit 0
                else
                    echo "❌ Backup verification failed"
                    exit 1
                fi
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
}

#===============================================================================
# SCRIPT ENTRY POINT
#===============================================================================

# Parse command line arguments
parse_arguments "$@"

# Run main function
main

# Script completed successfully
exit 0