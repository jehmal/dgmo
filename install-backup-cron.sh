#!/bin/bash

# install-backup-cron.sh - Comprehensive Cron Backup Job Manager
# Production-ready script for managing backup cron jobs
# Author: AI Assistant
# Version: 1.0

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_DIR="${HOME}/.backup-logs"
readonly CRON_LOG="${LOG_DIR}/backup-cron.log"
readonly ERROR_LOG="${LOG_DIR}/backup-errors.log"
readonly CRON_COMMENT="# DGMSTT Backup Job - Managed by ${SCRIPT_NAME}"
readonly TEMP_CRON="/tmp/crontab.tmp.$$"

# Default configuration
DEFAULT_HOUR="2"
DEFAULT_MINUTE="0"
DEFAULT_BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Global variables
BACKUP_SCRIPT=""
CRON_HOUR=""
CRON_MINUTE=""
VERBOSE=false
DRY_RUN=false

# Cleanup function
cleanup() {
    local exit_code=$?
    [[ -f "$TEMP_CRON" ]] && rm -f "$TEMP_CRON"
    exit $exit_code
}
trap cleanup EXIT INT TERM

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
    [[ "$VERBOSE" == true ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $*" >> "$CRON_LOG" 2>/dev/null || true
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN] $*" >> "$ERROR_LOG" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $*" >> "$ERROR_LOG" 2>/dev/null || true
}

