#!/bin/bash

# Qdrant Cron Setup Script
# Database Administrator: Automated Backup Scheduling
# Created: $(date '+%Y-%m-%d')
# Purpose: Configure cron jobs for automated Qdrant backups

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SCRIPT="${SCRIPT_DIR}/qdrant-backup.sh"
VERIFY_SCRIPT="${SCRIPT_DIR}/qdrant-verify.sh"
CRON_USER="${USER}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }

# Check if scripts exist
check_scripts() {
    log_info "Checking backup scripts..."
    
    if [ ! -f "$BACKUP_SCRIPT" ]; then
        log_error "Backup script not found: $BACKUP_SCRIPT"
        exit 1
    fi
    
    if [ ! -x "$BACKUP_SCRIPT" ]; then
        log_error "Backup script is not executable: $BACKUP_SCRIPT"
        exit 1
    fi
    
    if [ ! -f "$VERIFY_SCRIPT" ]; then
        log_error "Verify script not found: $VERIFY_SCRIPT"
        exit 1
    fi
    
    if [ ! -x "$VERIFY_SCRIPT" ]; then
        log_error "Verify script is not executable: $VERIFY_SCRIPT"
        exit 1
    fi
    
    log_success "All scripts found and executable"
}

# Generate cron entries
generate_cron_entries() {
    cat << EOF
# Qdrant Backup Automation
# Generated on $(date '+%Y-%m-%d %H:%M:%S')

# Daily backup at 2:00 AM
0 2 * * * ${BACKUP_SCRIPT} >> ${HOME}/backups/logs/qdrant-backup-cron.log 2>&1

# Weekly verification on Sundays at 3:00 AM
0 3 * * 0 ${VERIFY_SCRIPT} >> ${HOME}/backups/logs/qdrant-verify-cron.log 2>&1

# Monthly full verification on 1st of month at 4:00 AM
0 4 1 * * ${VERIFY_SCRIPT} --no-connectivity >> ${HOME}/backups/logs/qdrant-verify-monthly.log 2>&1

EOF
}

# Install cron jobs
install_cron() {
    log_info "Installing cron jobs for user: $CRON_USER"
    
    # Create temporary file with new cron entries
    local temp_cron=$(mktemp)
    
    # Get existing crontab (if any)
    if crontab -l > /dev/null 2>&1; then
        crontab -l > "$temp_cron"
        
        # Remove any existing Qdrant backup entries
        sed -i '/# Qdrant Backup Automation/,/^$/d' "$temp_cron"
    fi
    
    # Add new entries
    echo "" >> "$temp_cron"
    generate_cron_entries >> "$temp_cron"
    
    # Install new crontab
    if crontab "$temp_cron"; then
        log_success "Cron jobs installed successfully"
    else
        log_error "Failed to install cron jobs"
        rm -f "$temp_cron"
        exit 1
    fi
    
    # Clean up
    rm -f "$temp_cron"
    
    # Show installed cron jobs
    log_info "Current crontab for $CRON_USER:"
    crontab -l | grep -A 10 "Qdrant Backup" || log_warn "No Qdrant backup entries found in crontab"
}

# Remove cron jobs
remove_cron() {
    log_info "Removing Qdrant backup cron jobs..."
    
    if ! crontab -l > /dev/null 2>&1; then
        log_warn "No crontab found for user $CRON_USER"
        return 0
    fi
    
    # Create temporary file
    local temp_cron=$(mktemp)
    
    # Get existing crontab and remove Qdrant entries
    crontab -l > "$temp_cron"
    sed -i '/# Qdrant Backup Automation/,/^$/d' "$temp_cron"
    
    # Install modified crontab
    if crontab "$temp_cron"; then
        log_success "Qdrant backup cron jobs removed"
    else
        log_error "Failed to remove cron jobs"
        rm -f "$temp_cron"
        exit 1
    fi
    
    # Clean up
    rm -f "$temp_cron"
}

