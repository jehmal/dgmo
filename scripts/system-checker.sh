#!/bin/bash

# DGMSTT System Prerequisites Checker
# Comprehensive validation script for backup system requirements
# Author: DGMSTT Project
# Version: 1.0.0

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BACKUP_SCRIPT="$PROJECT_ROOT/qdrant-backup.sh"
LOG_DIR="$PROJECT_ROOT/logs"
BACKUP_DIR="$PROJECT_ROOT/backups"
LOCK_DIR="/tmp"
CONFIG_FILE="$PROJECT_ROOT/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Output format (text, json, markdown)
OUTPUT_FORMAT="text"
VERBOSE=false
DRY_RUN=false

# Arrays to store results
declare -a PASSED_ITEMS=()
declare -a FAILED_ITEMS=()
declare -a WARNING_ITEMS=()
declare -a RECOMMENDATIONS=()

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

DGMSTT System Prerequisites Checker

OPTIONS:
    -f, --format FORMAT     Output format: text, json, markdown (default: text)
    -v, --verbose          Enable verbose output
    -d, --dry-run          Perform dry run without making changes
    -h, --help             Show this help message

EXAMPLES:
    $0                     # Run basic checks with text output
    $0 -f json            # Output results in JSON format
    $0 -v                 # Run with verbose logging
    $0 -f markdown -v     # Verbose markdown report

EOF
}

# Logging functions
log_info() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1" >&2
    fi
}

log_success() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${GREEN}[PASS]${NC} $1" >&2
    fi
}

log_warning() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1" >&2
    fi
}

log_error() {
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${RED}[FAIL]${NC} $1" >&2
    fi
}

log_verbose() {
    if [[ "$VERBOSE" == "true" && "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1" >&2
    fi
}

# Check result tracking
add_check_result() {
    local status="$1"
    local description="$2"
    local recommendation="${3:-}"
    
    ((TOTAL_CHECKS++))
    
    case "$status" in
        "PASS")
            ((PASSED_CHECKS++))
            PASSED_ITEMS+=("$description")
            log_success "$description"
            ;;
        "FAIL")
            ((FAILED_CHECKS++))
            FAILED_ITEMS+=("$description")
            log_error "$description"
            if [[ -n "$recommendation" ]]; then
                RECOMMENDATIONS+=("$recommendation")
            fi
            ;;
        "WARN")
            ((WARNING_CHECKS++))
            WARNING_ITEMS+=("$description")
            log_warning "$description"
            if [[ -n "$recommendation" ]]; then
                RECOMMENDATIONS+=("$recommendation")
            fi
            ;;
    esac
}

# 1. Cron Service Verification
check_cron_service() {
    log_info "Checking cron service..."
    
    # Check if systemd is available
    if command -v systemctl >/dev/null 2>&1; then
        # SystemD systems
        if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
            add_check_result "PASS" "Cron service is running"
        else
            add_check_result "FAIL" "Cron service is not running" "Start cron service: sudo systemctl start cron (or crond)"
        fi
        
        if systemctl is-enabled --quiet cron 2>/dev/null || systemctl is-enabled --quiet crond 2>/dev/null; then
            add_check_result "PASS" "Cron service is enabled"
        else
            add_check_result "WARN" "Cron service is not enabled for startup" "Enable cron service: sudo systemctl enable cron (or crond)"
        fi
    else
        # Non-systemd systems
        if pgrep -x "cron\|crond" >/dev/null; then
            add_check_result "PASS" "Cron daemon is running"
        else
            add_check_result "FAIL" "Cron daemon is not running" "Start cron daemon manually or via init system"
        fi
    fi
    
    # Check crontab command availability
    if command -v crontab >/dev/null 2>&1; then
        add_check_result "PASS" "crontab command is available"
        
        # Test crontab access
        if crontab -l >/dev/null 2>&1 || [[ $? -eq 1 ]]; then
            add_check_result "PASS" "User has crontab access"
        else
            add_check_result "FAIL" "User cannot access crontab" "Check /etc/cron.allow and /etc/cron.deny files"
        fi
    else
        add_check_result "FAIL" "crontab command not found" "Install cron package: sudo apt-get install cron (Ubuntu/Debian) or sudo yum install cronie (RHEL/CentOS)"
    fi
    
    # Check cron permissions
    local current_user=$(whoami)
    
    if [[ -f /etc/cron.allow ]]; then
        if grep -q "^${current_user}$" /etc/cron.allow; then
            add_check_result "PASS" "User is explicitly allowed in /etc/cron.allow"
        else
            add_check_result "FAIL" "User not found in /etc/cron.allow" "Add user to /etc/cron.allow: echo '$current_user' | sudo tee -a /etc/cron.allow"
        fi
    elif [[ -f /etc/cron.deny ]]; then
        if grep -q "^${current_user}$" /etc/cron.deny; then
            add_check_result "FAIL" "User is denied in /etc/cron.deny" "Remove user from /etc/cron.deny or add to /etc/cron.allow"
        else
            add_check_result "PASS" "User is not denied cron access"
        fi
    else
        add_check_result "PASS" "No cron access restrictions found"
    fi
}

