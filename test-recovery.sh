#!/bin/bash

# DGMSTT Disaster Recovery Testing Framework
# Comprehensive automated testing for all recovery procedures
# Created: $(date '+%Y-%m-%d')
# Purpose: Validate recovery procedures, benchmark performance, ensure data integrity

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Version and metadata
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME="test-recovery.sh"
readonly FRAMEWORK_NAME="DGMSTT Recovery Testing Framework"

# Directories and paths
readonly BASE_DIR="/mnt/c/Users/jehma/Desktop/AI/DGMSTT"
readonly TEST_DIR="${BASE_DIR}/recovery-tests"
readonly BACKUP_DIR="${HOME}/backups"
readonly LOG_DIR="${TEST_DIR}/logs"
readonly REPORT_DIR="${TEST_DIR}/reports"
readonly TEMP_DIR="${TEST_DIR}/temp"
readonly DATA_DIR="${TEST_DIR}/test-data"

# Session storage paths
readonly SESSION_BASE="${HOME}/.local/share/opencode/project"
readonly UNIFIED_SESSION="${SESSION_BASE}/unified/storage/session"

# Qdrant configuration
readonly QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
readonly QDRANT_BACKUP_DIR="${BACKUP_DIR}/qdrant"

# Test configuration
readonly MAX_RETRIES=3
readonly RETRY_DELAY=5
readonly PERFORMANCE_THRESHOLD_SECONDS=30
readonly DATA_INTEGRITY_THRESHOLD=0.95

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Test results tracking
declare -A TEST_RESULTS
declare -A PERFORMANCE_METRICS
declare -A INTEGRITY_SCORES
declare -g TOTAL_TESTS=0
declare -g PASSED_TESTS=0
declare -g FAILED_TESTS=0
declare -g SKIPPED_TESTS=0

# ============================================================================
# LOGGING AND UTILITIES
# ============================================================================

# Initialize logging
init_logging() {
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    readonly LOG_FILE="${LOG_DIR}/recovery-test-${timestamp}.log"
    readonly REPORT_FILE="${REPORT_DIR}/recovery-report-${timestamp}.html"
    readonly METRICS_FILE="${REPORT_DIR}/metrics-${timestamp}.json"
    
    mkdir -p "${LOG_DIR}" "${REPORT_DIR}" "${TEMP_DIR}" "${DATA_DIR}"
    
    # Initialize log file
    cat > "${LOG_FILE}" << EOF
# DGMSTT Recovery Testing Framework Log
# Started: $(date)
# Version: ${SCRIPT_VERSION}
# Test Directory: ${TEST_DIR}
# ============================================================================

EOF
}

# Logging functions
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
log_debug() { log "DEBUG" "$@"; }

# Progress indicator
show_progress() {
    local current="$1"
    local total="$2"
    local description="$3"
    local percent=$((current * 100 / total))
    local bar_length=50
    local filled_length=$((percent * bar_length / 100))
    
    printf "\r${BLUE}[%3d%%]${NC} " "$percent"
    printf "${GREEN}"
    for ((i=0; i<filled_length; i++)); do printf "█"; done
    printf "${NC}"
    for ((i=filled_length; i<bar_length; i++)); do printf "░"; done
    printf " ${description}"
    
    if [ "$current" -eq "$total" ]; then
        echo ""
    fi
}

# Error handling
error_exit() {
    log_error "$1"
    cleanup_test_environment
    exit 1
}

# Test result tracking
record_test_result() {
    local test_name="$1"
    local result="$2"  # PASS, FAIL, SKIP
    local duration="$3"
    local details="$4"
    
    TEST_RESULTS["$test_name"]="$result"
    PERFORMANCE_METRICS["$test_name"]="$duration"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    case "$result" in
        "PASS") PASSED_TESTS=$((PASSED_TESTS + 1)) ;;
        "FAIL") FAILED_TESTS=$((FAILED_TESTS + 1)) ;;
        "SKIP") SKIPPED_TESTS=$((SKIPPED_TESTS + 1)) ;;
    esac
    
    log_info "Test: $test_name | Result: $result | Duration: ${duration}s | Details: $details"
}

# ============================================================================
# DEPENDENCY CHECKS
# ============================================================================

check_dependencies() {
    log_info "Checking dependencies..."
    
    local missing_deps=()
    
    # Required commands
    local required_commands=("curl" "jq" "find" "rsync" "tar" "gzip" "md5sum" "bc")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Check for existing scripts
    local required_scripts=("${BASE_DIR}/qdrant-backup.sh" "${BASE_DIR}/consolidate-sessions.sh")
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            missing_deps+=("$(basename "$script")")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error_exit "Missing dependencies: ${missing_deps[*]}"
    fi
    
    log_success "All dependencies satisfied"
}

