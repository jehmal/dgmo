#!/bin/bash

# Qdrant Snapshot Verification Utility
# Database Administrator: Vector Database Verification System
# Created: $(date '+%Y-%m-%d')
# Purpose: Comprehensive verification of Qdrant snapshots and backup integrity

set -euo pipefail

# Configuration
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
BACKUP_DIR="${HOME}/backups/qdrant"
LOG_DIR="${HOME}/backups/logs"
LOG_FILE="${LOG_DIR}/qdrant-verify.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Verification results
TOTAL_SNAPSHOTS=0
VALID_SNAPSHOTS=0
INVALID_SNAPSHOTS=0
CORRUPTED_SNAPSHOTS=0

# Verify single snapshot
verify_snapshot() {
    local snapshot_file="$1"
    local basename_snap=$(basename "$snapshot_file")
    
    log_info "Verifying: $basename_snap"
    
    # Check file exists
    if [ ! -f "$snapshot_file" ]; then
        log_error "File does not exist: $snapshot_file"
        return 1
    fi
    
    # Check file size
    local file_size=$(stat -f%z "$snapshot_file" 2>/dev/null || stat -c%s "$snapshot_file" 2>/dev/null)
    if [ "$file_size" -eq 0 ]; then
        log_error "File is empty: $basename_snap"
        CORRUPTED_SNAPSHOTS=$((CORRUPTED_SNAPSHOTS + 1))
        return 1
    fi
    
    # Check file type and basic structure
    local file_type=$(file "$snapshot_file" 2>/dev/null || echo "unknown")
    if ! echo "$file_type" | grep -q -E "(data|archive|compressed|binary)"; then
        log_warn "Suspicious file type for $basename_snap: $file_type"
    fi
    
    # Check filename format
    if [[ ! "$basename_snap" =~ ^[a-zA-Z0-9_-]+_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}\.snapshot$ ]]; then
        log_warn "Non-standard filename format: $basename_snap"
    fi
    
    # Extract collection name and verify it makes sense
    local collection_name=$(echo "$basename_snap" | sed 's/_[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}\.snapshot$//')
    if [ -z "$collection_name" ]; then
        log_error "Cannot extract collection name from: $basename_snap"
        return 1
    fi
    
    # Check file age
    local file_age_days=$(( ($(date +%s) - $(stat -f%m "$snapshot_file" 2>/dev/null || stat -c%Y "$snapshot_file" 2>/dev/null)) / 86400 ))
    if [ "$file_age_days" -gt 365 ]; then
        log_warn "Very old snapshot (${file_age_days} days): $basename_snap"
    fi
    
    # Size reasonableness check
    local size_mb=$((file_size / 1024 / 1024))
    if [ "$size_mb" -lt 1 ]; then
        log_warn "Very small snapshot (${size_mb}MB): $basename_snap"
    elif [ "$size_mb" -gt 10240 ]; then  # 10GB
        log_warn "Very large snapshot (${size_mb}MB): $basename_snap"
    fi
    
    log_success "✓ $basename_snap - Size: $(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B"), Collection: $collection_name, Age: ${file_age_days}d"
    VALID_SNAPSHOTS=$((VALID_SNAPSHOTS + 1))
    return 0
}