# 2. Backup Script Validation
check_backup_script() {
    log_info "Checking backup script..."
    
    # Check if backup script exists
    if [[ -f "$BACKUP_SCRIPT" ]]; then
        add_check_result "PASS" "Backup script exists at $BACKUP_SCRIPT"
        
        # Check if executable
        if [[ -x "$BACKUP_SCRIPT" ]]; then
            add_check_result "PASS" "Backup script is executable"
        else
            add_check_result "FAIL" "Backup script is not executable" "Make script executable: chmod +x $BACKUP_SCRIPT"
        fi
        
        # Check script syntax
        if bash -n "$BACKUP_SCRIPT" 2>/dev/null; then
            add_check_result "PASS" "Backup script syntax is valid"
        else
            add_check_result "FAIL" "Backup script has syntax errors" "Check script syntax: bash -n $BACKUP_SCRIPT"
        fi
        
        # Check script ownership
        local script_owner=$(stat -c '%U' "$BACKUP_SCRIPT" 2>/dev/null || stat -f '%Su' "$BACKUP_SCRIPT" 2>/dev/null)
        local current_user=$(whoami)
        
        if [[ "$script_owner" == "$current_user" ]] || [[ "$script_owner" == "root" ]]; then
            add_check_result "PASS" "Backup script has appropriate ownership"
        else
            add_check_result "WARN" "Backup script owned by different user: $script_owner" "Consider changing ownership: sudo chown $current_user $BACKUP_SCRIPT"
        fi
        
        # Check for dry-run capability
        if grep -q "\-\-dry-run\|DRY_RUN" "$BACKUP_SCRIPT"; then
            add_check_result "PASS" "Backup script supports dry-run mode"
        else
            add_check_result "WARN" "Backup script may not support dry-run mode" "Consider adding dry-run capability for testing"
        fi
        
    else
        add_check_result "FAIL" "Backup script not found at $BACKUP_SCRIPT" "Create backup script or update BACKUP_SCRIPT path"
    fi
}

# 3. Directory and File Checks
check_directories() {
    log_info "Checking directories and file permissions..."
    
    # Check log directory
    if [[ -d "$LOG_DIR" ]]; then
        add_check_result "PASS" "Log directory exists: $LOG_DIR"
        
        if [[ -w "$LOG_DIR" ]]; then
            add_check_result "PASS" "Log directory is writable"
        else
            add_check_result "FAIL" "Log directory is not writable" "Fix permissions: chmod 755 $LOG_DIR"
        fi
    else
        add_check_result "WARN" "Log directory does not exist: $LOG_DIR" "Create log directory: mkdir -p $LOG_DIR"
    fi
    
    # Check backup directory
    if [[ -d "$BACKUP_DIR" ]]; then
        add_check_result "PASS" "Backup directory exists: $BACKUP_DIR"
        
        if [[ -w "$BACKUP_DIR" ]]; then
            add_check_result "PASS" "Backup directory is writable"
        else
            add_check_result "FAIL" "Backup directory is not writable" "Fix permissions: chmod 755 $BACKUP_DIR"
        fi
    else
        add_check_result "WARN" "Backup directory does not exist: $BACKUP_DIR" "Create backup directory: mkdir -p $BACKUP_DIR"
    fi
    
    # Check lock file location
    if [[ -w "$LOCK_DIR" ]]; then
        add_check_result "PASS" "Lock directory is writable: $LOCK_DIR"
    else
        add_check_result "FAIL" "Lock directory is not writable: $LOCK_DIR" "Use alternative lock directory or fix permissions"
    fi
    
    # Test directory creation capability
    local test_dir="$PROJECT_ROOT/test_dir_$$"
    if mkdir "$test_dir" 2>/dev/null; then
        rmdir "$test_dir"
        add_check_result "PASS" "Can create directories in project root"
    else
        add_check_result "FAIL" "Cannot create directories in project root" "Check permissions on $PROJECT_ROOT"
    fi
}

