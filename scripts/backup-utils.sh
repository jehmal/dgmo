#!/bin/bash

#===============================================================================
# BACKUP SYSTEM SHARED UTILITIES
#===============================================================================
# Name: backup-utils.sh
# Purpose: Common functions and utilities for backup management system
# Author: DGMSTT Backup System
# Version: 1.0
#
# This file provides shared functionality for all backup management utilities:
# - Configuration loading and validation
# - Common UI/UX functions
# - JSON/XML output formatting
# - Error handling and logging
# - System information gathering
#===============================================================================

set -euo pipefail

#===============================================================================
# GLOBAL CONFIGURATION
#===============================================================================

# Script metadata
BACKUP_UTILS_VERSION="1.0"
BACKUP_UTILS_DATE="2025-07-06"

# Default configuration file locations
DEFAULT_CONFIG_FILES=(
    "/etc/dgmstt/backup-config.conf"
    "$HOME/.config/dgmstt/backup-config.conf"
    "$HOME/.dgmstt/backup-config.conf"
    "./backup-config.conf"
)

# Color codes for terminal output
declare -A COLORS=(
    [RED]='\033[0;31m'
    [GREEN]='\033[0;32m'
    [YELLOW]='\033[1;33m'
    [BLUE]='\033[0;34m'
    [PURPLE]='\033[0;35m'
    [CYAN]='\033[0;36m'
    [WHITE]='\033[1;37m'
    [BOLD]='\033[1m'
    [NC]='\033[0m'  # No Color
)

# Unicode symbols for better UX
declare -A SYMBOLS=(
    [CHECK]='✅'
    [CROSS]='❌'
    [WARNING]='⚠️'
    [INFO]='ℹ️'
    [CLOCK]='🕐'
    [FOLDER]='📁'
    [FILE]='📄'
    [GEAR]='⚙️'
    [ROCKET]='🚀'
    [SHIELD]='🛡️'
    [CHART]='📊'
    [SEARCH]='🔍'
)

# Global variables for configuration
declare -A CONFIG
declare -g OUTPUT_FORMAT="text"
declare -g VERBOSE=false
declare -g QUIET=false
declare -g CONFIG_FILE=""

#===============================================================================
# UTILITY FUNCTIONS
#===============================================================================

# Get current timestamp in various formats
timestamp() {
    local format="${1:-iso}"
    case "$format" in
        iso)     date '+%Y-%m-%d %H:%M:%S' ;;
        file)    date '+%Y-%m-%d_%H-%M-%S' ;;
        epoch)   date '+%s' ;;
        human)   date '+%B %d, %Y at %I:%M %p' ;;
        *)       date '+%Y-%m-%d %H:%M:%S' ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Convert bytes to human readable format
human_readable_size() {
    local bytes=$1
    local units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit=0
    local size=$bytes
    
    while [[ $size -gt 1024 && $unit -lt 5 ]]; do
        size=$((size / 1024))
        unit=$((unit + 1))
    done
    
    if [[ $unit -eq 0 ]]; then
        echo "${size}${units[$unit]}"
    else
        printf "%.1f%s\n" "$(echo "scale=1; $bytes / (1024^$unit)" | bc -l)" "${units[$unit]}"
    fi
}

# Calculate duration in human readable format
human_readable_duration() {
    local seconds=$1
    local days=$((seconds / 86400))
    local hours=$(((seconds % 86400) / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    local result=""
    [[ $days -gt 0 ]] && result="${days}d "
    [[ $hours -gt 0 ]] && result="${result}${hours}h "
    [[ $minutes -gt 0 ]] && result="${result}${minutes}m "
    [[ $secs -gt 0 || -z "$result" ]] && result="${result}${secs}s"
    
    echo "${result% }"
}

#===============================================================================
# OUTPUT FORMATTING FUNCTIONS
#===============================================================================

# Print colored output
print_color() {
    local color="$1"
    shift
    local message="$*"
    
    if [[ "$QUIET" == "true" ]]; then
        return 0
    fi
    
    if [[ -t 1 ]]; then  # Only use colors if outputting to terminal
        echo -e "${COLORS[$color]}${message}${COLORS[NC]}"
    else
        echo "$message"
    fi
}

# Print with symbol
print_symbol() {
    local symbol="$1"
    shift
    local message="$*"
    
    if [[ "$QUIET" == "true" ]]; then
        return 0
    fi
    
    echo -e "${SYMBOLS[$symbol]} $message"
}

# Print status message
print_status() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        success) print_color GREEN "${SYMBOLS[CHECK]} $message" ;;
        error)   print_color RED "${SYMBOLS[CROSS]} $message" ;;
        warning) print_color YELLOW "${SYMBOLS[WARNING]} $message" ;;
        info)    print_color BLUE "${SYMBOLS[INFO]} $message" ;;
        *)       echo "$message" ;;
    esac
}

# Print section header
print_header() {
    local title="$1"
    local width=80
    
    if [[ "$QUIET" == "true" ]]; then
        return 0
    fi
    
    print_color BOLD "\n$(printf '=%.0s' $(seq 1 $width))"
    print_color BOLD "$(printf '%-*s' $width "$title")"
    print_color BOLD "$(printf '=%.0s' $(seq 1 $width))\n"
}

# Print table row
print_table_row() {
    local -a columns=("$@")
    local format="%-20s %-15s %-25s %-20s\n"
    
    if [[ "$QUIET" == "true" ]]; then
        return 0
    fi
    
    printf "$format" "${columns[@]}"
}

#===============================================================================
# CONFIGURATION MANAGEMENT
#===============================================================================

# Find and load configuration file
load_config() {
    local config_file="$1"
    
    # If specific config file provided, use it
    if [[ -n "$config_file" ]]; then
        if [[ -f "$config_file" ]]; then
            CONFIG_FILE="$config_file"
        else
            print_status error "Configuration file not found: $config_file"
            return 1
        fi
    else
        # Search for default config files
        for file in "${DEFAULT_CONFIG_FILES[@]}"; do
            if [[ -f "$file" ]]; then
                CONFIG_FILE="$file"
                break
            fi
        done
        
        if [[ -z "$CONFIG_FILE" ]]; then
            print_status warning "No configuration file found, using defaults"
            set_default_config
            return 0
        fi
    fi
    
    # Parse configuration file
    parse_config_file "$CONFIG_FILE"
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_status info "Loaded configuration from: $CONFIG_FILE"
    fi
}

# Parse configuration file
parse_config_file() {
    local file="$1"
    local section=""
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ "$line" =~ ^[[:space:]]*$ ]] && continue
        
        # Handle sections
        if [[ "$line" =~ ^\[([^\]]+)\] ]]; then
            section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Handle key=value pairs
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            # Expand ~ to home directory
            value="${value/#\~/$HOME}"
            
            # Store with section prefix if in section
            if [[ -n "$section" ]]; then
                CONFIG["${section}.${key}"]="$value"
            else
                CONFIG["$key"]="$value"
            fi
        fi
    done < "$file"
}

# Set default configuration values
set_default_config() {
    CONFIG["PATHS.SOURCE_DIR"]="$HOME/.opencode/sessions"
    CONFIG["PATHS.BACKUP_DIR"]="$HOME/backups/sessions"
    CONFIG["PATHS.LOG_DIR"]="$HOME/backups/logs"
    CONFIG["PATHS.LOCK_FILE"]="/tmp/session-backup.lock"
    
    CONFIG["RETENTION.RETENTION_DAYS"]="30"
    CONFIG["RETENTION.MAX_BACKUPS"]="100"
    CONFIG["RETENTION.MIN_FREE_SPACE_GB"]="5"
    
    CONFIG["COMPRESSION.COMPRESSION_LEVEL"]="6"
    CONFIG["COMPRESSION.EXCLUDE_PATTERNS"]="*.tmp,*.log,*.cache,*.swp,*~,.DS_Store,Thumbs.db"
    CONFIG["COMPRESSION.VERIFY_INTEGRITY"]="true"
    
    CONFIG["NOTIFICATIONS.EMAIL_ON_FAILURE"]="false"
    CONFIG["NOTIFICATIONS.EMAIL_ADDRESS"]=""
    CONFIG["NOTIFICATIONS.SMTP_SERVER"]=""
    CONFIG["NOTIFICATIONS.NOTIFICATION_LEVEL"]="ERROR"
    
    CONFIG["LOGGING.LOG_LEVEL"]="INFO"
    CONFIG["LOGGING.MAX_LOG_SIZE_MB"]="10"
    CONFIG["LOGGING.LOG_RETENTION_COUNT"]="5"
    CONFIG["LOGGING.TIMESTAMP_FORMAT"]="%Y-%m-%d %H:%M:%S"
}

# Get configuration value with default
get_config() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG[$key]:-$default}"
}

#===============================================================================
# JSON/XML OUTPUT FUNCTIONS
#===============================================================================

# Start JSON output
json_start() {
    echo "{"
}

# End JSON output
json_end() {
    echo "}"
}

# Add JSON field
json_field() {
    local key="$1"
    local value="$2"
    local is_last="${3:-false}"
    local comma=""
    
    [[ "$is_last" != "true" ]] && comma=","
    
    # Escape JSON special characters
    value=$(echo "$value" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g; s/\n/\\n/g')
    
    echo "  \"$key\": \"$value\"$comma"
}

# Add JSON array
json_array() {
    local key="$1"
    shift
    local items=("$@")
    local is_last="${items[-1]}"
    unset 'items[-1]'
    
    echo "  \"$key\": ["
    for i in "${!items[@]}"; do
        local comma=","
        [[ $i -eq $((${#items[@]} - 1)) ]] && comma=""
        echo "    \"${items[$i]}\"$comma"
    done
    echo "  ]$([ "$is_last" != "true" ] && echo ",")"
}

# Start XML output
xml_start() {
    local root="${1:-backup_status}"
    echo "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    echo "<$root>"
}

# End XML output
xml_end() {
    local root="${1:-backup_status}"
    echo "</$root>"
}

# Add XML element
xml_element() {
    local tag="$1"
    local value="$2"
    
    # Escape XML special characters
    value=$(echo "$value" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g')
    
    echo "  <$tag>$value</$tag>"
}

#===============================================================================
# SYSTEM INFORMATION FUNCTIONS
#===============================================================================

# Get system information
get_system_info() {
    local info_type="$1"
    
    case "$info_type" in
        os)
            if [[ -f /etc/os-release ]]; then
                grep '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2
            else
                uname -s
            fi
            ;;
        kernel)
            uname -r
            ;;
        arch)
            uname -m
            ;;
        uptime)
            if command_exists uptime; then
                uptime -p 2>/dev/null || uptime | awk '{print $3,$4}' | sed 's/,//'
            else
                echo "Unknown"
            fi
            ;;
        load)
            if [[ -f /proc/loadavg ]]; then
                cut -d' ' -f1-3 /proc/loadavg
            else
                echo "Unknown"
            fi
            ;;
        memory)
            if [[ -f /proc/meminfo ]]; then
                local total=$(grep '^MemTotal:' /proc/meminfo | awk '{print $2}')
                local available=$(grep '^MemAvailable:' /proc/meminfo | awk '{print $2}')
                local used=$((total - available))
                local percent=$((used * 100 / total))
                echo "${percent}% ($(human_readable_size $((used * 1024))) / $(human_readable_size $((total * 1024))))"
            else
                echo "Unknown"
            fi
            ;;
        disk)
            local path="${2:-/}"
            if command_exists df; then
                df -h "$path" 2>/dev/null | awk 'NR==2 {print $5 " (" $3 "/" $2 ")"}'
            else
                echo "Unknown"
            fi
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# Get cron job information
get_cron_info() {
    local info_type="$1"
    
    case "$info_type" in
        user_jobs)
            crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' || echo ""
            ;;
        system_jobs)
            if [[ -d /etc/cron.d ]]; then
                find /etc/cron.d -type f -exec grep -l "backup\|session" {} \; 2>/dev/null || echo ""
            fi
            ;;
        service_status)
            if command_exists systemctl; then
                systemctl is-active cron 2>/dev/null || systemctl is-active crond 2>/dev/null || echo "unknown"
            else
                echo "unknown"
            fi
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

# Get backup statistics
get_backup_stats() {
    local backup_dir="$(get_config 'PATHS.BACKUP_DIR' "$HOME/backups/sessions")"
    local stat_type="$1"
    
    case "$stat_type" in
        count)
            if [[ -d "$backup_dir" ]]; then
                find "$backup_dir" -name "*.tar.gz" -type f 2>/dev/null | wc -l
            else
                echo "0"
            fi
            ;;
        total_size)
            if [[ -d "$backup_dir" ]]; then
                local size=$(find "$backup_dir" -name "*.tar.gz" -type f -exec du -cb {} + 2>/dev/null | tail -1 | cut -f1)
                human_readable_size "${size:-0}"
            else
                echo "0B"
            fi
            ;;
        latest)
            if [[ -d "$backup_dir" ]]; then
                find "$backup_dir" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "None"
            else
                echo "None"
            fi
            ;;
        oldest)
            if [[ -d "$backup_dir" ]]; then
                find "$backup_dir" -name "*.tar.gz" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "None"
            else
                echo "None"
            fi
            ;;
        *)
            echo "Unknown"
            ;;
    esac
}

#===============================================================================
# ERROR HANDLING AND LOGGING
#===============================================================================

# Log message with level
log_message() {
    local level="$1"
    shift
    local message="$*"
    local log_file="$(get_config 'PATHS.LOG_DIR' "$HOME/backups/logs")/backup-utils.log"
    local timestamp=$(timestamp iso)
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$log_file")"
    
    # Write to log file
    echo "[$timestamp] [$level] $message" >> "$log_file"
    
    # Also output to console if verbose or error
    if [[ "$VERBOSE" == "true" || "$level" == "ERROR" ]]; then
        case "$level" in
            ERROR)   print_status error "$message" ;;
            WARNING) print_status warning "$message" ;;
            INFO)    print_status info "$message" ;;
            *)       echo "$message" ;;
        esac
    fi
}

# Error handler
handle_error() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    
    log_message "ERROR" "Script failed at line $line_number: $command (exit code: $exit_code)"
    print_status error "An error occurred. Check logs for details."
    exit $exit_code
}

# Set up error trapping
setup_error_handling() {
    trap 'handle_error $LINENO "$BASH_COMMAND"' ERR
}

#===============================================================================
# VALIDATION FUNCTIONS
#===============================================================================

# Validate directory exists and is readable
validate_directory() {
    local dir="$1"
    local purpose="$2"
    
    if [[ ! -d "$dir" ]]; then
        log_message "ERROR" "$purpose directory does not exist: $dir"
        return 1
    fi
    
    if [[ ! -r "$dir" ]]; then
        log_message "ERROR" "$purpose directory is not readable: $dir"
        return 1
    fi
    
    return 0
}

# Validate file exists and is readable
validate_file() {
    local file="$1"
    local purpose="$2"
    
    if [[ ! -f "$file" ]]; then
        log_message "ERROR" "$purpose file does not exist: $file"
        return 1
    fi
    
    if [[ ! -r "$file" ]]; then
        log_message "ERROR" "$purpose file is not readable: $file"
        return 1
    fi
    
    return 0
}

# Validate cron expression
validate_cron_expression() {
    local cron_expr="$1"
    
    # Basic validation - should have 5 or 6 fields
    local field_count=$(echo "$cron_expr" | wc -w)
    
    if [[ $field_count -lt 5 || $field_count -gt 6 ]]; then
        return 1
    fi
    
    # Additional validation could be added here
    return 0
}

#===============================================================================
# INITIALIZATION
#===============================================================================

# Initialize backup utilities
init_backup_utils() {
    local config_file="${1:-}"
    
    # Set up error handling
    setup_error_handling
    
    # Load configuration
    load_config "$config_file"
    
    # Log initialization
    log_message "INFO" "Backup utilities initialized (version $BACKUP_UTILS_VERSION)"
}

# Export functions for use by other scripts
export -f timestamp command_exists human_readable_size human_readable_duration
export -f print_color print_symbol print_status print_header print_table_row
export -f load_config get_config
export -f json_start json_end json_field json_array xml_start xml_end xml_element
export -f get_system_info get_cron_info get_backup_stats
export -f log_message handle_error setup_error_handling
export -f validate_directory validate_file validate_cron_expression
export -f init_backup_utils

# Make configuration and variables available
export CONFIG
export OUTPUT_FORMAT VERBOSE QUIET CONFIG_FILE
export COLORS SYMBOLS