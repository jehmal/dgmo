#!/bin/bash

# ============================================================================
# DGMSTT Session Disaster Recovery Script
# ============================================================================
# 
# DESCRIPTION:
#   Comprehensive session restoration tool for OpenCode/DGMO session data
#   Supports full and partial recovery with integrity validation and rollback
#
# USAGE:
#   ./session-restore.sh [OPTIONS] [BACKUP_SOURCE]
#
# OPTIONS:
#   -h, --help              Show this help message
#   -f, --full              Full session recovery (default)
#   -p, --partial           Partial session recovery (specific sessions)
#   -s, --session-id ID     Restore specific session ID
#   -b, --backup-dir DIR    Backup directory path
#   -t, --target-dir DIR    Target restoration directory
#   -v, --validate-only     Only validate backup integrity
#   -r, --rollback          Rollback last restoration
#   -d, --dry-run           Show what would be restored without doing it
#   -q, --quiet             Suppress progress output
#   --force                 Force restoration even with validation warnings
#   --skip-validation       Skip integrity validation (dangerous)
#   --preserve-existing     Don't overwrite existing sessions
#
# EXAMPLES:
#   ./session-restore.sh --full /backup/sessions
#   ./session-restore.sh --partial --session-id ses_123456
#   ./session-restore.sh --validate-only /backup/sessions
#   ./session-restore.sh --rollback
#
# RECOVERY SCENARIOS:
#   1. Complete session data loss
#   2. Partial session corruption
#   3. Subsession recovery
#   4. Session hierarchy restoration
#   5. Cross-platform compatibility (WSL/Linux)
#
# ============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# ============================================================================
# CONFIGURATION AND CONSTANTS
# ============================================================================

# Script metadata
readonly SCRIPT_NAME="session-restore.sh"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_AUTHOR="DGMSTT Recovery System"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Progress indicators
readonly PROGRESS_CHARS="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
readonly CHECKMARK="✓"
readonly CROSSMARK="✗"
readonly WARNING="⚠"
readonly INFO="ℹ"

# Default configuration
DEFAULT_OPENCODE_BASE="/home/$(whoami)/.local/share/opencode/project"
DEFAULT_BACKUP_DIR="/tmp/session-backup-$(date +%Y%m%d-%H%M%S)"
DEFAULT_LOG_DIR="/tmp/session-restore-logs"

# Session storage structure
readonly SESSION_SUBDIRS=("info" "message" "performance" "sub-sessions" "sub-session-index")

# Validation thresholds
readonly MAX_SESSION_SIZE_MB=100
readonly MAX_MESSAGE_SIZE_MB=50
readonly MIN_JSON_SIZE_BYTES=10

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

# Command line options
OPERATION_MODE="full"
SESSION_ID=""
BACKUP_DIR=""
TARGET_DIR=""
VALIDATE_ONLY=false
ROLLBACK_MODE=false
DRY_RUN=false
QUIET=false
FORCE_MODE=false
SKIP_VALIDATION=false
PRESERVE_EXISTING=false

# Runtime variables
TEMP_DIR=""
LOG_FILE=""
ROLLBACK_FILE=""
PROGRESS_PID=""
START_TIME=""
TOTAL_OPERATIONS=0
COMPLETED_OPERATIONS=0

# Statistics
RESTORED_SESSIONS=0
RESTORED_SUBSESSIONS=0
RESTORED_MESSAGES=0
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Logging function with timestamps
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ "$level" == "ERROR" ]]; then
        echo -e "${RED}[${timestamp}] ERROR: ${message}${NC}" >&2
    elif [[ "$level" == "WARN" ]]; then
        echo -e "${YELLOW}[${timestamp}] WARN: ${message}${NC}" >&2
    elif [[ "$level" == "INFO" ]]; then
        [[ "$QUIET" == "false" ]] && echo -e "${BLUE}[${timestamp}] INFO: ${message}${NC}"
    elif [[ "$level" == "SUCCESS" ]]; then
        [[ "$QUIET" == "false" ]] && echo -e "${GREEN}[${timestamp}] SUCCESS: ${message}${NC}"
    elif [[ "$level" == "DEBUG" ]]; then
        [[ "$QUIET" == "false" ]] && echo -e "${PURPLE}[${timestamp}] DEBUG: ${message}${NC}"
    fi
    
    # Always log to file if available
    if [[ -n "$LOG_FILE" ]]; then
        echo "[${timestamp}] ${level}: ${message}" >> "$LOG_FILE"
    fi
}