# Verify backup directory structure
verify_backup_structure() {
    log_info "Verifying backup directory structure..."
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "Backup directory does not exist: $BACKUP_DIR"
        return 1
    fi
    
    if [ ! -w "$BACKUP_DIR" ]; then
        log_error "Backup directory is not writable: $BACKUP_DIR"
        return 1
    fi
    
    if [ ! -d "$LOG_DIR" ]; then
        log_warn "Log directory does not exist: $LOG_DIR"
        mkdir -p "$LOG_DIR" || log_error "Cannot create log directory"
    fi
    
    # Check disk space
    local available_space=$(df "$BACKUP_DIR" | awk 'NR==2 {print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    
    if [ "$available_gb" -lt 1 ]; then
        log_error "Very low disk space: ${available_gb}GB available"
        return 1
    elif [ "$available_gb" -lt 10 ]; then
        log_warn "Low disk space: ${available_gb}GB available"
    else
        log_info "Disk space: ${available_gb}GB available"
    fi
    
    log_success "Backup directory structure is valid"
    return 0
}

# Check for duplicate snapshots
check_duplicates() {
    log_info "Checking for duplicate snapshots..."
    
    local duplicates_found=0
    
    # Group by collection and check for same-day snapshots
    find "$BACKUP_DIR" -name "*.snapshot" -type f | while read -r snapshot; do
        local basename_snap=$(basename "$snapshot")
        local collection_name=$(echo "$basename_snap" | sed 's/_[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}\.snapshot$//')
        local date_part=$(echo "$basename_snap" | grep -o '[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}')
        
        if [ -n "$collection_name" ] && [ -n "$date_part" ]; then
            local same_day_count=$(find "$BACKUP_DIR" -name "${collection_name}_${date_part}_*.snapshot" -type f | wc -l)
            if [ "$same_day_count" -gt 1 ]; then
                log_warn "Multiple snapshots for $collection_name on $date_part ($same_day_count files)"
                duplicates_found=$((duplicates_found + 1))
            fi
        fi
    done
    
    if [ "$duplicates_found" -eq 0 ]; then
        log_success "No duplicate snapshots found"
    else
        log_warn "Found $duplicates_found potential duplicate groups"
    fi
}

# Verify Qdrant connectivity and collections
verify_qdrant_connectivity() {
    log_info "Verifying Qdrant connectivity..."
    
    if ! curl -s -f "${QDRANT_URL}/health" > /dev/null; then
        log_error "Cannot connect to Qdrant at $QDRANT_URL"
        return 1
    fi
    
    local collections_response
    collections_response=$(curl -s "${QDRANT_URL}/collections" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        log_error "Failed to retrieve collections from Qdrant"
        return 1
    fi
    
    local collections_count=$(echo "$collections_response" | jq -r '.result.collections | length' 2>/dev/null || echo "0")
    log_info "Qdrant has $collections_count collections"
    
    # Check if we have snapshots for existing collections
    local collections_list=$(echo "$collections_response" | jq -r '.result.collections[].name' 2>/dev/null)
    
    while IFS= read -r collection; do
        if [ -n "$collection" ]; then
            local snapshot_count=$(find "$BACKUP_DIR" -name "${collection}_*.snapshot" -type f | wc -l)
            if [ "$snapshot_count" -eq 0 ]; then
                log_warn "No snapshots found for collection: $collection"
            else
                log_info "Collection $collection has $snapshot_count snapshots"
            fi
        fi
    done <<< "$collections_list"
    
    log_success "Qdrant connectivity verified"
    return 0
}

# Generate verification report
generate_report() {
    local start_time="$1"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "=== VERIFICATION REPORT ==="
    log_info "Start Time: $start_time"
    log_info "End Time: $end_time"
    log_info "Backup Directory: $BACKUP_DIR"
    log_info ""
    log_info "SNAPSHOT STATISTICS:"
    log_info "  Total Snapshots: $TOTAL_SNAPSHOTS"
    log_info "  Valid Snapshots: $VALID_SNAPSHOTS"
    log_info "  Invalid Snapshots: $INVALID_SNAPSHOTS"
    log_info "  Corrupted Snapshots: $CORRUPTED_SNAPSHOTS"
    
    if [ "$TOTAL_SNAPSHOTS" -gt 0 ]; then
        local success_rate=$(( (VALID_SNAPSHOTS * 100) / TOTAL_SNAPSHOTS ))
        log_info "  Success Rate: ${success_rate}%"
    fi
    
    # Disk usage
    local backup_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)
    log_info "  Total Backup Size: $backup_size"
    
    # Oldest and newest snapshots
    local oldest_snapshot=$(find "$BACKUP_DIR" -name "*.snapshot" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
    local newest_snapshot=$(find "$BACKUP_DIR" -name "*.snapshot" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$oldest_snapshot" ]; then
        local oldest_date=$(stat -f%Sm -t '%Y-%m-%d %H:%M:%S' "$oldest_snapshot" 2>/dev/null || stat -c%y "$oldest_snapshot" 2>/dev/null | cut -d'.' -f1)
        log_info "  Oldest Snapshot: $(basename "$oldest_snapshot") ($oldest_date)"
    fi
    
    if [ -n "$newest_snapshot" ]; then
        local newest_date=$(stat -f%Sm -t '%Y-%m-%d %H:%M:%S' "$newest_snapshot" 2>/dev/null || stat -c%y "$newest_snapshot" 2>/dev/null | cut -d'.' -f1)
        log_info "  Newest Snapshot: $(basename "$newest_snapshot") ($newest_date)"
    fi
    
    log_info "=========================="
    
    # Return appropriate exit code
    if [ "$INVALID_SNAPSHOTS" -gt 0 ] || [ "$CORRUPTED_SNAPSHOTS" -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# Main verification function
main() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    local verify_connectivity="true"
    local quick_mode="false"
    
    log_info "Starting Qdrant snapshot verification..."
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-connectivity)
                verify_connectivity="false"
                shift
                ;;
            --quick)
                quick_mode="true"
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
    
    # Ensure log directory exists
    mkdir -p "$LOG_DIR"
    
    # Verify backup structure
    if ! verify_backup_structure; then
        log_error "Backup structure verification failed"
        exit 1
    fi
    
    # Verify Qdrant connectivity if requested
    if [ "$verify_connectivity" = "true" ]; then
        verify_qdrant_connectivity || log_warn "Qdrant connectivity check failed"
    fi
    
    # Find and verify all snapshots
    log_info "Scanning for snapshots in $BACKUP_DIR..."
    
    local snapshots
    snapshots=$(find "$BACKUP_DIR" -name "*.snapshot" -type f 2>/dev/null)
    
    if [ -z "$snapshots" ]; then
        log_warn "No snapshots found in $BACKUP_DIR"
        TOTAL_SNAPSHOTS=0
    else
        TOTAL_SNAPSHOTS=$(echo "$snapshots" | wc -l)
        log_info "Found $TOTAL_SNAPSHOTS snapshots to verify"
        
        # Verify each snapshot
        while IFS= read -r snapshot; do
            if [ -n "$snapshot" ]; then
                if ! verify_snapshot "$snapshot"; then
                    INVALID_SNAPSHOTS=$((INVALID_SNAPSHOTS + 1))
                fi
            fi
        done <<< "$snapshots"
    fi
    
    # Additional checks if not in quick mode
    if [ "$quick_mode" != "true" ]; then
        check_duplicates
    fi
    
    # Generate report
    if generate_report "$start_time"; then
        log_success "Verification completed successfully"
        exit 0
    else
        log_error "Verification completed with issues"
        exit 1
    fi
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Verify Qdrant snapshot integrity and backup system health"
    echo ""
    echo "Options:"
    echo "  --no-connectivity      Skip Qdrant connectivity checks"
    echo "  --quick               Quick mode (skip duplicate checks)"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  QDRANT_URL            Qdrant server URL (default: http://localhost:6333)"
    echo "  BACKUP_DIR            Backup directory (default: ~/backups/qdrant)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Full verification"
    echo "  $0 --quick           # Quick verification"
    echo "  $0 --no-connectivity # Verify snapshots only"
    echo ""
    echo "Exit codes:"
    echo "  0 - All verifications passed"
    echo "  1 - Issues found or verification failed"
}

# Run main function
main "$@"