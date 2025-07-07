#!/bin/bash

# Session Consolidation Script
# Consolidates all scattered session data into unified directory structure

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
UNIFIED_BASE="/home/jehma/.local/share/opencode/project/unified/storage/session"
OPENCODE_BASE="/home/jehma/.local/share/opencode/project"

# Source directories
declare -a SOURCE_DIRS=(
    "${OPENCODE_BASE}/mnt-c-Users-jehma-Desktop-AI-DGMSTT/storage/session"
    "${OPENCODE_BASE}/mnt-c-Users-jehma-Desktop-AI-DGMSTT-opencode/storage/session"
    "${OPENCODE_BASE}/mnt-c-Users-jehma-Desktop-AI-DGMSTT-web-ui/storage/session"
    "${OPENCODE_BASE}/global/storage/session"
)

# Subdirectories to consolidate
declare -a SUBDIRS=("info" "message" "performance" "sub-sessions" "sub-session-index")

# Logging
LOG_FILE="/tmp/session-consolidation-$(date +%Y%m%d-%H%M%S).log"
CONFLICT_LOG="/tmp/session-conflicts-$(date +%Y%m%d-%H%M%S).log"

echo -e "${BLUE}=== Session Consolidation Script ===${NC}"
echo "Log file: $LOG_FILE"
echo "Conflict log: $CONFLICT_LOG"
echo ""

# Initialize logs
echo "Session Consolidation Log - $(date)" > "$LOG_FILE"
echo "Session Conflict Log - $(date)" > "$CONFLICT_LOG"

# Function to log messages
log_message() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Function to log conflicts
log_conflict() {
    echo "$1" | tee -a "$CONFLICT_LOG"
}

# Function to copy files with conflict handling
copy_with_conflict_handling() {
    local src_file="$1"
    local dest_file="$2"
    local file_type="$3"
    
    if [[ -f "$dest_file" ]]; then
        # File exists, check if they're different
        if ! cmp -s "$src_file" "$dest_file"; then
            # Files are different, create backup with source identifier
            local basename=$(basename "$dest_file")
            local dirname=$(dirname "$dest_file")
            local source_id=$(echo "$src_file" | sed 's|.*/mnt-c-Users-jehma-Desktop-AI-DGMSTT||' | sed 's|/storage/session.*||' | sed 's|^-||' | sed 's|/|-|g')
            if [[ -z "$source_id" ]]; then
                source_id="global"
            fi
            local backup_file="${dirname}/${basename}.conflict-${source_id}"
            
            log_conflict "CONFLICT: $basename exists with different content"
            log_conflict "  Original: $dest_file"
            log_conflict "  Conflicting: $src_file"
            log_conflict "  Backup created: $backup_file"
            
            cp "$src_file" "$backup_file"
            echo -e "${YELLOW}  CONFLICT: Created backup $backup_file${NC}"
        else
            echo -e "${GREEN}  SKIP: Identical file already exists${NC}"
        fi
    else
        # File doesn't exist, copy it
        cp "$src_file" "$dest_file"
        echo -e "${GREEN}  COPIED: $(basename "$dest_file")${NC}"
    fi
}

# Function to consolidate a specific subdirectory
consolidate_subdir() {
    local subdir="$1"
    local total_files=0
    local copied_files=0
    local skipped_files=0
    local conflict_files=0
    
    log_message "${BLUE}Consolidating $subdir files...${NC}"
    
    for source_dir in "${SOURCE_DIRS[@]}"; do
        local src_path="${source_dir}/${subdir}"
        local dest_path="${UNIFIED_BASE}/${subdir}"
        
        if [[ -d "$src_path" ]]; then
            echo -e "${YELLOW}Processing: $src_path${NC}"
            
            # Count files in this source
            local file_count=$(find "$src_path" -type f 2>/dev/null | wc -l)
            total_files=$((total_files + file_count))
            
            if [[ $file_count -gt 0 ]]; then
                # Copy all files from this source
                find "$src_path" -type f -print0 | while IFS= read -r -d '' src_file; do
                    local rel_path="${src_file#$src_path/}"
                    local dest_file="${dest_path}/${rel_path}"
                    
                    # Create destination directory if needed
                    mkdir -p "$(dirname "$dest_file")"
                    
                    # Handle the copy with conflict detection
                    if [[ -f "$dest_file" ]]; then
                        if cmp -s "$src_file" "$dest_file"; then
                            echo -e "${GREEN}  SKIP: $(basename "$src_file") (identical)${NC}"
                        else
                            copy_with_conflict_handling "$src_file" "$dest_file" "$subdir"
                        fi
                    else
                        cp "$src_file" "$dest_file"
                        echo -e "${GREEN}  COPIED: $(basename "$src_file")${NC}"
                    fi
                done
                
                echo "  Found $file_count files"
            else
                echo "  No files found"
            fi
        else
            echo "  Directory not found: $src_path"
        fi
    done
    
    # Count final results
    local final_count=$(find "${UNIFIED_BASE}/${subdir}" -type f 2>/dev/null | wc -l)
    log_message "  Total files in unified $subdir: $final_count"
    echo ""
}