# Progress indicator
show_progress() {
    local message="$1"
    local current="$2"
    local total="$3"
    
    if [[ "$QUIET" == "true" ]]; then
        return
    fi
    
    local percentage=$((current * 100 / total))
    local bar_length=30
    local filled_length=$((percentage * bar_length / 100))
    
    # Create progress bar
    local bar=""
    for ((i=0; i<filled_length; i++)); do
        bar+="█"
    done
    for ((i=filled_length; i<bar_length; i++)); do
        bar+="░"
    done
    
    printf "\r${CYAN}%s${NC} [%s] %d%% (%d/%d)" "$message" "$bar" "$percentage" "$current" "$total"
    
    if [[ "$current" -eq "$total" ]]; then
        echo ""
    fi
}

# Spinner for long operations
start_spinner() {
    local message="$1"
    
    if [[ "$QUIET" == "true" ]]; then
        return
    fi
    
    {
        local i=0
        while true; do
            local char=${PROGRESS_CHARS:$((i % ${#PROGRESS_CHARS})):1}
            printf "\r${CYAN}%s${NC} %s" "$char" "$message"
            sleep 0.1
            ((i++))
        done
    } &
    
    PROGRESS_PID=$!
}

stop_spinner() {
    if [[ -n "$PROGRESS_PID" ]]; then
        kill "$PROGRESS_PID" 2>/dev/null || true
        wait "$PROGRESS_PID" 2>/dev/null || true
        PROGRESS_PID=""
        if [[ "$QUIET" == "false" ]]; then
            printf "\r%*s\r" 80 ""  # Clear line
        fi
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    
    stop_spinner
    log "ERROR" "Script failed at line $line_number with exit code $exit_code"
    
    # Cleanup
    cleanup_temp_files
    
    exit $exit_code
}

# Cleanup function
cleanup_temp_files() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        log "DEBUG" "Cleaning up temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
}

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

# Validate JSON file structure
validate_json_file() {
    local file_path="$1"
    local file_type="$2"
    
    if [[ ! -f "$file_path" ]]; then
        log "ERROR" "File not found: $file_path"
        return 1
    fi
    
    # Check file size
    local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")
    if [[ "$file_size" -lt "$MIN_JSON_SIZE_BYTES" ]]; then
        log "WARN" "File too small (${file_size} bytes): $file_path"
        ((VALIDATION_WARNINGS++))
    fi
    
    # Validate JSON syntax
    if ! jq empty "$file_path" 2>/dev/null; then
        log "ERROR" "Invalid JSON syntax: $file_path"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    # Type-specific validation
    case "$file_type" in
        "session_info")
            validate_session_info_structure "$file_path"
            ;;
        "subsession")
            validate_subsession_structure "$file_path"
            ;;
        "subsession_index")
            validate_subsession_index_structure "$file_path"
            ;;
        "message")
            validate_message_structure "$file_path"
            ;;
    esac
}

# Validate session info structure
validate_session_info_structure() {
    local file_path="$1"
    
    # Check required fields
    local required_fields=("id" "time")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$file_path" >/dev/null 2>&1; then
            log "ERROR" "Missing required field '$field' in session info: $file_path"
            ((VALIDATION_ERRORS++))
            return 1
        fi
    done
    
    # Validate ID format
    local session_id=$(jq -r '.id' "$file_path")
    if [[ ! "$session_id" =~ ^ses_[a-zA-Z0-9]+$ ]]; then
        log "WARN" "Invalid session ID format: $session_id in $file_path"
        ((VALIDATION_WARNINGS++))
    fi
    
    return 0
}