# 4. Environment Validation
check_environment() {
    log_info "Checking environment variables and configuration..."
    
    # Load environment file if it exists
    if [[ -f "$CONFIG_FILE" ]]; then
        add_check_result "PASS" "Environment file exists: $CONFIG_FILE"
        
        # Source the file safely
        if source "$CONFIG_FILE" 2>/dev/null; then
            add_check_result "PASS" "Environment file is valid"
        else
            add_check_result "WARN" "Environment file has issues" "Check syntax in $CONFIG_FILE"
        fi
    else
        add_check_result "WARN" "Environment file not found: $CONFIG_FILE" "Create .env file with required variables"
    fi
    
    # Check required environment variables
    local required_vars=("QDRANT_URL")
    for var in "${required_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            add_check_result "PASS" "Environment variable $var is set"
            log_verbose "$var = ${!var}"
        else
            add_check_result "WARN" "Environment variable $var is not set" "Set $var in environment or .env file"
        fi
    done
    
    # Check PATH
    local required_paths=("/usr/bin" "/bin" "/usr/local/bin")
    for path in "${required_paths[@]}"; do
        if echo "$PATH" | grep -q "$path"; then
            add_check_result "PASS" "PATH includes $path"
        else
            add_check_result "WARN" "PATH missing $path" "Add $path to PATH environment variable"
        fi
    done
    
    # Check shell compatibility
    if [[ "$BASH_VERSION" ]]; then
        local bash_major=$(echo "$BASH_VERSION" | cut -d. -f1)
        if [[ "$bash_major" -ge 4 ]]; then
            add_check_result "PASS" "Bash version is compatible: $BASH_VERSION"
        else
            add_check_result "WARN" "Bash version may be too old: $BASH_VERSION" "Consider upgrading to Bash 4.0 or later"
        fi
    else
        add_check_result "WARN" "Not running in Bash shell" "Scripts are designed for Bash"
    fi
    
    # Check user groups
    local current_user=$(whoami)
    local user_groups=$(groups 2>/dev/null || echo "")
    log_verbose "User groups: $user_groups"
    
    if echo "$user_groups" | grep -q "sudo\|wheel\|admin"; then
        add_check_result "PASS" "User has administrative privileges"
    else
        add_check_result "WARN" "User may not have administrative privileges" "Some operations may require sudo access"
    fi
}

# 5. Dependency Verification
check_dependencies() {
    log_info "Checking required dependencies..."
    
    # Required commands with their purposes
    declare -A required_commands=(
        ["curl"]="HTTP requests to Qdrant API"
        ["jq"]="JSON processing"
        ["tar"]="Archive creation"
        ["gzip"]="Compression"
        ["find"]="File searching"
        ["stat"]="File information"
        ["date"]="Timestamp generation"
        ["grep"]="Text searching"
        ["awk"]="Text processing"
        ["sed"]="Text manipulation"
    )
    
    for cmd in "${!required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            local cmd_path=$(command -v "$cmd")
            local cmd_version=""
            
            # Try to get version information
            case "$cmd" in
                "curl") cmd_version=$(curl --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown") ;;
                "jq") cmd_version=$(jq --version 2>/dev/null | sed 's/jq-//' || echo "unknown") ;;
                "tar") cmd_version=$(tar --version 2>/dev/null | head -n1 | awk '{print $NF}' || echo "unknown") ;;
                "gzip") cmd_version=$(gzip --version 2>/dev/null | head -n1 | awk '{print $2}' || echo "unknown") ;;
                *) cmd_version="available" ;;
            esac
            
            add_check_result "PASS" "$cmd command available ($cmd_version) - ${required_commands[$cmd]}"
            log_verbose "$cmd location: $cmd_path"
        else
            add_check_result "FAIL" "$cmd command not found - ${required_commands[$cmd]}" "Install $cmd package"
        fi
    done
    
    # Test network connectivity to Qdrant
    local qdrant_url="${QDRANT_URL:-http://localhost:6333}"
    log_verbose "Testing connectivity to: $qdrant_url"
    
    if command -v curl >/dev/null 2>&1; then
        if curl -s --connect-timeout 5 "$qdrant_url/health" >/dev/null 2>&1; then
            add_check_result "PASS" "Qdrant service is accessible at $qdrant_url"
        else
            add_check_result "WARN" "Cannot connect to Qdrant at $qdrant_url" "Check if Qdrant is running and accessible"
        fi
    else
        add_check_result "WARN" "Cannot test Qdrant connectivity (curl not available)"
    fi
}