# Show current cron status
show_status() {
    log_info "Cron job status for user: $CRON_USER"
    
    if ! crontab -l > /dev/null 2>&1; then
        log_warn "No crontab found"
        return 0
    fi
    
    echo ""
    echo "Current crontab:"
    crontab -l
    
    echo ""
    log_info "Qdrant backup related entries:"
    if crontab -l | grep -q "qdrant"; then
        crontab -l | grep "qdrant"
    else
        log_warn "No Qdrant backup entries found"
    fi
    
    # Check if cron service is running
    echo ""
    log_info "Cron service status:"
    if systemctl is-active --quiet cron 2>/dev/null || systemctl is-active --quiet crond 2>/dev/null; then
        log_success "Cron service is running"
    else
        log_warn "Cron service may not be running"
        echo "To start cron service:"
        echo "  sudo systemctl start cron    # On Debian/Ubuntu"
        echo "  sudo systemctl start crond   # On RHEL/CentOS"
    fi
}

# Test backup script
test_backup() {
    log_info "Testing backup script..."
    
    if [ ! -f "$BACKUP_SCRIPT" ]; then
        log_error "Backup script not found: $BACKUP_SCRIPT"
        exit 1
    fi
    
    log_info "Running backup script in dry-run mode..."
    if "$BACKUP_SCRIPT" --dry-run; then
        log_success "Backup script test passed"
    else
        log_error "Backup script test failed"
        exit 1
    fi
}

# Create systemd timer (alternative to cron)
create_systemd_timer() {
    log_info "Creating systemd timer as alternative to cron..."
    
    local service_file="/etc/systemd/system/qdrant-backup.service"
    local timer_file="/etc/systemd/system/qdrant-backup.timer"
    
    # Check if we have sudo access
    if ! sudo -n true 2>/dev/null; then
        log_error "Sudo access required to create systemd timer"
        exit 1
    fi
    
    # Create service file
    sudo tee "$service_file" > /dev/null << EOF
[Unit]
Description=Qdrant Database Backup
After=network.target

[Service]
Type=oneshot
User=${USER}
ExecStart=${BACKUP_SCRIPT}
StandardOutput=append:${HOME}/backups/logs/qdrant-backup-systemd.log
StandardError=append:${HOME}/backups/logs/qdrant-backup-systemd.log

[Install]
WantedBy=multi-user.target
EOF

    # Create timer file
    sudo tee "$timer_file" > /dev/null << EOF
[Unit]
Description=Run Qdrant backup daily
Requires=qdrant-backup.service

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=300

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable timer
    sudo systemctl daemon-reload
    sudo systemctl enable qdrant-backup.timer
    sudo systemctl start qdrant-backup.timer
    
    log_success "Systemd timer created and started"
    
    # Show timer status
    sudo systemctl status qdrant-backup.timer --no-pager
}

# Main function
main() {
    local action="install"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            install|add)
                action="install"
                shift
                ;;
            remove|delete)
                action="remove"
                shift
                ;;
            status|show)
                action="status"
                shift
                ;;
            test)
                action="test"
                shift
                ;;
            systemd)
                action="systemd"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    # Check scripts first
    check_scripts
    
    # Execute action
    case $action in
        install)
            install_cron
            ;;
        remove)
            remove_cron
            ;;
        status)
            show_status
            ;;
        test)
            test_backup
            ;;
        systemd)
            create_systemd_timer
            ;;
        *)
            log_error "Unknown action: $action"
            usage
            exit 1
            ;;
    esac
}

# Script usage
usage() {
    echo "Usage: $0 [ACTION]"
    echo ""
    echo "Configure automated Qdrant backup scheduling"
    echo ""
    echo "Actions:"
    echo "  install, add      Install cron jobs (default)"
    echo "  remove, delete    Remove cron jobs"
    echo "  status, show      Show current cron status"
    echo "  test             Test backup script"
    echo "  systemd          Create systemd timer (alternative to cron)"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "Scheduled jobs:"
    echo "  Daily backup:     2:00 AM"
    echo "  Weekly verify:    Sunday 3:00 AM"
    echo "  Monthly verify:   1st of month 4:00 AM"
    echo ""
    echo "Log files:"
    echo "  ~/backups/logs/qdrant-backup-cron.log"
    echo "  ~/backups/logs/qdrant-verify-cron.log"
    echo "  ~/backups/logs/qdrant-verify-monthly.log"
    echo ""
    echo "Examples:"
    echo "  $0 install       # Install cron jobs"
    echo "  $0 status        # Show current status"
    echo "  $0 test          # Test backup script"
    echo "  $0 remove        # Remove cron jobs"
}

# Run main function
main "$@"