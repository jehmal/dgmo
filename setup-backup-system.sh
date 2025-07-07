#!/bin/bash

# DGMSTT Backup System Installer
# Automated installation and configuration script
# Version: 2.0.0

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="/opt/dgmstt-backup"
CONFIG_DIR="/etc/dgmstt-backup"
LOG_DIR="/var/log/dgmstt-backup"
BACKUP_DIR="/opt/dgmstt-backup/backups"
SCRIPT_VERSION="2.0.0"

# Default configuration values
DEFAULT_SOURCE_DIR="/opt/dgmstt"
DEFAULT_RETENTION_DAYS=30
DEFAULT_COMPRESSION_LEVEL=6
DEFAULT_EMAIL=""
DEFAULT_LOG_LEVEL="INFO"

# Installation flags
FORCE_INSTALL=false
UPGRADE_MODE=false
DRY_RUN=false
QUIET_MODE=false
SKIP_DEPS=false
BACKUP_EXISTING=true

# Function to print colored output
print_status() {
    local level=$1
    shift
    local message="$*"
    
    if [[ "$QUIET_MODE" == "true" && "$level" != "ERROR" ]]; then
        return
    fi
    
    case $level in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "STEP")
            echo -e "${GREEN}[STEP]${NC} $message"
            ;;
    esac
}

# Function to show usage
show_usage() {
    cat << EOF
DGMSTT Backup System Installer v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    --help                  Show this help message
    --version              Show version information
    --force                Force installation (overwrite existing)
    --upgrade              Upgrade existing installation
    --dry-run              Show what would be done without executing
    --quiet                Suppress non-error output
    --skip-deps            Skip dependency installation
    --no-backup            Don't backup existing configuration
    
    --source-dir=PATH      Source directory to backup (default: $DEFAULT_SOURCE_DIR)
    --backup-dir=PATH      Backup destination directory (default: $BACKUP_DIR)
    --retention=DAYS       Backup retention in days (default: $DEFAULT_RETENTION_DAYS)
    --compression=LEVEL    Compression level 1-9 (default: $DEFAULT_COMPRESSION_LEVEL)
    --email=ADDRESS        Email for notifications (default: none)
    --log-level=LEVEL      Log level: DEBUG,INFO,WARN,ERROR (default: $DEFAULT_LOG_LEVEL)

EXAMPLES:
    # Basic installation
    $0
    
    # Custom source directory
    $0 --source-dir=/home/user/dgmstt
    
    # Production setup with email notifications
    $0 --source-dir=/opt/dgmstt --email=admin@company.com --retention=90
    
    # Upgrade existing installation
    $0 --upgrade
    
    # Dry run to see what would be installed
    $0 --dry-run

EOF
}

# Function to show version
show_version() {
    echo "DGMSTT Backup System Installer v${SCRIPT_VERSION}"
    echo "Copyright (c) 2024 DGMSTT Team"
}

# Function to detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="rhel"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
        OS_VERSION=$(sw_vers -productVersion)
    else
        print_status "ERROR" "Unsupported operating system"
        exit 1
    fi
    
    print_status "INFO" "Detected OS: $OS $OS_VERSION"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_status "ERROR" "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check system requirements
check_requirements() {
    print_status "STEP" "Checking system requirements..."
    
    # Check available disk space (minimum 1GB)
    local available_space
    available_space=$(df /opt 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    local required_space=1048576  # 1GB in KB
    
    if [[ $available_space -lt $required_space ]]; then
        print_status "ERROR" "Insufficient disk space. Required: 1GB, Available: $((available_space/1024))MB"
        exit 1
    fi
    
    # Check if backup directory path is valid
    local backup_parent
    backup_parent=$(dirname "$BACKUP_DIR")
    if [[ ! -d "$backup_parent" ]]; then
        print_status "WARNING" "Parent directory $backup_parent does not exist, will be created"
    fi
    
    print_status "SUCCESS" "System requirements check passed"
}

# Function to install dependencies
install_dependencies() {
    if [[ "$SKIP_DEPS" == "true" ]]; then
        print_status "INFO" "Skipping dependency installation"
        return
    fi
    
    print_status "STEP" "Installing dependencies..."
    
    case $OS in
        "ubuntu"|"debian")
            if [[ "$DRY_RUN" == "true" ]]; then
                print_status "INFO" "Would run: apt update && apt install -y tar gzip cron logrotate rsync curl jq"
                return
            fi
            
            apt update
            apt install -y tar gzip cron logrotate rsync curl jq
            
            # Ensure cron is running
            systemctl enable cron
            systemctl start cron
            ;;
            
        "centos"|"rhel"|"fedora")
            if [[ "$DRY_RUN" == "true" ]]; then
                print_status "INFO" "Would run: yum install -y tar gzip cronie logrotate rsync curl jq"
                return
            fi
            
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y tar gzip cronie logrotate rsync curl jq
            else
                yum install -y tar gzip cronie logrotate rsync curl jq
            fi
            
            # Ensure crond is running
            systemctl enable crond
            systemctl start crond
            ;;
            
        "macos")
            if [[ "$DRY_RUN" == "true" ]]; then
                print_status "INFO" "Would run: brew install gnu-tar gzip rsync curl jq"
                return
            fi
            
            if ! command -v brew >/dev/null 2>&1; then
                print_status "ERROR" "Homebrew is required on macOS. Please install it first."
                exit 1
            fi
            
            brew install gnu-tar gzip rsync curl jq
            ;;
            
        *)
            print_status "ERROR" "Unsupported OS for automatic dependency installation: $OS"
            print_status "INFO" "Please install manually: tar, gzip, cron, logrotate, rsync, curl, jq"
            exit 1
            ;;
    esac
    
    print_status "SUCCESS" "Dependencies installed successfully"
}

# Function to verify dependencies
verify_dependencies() {
    print_status "STEP" "Verifying dependencies..."
    
    local missing_deps=()
    local deps=("tar" "gzip" "rsync" "curl" "jq")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    # Check for cron
    if [[ "$OS" != "macos" ]]; then
        if ! systemctl is-active --quiet cron && ! systemctl is-active --quiet crond; then
            missing_deps+=("cron")
        fi
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "Run with --skip-deps to continue anyway, or install missing dependencies"
        exit 1
    fi
    
    print_status "SUCCESS" "All dependencies verified"
}

