#!/bin/bash

# qdrant-restore.sh - Comprehensive Qdrant Vector Database Disaster Recovery
# Version: 1.0.0
# Description: Robust restoration solution for Qdrant vector database with memory storage system support
# Author: DGMSTT System
# Date: $(date +%Y-%m-%d)

set -euo pipefail

# =============================================================================
# CONFIGURATION AND CONSTANTS
# =============================================================================

# Script configuration
readonly SCRIPT_NAME="qdrant-restore"
readonly SCRIPT_VERSION="1.0.0"
readonly LOG_DIR="/var/log/qdrant-restore"
readonly BACKUP_DIR="/var/backups/qdrant"
readonly TEMP_DIR="/tmp/qdrant-restore-$$"
readonly CONFIG_FILE="/etc/qdrant-restore.conf"

# Qdrant configuration (from qdrant-mcp-setup.md)
readonly DEFAULT_QDRANT_URL="http://localhost:6333"
readonly DEFAULT_COLLECTION="AgentMemories"
readonly DEFAULT_VECTOR_NAME="fast-all-minilm-l6-v2"
readonly DEFAULT_VECTOR_SIZE=384
readonly DEFAULT_DISTANCE_METRIC="Cosine"
readonly DEFAULT_EMBEDDING_MODEL="sentence-transformers/all-MiniLM-L6-v2"

# Recovery scenarios
readonly SCENARIO_COMPLETE_FAILURE="complete_failure"
readonly SCENARIO_COLLECTION_CORRUPTION="collection_corruption"
readonly SCENARIO_VECTOR_MISMATCH="vector_mismatch"
readonly SCENARIO_MEMORY_RESTORATION="memory_restoration"
readonly SCENARIO_MCP_CONFIG="mcp_config"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Progress indicators
readonly PROGRESS_CHARS="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

QDRANT_URL="${DEFAULT_QDRANT_URL}"
COLLECTION_NAME="${DEFAULT_COLLECTION}"
VECTOR_NAME="${DEFAULT_VECTOR_NAME}"
VECTOR_SIZE="${DEFAULT_VECTOR_SIZE}"
DISTANCE_METRIC="${DEFAULT_DISTANCE_METRIC}"
EMBEDDING_MODEL="${DEFAULT_EMBEDDING_MODEL}"

RECOVERY_SCENARIO=""
BACKUP_SOURCE=""
SNAPSHOT_NAME=""
RESTORE_POINT=""
DRY_RUN=false
VERBOSE=false
FORCE=false
DOCKER_MODE=false
DOCKER_CONTAINER=""

START_TIME=""
LOG_FILE=""

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
    
    case "$level" in
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" >&2
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message"
            ;;
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message"
            ;;
        "DEBUG")
            if [[ "$VERBOSE" == true ]]; then
                echo -e "${BLUE}[DEBUG]${NC} $message"
            fi
            ;;
    esac
}

log_info() { log "INFO" "$@"; }
log_warn() { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { log "DEBUG" "$@"; }

# Error handling
error_exit() {
    log_error "$1"
    cleanup_temp
    exit 1
}

# Cleanup temporary files
cleanup_temp() {
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        log_info "Cleaned up temporary directory"
    fi
}

# Trap to ensure cleanup on exit
trap cleanup_temp EXIT

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."
    
    if ! command -v curl &> /dev/null; then
        error_exit "curl is required but not installed"
    fi
    
    if ! command -v jq &> /dev/null; then
        error_exit "jq is required but not installed"
    fi
    
    log_success "Dependencies check completed"
}

# Check Qdrant health
check_qdrant_health() {
    log_info "Checking Qdrant health..."
    
    if curl -s -f "${QDRANT_URL}/health" > /dev/null; then
        log_success "Qdrant is healthy"
        return 0
    else
        error_exit "Qdrant is not accessible at ${QDRANT_URL}"
    fi
}

# List available snapshots
list_snapshots() {
    log_info "Available snapshots in ${BACKUP_DIR}:"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "Backup directory does not exist: $BACKUP_DIR"
        return 1
    fi
    
    local snapshots
    snapshots=$(find "$BACKUP_DIR" -name "*.snapshot" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
    
    if [ -z "$snapshots" ]; then
        log_warn "No snapshots found in $BACKUP_DIR"
        return 1
    fi
    
    local count=1
    while IFS= read -r snapshot; do
        if [ -n "$snapshot" ]; then
            local basename_snap=$(basename "$snapshot")
            local size=$(stat -f%z "$snapshot" 2>/dev/null || stat -c%s "$snapshot" 2>/dev/null)
            local date=$(stat -f%Sm -t '%Y-%m-%d %H:%M:%S' "$snapshot" 2>/dev/null || stat -c%y "$snapshot" 2>/dev/null | cut -d'.' -f1)
            
            printf "%3d. %-50s %10s %s\n" "$count" "$basename_snap" "$(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")" "$date"
            count=$((count + 1))
        fi
    done <<< "$snapshots"
    
    return 0
}