# 6. System Resource Checks
check_system_resources() {
    log_info "Checking system resources..."
    
    # Check disk space
    local backup_dir_parent=$(dirname "$BACKUP_DIR")
    if [[ -d "$backup_dir_parent" ]]; then
        local available_space=$(df "$backup_dir_parent" | awk 'NR==2 {print $4}')
        local available_gb=$((available_space / 1024 / 1024))
        
        if [[ "$available_gb" -gt 1 ]]; then
            add_check_result "PASS" "Sufficient disk space available: ${available_gb}GB"
        elif [[ "$available_gb" -gt 0 ]]; then
            add_check_result "WARN" "Limited disk space: ${available_gb}GB" "Monitor disk usage and clean old backups"
        else
            add_check_result "FAIL" "Very low disk space: ${available_space}KB" "Free up disk space before running backups"
        fi
    else
        add_check_result "WARN" "Cannot check disk space for backup directory"
    fi
    
    # Check memory
    if [[ -f /proc/meminfo ]]; then
        local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        local mem_available_mb=$((mem_available / 1024))
        
        if [[ "$mem_available_mb" -gt 512 ]]; then
            add_check_result "PASS" "Sufficient memory available: ${mem_available_mb}MB"
        elif [[ "$mem_available_mb" -gt 256 ]]; then
            add_check_result "WARN" "Limited memory available: ${mem_available_mb}MB" "Monitor memory usage during backups"
        else
            add_check_result "WARN" "Low memory available: ${mem_available_mb}MB" "Consider running backups during low-usage periods"
        fi
    else
        add_check_result "WARN" "Cannot check memory information"
    fi
    
    # Check file descriptor limits
    local fd_limit=$(ulimit -n)
    if [[ "$fd_limit" -gt 1024 ]]; then
        add_check_result "PASS" "File descriptor limit is adequate: $fd_limit"
    else
        add_check_result "WARN" "File descriptor limit may be low: $fd_limit" "Consider increasing with: ulimit -n 4096"
    fi
    
    # Check system load
    if [[ -f /proc/loadavg ]]; then
        local load_1min=$(awk '{print $1}' /proc/loadavg)
        local load_int=${load_1min%.*}
        
        if [[ "$load_int" -lt 2 ]]; then
            add_check_result "PASS" "System load is reasonable: $load_1min"
        else
            add_check_result "WARN" "System load is high: $load_1min" "Consider scheduling backups during low-load periods"
        fi
    else
        add_check_result "WARN" "Cannot check system load"
    fi
}