# Validate subsession structure
validate_subsession_structure() {
    local file_path="$1"
    
    local required_fields=("id" "parentSessionId" "agentName" "taskDescription" "status" "createdAt")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$file_path" >/dev/null 2>&1; then
            log "ERROR" "Missing required field '$field' in subsession: $file_path"
            ((VALIDATION_ERRORS++))
            return 1
        fi
    done
    
    # Validate status
    local status=$(jq -r '.status' "$file_path")
    if [[ ! "$status" =~ ^(pending|running|completed|failed)$ ]]; then
        log "WARN" "Invalid subsession status: $status in $file_path"
        ((VALIDATION_WARNINGS++))
    fi
    
    return 0
}

# Validate subsession index structure
validate_subsession_index_structure() {
    local file_path="$1"
    
    # Should be an array of session IDs
    if ! jq -e 'type == "array"' "$file_path" >/dev/null 2>&1; then
        log "ERROR" "Subsession index should be an array: $file_path"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    # Check each ID format
    local invalid_ids=$(jq -r '.[] | select(test("^ses_[a-zA-Z0-9]+$") | not)' "$file_path" 2>/dev/null || echo "")
    if [[ -n "$invalid_ids" ]]; then
        log "WARN" "Invalid session IDs in index: $file_path"
        ((VALIDATION_WARNINGS++))
    fi
    
    return 0
}

# Validate message structure
validate_message_structure() {
    local file_path="$1"
    
    # Check if it's a valid message file (can be various formats)
    local file_size=$(stat -f%z "$file_path" 2>/dev/null || stat -c%s "$file_path" 2>/dev/null || echo "0")
    local max_size=$((MAX_MESSAGE_SIZE_MB * 1024 * 1024))
    
    if [[ "$file_size" -gt "$max_size" ]]; then
        log "WARN" "Large message file (${file_size} bytes): $file_path"
        ((VALIDATION_WARNINGS++))
    fi
    
    return 0
}