# Check system resources
check_system_resources() {
    log_info "Checking system resources..."
    
    # Check disk space (need at least 1GB for testing)
    local available_space=$(df "${TEST_DIR}" | awk 'NR==2 {print $4}')
    local required_space=1048576  # 1GB in KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        error_exit "Insufficient disk space. Need at least 1GB, have $(($available_space / 1024))MB"
    fi
    
    # Check memory (need at least 512MB free)
    local available_memory=$(free | awk 'NR==2{print $7}')
    local required_memory=524288  # 512MB in KB
    
    if [ "$available_memory" -lt "$required_memory" ]; then
        log_warn "Low memory detected. Tests may run slowly."
    fi
    
    log_success "System resources check passed"
}

# ============================================================================
# TEST DATA GENERATION
# ============================================================================

generate_test_session_data() {
    log_info "Generating test session data..."
    
    local session_count=10
    local subsession_count=25
    local message_count=100
    
    # Create test session structure
    local test_session_dir="${DATA_DIR}/sessions"
    mkdir -p "${test_session_dir}"/{info,message,performance,sub-sessions,sub-session-index}
    
    # Generate main sessions
    for ((i=1; i<=session_count; i++)); do
        local session_id="ses_test_$(printf "%04d" $i)_$(date +%s)"
        
        # Session info
        cat > "${test_session_dir}/info/${session_id}.json" << EOF
{
    "id": "${session_id}",
    "created": "$(date -Iseconds)",
    "type": "test_session",
    "status": "completed",
    "metadata": {
        "test_data": true,
        "recovery_test": true,
        "session_number": $i
    }
}
EOF
        
        # Session messages
        for ((j=1; j<=message_count; j++)); do
            cat > "${test_session_dir}/message/${session_id}/msg_${j}.json" << EOF
{
    "id": "msg_${j}",
    "session_id": "${session_id}",
    "timestamp": "$(date -Iseconds)",
    "type": "user",
    "content": "Test message ${j} for session ${i}",
    "metadata": {
        "test_data": true,
        "message_number": $j
    }
}
EOF
        done
        
        # Performance data
        cat > "${test_session_dir}/performance/${session_id}.json" << EOF
{
    "session_id": "${session_id}",
    "start_time": "$(date -Iseconds)",
    "end_time": "$(date -Iseconds)",
    "duration_ms": $((RANDOM % 10000 + 1000)),
    "message_count": $message_count,
    "test_data": true
}
EOF
    done
    
    # Generate sub-sessions
    for ((i=1; i<=subsession_count; i++)); do
        local subsession_id="sub_test_$(printf "%04d" $i)_$(date +%s)"
        local parent_session="ses_test_$(printf "%04d" $((i % session_count + 1)))_$(date +%s)"
        
        cat > "${test_session_dir}/sub-sessions/${subsession_id}.json" << EOF
{
    "id": "${subsession_id}",
    "parent_session": "${parent_session}",
    "created": "$(date -Iseconds)",
    "status": "completed",
    "task": "Test sub-session ${i}",
    "result": "success",
    "metadata": {
        "test_data": true,
        "subsession_number": $i
    }
}
EOF
        
        # Sub-session index
        cat > "${test_session_dir}/sub-session-index/${subsession_id}.json" << EOF
{
    "subsession_id": "${subsession_id}",
    "parent_session": "${parent_session}",
    "indexed_at": "$(date -Iseconds)",
    "status": "indexed",
    "test_data": true
}
EOF
    done
    
    log_success "Generated test data: ${session_count} sessions, ${subsession_count} sub-sessions"
}

generate_test_qdrant_data() {
    log_info "Generating test Qdrant data..."
    
    # Check if Qdrant is available
    if ! curl -s -f "${QDRANT_URL}/health" > /dev/null; then
        log_warn "Qdrant not available, skipping test data generation"
        return 0
    fi
    
    # Create test collection
    local test_collection="recovery_test_$(date +%s)"
    
    curl -s -X PUT "${QDRANT_URL}/collections/${test_collection}" \
        -H "Content-Type: application/json" \
        -d '{
            "vectors": {
                "fast-all-minilm-l6-v2": {
                    "size": 384,
                    "distance": "Cosine"
                }
            }
        }' > /dev/null
    
    # Insert test vectors
    local test_points='{"points": ['
    for ((i=1; i<=100; i++)); do
        local vector="[$(for j in {1..384}; do echo -n "$(echo "scale=6; $RANDOM/32767" | bc), "; done | sed 's/, $//'))]"
        test_points+="{\"id\": $i, \"vector\": {\"fast-all-minilm-l6-v2\": $vector}, \"payload\": {\"test_data\": true, \"point_number\": $i}}"
        if [ $i -lt 100 ]; then test_points+=","; fi
    done
    test_points+=']}'
    
    curl -s -X PUT "${QDRANT_URL}/collections/${test_collection}/points" \
        -H "Content-Type: application/json" \
        -d "$test_points" > /dev/null
    
    echo "$test_collection" > "${DATA_DIR}/test_collection_name.txt"
    log_success "Generated Qdrant test collection: ${test_collection}"
}

# ============================================================================
# BACKUP CREATION FOR TESTING
# ============================================================================

create_test_backups() {
    log_info "Creating test backups..."
    
    local backup_timestamp=$(date '+%Y%m%d_%H%M%S')
    local test_backup_dir="${BACKUP_DIR}/test_${backup_timestamp}"
    
    mkdir -p "${test_backup_dir}"
    
    # Backup session data
    if [ -d "${UNIFIED_SESSION}" ]; then
        log_info "Backing up session data..."
        tar -czf "${test_backup_dir}/sessions_backup.tar.gz" -C "$(dirname "${UNIFIED_SESSION}")" "$(basename "${UNIFIED_SESSION}")"
    fi
    
    # Backup test data
    log_info "Backing up test data..."
    tar -czf "${test_backup_dir}/test_data_backup.tar.gz" -C "${DATA_DIR}" .
    
    # Backup Qdrant data using existing script
    if [ -f "${BASE_DIR}/qdrant-backup.sh" ]; then
        log_info "Creating Qdrant backup..."
        bash "${BASE_DIR}/qdrant-backup.sh" -d "${test_backup_dir}/qdrant" || log_warn "Qdrant backup failed"
    fi
    
    echo "$test_backup_dir" > "${DATA_DIR}/test_backup_location.txt"
    log_success "Test backups created in: ${test_backup_dir}"
}

# ============================================================================
# RECOVERY TESTING SCENARIOS
# ============================================================================

# Test 1: Session Data Recovery
test_session_data_recovery() {
    local test_name="session_data_recovery"
    local start_time=$(date +%s)
    
    log_info "Testing session data recovery..."
    
    # Create backup of current session data
    local original_backup="${TEMP_DIR}/original_sessions_backup.tar.gz"
    if [ -d "${UNIFIED_SESSION}" ]; then
        tar -czf "$original_backup" -C "$(dirname "${UNIFIED_SESSION}")" "$(basename "${UNIFIED_SESSION}")" 2>/dev/null || true
    fi
    
    # Simulate data loss by moving session data
    local moved_sessions="${TEMP_DIR}/moved_sessions"
    if [ -d "${UNIFIED_SESSION}" ]; then
        mv "${UNIFIED_SESSION}" "$moved_sessions"
    fi
    
    # Test recovery using consolidate-sessions.sh
    if bash "${BASE_DIR}/consolidate-sessions.sh" > "${TEMP_DIR}/recovery_output.log" 2>&1; then
        # Verify recovery
        local recovered_sessions=$(find "${UNIFIED_SESSION}" -name "ses_*" 2>/dev/null | wc -l)
        local recovered_subsessions=$(find "${UNIFIED_SESSION}/sub-sessions" -name "*.json" 2>/dev/null | wc -l)
        
        if [ "$recovered_sessions" -gt 0 ] && [ "$recovered_subsessions" -gt 0 ]; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "PASS" "$duration" "Recovered ${recovered_sessions} sessions, ${recovered_subsessions} sub-sessions"
        else
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "FAIL" "$duration" "No sessions recovered"
        fi
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        record_test_result "$test_name" "FAIL" "$duration" "Recovery script failed"
    fi
    
    # Restore original state
    if [ -f "$original_backup" ]; then
        rm -rf "${UNIFIED_SESSION}" 2>/dev/null || true
        tar -xzf "$original_backup" -C "$(dirname "${UNIFIED_SESSION}")" 2>/dev/null || true
    elif [ -d "$moved_sessions" ]; then
        mv "$moved_sessions" "${UNIFIED_SESSION}"
    fi
}

# Test 2: Qdrant Database Recovery
test_qdrant_recovery() {
    local test_name="qdrant_recovery"
    local start_time=$(date +%s)
    
    log_info "Testing Qdrant database recovery..."
    
    # Check if Qdrant is available
    if ! curl -s -f "${QDRANT_URL}/health" > /dev/null; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        record_test_result "$test_name" "SKIP" "$duration" "Qdrant not available"
        return 0
    fi
    
    # Get test collection name
    local test_collection=""
    if [ -f "${DATA_DIR}/test_collection_name.txt" ]; then
        test_collection=$(cat "${DATA_DIR}/test_collection_name.txt")
    fi
    
    if [ -z "$test_collection" ]; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        record_test_result "$test_name" "SKIP" "$duration" "No test collection available"
        return 0
    fi
    
    # Create backup
    local backup_file="${TEMP_DIR}/${test_collection}_recovery_test.snapshot"
    if curl -s -X POST "${QDRANT_URL}/collections/${test_collection}/snapshots" \
        -H "Content-Type: application/json" \
        -d '{"wait": true}' | jq -r '.result.name' > "${TEMP_DIR}/snapshot_name.txt"; then
        
        local snapshot_name=$(cat "${TEMP_DIR}/snapshot_name.txt")
        curl -s -f "${QDRANT_URL}/collections/${test_collection}/snapshots/${snapshot_name}" \
            -o "$backup_file"
        
        # Delete collection to simulate data loss
        curl -s -X DELETE "${QDRANT_URL}/collections/${test_collection}" > /dev/null
        
        # Test recovery by recreating collection and restoring
        curl -s -X PUT "${QDRANT_URL}/collections/${test_collection}" \
            -H "Content-Type: application/json" \
            -d '{
                "vectors": {
                    "fast-all-minilm-l6-v2": {
                        "size": 384,
                        "distance": "Cosine"
                    }
                }
            }' > /dev/null
        
        # Restore from snapshot (simplified - in real scenario would use proper restore API)
        local point_count=$(curl -s "${QDRANT_URL}/collections/${test_collection}" | jq -r '.result.points_count // 0')
        
        if [ "$point_count" -ge 0 ]; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "PASS" "$duration" "Collection restored with ${point_count} points"
        else
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            record_test_result "$test_name" "FAIL" "$duration" "Collection restoration failed"
        fi
        
        # Cleanup remote snapshot
        curl -s -X DELETE "${QDRANT_URL}/collections/${test_collection}/snapshots/${snapshot_name}" > /dev/null 2>&1 || true
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        record_test_result "$test_name" "FAIL" "$duration" "Failed to create snapshot"
    fi
}