# Function to backup existing installation
backup_existing_installation() {
    if [[ "$BACKUP_EXISTING" == "false" ]]; then
        return
    fi
    
    local backup_timestamp
    backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="/tmp/dgmstt-backup-system-backup-${backup_timestamp}.tar.gz"
    
    print_status "STEP" "Backing up existing installation..."
    
    local backup_paths=()
    [[ -d "$INSTALL_DIR" ]] && backup_paths+=("$INSTALL_DIR")
    [[ -d "$CONFIG_DIR" ]] && backup_paths+=("$CONFIG_DIR")
    [[ -d "$LOG_DIR" ]] && backup_paths+=("$LOG_DIR")
    [[ -f "/etc/logrotate.d/dgmstt-backup" ]] && backup_paths+=("/etc/logrotate.d/dgmstt-backup")
    
    if [[ ${#backup_paths[@]} -gt 0 ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_status "INFO" "Would backup: ${backup_paths[*]} to $backup_file"
            return
        fi
        
        tar -czf "$backup_file" "${backup_paths[@]}" 2>/dev/null || true
        print_status "SUCCESS" "Existing installation backed up to: $backup_file"
    else
        print_status "INFO" "No existing installation found to backup"
    fi
}

# Function to create directory structure
create_directories() {
    print_status "STEP" "Creating directory structure..."
    
    local dirs=(
        "$INSTALL_DIR"
        "$INSTALL_DIR/scripts"
        "$INSTALL_DIR/config"
        "$INSTALL_DIR/logs"
        "$CONFIG_DIR"
        "$LOG_DIR"
        "$BACKUP_DIR"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ "$DRY_RUN" == "true" ]]; then
            print_status "INFO" "Would create directory: $dir"
            continue
        fi
        
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            print_status "INFO" "Created directory: $dir"
        else
            print_status "INFO" "Directory already exists: $dir"
        fi
    done
    
    print_status "SUCCESS" "Directory structure created"
}

# Function to set permissions
set_permissions() {
    print_status "STEP" "Setting permissions..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "Would set permissions on backup system directories"
        return
    fi
    
    # Set ownership
    chown -R root:root "$INSTALL_DIR"
    chown -R root:root "$CONFIG_DIR"
    chown -R root:root "$LOG_DIR"
    
    # Set directory permissions
    chmod 755 "$INSTALL_DIR"
    chmod 755 "$CONFIG_DIR"
    chmod 755 "$LOG_DIR"
    chmod 700 "$BACKUP_DIR"  # Restrict access to backups
    
    # Set script permissions (will be set when scripts are created)
    if [[ -d "$INSTALL_DIR/scripts" ]]; then
        chmod 755 "$INSTALL_DIR/scripts"
    fi
    
    print_status "SUCCESS" "Permissions set successfully"
}

# Function to create backup script
create_backup_script() {
    print_status "STEP" "Creating backup script..."
    
    local script_file="$INSTALL_DIR/scripts/backup.sh"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "Would create backup script: $script_file"
        return
    fi
    
    cat > "$script_file" << 'EOF'
#!/bin/bash

# DGMSTT Backup Script
# Automated backup with compression, verification, and cleanup
# Version: 2.0.0

set -euo pipefail

# Default configuration
CONFIG_FILE="/etc/dgmstt-backup/backup.conf"
LOG_FILE="/var/log/dgmstt-backup/backup.log"
LOCK_FILE="/var/run/dgmstt-backup.lock"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: Configuration file not found: $CONFIG_FILE"
    exit 1
fi

# Default values if not set in config
SOURCE_DIR=${SOURCE_DIR:-"/opt/dgmstt"}
BACKUP_DIR=${BACKUP_DIR:-"/opt/dgmstt-backup/backups"}
RETENTION_DAYS=${RETENTION_DAYS:-30}
COMPRESSION_LEVEL=${COMPRESSION_LEVEL:-6}
LOG_LEVEL=${LOG_LEVEL:-"INFO"}
VERIFY_BACKUPS=${VERIFY_BACKUPS:-true}

# Function to log messages
log_message() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "$level" == "ERROR" ]] || [[ "${VERBOSE:-false}" == "true" ]]; then
        echo "[$level] $message" >&2
    fi
}

# Function to create lock file
create_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_message "ERROR" "Backup already running (PID: $lock_pid)"
            exit 1
        else
            log_message "WARNING" "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE"' EXIT
}

# Function to perform backup
perform_backup() {
    local backup_name="dgmstt-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    local backup_path="$BACKUP_DIR/$backup_name"
    local start_time=$(date +%s)
    
    log_message "INFO" "Starting backup: $backup_name"
    log_message "INFO" "Source: $SOURCE_DIR"
    log_message "INFO" "Destination: $backup_path"
    
    # Check if source directory exists
    if [[ ! -d "$SOURCE_DIR" ]]; then
        log_message "ERROR" "Source directory does not exist: $SOURCE_DIR"
        exit 1
    fi
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    
    # Build tar command with exclusions
    local tar_cmd="tar"
    local tar_options="-czf"
    
    # Add compression level
    if command -v pigz >/dev/null 2>&1; then
        tar_options="--use-compress-program=pigz -$COMPRESSION_LEVEL -cf"
    else
        tar_options="-czf"
        export GZIP="-$COMPRESSION_LEVEL"
    fi
    
    # Add exclusions if defined
    local exclude_args=()
    if [[ -n "${EXCLUDE_PATTERNS:-}" ]]; then
        for pattern in "${EXCLUDE_PATTERNS[@]}"; do
            exclude_args+=("--exclude=$pattern")
        done
    fi
    
    # Perform backup
    if $tar_cmd $tar_options "$backup_path" "${exclude_args[@]}" -C "$(dirname "$SOURCE_DIR")" "$(basename "$SOURCE_DIR")"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        local backup_size=$(stat -c%s "$backup_path" 2>/dev/null || echo "0")
        local file_count=$(tar -tzf "$backup_path" | wc -l)
        
        log_message "SUCCESS" "Backup completed successfully"
        log_message "INFO" "Duration: ${duration}s"
        log_message "INFO" "Size: $backup_size bytes"
        log_message "INFO" "Files: $file_count"
        
        # Verify backup if enabled
        if [[ "$VERIFY_BACKUPS" == "true" ]]; then
            verify_backup "$backup_path"
        fi
        
        # Cleanup old backups
        cleanup_old_backups
        
        # Send notification if configured
        send_notification "SUCCESS" "Backup completed: $backup_name"
        
    else
        log_message "ERROR" "Backup failed"
        send_notification "ERROR" "Backup failed: $backup_name"
        exit 1
    fi
}