# Validate backup directory structure
validate_backup_structure() {
    local backup_dir="$1"
    
    log "INFO" "Validating backup directory structure: $backup_dir"
    
    if [[ ! -d "$backup_dir" ]]; then
        log "ERROR" "Backup directory not found: $backup_dir"
        return 1
    fi
    
    # Check for required subdirectories
    local missing_dirs=()
    for subdir in "${SESSION_SUBDIRS[@]}"; do
        if [[ ! -d "$backup_dir/$subdir" ]]; then
            missing_dirs+=("$subdir")
        fi
    done
    
    if [[ ${#missing_dirs[@]} -gt 0 ]]; then
        log "WARN" "Missing subdirectories in backup: ${missing_dirs[*]}"
        ((VALIDATION_WARNINGS++))
    fi
    
    # Count files in each subdirectory
    local total_files=0
    for subdir in "${SESSION_SUBDIRS[@]}"; do
        if [[ -d "$backup_dir/$subdir" ]]; then
            local file_count=$(find "$backup_dir/$subdir" -type f 2>/dev/null | wc -l)
            log "DEBUG" "Found $file_count files in $subdir"
            total_files=$((total_files + file_count))
        fi
    done
    
    if [[ "$total_files" -eq 0 ]]; then
        log "ERROR" "No session files found in backup directory"
        return 1
    fi
    
    log "SUCCESS" "Backup structure validation completed. Total files: $total_files"
    return 0
}

# Validate session relationships
validate_session_relationships() {
    local backup_dir="$1"
    
    log "INFO" "Validating session relationships and hierarchy"
    
    # Build session relationship map
    local -A session_parents
    local -A session_children
    
    # Read all session info files
    if [[ -d "$backup_dir/info" ]]; then
        while IFS= read -r -d '' info_file; do
            if [[ -f "$info_file" ]]; then
                local session_id=$(basename "$info_file" .json)
                local parent_id=$(jq -r '.parentID // empty' "$info_file" 2>/dev/null || echo "")
                
                if [[ -n "$parent_id" ]]; then
                    session_parents["$session_id"]="$parent_id"
                    if [[ -z "${session_children[$parent_id]:-}" ]]; then
                        session_children["$parent_id"]="$session_id"
                    else
                        session_children["$parent_id"]+=" $session_id"
                    fi
                fi
            fi
        done < <(find "$backup_dir/info" -name "*.json" -type f -print0 2>/dev/null)
    fi
    
    # Validate subsession indices match actual subsessions
    if [[ -d "$backup_dir/sub-session-index" ]]; then
        while IFS= read -r -d '' index_file; do
            if [[ -f "$index_file" ]]; then
                local parent_id=$(basename "$index_file" .json)
                local indexed_sessions=$(jq -r '.[]' "$index_file" 2>/dev/null || echo "")
                
                for sub_id in $indexed_sessions; do
                    if [[ ! -f "$backup_dir/sub-sessions/$sub_id.json" ]]; then
                        log "WARN" "Subsession $sub_id indexed but file missing"
                        ((VALIDATION_WARNINGS++))
                    fi
                done
            fi
        done < <(find "$backup_dir/sub-session-index" -name "*.json" -type f -print0 2>/dev/null)
    fi
    
    log "SUCCESS" "Session relationship validation completed"
    return 0
}

# ============================================================================
# BACKUP AND RESTORE FUNCTIONS
# ============================================================================

# Create backup of current session data
create_backup() {
    local target_backup_dir="$1"
    
    log "INFO" "Creating backup of current session data"
    
    # Find all OpenCode project directories
    local opencode_dirs=()
    if [[ -d "$DEFAULT_OPENCODE_BASE" ]]; then
        while IFS= read -r -d '' dir; do
            if [[ -d "$dir/storage/session" ]]; then
                opencode_dirs+=("$dir")
            fi
        done < <(find "$DEFAULT_OPENCODE_BASE" -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    
    if [[ ${#opencode_dirs[@]} -eq 0 ]]; then
        log "WARN" "No OpenCode session directories found"
        return 0
    fi
    
    # Create backup directory structure
    mkdir -p "$target_backup_dir"
    for subdir in "${SESSION_SUBDIRS[@]}"; do
        mkdir -p "$target_backup_dir/$subdir"
    done
    
    # Copy files from all source directories
    local total_copied=0
    for source_dir in "${opencode_dirs[@]}"; do
        local session_dir="$source_dir/storage/session"
        log "DEBUG" "Backing up from: $session_dir"
        
        for subdir in "${SESSION_SUBDIRS[@]}"; do
            if [[ -d "$session_dir/$subdir" ]]; then
                local file_count=$(find "$session_dir/$subdir" -type f 2>/dev/null | wc -l)
                if [[ "$file_count" -gt 0 ]]; then
                    cp -r "$session_dir/$subdir"/* "$target_backup_dir/$subdir/" 2>/dev/null || true
                    total_copied=$((total_copied + file_count))
                fi
            fi
        done
    done
    
    # Create backup metadata
    cat > "$target_backup_dir/backup-metadata.json" << EOF
{
    "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "script_version": "$SCRIPT_VERSION",
    "source_directories": $(printf '%s\n' "${opencode_dirs[@]}" | jq -R . | jq -s .),
    "total_files": $total_copied,
    "backup_type": "pre_restore"
}
EOF
    
    log "SUCCESS" "Backup created with $total_copied files: $target_backup_dir"
    return 0
}

# Restore session files
restore_session_files() {
    local backup_dir="$1"
    local target_dir="$2"
    local subdir="$3"
    
    local source_path="$backup_dir/$subdir"
    local target_path="$target_dir/storage/session/$subdir"
    
    if [[ ! -d "$source_path" ]]; then
        log "DEBUG" "Source directory not found: $source_path"
        return 0
    fi
    
    # Create target directory
    mkdir -p "$target_path"
    
    # Count files to restore
    local file_count=$(find "$source_path" -type f 2>/dev/null | wc -l)
    if [[ "$file_count" -eq 0 ]]; then
        log "DEBUG" "No files to restore in $subdir"
        return 0
    fi
    
    log "INFO" "Restoring $file_count files to $subdir"
    
    # Restore files with progress tracking
    local current_file=0
    while IFS= read -r -d '' source_file; do
        local relative_path="${source_file#$source_path/}"
        local target_file="$target_path/$relative_path"
        
        # Create target subdirectory if needed
        mkdir -p "$(dirname "$target_file")"
        
        # Check if file exists and handle conflicts
        if [[ -f "$target_file" && "$PRESERVE_EXISTING" == "true" ]]; then
            log "DEBUG" "Preserving existing file: $relative_path"
        else
            if [[ "$DRY_RUN" == "true" ]]; then
                log "DEBUG" "Would restore: $relative_path"
            else
                cp "$source_file" "$target_file"
                
                # Validate restored file
                if [[ "$SKIP_VALIDATION" == "false" ]]; then
                    case "$subdir" in
                        "info")
                            validate_json_file "$target_file" "session_info" || true
                            ;;
                        "sub-sessions")
                            validate_json_file "$target_file" "subsession" || true
                            ;;
                        "sub-session-index")
                            validate_json_file "$target_file" "subsession_index" || true
                            ;;
                    esac
                fi
            fi
        fi
        
        ((current_file++))
        show_progress "Restoring $subdir" "$current_file" "$file_count"
        
        # Update statistics
        case "$subdir" in
            "info")
                ((RESTORED_SESSIONS++))
                ;;
            "sub-sessions")
                ((RESTORED_SUBSESSIONS++))
                ;;
            "message")
                ((RESTORED_MESSAGES++))
                ;;
        esac
        
    done < <(find "$source_path" -type f -print0 2>/dev/null)
    
    return 0
}

# Restore specific session
restore_specific_session() {
    local backup_dir="$1"
    local target_dir="$2"
    local session_id="$3"
    
    log "INFO" "Restoring specific session: $session_id"
    
    # Restore session info
    local info_file="$backup_dir/info/$session_id.json"
    if [[ -f "$info_file" ]]; then
        mkdir -p "$target_dir/storage/session/info"
        cp "$info_file" "$target_dir/storage/session/info/"
        ((RESTORED_SESSIONS++))
        log "SUCCESS" "Restored session info: $session_id"
    else
        log "ERROR" "Session info not found: $session_id"
        return 1
    fi
    
    # Restore session messages
    local message_dir="$backup_dir/message/$session_id"
    if [[ -d "$message_dir" ]]; then
        mkdir -p "$target_dir/storage/session/message"
        cp -r "$message_dir" "$target_dir/storage/session/message/"
        local message_count=$(find "$message_dir" -type f 2>/dev/null | wc -l)
        RESTORED_MESSAGES=$((RESTORED_MESSAGES + message_count))
        log "SUCCESS" "Restored $message_count messages for session: $session_id"
    fi
    
    # Restore subsessions
    local index_file="$backup_dir/sub-session-index/$session_id.json"
    if [[ -f "$index_file" ]]; then
        mkdir -p "$target_dir/storage/session/sub-session-index"
        cp "$index_file" "$target_dir/storage/session/sub-session-index/"
        
        # Restore individual subsession files
        local subsession_ids=$(jq -r '.[]' "$index_file" 2>/dev/null || echo "")
        for sub_id in $subsession_ids; do
            local sub_file="$backup_dir/sub-sessions/$sub_id.json"
            if [[ -f "$sub_file" ]]; then
                mkdir -p "$target_dir/storage/session/sub-sessions"
                cp "$sub_file" "$target_dir/storage/session/sub-sessions/"
                ((RESTORED_SUBSESSIONS++))
            fi
        done
        
        log "SUCCESS" "Restored subsessions for session: $session_id"
    fi
    
    return 0
}

# ============================================================================
# ROLLBACK FUNCTIONS
# ============================================================================

# Create rollback point
create_rollback_point() {
    local rollback_dir="$DEFAULT_LOG_DIR/rollback-$(date +%Y%m%d-%H%M%S)"
    
    log "INFO" "Creating rollback point: $rollback_dir"
    
    if create_backup "$rollback_dir"; then
        echo "$rollback_dir" > "$ROLLBACK_FILE"
        log "SUCCESS" "Rollback point created: $rollback_dir"
        return 0
    else
        log "ERROR" "Failed to create rollback point"
        return 1
    fi
}

# Execute rollback
execute_rollback() {
    if [[ ! -f "$ROLLBACK_FILE" ]]; then
        log "ERROR" "No rollback point found. File: $ROLLBACK_FILE"
        return 1
    fi
    
    local rollback_dir=$(cat "$ROLLBACK_FILE")
    
    if [[ ! -d "$rollback_dir" ]]; then
        log "ERROR" "Rollback directory not found: $rollback_dir"
        return 1
    fi
    
    log "INFO" "Rolling back to: $rollback_dir"
    
    # Find target directories
    local target_dirs=()
    if [[ -d "$DEFAULT_OPENCODE_BASE" ]]; then
        while IFS= read -r -d '' dir; do
            if [[ -d "$dir/storage" ]]; then
                target_dirs+=("$dir")
            fi
        done < <(find "$DEFAULT_OPENCODE_BASE" -maxdepth 1 -type d -print0 2>/dev/null)
    fi
    
    if [[ ${#target_dirs[@]} -eq 0 ]]; then
        log "ERROR" "No target directories found for rollback"
        return 1
    fi
    
    # Execute rollback for each target
    for target_dir in "${target_dirs[@]}"; do
        log "INFO" "Rolling back: $target_dir"
        
        # Remove current session data
        if [[ -d "$target_dir/storage/session" ]]; then
            rm -rf "$target_dir/storage/session"
        fi
        
        # Restore from rollback point
        mkdir -p "$target_dir/storage/session"
        for subdir in "${SESSION_SUBDIRS[@]}"; do
            if [[ -d "$rollback_dir/$subdir" ]]; then
                cp -r "$rollback_dir/$subdir" "$target_dir/storage/session/"
            fi
        done
    done
    
    log "SUCCESS" "Rollback completed successfully"
    return 0
}

# ============================================================================
# MAIN RESTORATION FUNCTIONS
# ============================================================================

# Full session restoration
perform_full_restore() {
    local backup_dir="$1"
    local target_base="$2"
    
    log "INFO" "Starting full session restoration"
    
    # Validate backup first
    if [[ "$SKIP_VALIDATION" == "false" ]]; then
        if ! validate_backup_structure "$backup_dir"; then
            if [[ "$FORCE_MODE" == "false" ]]; then
                log "ERROR" "Backup validation failed. Use --force to proceed anyway."
                return 1
            else
                log "WARN" "Proceeding with restoration despite validation errors"
            fi
        fi
    fi
    
    # Find all target directories
    local target_dirs=()
    if [[ -n "$target_base" ]]; then
        target_dirs=("$target_base")
    else
        # Auto-detect OpenCode directories
        if [[ -d "$DEFAULT_OPENCODE_BASE" ]]; then
            while IFS= read -r -d '' dir; do
                if [[ -d "$dir/storage" || "$DRY_RUN" == "true" ]]; then
                    target_dirs+=("$dir")
                fi
            done < <(find "$DEFAULT_OPENCODE_BASE" -maxdepth 1 -type d -print0 2>/dev/null)
        fi
    fi
    
    if [[ ${#target_dirs[@]} -eq 0 ]]; then
        log "ERROR" "No target directories found for restoration"
        return 1
    fi
    
    # Calculate total operations
    TOTAL_OPERATIONS=$((${#target_dirs[@]} * ${#SESSION_SUBDIRS[@]}))
    COMPLETED_OPERATIONS=0
    
    # Restore to each target directory
    for target_dir in "${target_dirs[@]}"; do
        log "INFO" "Restoring to: $target_dir"
        
        # Create rollback point for this target
        if [[ "$DRY_RUN" == "false" ]]; then
            create_rollback_point
        fi
        
        # Restore each subdirectory
        for subdir in "${SESSION_SUBDIRS[@]}"; do
            restore_session_files "$backup_dir" "$target_dir" "$subdir"
            ((COMPLETED_OPERATIONS++))
        done
    done
    
    log "SUCCESS" "Full restoration completed"
    return 0
}

# Partial session restoration
perform_partial_restore() {
    local backup_dir="$1"
    local target_base="$2"
    local session_id="$3"
    
    log "INFO" "Starting partial session restoration for: $session_id"
    
    # Find target directory
    local target_dir="$target_base"
    if [[ -z "$target_dir" ]]; then
        # Use the main OpenCode directory
        target_dir="$DEFAULT_OPENCODE_BASE/mnt-c-Users-$(whoami)-Desktop-AI-DGMSTT-opencode"
        if [[ ! -d "$target_dir" ]]; then
            target_dir="$DEFAULT_OPENCODE_BASE/global"
        fi
    fi
    
    if [[ ! -d "$target_dir" && "$DRY_RUN" == "false" ]]; then
        log "ERROR" "Target directory not found: $target_dir"
        return 1
    fi
    
    # Create rollback point
    if [[ "$DRY_RUN" == "false" ]]; then
        create_rollback_point
    fi
    
    # Restore specific session
    restore_specific_session "$backup_dir" "$target_dir" "$session_id"
    
    log "SUCCESS" "Partial restoration completed for session: $session_id"
    return 0
}

# ============================================================================
# COMMAND LINE PARSING
# ============================================================================

show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION - DGMSTT Session Disaster Recovery

DESCRIPTION:
    Comprehensive session restoration tool for OpenCode/DGMO session data.
    Supports full and partial recovery with integrity validation and rollback.

USAGE:
    $SCRIPT_NAME [OPTIONS] [BACKUP_SOURCE]

OPTIONS:
    -h, --help              Show this help message
    -f, --full              Full session recovery (default)
    -p, --partial           Partial session recovery (specific sessions)
    -s, --session-id ID     Restore specific session ID
    -b, --backup-dir DIR    Backup directory path
    -t, --target-dir DIR    Target restoration directory
    -v, --validate-only     Only validate backup integrity
    -r, --rollback          Rollback last restoration
    -d, --dry-run           Show what would be restored without doing it
    -q, --quiet             Suppress progress output
    --force                 Force restoration even with validation warnings
    --skip-validation       Skip integrity validation (dangerous)
    --preserve-existing     Don't overwrite existing sessions

EXAMPLES:
    $SCRIPT_NAME --full /backup/sessions
    $SCRIPT_NAME --partial --session-id ses_123456
    $SCRIPT_NAME --validate-only /backup/sessions
    $SCRIPT_NAME --rollback

RECOVERY SCENARIOS:
    1. Complete session data loss
    2. Partial session corruption
    3. Subsession recovery
    4. Session hierarchy restoration
    5. Cross-platform compatibility (WSL/Linux)

AUTHOR: $SCRIPT_AUTHOR
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -f|--full)
                OPERATION_MODE="full"
                shift
                ;;
            -p|--partial)
                OPERATION_MODE="partial"
                shift
                ;;
            -s|--session-id)
                SESSION_ID="$2"
                shift 2
                ;;
            -b|--backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            -t|--target-dir)
                TARGET_DIR="$2"
                shift 2
                ;;
            -v|--validate-only)
                VALIDATE_ONLY=true
                shift
                ;;
            -r|--rollback)
                ROLLBACK_MODE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            --force)
                FORCE_MODE=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            --preserve-existing)
                PRESERVE_EXISTING=true
                shift
                ;;
            -*)
                log "ERROR" "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$BACKUP_DIR" ]]; then
                    BACKUP_DIR="$1"
                fi
                shift
                ;;
        esac
    done
}

# ============================================================================
# INITIALIZATION AND SETUP
# ============================================================================

initialize_script() {
    # Set up error handling
    trap 'handle_error $LINENO' ERR
    trap 'cleanup_temp_files' EXIT
    
    # Record start time
    START_TIME=$(date +%s)
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d -t session-restore-XXXXXX)
    
    # Create log directory
    mkdir -p "$DEFAULT_LOG_DIR"
    LOG_FILE="$DEFAULT_LOG_DIR/session-restore-$(date +%Y%m%d-%H%M%S).log"
    ROLLBACK_FILE="$DEFAULT_LOG_DIR/last-rollback-point"
    
    # Initialize log
    log "INFO" "Session restoration script started"
    log "INFO" "Script version: $SCRIPT_VERSION"
    log "INFO" "Log file: $LOG_FILE"
    log "INFO" "Temporary directory: $TEMP_DIR"
    
    # Validate dependencies
    local missing_deps=()
    for cmd in jq find cp rm mkdir; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log "ERROR" "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Initialize
    initialize_script
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Handle rollback mode
    if [[ "$ROLLBACK_MODE" == "true" ]]; then
        log "INFO" "Executing rollback operation"
        execute_rollback
        exit $?
    fi
    
    # Validate backup directory
    if [[ -z "$BACKUP_DIR" ]]; then
        log "ERROR" "Backup directory must be specified"
        show_help
        exit 1
    fi
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log "ERROR" "Backup directory not found: $BACKUP_DIR"
        exit 1
    fi
    
    # Handle validation-only mode
    if [[ "$VALIDATE_ONLY" == "true" ]]; then
        log "INFO" "Validation-only mode"
        validate_backup_structure "$BACKUP_DIR"
        validate_session_relationships "$BACKUP_DIR"
        
        if [[ "$VALIDATION_ERRORS" -eq 0 ]]; then
            log "SUCCESS" "Backup validation passed with $VALIDATION_WARNINGS warnings"
            exit 0
        else
            log "ERROR" "Backup validation failed with $VALIDATION_ERRORS errors"
            exit 1
        fi
    fi
    
    # Execute restoration based on mode
    case "$OPERATION_MODE" in
        "full")
            perform_full_restore "$BACKUP_DIR" "$TARGET_DIR"
            ;;
        "partial")
            if [[ -z "$SESSION_ID" ]]; then
                log "ERROR" "Session ID required for partial restoration"
                exit 1
            fi
            perform_partial_restore "$BACKUP_DIR" "$TARGET_DIR" "$SESSION_ID"
            ;;
        *)
            log "ERROR" "Invalid operation mode: $OPERATION_MODE"
            exit 1
            ;;
    esac
    
    # Calculate execution time
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    # Final report
    echo ""
    log "SUCCESS" "Session restoration completed successfully!"
    log "INFO" "Execution time: ${duration}s"
    log "INFO" "Sessions restored: $RESTORED_SESSIONS"
    log "INFO" "Subsessions restored: $RESTORED_SUBSESSIONS"
    log "INFO" "Messages restored: $RESTORED_MESSAGES"
    log "INFO" "Validation errors: $VALIDATION_ERRORS"
    log "INFO" "Validation warnings: $VALIDATION_WARNINGS"
    log "INFO" "Log file: $LOG_FILE"
    
    if [[ "$VALIDATION_ERRORS" -gt 0 ]]; then
        log "WARN" "Restoration completed with validation errors. Check log for details."
        exit 2
    fi
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi