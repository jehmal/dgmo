#!/bin/bash

# Qdrant Backup Automation Script
# Database Administrator: Vector Database Backup System
# Created: $(date '+%Y-%m-%d')
# Purpose: Automated Qdrant snapshot management with retention and verification

set -euo pipefail

# Configuration
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
BACKUP_DIR="${HOME}/backups/qdrant"
LOG_DIR="${HOME}/backups/logs"
LOG_FILE="${LOG_DIR}/qdrant-backup.log"
RETENTION_DAYS=14
MAX_RETRIES=3
RETRY_DELAY=5

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

# Error handling
error_exit() {
    log_error "$1"
    exit 1
}

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v curl &> /dev/null; then
        error_exit "curl is required but not installed"
    fi
    
    if ! command -v jq &> /dev/null; then
        log_warn "jq not found, installing..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum &> /dev/null; then
            sudo yum install -y jq
        else
            error_exit "Cannot install jq automatically. Please install manually."
        fi
    fi
    
    log_success "Dependencies check completed"
}

# Check Qdrant health
check_qdrant_health() {
    log_info "Checking Qdrant health..."
    
    local retry_count=0
    while [ $retry_count -lt $MAX_RETRIES ]; do
        if curl -s -f "${QDRANT_URL}/health" > /dev/null; then
            log_success "Qdrant is healthy"
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        log_warn "Qdrant health check failed (attempt ${retry_count}/${MAX_RETRIES})"
        
        if [ $retry_count -lt $MAX_RETRIES ]; then
            sleep $RETRY_DELAY
        fi
    done
    
    error_exit "Qdrant is not accessible after ${MAX_RETRIES} attempts"
}

# Get list of collections
get_collections() {
    log_info "Retrieving collection list..."
    
    local collections_response
    collections_response=$(curl -s -f "${QDRANT_URL}/collections" | jq -r '.result.collections[].name' 2>/dev/null)
    
    if [ -z "$collections_response" ]; then
        error_exit "Failed to retrieve collections or no collections found"
    fi
    
    echo "$collections_response"
}

# Create snapshot for a collection
create_snapshot() {
    local collection_name="$1"
    local timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
    
    log_info "Creating snapshot for collection: ${collection_name}"
    
    # Create snapshot via API
    local snapshot_response
    snapshot_response=$(curl -s -X POST "${QDRANT_URL}/collections/${collection_name}/snapshots" \
        -H "Content-Type: application/json" \
        -d '{"wait": true}')
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create snapshot for ${collection_name}"
        return 1
    fi
    
    # Extract snapshot name from response
    local snapshot_name
    snapshot_name=$(echo "$snapshot_response" | jq -r '.result.name' 2>/dev/null)
    
    if [ "$snapshot_name" = "null" ] || [ -z "$snapshot_name" ]; then
        log_error "Failed to extract snapshot name for ${collection_name}"
        return 1
    fi
    
    log_success "Snapshot created: ${snapshot_name}"
    
    # Download snapshot
    local backup_file="${BACKUP_DIR}/${collection_name}_${timestamp}.snapshot"
    log_info "Downloading snapshot to: ${backup_file}"
    
    if curl -s -f "${QDRANT_URL}/collections/${collection_name}/snapshots/${snapshot_name}" \
        -o "${backup_file}"; then
        log_success "Snapshot downloaded: ${backup_file}"
        
        # Verify file size
        local file_size=$(stat -f%z "${backup_file}" 2>/dev/null || stat -c%s "${backup_file}" 2>/dev/null)
        if [ "$file_size" -gt 0 ]; then
            log_info "Snapshot size: ${file_size} bytes"
        else
            log_error "Downloaded snapshot appears to be empty"
            rm -f "${backup_file}"
            return 1
        fi
        
        # Clean up remote snapshot
        curl -s -X DELETE "${QDRANT_URL}/collections/${collection_name}/snapshots/${snapshot_name}" > /dev/null
        log_info "Remote snapshot cleaned up"
        
        return 0
    else
        log_error "Failed to download snapshot for ${collection_name}"
        return 1
    fi
}

# Verify snapshot integrity
verify_snapshot() {
    local snapshot_file="$1"
    
    log_info "Verifying snapshot: $(basename "$snapshot_file")"
    
    # Check file exists and has content
    if [ ! -f "$snapshot_file" ]; then
        log_error "Snapshot file does not exist: $snapshot_file"
        return 1
    fi
    
    local file_size=$(stat -f%z "$snapshot_file" 2>/dev/null || stat -c%s "$snapshot_file" 2>/dev/null)
    if [ "$file_size" -eq 0 ]; then
        log_error "Snapshot file is empty: $snapshot_file"
        return 1
    fi
    
    # Basic file type check (should be a valid archive/binary)
    if file "$snapshot_file" | grep -q "data"; then
        log_success "Snapshot verification passed: $(basename "$snapshot_file") (${file_size} bytes)"
        return 0
    else
        log_error "Snapshot file appears corrupted: $snapshot_file"
        return 1
    fi
}