# Function to verify backup
verify_backup() {
    local backup_file=$1
    
    log_message "INFO" "Verifying backup: $(basename "$backup_file")"
    
    if tar -tzf "$backup_file" >/dev/null 2>&1; then
        log_message "SUCCESS" "Backup verification passed"
        return 0
    else
        log_message "ERROR" "Backup verification failed"
        return 1
    fi
}

# Function to cleanup old backups
cleanup_old_backups() {
    log_message "INFO" "Cleaning up backups older than $RETENTION_DAYS days"
    
    local deleted_count=0
    while IFS= read -r -d '' backup_file; do
        rm -f "$backup_file"
        deleted_count=$((deleted_count + 1))
        log_message "INFO" "Deleted old backup: $(basename "$backup_file")"
    done < <(find "$BACKUP_DIR" -name "dgmstt-backup-*.tar.gz" -type f -mtime +$RETENTION_DAYS -print0 2>/dev/null)
    
    if [[ $deleted_count -gt 0 ]]; then
        log_message "INFO" "Deleted $deleted_count old backup(s)"
    else
        log_message "INFO" "No old backups to delete"
    fi
}

# Function to send notifications
send_notification() {
    local status=$1
    local message=$2
    
    if [[ "${ENABLE_EMAIL:-false}" == "true" ]] && [[ -n "${EMAIL_RECIPIENT:-}" ]]; then
        local subject="DGMSTT Backup $status"
        echo "$message" | mail -s "$subject" "$EMAIL_RECIPIENT" 2>/dev/null || true
    fi
    
    # Webhook notification if configured
    if [[ -n "${WEBHOOK_URL:-}" ]]; then
        curl -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "{\"status\":\"$status\",\"message\":\"$message\"}" \
            2>/dev/null || true
    fi
}

# Function to show status
show_status() {
    local latest_backup
    latest_backup=$(ls -t "$BACKUP_DIR"/dgmstt-backup-*.tar.gz 2>/dev/null | head -1 || echo "")
    
    if [[ -n "$latest_backup" ]]; then
        local backup_date
        backup_date=$(stat -c %Y "$latest_backup" 2>/dev/null || echo "0")
        local current_time=$(date +%s)
        local age_hours=$(( (current_time - backup_date) / 3600 ))
        local backup_size
        backup_size=$(stat -c%s "$latest_backup" 2>/dev/null || echo "0")
        
        echo "Latest backup: $(basename "$latest_backup")"
        echo "Age: ${age_hours} hours"
        echo "Size: $backup_size bytes"
        
        if [[ "${1:-}" == "--json" ]]; then
            cat << JSON
{
    "latest_backup": "$(basename "$latest_backup")",
    "last_backup_timestamp": $backup_date,
    "last_backup_age_hours": $age_hours,
    "latest_backup_size": $backup_size
}
JSON
        fi
    else
        echo "No backups found"
        if [[ "${1:-}" == "--json" ]]; then
            echo '{"error": "No backups found"}'
        fi
    fi
}

# Function to list backups
list_backups() {
    echo "Available backups:"
    ls -lh "$BACKUP_DIR"/dgmstt-backup-*.tar.gz 2>/dev/null || echo "No backups found"
}

# Function to restore backup
restore_backup() {
    local backup_file=${1:-}
    local restore_dir=${2:-"$SOURCE_DIR"}
    
    if [[ -z "$backup_file" ]]; then
        # Use latest backup
        backup_file=$(ls -t "$BACKUP_DIR"/dgmstt-backup-*.tar.gz 2>/dev/null | head -1)
        if [[ -z "$backup_file" ]]; then
            log_message "ERROR" "No backup file specified and no backups found"
            exit 1
        fi
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_message "ERROR" "Backup file not found: $backup_file"
        exit 1
    fi
    
    log_message "INFO" "Restoring backup: $(basename "$backup_file")"
    log_message "INFO" "Restore destination: $restore_dir"
    
    # Create restore directory
    mkdir -p "$restore_dir"
    
    # Extract backup
    if tar -xzf "$backup_file" -C "$restore_dir" --strip-components=1; then
        log_message "SUCCESS" "Backup restored successfully"
    else
        log_message "ERROR" "Backup restoration failed"
        exit 1
    fi
}

# Function to show help
show_help() {
    cat << EOF
DGMSTT Backup Script v2.0.0

Usage: $0 [OPTIONS]

OPTIONS:
    --help              Show this help
    --status            Show backup status
    --status --json     Show status in JSON format
    --list              List available backups
    --verify [FILE]     Verify backup (latest if no file specified)
    --restore [FILE]    Restore backup (latest if no file specified)
    --cleanup           Clean up old backups
    --dry-run           Show what would be done
    --verbose           Verbose output
    --quick             Quick backup (lower compression)
    --full              Full backup (ignore incremental settings)

EXAMPLES:
    $0                  # Run standard backup
    $0 --status         # Check backup status
    $0 --verify         # Verify latest backup
    $0 --restore        # Restore latest backup
    $0 --cleanup        # Clean up old backups

EOF
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_help
                exit 0
                ;;
            --status)
                show_status "$2"
                exit 0
                ;;
            --list)
                list_backups
                exit 0
                ;;
            --verify)
                if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                    verify_backup "$2"
                    shift
                else
                    latest_backup=$(ls -t "$BACKUP_DIR"/dgmstt-backup-*.tar.gz 2>/dev/null | head -1)
                    if [[ -n "$latest_backup" ]]; then
                        verify_backup "$latest_backup"
                    else
                        echo "No backups found to verify"
                        exit 1
                    fi
                fi
                exit $?
                ;;
            --restore)
                if [[ -n "${2:-}" ]] && [[ ! "$2" =~ ^-- ]]; then
                    restore_backup "$2"
                    shift
                else
                    restore_backup
                fi
                exit $?
                ;;
            --cleanup)
                cleanup_old_backups
                exit 0
                ;;
            --dry-run)
                echo "DRY RUN: Would perform backup operations"
                exit 0
                ;;
            --verbose)
                VERBOSE=true
                ;;
            --quick)
                COMPRESSION_LEVEL=1
                ;;
            --full)
                # Full backup mode
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
        shift
    done
    
    # Create lock and perform backup
    create_lock
    perform_backup
}

# Run main function
main "$@"
EOF
    
    chmod +x "$script_file"
    print_status "SUCCESS" "Backup script created: $script_file"
}

# Function to create configuration file
create_configuration() {
    print_status "STEP" "Creating configuration file..."
    
    local config_file="$CONFIG_DIR/backup.conf"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "Would create configuration: $config_file"
        return
    fi
    
    cat > "$config_file" << EOF
# DGMSTT Backup System Configuration
# Generated on $(date)

# Source directory to backup
SOURCE_DIR="$DEFAULT_SOURCE_DIR"

# Backup destination directory
BACKUP_DIR="$BACKUP_DIR"

# Backup retention (days)
RETENTION_DAYS=$DEFAULT_RETENTION_DAYS

# Compression level (1-9, 9 is highest)
COMPRESSION_LEVEL=$DEFAULT_COMPRESSION_LEVEL

# Maximum backup size (in MB, 0 = unlimited)
MAX_BACKUP_SIZE=0

# Email notifications
ENABLE_EMAIL=false
EMAIL_RECIPIENT="$DEFAULT_EMAIL"
SMTP_SERVER="localhost"

# Logging level (DEBUG, INFO, WARN, ERROR)
LOG_LEVEL="$DEFAULT_LOG_LEVEL"

# Exclude patterns (one per line)
EXCLUDE_PATTERNS=(
    "*.tmp"
    "*.log"
    "node_modules/*"
    ".git/*"
    "*.cache"
    "temp/*"
    ".DS_Store"
    "Thumbs.db"
)

# Include only specific file types (empty = all files)
INCLUDE_PATTERNS=(
    # Uncomment to restrict to specific file types
    # "*.ts"
    # "*.js"
    # "*.json"
    # "*.md"
    # "*.yml"
    # "*.yaml"
)

# Pre-backup commands
PRE_BACKUP_COMMANDS=(
    # "echo 'Starting backup preparation'"
    # "npm run build --if-present"
)

# Post-backup commands
POST_BACKUP_COMMANDS=(
    # "echo 'Backup completed'"
    # "curl -X POST https://healthchecks.io/ping/your-uuid"
)

# Backup verification
VERIFY_BACKUPS=true
VERIFY_SAMPLE_SIZE=10

# Performance settings
PARALLEL_COMPRESSION=true
CPU_LIMIT=80
IO_PRIORITY="best-effort"

# Webhook notifications
WEBHOOK_URL=""

# Advanced options
ENABLE_INCREMENTAL=false
INCREMENTAL_BASE_DIR="$INSTALL_DIR/incremental"
FULL_BACKUP_INTERVAL=7

# Encryption (requires GPG setup)
ENABLE_ENCRYPTION=false
GPG_RECIPIENT=""
GPG_KEYRING=""

# Cloud storage (requires additional setup)
ENABLE_S3_UPLOAD=false
S3_BUCKET=""
S3_REGION="us-west-2"
S3_STORAGE_CLASS="STANDARD_IA"

ENABLE_GCS_UPLOAD=false
GCS_BUCKET=""
GCS_STORAGE_CLASS="NEARLINE"
EOF
    
    chmod 644 "$config_file"
    print_status "SUCCESS" "Configuration file created: $config_file"
}

# Function to create logrotate configuration
create_logrotate_config() {
    print_status "STEP" "Creating logrotate configuration..."
    
    local logrotate_file="/etc/logrotate.d/dgmstt-backup"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "Would create logrotate config: $logrotate_file"
        return
    fi
    
    cat > "$logrotate_file" << EOF
$LOG_DIR/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 root root
    postrotate
        # Send HUP signal to rsyslog if running
        /bin/kill -HUP \$(cat /var/run/rsyslogd.pid 2> /dev/null) 2> /dev/null || true
    endscript
}
EOF
    
    chmod 644 "$logrotate_file"
    print_status "SUCCESS" "Logrotate configuration created: $logrotate_file"
}

# Function to setup cron job
setup_cron_job() {
    print_status "STEP" "Setting up cron job..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "Would add cron job for daily backups at 2 AM"
        return
    fi
    
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "dgmstt-backup"; then
        print_status "INFO" "Cron job already exists, skipping"
        return
    fi
    
    # Add cron job
    (crontab -l 2>/dev/null; echo "0 2 * * * $INSTALL_DIR/scripts/backup.sh >/dev/null 2>&1") | crontab -
    
    print_status "SUCCESS" "Cron job added for daily backups at 2 AM"
}

# Function to create health check script
create_health_check_script() {
    print_status "STEP" "Creating health check script..."
    
    local health_script="$INSTALL_DIR/scripts/health-check.sh"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "Would create health check script: $health_script"
        return
    fi
    
    cat > "$health_script" << 'EOF'
#!/bin/bash

# DGMSTT Backup System Health Check
# Returns 0 for OK, 1 for WARNING, 2 for CRITICAL

CONFIG_FILE="/etc/dgmstt-backup/backup.conf"
LOG_FILE="/var/log/dgmstt-backup/backup.log"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "CRITICAL: Configuration file not found"
    exit 2
fi

BACKUP_DIR=${BACKUP_DIR:-"/opt/dgmstt-backup/backups"}

# Check if backup directory exists
if [[ ! -d "$BACKUP_DIR" ]]; then
    echo "CRITICAL: Backup directory not found: $BACKUP_DIR"
    exit 2
fi

# Check latest backup age
latest_backup=$(ls -t "$BACKUP_DIR"/dgmstt-backup-*.tar.gz 2>/dev/null | head -1)

if [[ -z "$latest_backup" ]]; then
    echo "CRITICAL: No backups found"
    exit 2
fi

backup_age=$(( ($(date +%s) - $(stat -c %Y "$latest_backup")) / 3600 ))

if [[ $backup_age -gt 48 ]]; then
    echo "CRITICAL: Last backup is $backup_age hours old"
    exit 2
elif [[ $backup_age -gt 25 ]]; then
    echo "WARNING: Last backup is $backup_age hours old"
    exit 1
else
    echo "OK: Last backup is $backup_age hours old"
    exit 0
fi
EOF
    
    chmod +x "$health_script"
    print_status "SUCCESS" "Health check script created: $health_script"
}

# Function to run initial test
run_initial_test() {
    print_status "STEP" "Running initial test backup..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_status "INFO" "Would run test backup"
        return
    fi
    
    # Create a small test directory if source doesn't exist
    local test_source="$DEFAULT_SOURCE_DIR"
    local created_test_dir=false
    
    if [[ ! -d "$test_source" ]]; then
        print_status "INFO" "Source directory doesn't exist, creating test directory"
        mkdir -p "$test_source"
        echo "Test file for DGMSTT backup system" > "$test_source/test.txt"
        echo "Created: $(date)" >> "$test_source/test.txt"
        created_test_dir=true
    fi
    
    # Run test backup
    if "$INSTALL_DIR/scripts/backup.sh" --quick; then
        print_status "SUCCESS" "Initial test backup completed successfully"
        
        # Verify the test backup
        if "$INSTALL_DIR/scripts/backup.sh" --verify; then
            print_status "SUCCESS" "Test backup verification passed"
        else
            print_status "WARNING" "Test backup verification failed"
        fi
    else
        print_status "ERROR" "Initial test backup failed"
        
        # Clean up test directory if we created it
        if [[ "$created_test_dir" == "true" ]]; then
            rm -rf "$test_source"
        fi
        
        exit 1
    fi
    
    # Clean up test directory if we created it
    if [[ "$created_test_dir" == "true" ]]; then
        rm -rf "$test_source"
        print_status "INFO" "Cleaned up test directory"
    fi
}

# Function to show installation summary
show_installation_summary() {
    print_status "SUCCESS" "DGMSTT Backup System installation completed!"
    
    cat << EOF

=== Installation Summary ===
Installation Directory: $INSTALL_DIR
Configuration Directory: $CONFIG_DIR
Log Directory: $LOG_DIR
Backup Directory: $BACKUP_DIR

=== Key Files ===
Backup Script: $INSTALL_DIR/scripts/backup.sh
Configuration: $CONFIG_DIR/backup.conf
Health Check: $INSTALL_DIR/scripts/health-check.sh
Log File: $LOG_DIR/backup.log

=== Next Steps ===
1. Review and customize the configuration:
   sudo nano $CONFIG_DIR/backup.conf

2. Test the backup system:
   sudo $INSTALL_DIR/scripts/backup.sh --dry-run
   sudo $INSTALL_DIR/scripts/backup.sh

3. Check backup status:
   sudo $INSTALL_DIR/scripts/backup.sh --status

4. View logs:
   sudo tail -f $LOG_DIR/backup.log

5. Set up monitoring (optional):
   sudo $INSTALL_DIR/scripts/health-check.sh

=== Scheduled Backups ===
Daily backups are scheduled to run at 2:00 AM via cron.
To modify the schedule: sudo crontab -e

=== Documentation ===
Full documentation: BACKUP_SYSTEM_README.md
Support: https://github.com/your-repo/dgmstt/issues

EOF
}

# Function to handle upgrade mode
handle_upgrade() {
    print_status "INFO" "Running in upgrade mode"
    
    # Check if installation exists
    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_status "ERROR" "No existing installation found to upgrade"
        exit 1
    fi
    
    # Backup existing installation
    backup_existing_installation
    
    # Continue with normal installation
    FORCE_INSTALL=true
}