# 7. Security Validation
check_security() {
    log_info "Checking security configuration..."
    
    # Check file permissions on critical files
    local critical_files=("$BACKUP_SCRIPT" "$CONFIG_FILE")
    
    for file in "${critical_files[@]}"; do
        if [[ -f "$file" ]]; then
            local perms=$(stat -c '%a' "$file" 2>/dev/null || stat -f '%A' "$file" 2>/dev/null)
            local owner=$(stat -c '%U' "$file" 2>/dev/null || stat -f '%Su' "$file" 2>/dev/null)
            
            # Check if world-writable
            if [[ "${perms: -1}" =~ [2367] ]]; then
                add_check_result "FAIL" "File $file is world-writable ($perms)" "Fix permissions: chmod 644 $file"
            else
                add_check_result "PASS" "File $file has secure permissions ($perms)"
            fi
            
            log_verbose "$file: owner=$owner, permissions=$perms"
        fi
    done
    
    # Check for world-writable directories in critical paths
    local critical_dirs=("$PROJECT_ROOT" "$LOG_DIR" "$BACKUP_DIR")
    
    for dir in "${critical_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            local perms=$(stat -c '%a' "$dir" 2>/dev/null || stat -f '%A' "$dir" 2>/dev/null)
            
            # Check if world-writable without sticky bit
            if [[ "${perms: -1}" =~ [23] ]]; then
                add_check_result "WARN" "Directory $dir is world-writable ($perms)" "Consider restricting permissions: chmod 755 $dir"
            else
                add_check_result "PASS" "Directory $dir has secure permissions ($perms)"
            fi
        fi
    done
    
    # Check SELinux status
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status=$(getenforce 2>/dev/null || echo "Unknown")
        case "$selinux_status" in
            "Enforcing")
                add_check_result "WARN" "SELinux is enforcing" "May need to configure SELinux policies for backup scripts"
                ;;
            "Permissive")
                add_check_result "PASS" "SELinux is permissive"
                ;;
            "Disabled")
                add_check_result "PASS" "SELinux is disabled"
                ;;
            *)
                add_check_result "WARN" "SELinux status unknown: $selinux_status"
                ;;
        esac
    fi
    
    # Check AppArmor status
    if command -v aa-status >/dev/null 2>&1; then
        if aa-status --enabled 2>/dev/null; then
            add_check_result "WARN" "AppArmor is enabled" "May need to configure AppArmor profiles for backup scripts"
        else
            add_check_result "PASS" "AppArmor is not restricting"
        fi
    fi
    
    # Check user privilege requirements
    local current_user=$(whoami)
    if [[ "$current_user" == "root" ]]; then
        add_check_result "WARN" "Running as root user" "Consider running as non-privileged user for security"
    else
        add_check_result "PASS" "Running as non-root user: $current_user"
    fi
}