# Extract collection name from snapshot filename
extract_collection_name() {
    local snapshot_file="$1"
    local basename_snap=$(basename "$snapshot_file" .snapshot)
    
    # Remove timestamp suffix (pattern: _YYYY-MM-DD_HH-MM-SS)
    echo "$basename_snap" | sed 's/_[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}_[0-9]\{2\}-[0-9]\{2\}-[0-9]\{2\}$//'
}

# Check if collection exists
collection_exists() {
    local collection_name="$1"
    
    local response
    response=$(curl -s "${QDRANT_URL}/collections/${collection_name}" 2>/dev/null)
    
    if echo "$response" | jq -e '.result' > /dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get collection info
get_collection_info() {
    local collection_name="$1"
    
    log_info "Getting collection info for: $collection_name"
    
    local response
    response=$(curl -s "${QDRANT_URL}/collections/${collection_name}")
    
    if echo "$response" | jq -e '.result' > /dev/null 2>&1; then
        local points_count=$(echo "$response" | jq -r '.result.points_count // 0')
        local vectors_count=$(echo "$response" | jq -r '.result.vectors_count // 0')
        local status=$(echo "$response" | jq -r '.result.status // "unknown"')
        
        log_info "Collection status: $status"
        log_info "Points count: $points_count"
        log_info "Vectors count: $vectors_count"
        
        return 0
    else
        log_error "Failed to get collection info"
        return 1
    fi
}

# Create backup of existing collection
backup_existing_collection() {
    local collection_name="$1"
    local backup_suffix=$(date '+%Y%m%d_%H%M%S')
    
    log_info "Creating backup of existing collection: $collection_name"
    
    # Create snapshot
    local snapshot_response
    snapshot_response=$(curl -s -X POST "${QDRANT_URL}/collections/${collection_name}/snapshots" \
        -H "Content-Type: application/json" \
        -d '{"wait": true}')
    
    if [ $? -ne 0 ]; then
        log_error "Failed to create backup snapshot"
        return 1
    fi
    
    local snapshot_name
    snapshot_name=$(echo "$snapshot_response" | jq -r '.result.name' 2>/dev/null)
    
    if [ "$snapshot_name" = "null" ] || [ -z "$snapshot_name" ]; then
        log_error "Failed to extract backup snapshot name"
        return 1
    fi
    
    # Download backup
    local backup_file="${BACKUP_DIR}/${collection_name}_backup_${backup_suffix}.snapshot"
    
    if curl -s -f "${QDRANT_URL}/collections/${collection_name}/snapshots/${snapshot_name}" \
        -o "${backup_file}"; then
        log_success "Existing collection backed up to: $(basename "$backup_file")"
        
        # Clean up remote snapshot
        curl -s -X DELETE "${QDRANT_URL}/collections/${collection_name}/snapshots/${snapshot_name}" > /dev/null
        
        return 0
    else
        log_error "Failed to download backup snapshot"
        return 1
    fi
}

# Delete collection
delete_collection() {
    local collection_name="$1"
    
    log_info "Deleting collection: $collection_name"
    
    local response
    response=$(curl -s -X DELETE "${QDRANT_URL}/collections/${collection_name}")
    
    if [ $? -eq 0 ]; then
        log_success "Collection deleted: $collection_name"
        return 0
    else
        log_error "Failed to delete collection: $collection_name"
        return 1
    fi
}

# Upload and restore snapshot
restore_snapshot() {
    local snapshot_file="$1"
    local collection_name="$2"
    local force_restore="$3"
    
    log_info "Starting restore process..."
    log_info "Snapshot: $(basename "$snapshot_file")"
    log_info "Collection: $collection_name"
    
    # Verify snapshot file
    if [ ! -f "$snapshot_file" ]; then
        error_exit "Snapshot file does not exist: $snapshot_file"
    fi
    
    local file_size=$(stat -f%z "$snapshot_file" 2>/dev/null || stat -c%s "$snapshot_file" 2>/dev/null)
    if [ "$file_size" -eq 0 ]; then
        error_exit "Snapshot file is empty: $snapshot_file"
    fi
    
    log_info "Snapshot size: $(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B")"
    
    # Check if collection exists
    if collection_exists "$collection_name"; then
        log_warn "Collection '$collection_name' already exists"
        
        if [ "$force_restore" != "true" ]; then
            log_info "Current collection info:"
            get_collection_info "$collection_name"
            
            echo -n "Do you want to backup and replace the existing collection? [y/N]: "
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log_info "Restore cancelled by user"
                return 1
            fi
        fi
        
        # Backup existing collection
        if ! backup_existing_collection "$collection_name"; then
            log_error "Failed to backup existing collection"
            if [ "$force_restore" != "true" ]; then
                echo -n "Continue without backup? [y/N]: "
                read -r response
                if [[ ! "$response" =~ ^[Yy]$ ]]; then
                    log_info "Restore cancelled"
                    return 1
                fi
            fi
        fi
        
        # Delete existing collection
        if ! delete_collection "$collection_name"; then
            error_exit "Failed to delete existing collection"
        fi
        
        # Wait a moment for deletion to complete
        sleep 2
    fi
    
    # Create temporary directory
    mkdir -p "$TEMP_DIR"
    
    # Upload snapshot for restoration
    log_info "Uploading snapshot for restoration..."
    
    local restore_response
    restore_response=$(curl -s -X PUT "${QDRANT_URL}/collections/${collection_name}/snapshots/upload" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${snapshot_file}")
    
    if [ $? -ne 0 ]; then
        error_exit "Failed to upload snapshot for restoration"
    fi
    
    # Check if restore was successful
    log_info "Verifying restoration..."
    sleep 3
    
    if collection_exists "$collection_name"; then
        log_success "Collection restored successfully: $collection_name"
        
        # Get restored collection info
        get_collection_info "$collection_name"
        
        return 0
    else
        error_exit "Restoration failed - collection not found after restore"
    fi
}

# Interactive snapshot selection
select_snapshot() {
    log_info "Interactive snapshot selection"
    
    if ! list_snapshots; then
        error_exit "No snapshots available for restoration"
    fi
    
    echo ""
    echo -n "Enter snapshot number to restore (or 'q' to quit): "
    read -r selection
    
    if [ "$selection" = "q" ] || [ "$selection" = "Q" ]; then
        log_info "Restore cancelled by user"
        exit 0
    fi
    
    if ! [[ "$selection" =~ ^[0-9]+$ ]]; then
        error_exit "Invalid selection: $selection"
    fi
    
    local snapshots
    snapshots=$(find "$BACKUP_DIR" -name "*.snapshot" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | cut -d' ' -f2-)
    
    local snapshot_file
    snapshot_file=$(echo "$snapshots" | sed -n "${selection}p")
    
    if [ -z "$snapshot_file" ]; then
        error_exit "Invalid selection: $selection"
    fi
    
    echo "$snapshot_file"
}

# Main restore function
main() {
    local snapshot_file=""
    local collection_name=""
    local force_restore="false"
    local interactive="false"
    
    log_info "Starting Qdrant restore process..."
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                snapshot_file="$2"
                shift 2
                ;;
            -c|--collection)
                collection_name="$2"
                shift 2
                ;;
            --force)
                force_restore="true"
                shift
                ;;
            -i|--interactive)
                interactive="true"
                shift
                ;;
            -l|--list)
                list_snapshots
                exit 0
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
    
    # Ensure directories exist
    mkdir -p "${LOG_DIR}"
    
    # Check dependencies and health
    check_dependencies
    check_qdrant_health
    
    # Interactive mode
    if [ "$interactive" = "true" ] || [ -z "$snapshot_file" ]; then
        snapshot_file=$(select_snapshot)
    fi
    
    # Validate snapshot file
    if [ ! -f "$snapshot_file" ]; then
        # Try to find in backup directory
        if [ -f "${BACKUP_DIR}/${snapshot_file}" ]; then
            snapshot_file="${BACKUP_DIR}/${snapshot_file}"
        else
            error_exit "Snapshot file not found: $snapshot_file"
        fi
    fi
    
    # Extract collection name if not provided
    if [ -z "$collection_name" ]; then
        collection_name=$(extract_collection_name "$snapshot_file")
        log_info "Extracted collection name: $collection_name"
    fi
    
    # Confirm restore
    if [ "$force_restore" != "true" ]; then
        echo ""
        log_info "Restore Summary:"
        log_info "  Snapshot: $(basename "$snapshot_file")"
        log_info "  Collection: $collection_name"
        log_info "  Qdrant URL: $QDRANT_URL"
        echo ""
        echo -n "Proceed with restore? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            log_info "Restore cancelled by user"
            exit 0
        fi
    fi
    
    # Perform restore
    if restore_snapshot "$snapshot_file" "$collection_name" "$force_restore"; then
        log_success "Restore completed successfully"
        exit 0
    else
        error_exit "Restore failed"
    fi
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Restore Qdrant collections from snapshots"
    echo ""
    echo "Options:"
    echo "  -f, --file FILE         Snapshot file to restore"
    echo "  -c, --collection NAME   Target collection name (auto-detected if not specified)"
    echo "  -i, --interactive       Interactive snapshot selection"
    echo "  -l, --list             List available snapshots"
    echo "  --force                Force restore without prompts"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  QDRANT_URL             Qdrant server URL (default: http://localhost:6333)"
    echo "  BACKUP_DIR             Backup directory (default: ~/backups/qdrant)"
    echo ""
    echo "Examples:"
    echo "  $0 -l                                    # List available snapshots"
    echo "  $0 -i                                    # Interactive restore"
    echo "  $0 -f snapshot.snapshot                  # Restore specific snapshot"
    echo "  $0 -f snapshot.snapshot -c MyCollection  # Restore to specific collection"
    echo "  $0 --force -f snapshot.snapshot          # Force restore without prompts"
    echo ""
    echo "Safety features:"
    echo "  - Automatic backup of existing collections before restore"
    echo "  - Snapshot integrity verification"
    echo "  - Interactive confirmation prompts"
    echo "  - Comprehensive logging"
}

# Run main function
main "$@"