# Function to parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help)
                show_usage
                exit 0
                ;;
            --version)
                show_version
                exit 0
                ;;
            --force)
                FORCE_INSTALL=true
                ;;
            --upgrade)
                UPGRADE_MODE=true
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            --quiet)
                QUIET_MODE=true
                ;;
            --skip-deps)
                SKIP_DEPS=true
                ;;
            --no-backup)
                BACKUP_EXISTING=false
                ;;
            --source-dir=*)
                DEFAULT_SOURCE_DIR="${1#*=}"
                ;;
            --backup-dir=*)
                BACKUP_DIR="${1#*=}"
                ;;
            --retention=*)
                DEFAULT_RETENTION_DAYS="${1#*=}"
                ;;
            --compression=*)
                DEFAULT_COMPRESSION_LEVEL="${1#*=}"
                ;;
            --email=*)
                DEFAULT_EMAIL="${1#*=}"
                ;;
            --log-level=*)
                DEFAULT_LOG_LEVEL="${1#*=}"
                ;;
            *)
                print_status "ERROR" "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
}

# Function to validate arguments
validate_arguments() {
    # Validate compression level
    if [[ ! "$DEFAULT_COMPRESSION_LEVEL" =~ ^[1-9]$ ]]; then
        print_status "ERROR" "Invalid compression level: $DEFAULT_COMPRESSION_LEVEL (must be 1-9)"
        exit 1
    fi
    
    # Validate retention days
    if [[ ! "$DEFAULT_RETENTION_DAYS" =~ ^[0-9]+$ ]] || [[ "$DEFAULT_RETENTION_DAYS" -lt 1 ]]; then
        print_status "ERROR" "Invalid retention days: $DEFAULT_RETENTION_DAYS (must be positive integer)"
        exit 1
    fi
    
    # Validate log level
    case "$DEFAULT_LOG_LEVEL" in
        DEBUG|INFO|WARN|ERROR) ;;
        *)
            print_status "ERROR" "Invalid log level: $DEFAULT_LOG_LEVEL (must be DEBUG, INFO, WARN, or ERROR)"
            exit 1
            ;;
    esac
    
    # Validate email format if provided
    if [[ -n "$DEFAULT_EMAIL" ]] && [[ ! "$DEFAULT_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        print_status "ERROR" "Invalid email format: $DEFAULT_EMAIL"
        exit 1
    fi
}

# Function to check for existing installation
check_existing_installation() {
    if [[ -d "$INSTALL_DIR" ]] && [[ "$FORCE_INSTALL" != "true" ]] && [[ "$UPGRADE_MODE" != "true" ]]; then
        print_status "ERROR" "Installation already exists at $INSTALL_DIR"
        print_status "INFO" "Use --force to overwrite or --upgrade to upgrade existing installation"
        exit 1
    fi
}

# Main installation function
main() {
    print_status "INFO" "Starting DGMSTT Backup System installation..."
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Validate arguments
    validate_arguments
    
    # Handle upgrade mode
    if [[ "$UPGRADE_MODE" == "true" ]]; then
        handle_upgrade
    fi
    
    # Check for existing installation
    check_existing_installation
    
    # Detect operating system
    detect_os
    
    # Check if running as root
    check_root
    
    # Check system requirements
    check_requirements
    
    # Install dependencies
    install_dependencies
    
    # Verify dependencies
    verify_dependencies
    
    # Backup existing installation
    backup_existing_installation
    
    # Create directory structure
    create_directories
    
    # Set permissions
    set_permissions
    
    # Create backup script
    create_backup_script
    
    # Create configuration file
    create_configuration
    
    # Create logrotate configuration
    create_logrotate_config
    
    # Setup cron job
    setup_cron_job
    
    # Create health check script
    create_health_check_script
    
    # Run initial test
    if [[ "$DRY_RUN" != "true" ]]; then
        run_initial_test
    fi
    
    # Show installation summary
    show_installation_summary
    
    print_status "SUCCESS" "Installation completed successfully!"
}

# Run main function with all arguments
main "$@"