# Clean up old snapshots
cleanup_old_snapshots() {
    log_info "Cleaning up snapshots older than ${RETENTION_DAYS} days..."
    
    local deleted_count=0
    
    # Find and delete old snapshots
    while IFS= read -r -d '' file; do
        if [ -f "$file" ]; then
            rm -f "$file"
            log_info "Deleted old snapshot: $(basename "$file")"
            deleted_count=$((deleted_count + 1))
        fi
    done < <(find "${BACKUP_DIR}" -name "*.snapshot" -type f -mtime +${RETENTION_DAYS} -print0 2>/dev/null)
    
    if [ $deleted_count -eq 0 ]; then
        log_info "No old snapshots to clean up"
    else
        log_success "Cleaned up ${deleted_count} old snapshots"
    fi
}

# Generate backup report
generate_report() {
    local start_time="$1"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    local collections_backed_up="$2"
    local failed_collections="$3"
    
    log_info "=== BACKUP REPORT ==="
    log_info "Start Time: ${start_time}"
    log_info "End Time: ${end_time}"
    log_info "Collections Backed Up: ${collections_backed_up}"
    log_info "Failed Collections: ${failed_collections}"
    
    # Disk usage
    local backup_size=$(du -sh "${BACKUP_DIR}" 2>/dev/null | cut -f1)
    log_info "Total Backup Size: ${backup_size}"
    
    # Current snapshots
    local snapshot_count=$(find "${BACKUP_DIR}" -name "*.snapshot" -type f | wc -l)
    log_info "Total Snapshots: ${snapshot_count}"
    
    log_info "===================="
}

# Main backup function
main() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "Starting Qdrant backup process..."
    log_info "Backup directory: ${BACKUP_DIR}"
    log_info "Log file: ${LOG_FILE}"
    
    # Ensure directories exist
    mkdir -p "${BACKUP_DIR}" "${LOG_DIR}"
    
    # Check dependencies and health
    check_dependencies
    check_qdrant_health
    
    # Get collections
    local collections
    collections=$(get_collections)
    
    if [ -z "$collections" ]; then
        error_exit "No collections found to backup"
    fi
    
    log_info "Found collections: $(echo "$collections" | tr '\n' ' ')"
    
    # Backup each collection
    local success_count=0
    local failed_count=0
    local failed_collections=""
    
    while IFS= read -r collection; do
        if [ -n "$collection" ]; then
            log_info "Processing collection: ${collection}"
            
            if create_snapshot "$collection"; then
                # Find the most recent snapshot for this collection
                local latest_snapshot
                latest_snapshot=$(find "${BACKUP_DIR}" -name "${collection}_*.snapshot" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
                
                if [ -n "$latest_snapshot" ] && verify_snapshot "$latest_snapshot"; then
                    success_count=$((success_count + 1))
                    log_success "Successfully backed up collection: ${collection}"
                else
                    failed_count=$((failed_count + 1))
                    failed_collections="${failed_collections} ${collection}"
                    log_error "Verification failed for collection: ${collection}"
                fi
            else
                failed_count=$((failed_count + 1))
                failed_collections="${failed_collections} ${collection}"
                log_error "Failed to backup collection: ${collection}"
            fi
        fi
    done <<< "$collections"
    
    # Cleanup old snapshots
    cleanup_old_snapshots
    
    # Generate report
    generate_report "$start_time" "$success_count" "$failed_count"
    
    # Final status
    if [ $failed_count -eq 0 ]; then
        log_success "Backup completed successfully for all ${success_count} collections"
        exit 0
    else
        log_error "Backup completed with ${failed_count} failures out of $((success_count + failed_count)) collections"
        log_error "Failed collections:${failed_collections}"
        exit 1
    fi
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -u, --url URL       Qdrant URL (default: http://localhost:6333)"
    echo "  -d, --dir DIR       Backup directory (default: ~/backups/qdrant)"
    echo "  -r, --retention N   Retention days (default: 14)"
    echo "  -v, --verify        Verify existing snapshots only"
    echo "  --dry-run          Show what would be done without executing"
    echo ""
    echo "Environment variables:"
    echo "  QDRANT_URL         Qdrant server URL"
    echo "  BACKUP_DIR         Backup directory path"
    echo ""
    echo "Examples:"
    echo "  $0                 # Run backup with defaults"
    echo "  $0 -u http://remote:6333 -r 30"
    echo "  $0 --verify        # Only verify existing snapshots"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -u|--url)
            QDRANT_URL="$2"
            shift 2
            ;;
        -d|--dir)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -r|--retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        -v|--verify)
            # Verify mode - only check existing snapshots
            log_info "Verification mode - checking existing snapshots..."
            find "${BACKUP_DIR}" -name "*.snapshot" -type f | while read -r snapshot; do
                verify_snapshot "$snapshot"
            done
            exit 0
            ;;
        --dry-run)
            log_info "DRY RUN MODE - showing what would be done..."
            check_qdrant_health
            collections=$(get_collections)
            log_info "Would backup collections: $(echo "$collections" | tr '\n' ' ')"
            log_info "Would clean up snapshots older than ${RETENTION_DAYS} days"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run main function
main "$@"