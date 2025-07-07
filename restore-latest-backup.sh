#!/bin/bash

# DGMSTT Latest Backup Restoration Script
# Restores the most recent backup of all system components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_BASE_DIR="${HOME}/backups"
QDRANT_BACKUP_DIR="${BACKUP_BASE_DIR}/qdrant"
SESSION_BACKUP_DIR="${BACKUP_BASE_DIR}/sessions"
SYSTEM_BACKUP_DIR="${BACKUP_BASE_DIR}/system"
LOG_FILE="/tmp/restore-$(date +%Y%m%d-%H%M%S).log"

# Flags
FORCE_RESTORE=false
DRY_RUN=false
BACKUP_CURRENT=true
RESTORE_QDRANT=true
RESTORE_SESSIONS=true
RESTORE_CONFIG=true

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_success() { log "SUCCESS" "$@"; }

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

echo -e "${BLUE}=== DGMSTT Latest Backup Restoration ===${NC}"
echo "Log file: $LOG_FILE"
echo ""

# Initialize log
echo "DGMSTT Backup Restoration - $(date)" > "$LOG_FILE"

# Function to find latest backup
find_latest_backup() {
    local backup_dir="$1"
    local pattern="$2"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_warn "Backup directory not found: $backup_dir"
        return 1
    fi
    
    local latest_backup
    latest_backup=$(find "$backup_dir" -name "$pattern" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [[ -n "$latest_backup" && -f "$latest_backup" ]]; then
        echo "$latest_backup"
        return 0
    else
        log_warn "No backup found matching pattern: $pattern in $backup_dir"
        return 1
    fi
}

# Function to backup current state
backup_current_state() {
    if ! $BACKUP_CURRENT; then
        log_info "Skipping current state backup (--no-backup specified)"
        return 0
    fi
    
    log_info "Creating backup of current state before restoration..."
    local backup_timestamp=$(date +%Y%m%d-%H%M%S)
    local current_backup_dir="${BACKUP_BASE_DIR}/pre-restore-${backup_timestamp}"
    
    mkdir -p "$current_backup_dir"
    
    # Backup current Qdrant data
    if docker-compose ps qdrant | grep -q "Up"; then
        log_info "Backing up current Qdrant state..."
        ./qdrant-backup.sh --output "$current_backup_dir/qdrant" || log_warn "Qdrant backup failed"
    fi
    
    # Backup current session data
    local session_dir="$HOME/.local/share/opencode/project/storage/session"
    if [[ -d "$session_dir" ]]; then
        log_info "Backing up current session data..."
        tar -czf "$current_backup_dir/sessions-current.tar.gz" -C "$(dirname "$session_dir")" "$(basename "$session_dir")" || log_warn "Session backup failed"
    fi
    
    # Backup current configuration
    if [[ -f ".env" ]]; then
        cp ".env" "$current_backup_dir/env-current" || log_warn "Environment backup failed"
    fi
    
    log_success "Current state backed up to: $current_backup_dir"
}

# Function to stop services safely
stop_services() {
    log_info "Stopping services for restoration..."
    
    if $DRY_RUN; then
        log_info "DRY RUN: Would stop docker-compose services"
        return 0
    fi
    
    # Stop application services first
    docker-compose stop opencode dgm || log_warn "Failed to stop application services"
    
    # Stop data services
    docker-compose stop qdrant || log_warn "Failed to stop Qdrant"
    
    log_success "Services stopped"
}

# Function to start services
start_services() {
    log_info "Starting services after restoration..."
    
    if $DRY_RUN; then
        log_info "DRY RUN: Would start docker-compose services"
        return 0
    fi
    
    # Start data services first
    docker-compose up -d redis postgres || error_exit "Failed to start core services"
    sleep 5
    
    docker-compose up -d qdrant || error_exit "Failed to start Qdrant"
    sleep 10
    
    # Start application services
    docker-compose up -d dgm opencode || error_exit "Failed to start application services"
    
    # Start reverse proxy
    docker-compose up -d nginx || log_warn "Failed to start nginx"
    
    log_success "Services started"
}

# Function to restore Qdrant backup
restore_qdrant() {
    if ! $RESTORE_QDRANT; then
        log_info "Skipping Qdrant restoration"
        return 0
    fi
    
    log_info "Restoring Qdrant from latest backup..."
    
    # Find latest Qdrant backup
    local latest_qdrant_backup
    if ! latest_qdrant_backup=$(find_latest_backup "$QDRANT_BACKUP_DIR" "*.snapshot"); then
        log_warn "No Qdrant backup found, skipping Qdrant restoration"
        return 0
    fi
    
    log_info "Latest Qdrant backup: $latest_qdrant_backup"
    
    if $DRY_RUN; then
        log_info "DRY RUN: Would restore Qdrant from $latest_qdrant_backup"
        return 0
    fi
    
    # Extract collection name from backup filename
    local backup_filename=$(basename "$latest_qdrant_backup")
    local collection_name=$(echo "$backup_filename" | sed 's/_[0-9-]*\.snapshot$//')
    
    log_info "Restoring collection: $collection_name"
    
    # Upload snapshot to Qdrant
    if curl -X POST "http://localhost:6333/collections/${collection_name}/snapshots/upload" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${latest_qdrant_backup}" > /dev/null 2>&1; then
        log_success "Qdrant backup restored successfully"
    else
        log_error "Failed to restore Qdrant backup"
        return 1
    fi
}

# Function to restore session data
restore_sessions() {
    if ! $RESTORE_SESSIONS; then
        log_info "Skipping session restoration"
        return 0
    fi
    
    log_info "Restoring sessions from latest backup..."
    
    # Find latest session backup
    local latest_session_backup
    if ! latest_session_backup=$(find_latest_backup "$SESSION_BACKUP_DIR" "sessions-*.tar.gz"); then
        log_warn "No session backup found, running consolidation instead"
        
        if $DRY_RUN; then
            log_info "DRY RUN: Would run session consolidation"
        else
            ./consolidate-sessions.sh || log_warn "Session consolidation failed"
        fi
        return 0
    fi
    
    log_info "Latest session backup: $latest_session_backup"
    
    if $DRY_RUN; then
        log_info "DRY RUN: Would restore sessions from $latest_session_backup"
        return 0
    fi
    
    # Extract session backup
    local session_dir="$HOME/.local/share/opencode/project/storage/session"
    local session_parent=$(dirname "$session_dir")
    
    # Create backup directory if it doesn't exist
    mkdir -p "$session_parent"
    
    # Extract backup
    if tar -xzf "$latest_session_backup" -C "$session_parent"; then
        log_success "Session backup restored successfully"
    else
        log_error "Failed to restore session backup"
        return 1
    fi
}

# Function to restore configuration
restore_configuration() {
    if ! $RESTORE_CONFIG; then
        log_info "Skipping configuration restoration"
        return 0
    fi
    
    log_info "Restoring configuration from latest backup..."
    
    # Find latest config backup
    local latest_config_backup
    if ! latest_config_backup=$(find_latest_backup "$SYSTEM_BACKUP_DIR" "env-*"); then
        log_warn "No configuration backup found, using .env.example"
        
        if $DRY_RUN; then
            log_info "DRY RUN: Would copy .env.example to .env"
        else
            if [[ -f ".env.example" ]]; then
                cp ".env.example" ".env"
                log_info "Copied .env.example to .env"
            else
                log_warn "No .env.example found"
            fi
        fi
        return 0
    fi
    
    log_info "Latest configuration backup: $latest_config_backup"
    
    if $DRY_RUN; then
        log_info "DRY RUN: Would restore configuration from $latest_config_backup"
        return 0
    fi
    
    # Restore configuration
    if cp "$latest_config_backup" ".env"; then
        log_success "Configuration restored successfully"
    else
        log_error "Failed to restore configuration"
        return 1
    fi
}

# Function to validate restoration
validate_restoration() {
    log_info "Validating restoration..."
    
    if $DRY_RUN; then
        log_info "DRY RUN: Would run validation checks"
        return 0
    fi
    
    # Wait for services to be ready
    sleep 30
    
    # Run health check
    if [[ -f "./validate-system-health.sh" ]]; then
        if ./validate-system-health.sh --quick; then
            log_success "System health validation passed"
        else
            log_error "System health validation failed"
            return 1
        fi
    else
        log_warn "Health check script not found, running basic checks"
        
        # Basic endpoint checks
        if curl -f http://localhost:3000/health > /dev/null 2>&1; then
            log_success "OpenCode service is responding"
        else
            log_error "OpenCode service is not responding"
        fi
        
        if curl -f http://localhost:8000/health > /dev/null 2>&1; then
            log_success "DGM service is responding"
        else
            log_error "DGM service is not responding"
        fi
        
        if curl -f http://localhost:6333/health > /dev/null 2>&1; then
            log_success "Qdrant service is responding"
        else
            log_error "Qdrant service is not responding"
        fi
    fi
}

# Main restoration function
main() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_info "Starting DGMSTT backup restoration..."
    
    # Pre-restoration checks
    if [[ ! -d "$BACKUP_BASE_DIR" ]]; then
        error_exit "Backup directory not found: $BACKUP_BASE_DIR"
    fi
    
    # Show what will be restored
    log_info "Restoration plan:"
    log_info "  Qdrant: $($RESTORE_QDRANT && echo "YES" || echo "NO")"
    log_info "  Sessions: $($RESTORE_SESSIONS && echo "YES" || echo "NO")"
    log_info "  Configuration: $($RESTORE_CONFIG && echo "YES" || echo "NO")"
    log_info "  Backup current state: $($BACKUP_CURRENT && echo "YES" || echo "NO")"
    log_info "  Force restore: $($FORCE_RESTORE && echo "YES" || echo "NO")"
    log_info "  Dry run: $($DRY_RUN && echo "YES" || echo "NO")"
    
    # Confirmation prompt (unless force mode)
    if ! $FORCE_RESTORE && ! $DRY_RUN; then
        echo -e "${YELLOW}This will restore from the latest backups and may overwrite current data.${NC}"
        read -p "Continue? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restoration cancelled by user"
            exit 0
        fi
    fi
    
    # Backup current state
    backup_current_state
    
    # Stop services
    stop_services
    
    # Perform restorations
    restore_configuration
    restore_qdrant
    restore_sessions
    
    # Start services
    start_services
    
    # Validate restoration
    validate_restoration
    
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_success "Restoration completed successfully!"
    log_info "Start time: $start_time"
    log_info "End time: $end_time"
    log_info "Log file: $LOG_FILE"
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Restore DGMSTT system from latest backups"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -f, --force             Force restoration without confirmation"
    echo "  -n, --dry-run           Show what would be done without executing"
    echo "  --no-backup             Skip backing up current state"
    echo "  --no-qdrant             Skip Qdrant restoration"
    echo "  --no-sessions           Skip session data restoration"
    echo "  --no-config             Skip configuration restoration"
    echo "  --qdrant-only           Restore only Qdrant data"
    echo "  --sessions-only         Restore only session data"
    echo "  --config-only           Restore only configuration"
    echo ""
    echo "Examples:"
    echo "  $0                      # Full restoration with confirmation"
    echo "  $0 --force              # Full restoration without confirmation"
    echo "  $0 --dry-run            # Show what would be restored"
    echo "  $0 --qdrant-only        # Restore only Qdrant data"
    echo "  $0 --no-backup --force  # Restore without backing up current state"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -f|--force)
            FORCE_RESTORE=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        --no-backup)
            BACKUP_CURRENT=false
            shift
            ;;
        --no-qdrant)
            RESTORE_QDRANT=false
            shift
            ;;
        --no-sessions)
            RESTORE_SESSIONS=false
            shift
            ;;
        --no-config)
            RESTORE_CONFIG=false
            shift
            ;;
        --qdrant-only)
            RESTORE_QDRANT=true
            RESTORE_SESSIONS=false
            RESTORE_CONFIG=false
            shift
            ;;
        --sessions-only)
            RESTORE_QDRANT=false
            RESTORE_SESSIONS=true
            RESTORE_CONFIG=false
            shift
            ;;
        --config-only)
            RESTORE_QDRANT=false
            RESTORE_SESSIONS=false
            RESTORE_CONFIG=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Ensure we're in the right directory
if [[ ! -f "docker-compose.yml" ]]; then
    error_exit "docker-compose.yml not found. Please run from the DGMSTT root directory."
fi

# Run main function
main