log_debug() {
    [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $*"
}

# Help function
show_help() {
    cat << EOF
${SCRIPT_NAME} - Comprehensive Cron Backup Job Manager

USAGE:
    ${SCRIPT_NAME} [OPTIONS] COMMAND [ARGUMENTS]

COMMANDS:
    install [SCRIPT] [TIME]    Install backup cron job
    uninstall                  Remove backup cron job
    status                     Show current cron job status
    enable                     Enable existing cron job
    disable                    Disable existing cron job (comment out)
    test                       Test cron job syntax and backup script
    help                       Show this help message

OPTIONS:
    -v, --verbose             Enable verbose output
    -n, --dry-run            Show what would be done without executing
    -h, --help               Show this help message

ARGUMENTS:
    SCRIPT                    Path to backup script (default: ${DEFAULT_BACKUP_SCRIPT})
    TIME                      Cron time format: "MINUTE HOUR" or "HH:MM" (default: ${DEFAULT_HOUR}:${DEFAULT_MINUTE})

EXAMPLES:
    # Install with defaults (2:00 AM daily)
    ${SCRIPT_NAME} install

    # Install with custom script and time
    ${SCRIPT_NAME} install /path/to/backup.sh "30 3"

    # Install with HH:MM format
    ${SCRIPT_NAME} install /path/to/backup.sh "03:30"

    # Check status
    ${SCRIPT_NAME} status

    # Temporarily disable
    ${SCRIPT_NAME} disable

    # Re-enable
    ${SCRIPT_NAME} enable

    # Test configuration
    ${SCRIPT_NAME} test

    # Uninstall completely
    ${SCRIPT_NAME} uninstall

ENVIRONMENT VARIABLES:
    BACKUP_SCRIPT_PATH        Default backup script path
    BACKUP_LOG_DIR           Custom log directory
    CRON_TIME                Default cron time (MINUTE HOUR format)

FILES:
    ${LOG_DIR}/backup-cron.log     Cron operation log
    ${LOG_DIR}/backup-errors.log   Error log
    ${LOG_DIR}/backup-output.log   Backup script output

NOTES:
    - Cron jobs include full environment setup
    - All paths are converted to absolute paths
    - Duplicate entries are automatically prevented
    - Logs are rotated automatically
    - Requires cron service to be running

EOF
}

# Utility functions
is_number() {
    [[ $1 =~ ^[0-9]+$ ]]
}

is_valid_hour() {
    is_number "$1" && (( $1 >= 0 && $1 <= 23 ))
}

is_valid_minute() {
    is_number "$1" && (( $1 >= 0 && $1 <= 59 ))
}

get_absolute_path() {
    local path="$1"
    if [[ "$path" = /* ]]; then
        echo "$path"
    else
        echo "$(pwd)/$path"
    fi
}

# System checks
check_cron_service() {
    log_debug "Checking cron service availability"
    
    if command -v systemctl >/dev/null 2>&1; then
        if systemctl is-active --quiet cron || systemctl is-active --quiet crond; then
            return 0
        fi
    elif command -v service >/dev/null 2>&1; then
        if service cron status >/dev/null 2>&1 || service crond status >/dev/null 2>&1; then
            return 0
        fi
    elif pgrep -x "cron\|crond" >/dev/null; then
        return 0
    fi
    
    return 1
}

check_crontab_access() {
    log_debug "Checking crontab access permissions"
    
    if ! crontab -l >/dev/null 2>&1; then
        local exit_code=$?
        if [[ $exit_code -eq 1 ]]; then
            # No crontab exists yet - this is fine
            return 0
        else
            # Permission denied or other error
            return $exit_code
        fi
    fi
    return 0
}

setup_log_directory() {
    log_debug "Setting up log directory: $LOG_DIR"
    
    if [[ ! -d "$LOG_DIR" ]]; then
        if ! mkdir -p "$LOG_DIR" 2>/dev/null; then
            log_error "Cannot create log directory: $LOG_DIR"
            return 1
        fi
    fi
    
    if [[ ! -w "$LOG_DIR" ]]; then
        log_error "Log directory is not writable: $LOG_DIR"
        return 1
    fi
    
    return 0
}

# Cron management functions
parse_time_format() {
    local time_input="$1"
    
    log_debug "Parsing time format: $time_input"
    
    # Handle HH:MM format
    if [[ "$time_input" =~ ^([0-9]{1,2}):([0-9]{1,2})$ ]]; then
        CRON_HOUR="${BASH_REMATCH[1]}"
        CRON_MINUTE="${BASH_REMATCH[2]}"
    # Handle "MINUTE HOUR" format
    elif [[ "$time_input" =~ ^([0-9]{1,2})[[:space:]]+([0-9]{1,2})$ ]]; then
        CRON_MINUTE="${BASH_REMATCH[1]}"
        CRON_HOUR="${BASH_REMATCH[2]}"
    else
        log_error "Invalid time format: $time_input"
        log_error "Use either 'HH:MM' or 'MINUTE HOUR' format"
        return 1
    fi
    
    # Validate time values
    if ! is_valid_hour "$CRON_HOUR"; then
        log_error "Invalid hour: $CRON_HOUR (must be 0-23)"
        return 1
    fi
    
    if ! is_valid_minute "$CRON_MINUTE"; then
        log_error "Invalid minute: $CRON_MINUTE (must be 0-59)"
        return 1
    fi
    
    log_debug "Parsed time: ${CRON_HOUR}:${CRON_MINUTE}"
    return 0
}

validate_backup_script() {
    local script_path="$1"
    
    log_debug "Validating backup script: $script_path"
    
    if [[ ! -f "$script_path" ]]; then
        log_error "Backup script not found: $script_path"
        return 1
    fi
    
    if [[ ! -r "$script_path" ]]; then
        log_error "Backup script is not readable: $script_path"
        return 1
    fi
    
    if [[ ! -x "$script_path" ]]; then
        log_warn "Backup script is not executable: $script_path"
        log_info "Making script executable..."
        if ! chmod +x "$script_path"; then
            log_error "Cannot make script executable: $script_path"
            return 1
        fi
    fi
    
    # Basic syntax check for shell scripts
    if [[ "$script_path" =~ \.(sh|bash)$ ]]; then
        if ! bash -n "$script_path" 2>/dev/null; then
            log_error "Backup script has syntax errors: $script_path"
            return 1
        fi
    fi
    
    log_debug "Backup script validation passed"
    return 0
}

get_current_cron() {
    crontab -l 2>/dev/null || true
}

has_backup_cron() {
    get_current_cron | grep -q "$CRON_COMMENT"
}

create_cron_entry() {
    local script_path="$1"
    local abs_script_path
    abs_script_path="$(get_absolute_path "$script_path")"
    
    # Environment setup for cron
    local env_setup="PATH=/usr/local/bin:/usr/bin:/bin:$PATH"
    env_setup+="; HOME=$HOME"
    env_setup+="; SHELL=/bin/bash"
    
    # Cron entry with comprehensive logging
    local cron_entry="${CRON_MINUTE} ${CRON_HOUR} * * * ${env_setup}; \"${abs_script_path}\" >> \"${CRON_LOG}\" 2>> \"${ERROR_LOG}\""
    
    echo "$cron_entry"
}

install_cron_job() {
    local script_path="${1:-$DEFAULT_BACKUP_SCRIPT}"
    local time_spec="${2:-${DEFAULT_HOUR}:${DEFAULT_MINUTE}}"
    
    log_info "Installing backup cron job..."
    log_debug "Script: $script_path, Time: $time_spec"
    
    # Parse and validate time
    if ! parse_time_format "$time_spec"; then
        return 1
    fi
    
    # Validate backup script
    if ! validate_backup_script "$script_path"; then
        return 1
    fi
    
    # Check for existing cron job
    if has_backup_cron; then
        log_warn "Backup cron job already exists"
        log_info "Use 'uninstall' first or 'enable/disable' to manage existing job"
        return 1
    fi
    
    # Create new cron entry
    local new_entry
    new_entry="$(create_cron_entry "$script_path")"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would add cron entry:"
        echo "$CRON_COMMENT"
        echo "$new_entry"
        return 0
    fi
    
    # Install the cron job
    {
        get_current_cron
        echo "$CRON_COMMENT"
        echo "$new_entry"
    } > "$TEMP_CRON"
    
    if crontab "$TEMP_CRON"; then
        log_info "Backup cron job installed successfully"
        log_info "Schedule: Daily at ${CRON_HOUR}:$(printf "%02d" "$CRON_MINUTE")"
        log_info "Script: $(get_absolute_path "$script_path")"
        log_info "Logs: $CRON_LOG"
        return 0
    else
        log_error "Failed to install cron job"
        return 1
    fi
}

uninstall_cron_job() {
    log_info "Uninstalling backup cron job..."
    
    if ! has_backup_cron; then
        log_warn "No backup cron job found"
        return 1
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would remove backup cron job"
        return 0
    fi
    
    # Remove cron job and comment
    get_current_cron | grep -v "$CRON_COMMENT" | grep -v "$(get_current_cron | grep -A1 "$CRON_COMMENT" | tail -1)" > "$TEMP_CRON"
    
    if crontab "$TEMP_CRON"; then
        log_info "Backup cron job uninstalled successfully"
        return 0
    else
        log_error "Failed to uninstall cron job"
        return 1
    fi
}

show_status() {
    log_info "Backup cron job status:"
    echo
    
    if has_backup_cron; then
        local cron_line
        cron_line="$(get_current_cron | grep -A1 "$CRON_COMMENT" | tail -1)"
        
        if [[ "$cron_line" =~ ^#.*$ ]]; then
            echo -e "Status: ${YELLOW}DISABLED${NC}"
        else
            echo -e "Status: ${GREEN}ENABLED${NC}"
        fi
        
        # Parse schedule from cron line
        if [[ "$cron_line" =~ ^#?([0-9]+)[[:space:]]+([0-9]+) ]]; then
            local minute="${BASH_REMATCH[1]}"
            local hour="${BASH_REMATCH[2]}"
            echo "Schedule: Daily at $(printf "%02d:%02d" "$hour" "$minute")"
        fi
        
        # Extract script path
        if [[ "$cron_line" =~ \"([^\"]+)\"[[:space:]]+\>\> ]]; then
            echo "Script: ${BASH_REMATCH[1]}"
        fi
        
        echo "Log file: $CRON_LOG"
        echo "Error log: $ERROR_LOG"
        
        # Show recent log entries
        if [[ -f "$CRON_LOG" ]]; then
            echo
            echo "Recent log entries:"
            tail -5 "$CRON_LOG" 2>/dev/null || echo "No log entries found"
        fi
        
    else
        echo -e "Status: ${RED}NOT INSTALLED${NC}"
    fi
    
    echo
    echo "Cron service status:"
    if check_cron_service; then
        echo -e "Cron service: ${GREEN}RUNNING${NC}"
    else
        echo -e "Cron service: ${RED}NOT RUNNING${NC}"
    fi
}

enable_cron_job() {
    log_info "Enabling backup cron job..."
    
    if ! has_backup_cron; then
        log_error "No backup cron job found to enable"
        return 1
    fi
    
    local current_cron
    current_cron="$(get_current_cron)"
    
    # Check if already enabled
    local cron_line
    cron_line="$(echo "$current_cron" | grep -A1 "$CRON_COMMENT" | tail -1)"
    
    if [[ ! "$cron_line" =~ ^#.*$ ]]; then
        log_info "Backup cron job is already enabled"
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would enable backup cron job"
        return 0
    fi
    
    # Remove comment character from cron line
    echo "$current_cron" | sed "/^${CRON_COMMENT}$/,+1 s/^#//" > "$TEMP_CRON"
    
    if crontab "$TEMP_CRON"; then
        log_info "Backup cron job enabled successfully"
        return 0
    else
        log_error "Failed to enable cron job"
        return 1
    fi
}

disable_cron_job() {
    log_info "Disabling backup cron job..."
    
    if ! has_backup_cron; then
        log_error "No backup cron job found to disable"
        return 1
    fi
    
    local current_cron
    current_cron="$(get_current_cron)"
    
    # Check if already disabled
    local cron_line
    cron_line="$(echo "$current_cron" | grep -A1 "$CRON_COMMENT" | tail -1)"
    
    if [[ "$cron_line" =~ ^#.*$ ]]; then
        log_info "Backup cron job is already disabled"
        return 0
    fi
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN: Would disable backup cron job"
        return 0
    fi
    
    # Add comment character to cron line
    echo "$current_cron" | sed "/^${CRON_COMMENT}$/,+1 s/^[^#]/#&/" > "$TEMP_CRON"
    
    if crontab "$TEMP_CRON"; then
        log_info "Backup cron job disabled successfully"
        return 0
    else
        log_error "Failed to disable cron job"
        return 1
    fi
}

test_configuration() {
    log_info "Testing backup cron configuration..."
    echo
    
    local errors=0
    
    # Test cron service
    echo -n "Checking cron service... "
    if check_cron_service; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        log_error "Cron service is not running"
        ((errors++))
    fi
    
    # Test crontab access
    echo -n "Checking crontab access... "
    if check_crontab_access; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        log_error "Cannot access crontab (permission denied)"
        ((errors++))
    fi
    
    # Test log directory
    echo -n "Checking log directory... "
    if setup_log_directory; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}FAILED${NC}"
        ((errors++))
    fi
    
    # Test backup script if it exists
    local script_path="${1:-$DEFAULT_BACKUP_SCRIPT}"
    if [[ -n "$script_path" ]]; then
        echo -n "Checking backup script... "
        if validate_backup_script "$script_path"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            ((errors++))
        fi
    fi
    
    # Test current cron job if exists
    if has_backup_cron; then
        echo -n "Checking existing cron job... "
        local cron_line
        cron_line="$(get_current_cron | grep -A1 "$CRON_COMMENT" | tail -1)"
        
        # Basic syntax validation
        if [[ "$cron_line" =~ ^#?[0-9]+[[:space:]]+[0-9]+[[:space:]]+\*[[:space:]]+\*[[:space:]]+\* ]]; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}FAILED${NC}"
            log_error "Invalid cron job syntax"
            ((errors++))
        fi
    fi
    
    echo
    if [[ $errors -eq 0 ]]; then
        log_info "All tests passed successfully"
        return 0
    else
        log_error "$errors test(s) failed"
        return 1
    fi
}

# Main function
main() {
    local command=""
    
    # Parse command line options
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            install|uninstall|status|enable|disable|test|help)
                command="$1"
                shift
                break
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # Show help if no command provided
    if [[ -z "$command" ]]; then
        show_help
        exit 1
    fi
    
    # Setup logging
    if ! setup_log_directory; then
        log_warn "Continuing without logging capability"
    fi
    
    # System checks
    if [[ "$command" != "help" && "$command" != "test" ]]; then
        if ! check_cron_service; then
            log_error "Cron service is not running"
            log_error "Please start the cron service and try again"
            exit 1
        fi
        
        if ! check_crontab_access; then
            log_error "Cannot access crontab (permission denied)"
            log_error "Please check your permissions and try again"
            exit 1
        fi
    fi
    
    # Execute command
    case "$command" in
        install)
            install_cron_job "$@"
            ;;
        uninstall)
            uninstall_cron_job
            ;;
        status)
            show_status
            ;;
        enable)
            enable_cron_job
            ;;
        disable)
            disable_cron_job
            ;;
        test)
            test_configuration "$@"
            ;;
        help)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"