# Output generation functions
generate_text_output() {
    echo
    echo "=========================================="
    echo "DGMSTT System Prerequisites Check Report"
    echo "=========================================="
    echo "Generated: $(date)"
    echo "Host: $(hostname)"
    echo "User: $(whoami)"
    echo "Project: $PROJECT_ROOT"
    echo
    
    echo "SUMMARY:"
    echo "--------"
    echo "Total Checks: $TOTAL_CHECKS"
    echo -e "Passed: ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "Failed: ${RED}$FAILED_CHECKS${NC}"
    echo -e "Warnings: ${YELLOW}$WARNING_CHECKS${NC}"
    echo
    
    if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
        echo -e "${RED}FAILED CHECKS:${NC}"
        printf '%s\n' "${FAILED_ITEMS[@]}" | sed 's/^/  ❌ /'
        echo
    fi
    
    if [[ ${#WARNING_ITEMS[@]} -gt 0 ]]; then
        echo -e "${YELLOW}WARNINGS:${NC}"
        printf '%s\n' "${WARNING_ITEMS[@]}" | sed 's/^/  ⚠️  /'
        echo
    fi
    
    if [[ ${#PASSED_ITEMS[@]} -gt 0 ]]; then
        echo -e "${GREEN}PASSED CHECKS:${NC}"
        printf '%s\n' "${PASSED_ITEMS[@]}" | sed 's/^/  ✅ /'
        echo
    fi
    
    if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
        echo -e "${BLUE}RECOMMENDATIONS:${NC}"
        printf '%s\n' "${RECOMMENDATIONS[@]}" | sed 's/^/  💡 /'
        echo
    fi
    
    # Overall status
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        if [[ $WARNING_CHECKS -eq 0 ]]; then
            echo -e "${GREEN}✅ SYSTEM READY: All checks passed!${NC}"
        else
            echo -e "${YELLOW}⚠️  SYSTEM MOSTLY READY: $WARNING_CHECKS warnings found${NC}"
        fi
    else
        echo -e "${RED}❌ SYSTEM NOT READY: $FAILED_CHECKS critical issues found${NC}"
    fi
}

generate_json_output() {
    cat << EOF
{
  "report": {
    "generated": "$(date -Iseconds)",
    "host": "$(hostname)",
    "user": "$(whoami)",
    "project_root": "$PROJECT_ROOT",
    "summary": {
      "total_checks": $TOTAL_CHECKS,
      "passed": $PASSED_CHECKS,
      "failed": $FAILED_CHECKS,
      "warnings": $WARNING_CHECKS
    },
    "status": "$(if [[ $FAILED_CHECKS -eq 0 ]]; then echo "ready"; else echo "not_ready"; fi)",
    "results": {
      "passed": $(printf '%s\n' "${PASSED_ITEMS[@]}" | jq -R . | jq -s .),
      "failed": $(printf '%s\n' "${FAILED_ITEMS[@]}" | jq -R . | jq -s .),
      "warnings": $(printf '%s\n' "${WARNING_ITEMS[@]}" | jq -R . | jq -s .),
      "recommendations": $(printf '%s\n' "${RECOMMENDATIONS[@]}" | jq -R . | jq -s .)
    }
  }
}
EOF
}

generate_markdown_output() {
    cat << EOF
# DGMSTT System Prerequisites Check Report

**Generated:** $(date)  
**Host:** $(hostname)  
**User:** $(whoami)  
**Project:** $PROJECT_ROOT  

## Summary

| Metric | Count |
|--------|-------|
| Total Checks | $TOTAL_CHECKS |
| ✅ Passed | $PASSED_CHECKS |
| ❌ Failed | $FAILED_CHECKS |
| ⚠️ Warnings | $WARNING_CHECKS |

EOF

    if [[ ${#FAILED_ITEMS[@]} -gt 0 ]]; then
        echo "## ❌ Failed Checks"
        echo
        printf '%s\n' "${FAILED_ITEMS[@]}" | sed 's/^/- /'
        echo
    fi
    
    if [[ ${#WARNING_ITEMS[@]} -gt 0 ]]; then
        echo "## ⚠️ Warnings"
        echo
        printf '%s\n' "${WARNING_ITEMS[@]}" | sed 's/^/- /'
        echo
    fi
    
    if [[ ${#PASSED_ITEMS[@]} -gt 0 ]]; then
        echo "## ✅ Passed Checks"
        echo
        printf '%s\n' "${PASSED_ITEMS[@]}" | sed 's/^/- /'
        echo
    fi
    
    if [[ ${#RECOMMENDATIONS[@]} -gt 0 ]]; then
        echo "## 💡 Recommendations"
        echo
        printf '%s\n' "${RECOMMENDATIONS[@]}" | sed 's/^/- /'
        echo
    fi
    
    echo "## Overall Status"
    echo
    if [[ $FAILED_CHECKS -eq 0 ]]; then
        if [[ $WARNING_CHECKS -eq 0 ]]; then
            echo "✅ **SYSTEM READY:** All checks passed!"
        else
            echo "⚠️ **SYSTEM MOSTLY READY:** $WARNING_CHECKS warnings found"
        fi
    else
        echo "❌ **SYSTEM NOT READY:** $FAILED_CHECKS critical issues found"
    fi
}

# Main execution function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage
                exit 1
                ;;
        esac
    done
    
    # Validate output format
    if [[ ! "$OUTPUT_FORMAT" =~ ^(text|json|markdown)$ ]]; then
        echo "Error: Invalid output format '$OUTPUT_FORMAT'. Must be text, json, or markdown." >&2
        exit 1
    fi
    
    # Show header for text output
    if [[ "$OUTPUT_FORMAT" == "text" ]]; then
        echo -e "${PURPLE}DGMSTT System Prerequisites Checker${NC}"
        echo -e "${PURPLE}====================================${NC}"
        echo
    fi
    
    # Run all checks
    check_cron_service
    check_backup_script
    check_directories
    check_environment
    check_dependencies
    check_system_resources
    check_security
    
    # Generate output based on format
    case "$OUTPUT_FORMAT" in
        "text")
            generate_text_output
            ;;
        "json")
            generate_json_output
            ;;
        "markdown")
            generate_markdown_output
            ;;
    esac
    
    # Exit with appropriate code
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        exit 1
    elif [[ $WARNING_CHECKS -gt 0 ]]; then
        exit 2
    else
        exit 0
    fi
}

# Run main function with all arguments
main "$@"