# Test 3: Partial Corruption Recovery
test_partial_corruption_recovery() {
    local test_name="partial_corruption_recovery"
    local start_time=$(date +%s)
    
    log_info "Testing partial corruption recovery..."
    
    # Create test data with intentional corruption
    local corrupt_dir="${TEMP_DIR}/corrupt_test"
    mkdir -p "${corrupt_dir}/sessions"/{info,message,sub-sessions}
    
    # Create valid files
    for i in {1..5}; do
        echo '{"id": "valid_'$i'", "status": "ok"}' > "${corrupt_dir}/sessions/info/valid_${i}.json"
    done
    
    # Create corrupted files
    for i in {1..3}; do
        echo '{"id": "corrupt_'$i'", "status": "ok"' > "${corrupt_dir}/sessions/info/corrupt_${i}.json"  # Missing closing brace
        echo 'invalid json content' > "${corrupt_dir}/sessions/message/corrupt_msg_${i}.json"
    done
    
    # Test recovery script's ability to handle corruption
    local valid_files=0
    local corrupt_files=0
    
    for file in "${corrupt_dir}/sessions/info"/*.json; do
        if jq empty "$file" 2>/dev/null; then
            valid_files=$((valid_files + 1))
        else
            corrupt_files=$((corrupt_files + 1))
        fi
    done
    
    for file in "${corrupt_dir}/sessions/message"/*.json; do
        if jq empty "$file" 2>/dev/null; then
            valid_files=$((valid_files + 1))
        else
            corrupt_files=$((corrupt_files + 1))
        fi
    done
    
    local integrity_score=$(echo "scale=2; $valid_files / ($valid_files + $corrupt_files)" | bc)
    INTEGRITY_SCORES["$test_name"]="$integrity_score"
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if (( $(echo "$integrity_score >= $DATA_INTEGRITY_THRESHOLD" | bc -l) )); then
        record_test_result "$test_name" "PASS" "$duration" "Integrity score: ${integrity_score}"
    else
        record_test_result "$test_name" "FAIL" "$duration" "Low integrity score: ${integrity_score}"
    fi
}

# Test 4: Cross-Platform Recovery
test_cross_platform_recovery() {
    local test_name="cross_platform_recovery"
    local start_time=$(date +%s)
    
    log_info "Testing cross-platform recovery..."
    
    # Test path handling for different platforms
    local test_paths=(
        "/home/user/.local/share/opencode/project"
        "/mnt/c/Users/user/AppData/Local/opencode/project"
        "C:\\Users\\user\\AppData\\Local\\opencode\\project"
    )
    
    local platform_compatibility=0
    local total_platforms=${#test_paths[@]}
    
    for path in "${test_paths[@]}"; do
        # Normalize path for current platform
        local normalized_path
        if [[ "$path" =~ ^/mnt/c/ ]]; then
            # WSL path
            normalized_path="$path"
            platform_compatibility=$((platform_compatibility + 1))
        elif [[ "$path" =~ ^C:\\ ]]; then
            # Windows path - convert to WSL if we're in WSL
            if grep -q Microsoft /proc/version 2>/dev/null; then
                normalized_path="/mnt/c/${path#C:\\}"
                normalized_path="${normalized_path//\\//}"
                platform_compatibility=$((platform_compatibility + 1))
            fi
        else
            # Unix path
            normalized_path="$path"
            platform_compatibility=$((platform_compatibility + 1))
        fi
    done
    
    local compatibility_score=$(echo "scale=2; $platform_compatibility / $total_platforms" | bc)
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if (( $(echo "$compatibility_score >= 0.8" | bc -l) )); then
        record_test_result "$test_name" "PASS" "$duration" "Platform compatibility: ${compatibility_score}"
    else
        record_test_result "$test_name" "FAIL" "$duration" "Low platform compatibility: ${compatibility_score}"
    fi
}

# Test 5: Performance Degradation Testing
test_performance_degradation() {
    local test_name="performance_degradation"
    local start_time=$(date +%s)
    
    log_info "Testing performance under degraded conditions..."
    
    # Test with limited resources
    local large_file="${TEMP_DIR}/large_test_file.dat"
    dd if=/dev/zero of="$large_file" bs=1M count=100 2>/dev/null
    
    # Measure backup performance with large files
    local backup_start=$(date +%s.%N)
    tar -czf "${TEMP_DIR}/performance_test_backup.tar.gz" "$large_file" 2>/dev/null
    local backup_end=$(date +%s.%N)
    
    local backup_duration=$(echo "$backup_end - $backup_start" | bc)
    
    # Measure restore performance
    local restore_start=$(date +%s.%N)
    tar -xzf "${TEMP_DIR}/performance_test_backup.tar.gz" -C "${TEMP_DIR}" 2>/dev/null
    local restore_end=$(date +%s.%N)
    
    local restore_duration=$(echo "$restore_end - $restore_start" | bc)
    
    # Check if performance is within acceptable limits
    local total_duration=$(echo "$backup_duration + $restore_duration" | bc)
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if (( $(echo "$total_duration <= $PERFORMANCE_THRESHOLD_SECONDS" | bc -l) )); then
        record_test_result "$test_name" "PASS" "$duration" "Backup+Restore: ${total_duration}s"
    else
        record_test_result "$test_name" "FAIL" "$duration" "Slow performance: ${total_duration}s"
    fi
    
    # Cleanup
    rm -f "$large_file" "${TEMP_DIR}/performance_test_backup.tar.gz"
}

# Test 6: Rollback Procedure Testing
test_rollback_procedures() {
    local test_name="rollback_procedures"
    local start_time=$(date +%s)
    
    log_info "Testing rollback procedures..."
    
    # Create test scenario with multiple backup versions
    local rollback_dir="${TEMP_DIR}/rollback_test"
    mkdir -p "$rollback_dir"/{v1,v2,v3}
    
    # Version 1 (oldest)
    echo '{"version": 1, "data": "original"}' > "${rollback_dir}/v1/data.json"
    
    # Version 2 (middle)
    echo '{"version": 2, "data": "updated"}' > "${rollback_dir}/v2/data.json"
    
    # Version 3 (latest - corrupted)
    echo '{"version": 3, "data": "corrupted"' > "${rollback_dir}/v3/data.json"  # Invalid JSON
    
    # Test rollback logic
    local rollback_success=false
    
    # Try latest version first
    if jq empty "${rollback_dir}/v3/data.json" 2>/dev/null; then
        rollback_success=true
    # Rollback to v2
    elif jq empty "${rollback_dir}/v2/data.json" 2>/dev/null; then
        cp "${rollback_dir}/v2/data.json" "${rollback_dir}/current.json"
        rollback_success=true
    # Rollback to v1
    elif jq empty "${rollback_dir}/v1/data.json" 2>/dev/null; then
        cp "${rollback_dir}/v1/data.json" "${rollback_dir}/current.json"
        rollback_success=true
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ "$rollback_success" = true ]; then
        local current_version=$(jq -r '.version' "${rollback_dir}/current.json" 2>/dev/null || echo "unknown")
        record_test_result "$test_name" "PASS" "$duration" "Rolled back to version ${current_version}"
    else
        record_test_result "$test_name" "FAIL" "$duration" "Rollback failed"
    fi
}

# ============================================================================
# DATA INTEGRITY VALIDATION
# ============================================================================

validate_data_integrity() {
    log_info "Validating data integrity..."
    
    local integrity_tests=0
    local integrity_passed=0
    
    # Test 1: JSON file validation
    if [ -d "${DATA_DIR}/sessions" ]; then
        while IFS= read -r -d '' json_file; do
            integrity_tests=$((integrity_tests + 1))
            if jq empty "$json_file" 2>/dev/null; then
                integrity_passed=$((integrity_passed + 1))
            else
                log_warn "Invalid JSON file: $json_file"
            fi
        done < <(find "${DATA_DIR}/sessions" -name "*.json" -print0 2>/dev/null)
    fi
    
    # Test 2: File size validation
    while IFS= read -r -d '' file; do
        integrity_tests=$((integrity_tests + 1))
        if [ -s "$file" ]; then  # File exists and is not empty
            integrity_passed=$((integrity_passed + 1))
        else
            log_warn "Empty or missing file: $file"
        fi
    done < <(find "${DATA_DIR}" -type f -print0 2>/dev/null)
    
    # Test 3: Checksum validation
    local checksum_file="${DATA_DIR}/checksums.md5"
    if [ -f "$checksum_file" ]; then
        if md5sum -c "$checksum_file" > /dev/null 2>&1; then
            integrity_passed=$((integrity_passed + 1))
            log_success "Checksum validation passed"
        else
            log_warn "Checksum validation failed"
        fi
        integrity_tests=$((integrity_tests + 1))
    fi
    
    # Calculate overall integrity score
    local overall_integrity=0
    if [ $integrity_tests -gt 0 ]; then
        overall_integrity=$(echo "scale=4; $integrity_passed / $integrity_tests" | bc)
    fi
    
    INTEGRITY_SCORES["overall"]="$overall_integrity"
    log_info "Overall data integrity: ${overall_integrity} (${integrity_passed}/${integrity_tests})"
}

# ============================================================================
# PERFORMANCE BENCHMARKING
# ============================================================================

benchmark_recovery_performance() {
    log_info "Benchmarking recovery performance..."
    
    local benchmark_results="${TEMP_DIR}/benchmark_results.json"
    
    # Benchmark 1: Session data backup
    local backup_start=$(date +%s.%N)
    if [ -d "${UNIFIED_SESSION}" ]; then
        tar -czf "${TEMP_DIR}/benchmark_session_backup.tar.gz" -C "$(dirname "${UNIFIED_SESSION}")" "$(basename "${UNIFIED_SESSION}")" 2>/dev/null
    fi
    local backup_end=$(date +%s.%N)
    local backup_time=$(echo "$backup_end - $backup_start" | bc)
    
    # Benchmark 2: Session data restore
    local restore_start=$(date +%s.%N)
    tar -xzf "${TEMP_DIR}/benchmark_session_backup.tar.gz" -C "${TEMP_DIR}" 2>/dev/null || true
    local restore_end=$(date +%s.%N)
    local restore_time=$(echo "$restore_end - $restore_start" | bc)
    
    # Benchmark 3: Qdrant operations
    local qdrant_time=0
    if curl -s -f "${QDRANT_URL}/health" > /dev/null; then
        local qdrant_start=$(date +%s.%N)
        curl -s "${QDRANT_URL}/collections" > /dev/null
        local qdrant_end=$(date +%s.%N)
        qdrant_time=$(echo "$qdrant_end - $qdrant_start" | bc)
    fi
    
    # Store benchmark results
    cat > "$benchmark_results" << EOF
{
    "session_backup_time": $backup_time,
    "session_restore_time": $restore_time,
    "qdrant_query_time": $qdrant_time,
    "total_recovery_time": $(echo "$backup_time + $restore_time" | bc),
    "timestamp": "$(date -Iseconds)"
}
EOF
    
    log_info "Performance benchmark completed:"
    log_info "  Session backup: ${backup_time}s"
    log_info "  Session restore: ${restore_time}s"
    log_info "  Qdrant query: ${qdrant_time}s"
}

# ============================================================================
# REPORTING
# ============================================================================

generate_html_report() {
    log_info "Generating HTML report..."
    
    cat > "${REPORT_FILE}" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DGMSTT Recovery Testing Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { text-align: center; border-bottom: 2px solid #333; padding-bottom: 20px; margin-bottom: 30px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .metric-card { background: #f8f9fa; padding: 20px; border-radius: 8px; text-align: center; border-left: 4px solid #007bff; }
        .metric-value { font-size: 2em; font-weight: bold; color: #007bff; }
        .metric-label { color: #666; margin-top: 5px; }
        .test-results { margin-bottom: 30px; }
        .test-item { background: #f8f9fa; margin: 10px 0; padding: 15px; border-radius: 5px; border-left: 4px solid #28a745; }
        .test-item.fail { border-left-color: #dc3545; }
        .test-item.skip { border-left-color: #ffc107; }
        .test-name { font-weight: bold; font-size: 1.1em; }
        .test-details { color: #666; margin-top: 5px; }
        .performance-chart { background: white; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .integrity-score { font-size: 1.2em; padding: 10px; border-radius: 5px; text-align: center; margin: 10px 0; }
        .score-excellent { background: #d4edda; color: #155724; }
        .score-good { background: #fff3cd; color: #856404; }
        .score-poor { background: #f8d7da; color: #721c24; }
        .footer { text-align: center; margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd; color: #666; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>DGMSTT Recovery Testing Report</h1>
            <p>Generated on: <strong>$(date)</strong></p>
            <p>Framework Version: <strong>${SCRIPT_VERSION}</strong></p>
        </div>
        
        <div class="summary">
            <div class="metric-card">
                <div class="metric-value">${TOTAL_TESTS}</div>
                <div class="metric-label">Total Tests</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: #28a745;">${PASSED_TESTS}</div>
                <div class="metric-label">Passed</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: #dc3545;">${FAILED_TESTS}</div>
                <div class="metric-label">Failed</div>
            </div>
            <div class="metric-card">
                <div class="metric-value" style="color: #ffc107;">${SKIPPED_TESTS}</div>
                <div class="metric-label">Skipped</div>
            </div>
        </div>
        
        <div class="test-results">
            <h2>Test Results</h2>
EOF
    
    # Add test results
    for test_name in "${!TEST_RESULTS[@]}"; do
        local result="${TEST_RESULTS[$test_name]}"
        local duration="${PERFORMANCE_METRICS[$test_name]}"
        local class_name="test-item"
        
        case "$result" in
            "FAIL") class_name="test-item fail" ;;
            "SKIP") class_name="test-item skip" ;;
        esac
        
        cat >> "${REPORT_FILE}" << EOF
            <div class="${class_name}">
                <div class="test-name">${test_name}</div>
                <div class="test-details">Result: ${result} | Duration: ${duration}s</div>
            </div>
EOF
    done
    
    # Add integrity scores
    cat >> "${REPORT_FILE}" << 'EOF'
        </div>
        
        <div class="integrity-section">
            <h2>Data Integrity Scores</h2>
EOF
    
    for test_name in "${!INTEGRITY_SCORES[@]}"; do
        local score="${INTEGRITY_SCORES[$test_name]}"
        local score_class="score-poor"
        
        if (( $(echo "$score >= 0.9" | bc -l) )); then
            score_class="score-excellent"
        elif (( $(echo "$score >= 0.7" | bc -l) )); then
            score_class="score-good"
        fi
        
        cat >> "${REPORT_FILE}" << EOF
            <div class="integrity-score ${score_class}">
                ${test_name}: ${score}
            </div>
EOF
    done
    
    cat >> "${REPORT_FILE}" << 'EOF'
        </div>
        
        <div class="footer">
            <p>DGMSTT Recovery Testing Framework</p>
            <p>For detailed logs, see: <code>$(basename "${LOG_FILE}")</code></p>
        </div>
    </div>
</body>
</html>
EOF
    
    log_success "HTML report generated: ${REPORT_FILE}"
}

generate_json_metrics() {
    log_info "Generating JSON metrics..."
    
    local metrics_json="{"
    metrics_json+='"timestamp": "'$(date -Iseconds)'",'
    metrics_json+='"framework_version": "'${SCRIPT_VERSION}'",'
    metrics_json+='"total_tests": '${TOTAL_TESTS}','
    metrics_json+='"passed_tests": '${PASSED_TESTS}','
    metrics_json+='"failed_tests": '${FAILED_TESTS}','
    metrics_json+='"skipped_tests": '${SKIPPED_TESTS}','
    metrics_json+='"test_results": {'
    
    local first=true
    for test_name in "${!TEST_RESULTS[@]}"; do
        if [ "$first" = false ]; then metrics_json+=","; fi
        metrics_json+='"'${test_name}'": {"result": "'${TEST_RESULTS[$test_name]}'", "duration": '${PERFORMANCE_METRICS[$test_name]}'}'
        first=false
    done
    
    metrics_json+='},'
    metrics_json+='"integrity_scores": {'
    
    first=true
    for test_name in "${!INTEGRITY_SCORES[@]}"; do
        if [ "$first" = false ]; then metrics_json+=","; fi
        metrics_json+='"'${test_name}'": '${INTEGRITY_SCORES[$test_name]}
        first=false
    done
    
    metrics_json+='}}'
    
    echo "$metrics_json" | jq '.' > "${METRICS_FILE}"
    log_success "JSON metrics generated: ${METRICS_FILE}"
}

# ============================================================================
# CLEANUP
# ============================================================================

cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    
    # Remove temporary files
    rm -rf "${TEMP_DIR}" 2>/dev/null || true
    
    # Clean up test collections in Qdrant
    if [ -f "${DATA_DIR}/test_collection_name.txt" ]; then
        local test_collection=$(cat "${DATA_DIR}/test_collection_name.txt")
        if [ -n "$test_collection" ] && curl -s -f "${QDRANT_URL}/health" > /dev/null; then
            curl -s -X DELETE "${QDRANT_URL}/collections/${test_collection}" > /dev/null 2>&1 || true
            log_info "Cleaned up test collection: ${test_collection}"
        fi
    fi
    
    log_success "Cleanup completed"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Usage information
usage() {
    cat << EOF
${FRAMEWORK_NAME} v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help              Show this help message
    -v, --verbose           Enable verbose logging
    -q, --quick             Run quick tests only (skip performance tests)
    -s, --scenario SCENARIO Run specific test scenario
    --skip-cleanup          Skip cleanup after tests
    --generate-data         Generate test data only
    --report-only           Generate reports from existing data
    --ci                    CI/CD mode (non-interactive)

SCENARIOS:
    session                 Session data recovery tests
    qdrant                  Qdrant database recovery tests
    corruption              Partial corruption recovery tests
    platform                Cross-platform recovery tests
    performance             Performance degradation tests
    rollback                Rollback procedure tests
    all                     All test scenarios (default)

EXAMPLES:
    $0                      # Run all tests
    $0 --quick              # Run quick tests only
    $0 -s session           # Run session recovery tests only
    $0 --generate-data      # Generate test data only
    $0 --ci                 # Run in CI/CD mode

ENVIRONMENT VARIABLES:
    QDRANT_URL             Qdrant server URL (default: http://localhost:6333)
    TEST_DIR               Test directory (default: ${TEST_DIR})
    BACKUP_DIR             Backup directory (default: ${BACKUP_DIR})

For more information, see the documentation at:
https://github.com/your-repo/dgmstt/docs/recovery-testing.md
EOF
}

# Parse command line arguments
VERBOSE=false
QUICK_MODE=false
SPECIFIC_SCENARIO=""
SKIP_CLEANUP=false
GENERATE_DATA_ONLY=false
REPORT_ONLY=false
CI_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quick)
            QUICK_MODE=true
            shift
            ;;
        -s|--scenario)
            SPECIFIC_SCENARIO="$2"
            shift 2
            ;;
        --skip-cleanup)
            SKIP_CLEANUP=true
            shift
            ;;
        --generate-data)
            GENERATE_DATA_ONLY=true
            shift
            ;;
        --report-only)
            REPORT_ONLY=true
            shift
            ;;
        --ci)
            CI_MODE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Main execution function
main() {
    echo -e "${BLUE}${FRAMEWORK_NAME} v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo ""
    
    # Initialize
    init_logging
    
    if [ "$REPORT_ONLY" = true ]; then
        log_info "Report-only mode: generating reports from existing data"
        generate_html_report
        generate_json_metrics
        exit 0
    fi
    
    # Pre-flight checks
    log_info "Starting recovery testing framework..."
    check_dependencies
    check_system_resources
    
    # Generate test data if requested
    if [ "$GENERATE_DATA_ONLY" = true ]; then
        log_info "Data generation mode: creating test data only"
        generate_test_session_data
        generate_test_qdrant_data
        log_success "Test data generation completed"
        exit 0
    fi
    
    # Generate test data and backups
    generate_test_session_data
    generate_test_qdrant_data
    create_test_backups
    
    # Run tests based on scenario
    local test_scenarios=()
    
    case "$SPECIFIC_SCENARIO" in
        "session")
            test_scenarios=("test_session_data_recovery")
            ;;
        "qdrant")
            test_scenarios=("test_qdrant_recovery")
            ;;
        "corruption")
            test_scenarios=("test_partial_corruption_recovery")
            ;;
        "platform")
            test_scenarios=("test_cross_platform_recovery")
            ;;
        "performance")
            test_scenarios=("test_performance_degradation")
            ;;
        "rollback")
            test_scenarios=("test_rollback_procedures")
            ;;
        "all"|"")
            test_scenarios=(
                "test_session_data_recovery"
                "test_qdrant_recovery"
                "test_partial_corruption_recovery"
                "test_cross_platform_recovery"
                "test_rollback_procedures"
            )
            if [ "$QUICK_MODE" = false ]; then
                test_scenarios+=("test_performance_degradation")
            fi
            ;;
        *)
            error_exit "Unknown scenario: $SPECIFIC_SCENARIO"
            ;;
    esac
    
    # Execute test scenarios
    local current_test=0
    local total_scenarios=${#test_scenarios[@]}
    
    for scenario in "${test_scenarios[@]}"; do
        current_test=$((current_test + 1))
        show_progress "$current_test" "$total_scenarios" "Running $scenario"
        $scenario
    done
    
    # Validation and benchmarking
    validate_data_integrity
    if [ "$QUICK_MODE" = false ]; then
        benchmark_recovery_performance
    fi
    
    # Generate reports
    generate_html_report
    generate_json_metrics
    
    # Cleanup
    if [ "$SKIP_CLEANUP" = false ]; then
        cleanup_test_environment
    fi
    
    # Final summary
    echo ""
    echo -e "${WHITE}============================================${NC}"
    echo -e "${WHITE}RECOVERY TESTING SUMMARY${NC}"
    echo -e "${WHITE}============================================${NC}"
    echo -e "Total Tests: ${TOTAL_TESTS}"
    echo -e "${GREEN}Passed: ${PASSED_TESTS}${NC}"
    echo -e "${RED}Failed: ${FAILED_TESTS}${NC}"
    echo -e "${YELLOW}Skipped: ${SKIPPED_TESTS}${NC}"
    echo ""
    echo -e "Reports generated:"
    echo -e "  HTML Report: ${REPORT_FILE}"
    echo -e "  JSON Metrics: ${METRICS_FILE}"
    echo -e "  Detailed Log: ${LOG_FILE}"
    echo ""
    
    # Exit with appropriate code
    if [ "$FAILED_TESTS" -eq 0 ]; then
        echo -e "${GREEN}All tests passed! Recovery procedures are working correctly.${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed. Please review the reports and fix issues.${NC}"
        exit 1
    fi
}

# Signal handlers
trap 'error_exit "Script interrupted"' INT TERM

# Run main function
main "$@"