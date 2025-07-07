#!/bin/bash

# backup.sh - Example backup script for DGMSTT project
# This script demonstrates the backup functionality that can be scheduled with install-backup-cron.sh

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIR="$SCRIPT_DIR"
readonly BACKUP_BASE_DIR="${HOME}/backups/dgmstt"
readonly TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
readonly BACKUP_DIR="${BACKUP_BASE_DIR}/${TIMESTAMP}"
readonly LOG_FILE="${HOME}/.backup-logs/backup-output.log"

# Colors for output
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    
    case "$level" in
        INFO)
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
    
    # Also log to file if possible
    echo "$timestamp [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
}

# Create backup directory
create_backup_dir() {
    log INFO "Creating backup directory: $BACKUP_DIR"
    
    if ! mkdir -p "$BACKUP_DIR"; then
        log ERROR "Failed to create backup directory: $BACKUP_DIR"
        return 1
    fi
    
    return 0
}

# Backup function for important files
backup_files() {
    log INFO "Backing up important project files..."
    
    local files_to_backup=(
        "package.json"
        "tsconfig.json"
        "README.md"
        "docker-compose.yml"
        "Makefile"
        ".env.example"
        "src/"
        "packages/"
        "docs/"
        "scripts/"
        "shared/"
        "protocol/"
    )
    
    local backup_count=0
    
    for item in "${files_to_backup[@]}"; do
        local source_path="$PROJECT_DIR/$item"
        
        if [[ -e "$source_path" ]]; then
            log INFO "Backing up: $item"
            
            if [[ -d "$source_path" ]]; then
                # Directory backup
                if cp -r "$source_path" "$BACKUP_DIR/"; then
                    ((backup_count++))
                else
                    log WARN "Failed to backup directory: $item"
                fi
            else
                # File backup
                if cp "$source_path" "$BACKUP_DIR/"; then
                    ((backup_count++))
                else
                    log WARN "Failed to backup file: $item"
                fi
            fi
        else
            log WARN "Item not found, skipping: $item"
        fi
    done
    
    log INFO "Backed up $backup_count items"
    return 0
}

# Backup git information
backup_git_info() {
    log INFO "Backing up git information..."
    
    cd "$PROJECT_DIR"
    
    # Save current branch and commit
    {
        echo "Git Backup Information"
        echo "======================"
        echo "Date: $(date)"
        echo "Branch: $(git branch --show-current 2>/dev/null || echo 'unknown')"
        echo "Commit: $(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
        echo "Status:"
        git status --porcelain 2>/dev/null || echo "Git status unavailable"
        echo
        echo "Recent commits:"
        git log --oneline -10 2>/dev/null || echo "Git log unavailable"
    } > "$BACKUP_DIR/git-info.txt"
    
    # Save git config
    if [[ -f ".git/config" ]]; then
        cp ".git/config" "$BACKUP_DIR/git-config.txt" 2>/dev/null || true
    fi
    
    log INFO "Git information saved"
    return 0
}

# Create backup manifest
create_manifest() {
    log INFO "Creating backup manifest..."
    
    {
        echo "DGMSTT Backup Manifest"
        echo "======================"
        echo "Backup Date: $(date)"
        echo "Backup Directory: $BACKUP_DIR"
        echo "Source Directory: $PROJECT_DIR"
        echo "Backup Size: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo 'unknown')"
        echo
        echo "Contents:"
        find "$BACKUP_DIR" -type f -exec basename {} \; | sort
        echo
        echo "Directory Structure:"
        tree "$BACKUP_DIR" 2>/dev/null || find "$BACKUP_DIR" -type d | sort
    } > "$BACKUP_DIR/MANIFEST.txt"
    
    log INFO "Backup manifest created"
    return 0
}

# Cleanup old backups (keep last 7 days)
cleanup_old_backups() {
    log INFO "Cleaning up old backups..."
    
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        log INFO "No backup directory found, skipping cleanup"
        return 0
    fi
    
    local cleanup_count=0
    
    # Find and remove backups older than 7 days
    while IFS= read -r -d '' backup_dir; do
        local dir_name="$(basename "$backup_dir")"
        
        # Extract date from directory name (format: YYYYMMDD_HHMMSS)
        if [[ "$dir_name" =~ ^([0-9]{8})_[0-9]{6}$ ]]; then
            local backup_date="${BASH_REMATCH[1]}"
            local backup_timestamp="$(date -d "$backup_date" +%s 2>/dev/null || echo 0)"
            local current_timestamp="$(date +%s)"
            local age_days=$(( (current_timestamp - backup_timestamp) / 86400 ))
            
            if [[ $age_days -gt 7 ]]; then
                log INFO "Removing old backup: $dir_name (${age_days} days old)"
                if rm -rf "$backup_dir"; then
                    ((cleanup_count++))
                else
                    log WARN "Failed to remove old backup: $backup_dir"
                fi
            fi
        fi
    done < <(find "$BACKUP_BASE_DIR" -maxdepth 1 -type d -name "*_*" -print0 2>/dev/null)
    
    log INFO "Cleaned up $cleanup_count old backups"
    return 0
}

# Main backup function
main() {
    log INFO "Starting DGMSTT backup process..."
    log INFO "Timestamp: $TIMESTAMP"
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    # Create backup directory
    if ! create_backup_dir; then
        log ERROR "Backup failed: Cannot create backup directory"
        exit 1
    fi
    
    # Perform backup operations
    local errors=0
    
    if ! backup_files; then
        log ERROR "File backup failed"
        ((errors++))
    fi
    
    if ! backup_git_info; then
        log WARN "Git backup failed (non-critical)"
    fi
    
    if ! create_manifest; then
        log WARN "Manifest creation failed (non-critical)"
    fi
    
    if ! cleanup_old_backups; then
        log WARN "Cleanup failed (non-critical)"
    fi
    
    # Final status
    if [[ $errors -eq 0 ]]; then
        log INFO "Backup completed successfully"
        log INFO "Backup location: $BACKUP_DIR"
        log INFO "Backup size: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo 'unknown')"
        exit 0
    else
        log ERROR "Backup completed with $errors error(s)"
        exit 1
    fi
}

# Run main function
main "$@"