# Function to merge sub-session indices
merge_subsession_indices() {
    log_message "${BLUE}Merging sub-session indices...${NC}"
    
    local unified_index="${UNIFIED_BASE}/sub-session-index"
    local temp_merged="/tmp/merged-subsession-index.json"
    
    # Initialize empty index
    echo "{}" > "$temp_merged"
    
    for source_dir in "${SOURCE_DIRS[@]}"; do
        local index_dir="${source_dir}/sub-session-index"
        
        if [[ -d "$index_dir" ]]; then
            echo -e "${YELLOW}Processing indices from: $index_dir${NC}"
            
            find "$index_dir" -name "*.json" -type f | while read -r index_file; do
                echo "  Merging: $(basename "$index_file")"
                # Copy individual index files
                cp "$index_file" "${unified_index}/"
            done
        fi
    done
    
    local index_count=$(find "$unified_index" -name "*.json" -type f 2>/dev/null | wc -l)
    log_message "  Total index files: $index_count"
    echo ""
}

# Main consolidation process
main() {
    log_message "Starting session consolidation..."
    log_message "Target directory: $UNIFIED_BASE"
    log_message ""
    
    # Pre-consolidation counts
    log_message "=== PRE-CONSOLIDATION COUNTS ==="
    for source_dir in "${SOURCE_DIRS[@]}"; do
        if [[ -d "$source_dir" ]]; then
            local session_count=$(find "${source_dir}/message" -name "ses_*" 2>/dev/null | wc -l)
            local subsession_count=$(find "${source_dir}/sub-sessions" -name "*.json" 2>/dev/null | wc -l)
            log_message "Source: $(basename "$(dirname "$source_dir")")"
            log_message "  Sessions: $session_count"
            log_message "  Sub-sessions: $subsession_count"
        fi
    done
    log_message ""
    
    # Consolidate each subdirectory
    for subdir in "${SUBDIRS[@]}"; do
        consolidate_subdir "$subdir"
    done
    
    # Special handling for sub-session indices
    merge_subsession_indices
    
    # Post-consolidation verification
    log_message "=== POST-CONSOLIDATION VERIFICATION ==="
    for subdir in "${SUBDIRS[@]}"; do
        local count=$(find "${UNIFIED_BASE}/${subdir}" -type f 2>/dev/null | wc -l)
        log_message "Unified $subdir: $count files"
    done
    
    # Special counts for sessions and sub-sessions
    local total_sessions=$(find "${UNIFIED_BASE}/message" -name "ses_*" 2>/dev/null | wc -l)
    local total_subsessions=$(find "${UNIFIED_BASE}/sub-sessions" -name "*.json" 2>/dev/null | wc -l)
    local total_indices=$(find "${UNIFIED_BASE}/sub-session-index" -name "*.json" 2>/dev/null | wc -l)
    
    log_message ""
    log_message "=== FINAL SUMMARY ==="
    log_message "Total sessions consolidated: $total_sessions"
    log_message "Total sub-sessions consolidated: $total_subsessions"
    log_message "Total index files: $total_indices"
    
    # Check for conflicts
    local conflict_count=$(grep -c "CONFLICT:" "$CONFLICT_LOG" 2>/dev/null || echo "0")
    if [[ $conflict_count -gt 0 ]]; then
        log_message "${YELLOW}Conflicts detected: $conflict_count${NC}"
        log_message "See conflict log: $CONFLICT_LOG"
    else
        log_message "${GREEN}No conflicts detected${NC}"
    fi
    
    log_message ""
    log_message "${GREEN}Consolidation completed successfully!${NC}"
    log_message "Unified directory: $UNIFIED_BASE"
}

# Run the consolidation
main

echo ""
echo -e "${BLUE}=== Consolidation Complete ===${NC}"
echo "Check the logs for detailed information:"
echo "  Main log: $LOG_FILE"
echo "  Conflict log: $CONFLICT_LOG"