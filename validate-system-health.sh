#!/bin/bash

# DGMSTT System Health Validation Script
# Comprehensive health check for all system components

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
TIMEOUT=10
LOG_FILE="/tmp/health-check-$(date +%Y%m%d-%H%M%S).log"

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

echo -e "${BLUE}=== DGMSTT System Health Check ===${NC}"
echo "Log file: $LOG_FILE"
echo ""

# Initialize log
echo "DGMSTT System Health Check - $(date)" > "$LOG_FILE"

# Health check results
declare -A health_results

# Function to check HTTP endpoint
check_endpoint() {
    local name="$1"
    local url="$2"
    local expected_status="${3:-200}"
    
    log_info "Checking $name endpoint: $url"
    
    if curl -s -f --max-time $TIMEOUT "$url" > /dev/null 2>&1; then
        health_results["$name"]="HEALTHY"
        echo -e "${GREEN}✓ $name healthy${NC}"
        log_success "$name endpoint is healthy"
        return 0
    else
        health_results["$name"]="UNHEALTHY"
        echo -e "${RED}✗ $name unhealthy${NC}"
        log_error "$name endpoint is unhealthy"
        return 1
    fi
}

# Function to check container status
check_containers() {
    log_info "Checking Docker container status..."
    echo -e "${YELLOW}Container Status:${NC}"
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "docker-compose not found"
        echo -e "${RED}✗ docker-compose not available${NC}"
        return 1
    fi
    
    # Get container status
    local containers_output
    containers_output=$(docker-compose ps --format "table {{.Name}}\t{{.State}}\t{{.Status}}" 2>/dev/null || echo "No containers found")
    
    echo "$containers_output"
    log_info "Container status: $containers_output"
    
    # Check if all expected containers are running
    local expected_containers=("opencode" "dgm" "qdrant" "redis" "postgres")
    local all_running=true
    
    for container in "${expected_containers[@]}"; do
        if docker-compose ps "$container" 2>/dev/null | grep -q "Up"; then
            echo -e "${GREEN}✓ $container running${NC}"
            health_results["container_$container"]="RUNNING"
        else
            echo -e "${RED}✗ $container not running${NC}"
            health_results["container_$container"]="STOPPED"
            all_running=false
        fi
    done
    
    if $all_running; then
        log_success "All containers are running"
        return 0
    else
        log_error "Some containers are not running"
        return 1
    fi
}

# Function to check service endpoints
check_services() {
    log_info "Checking service endpoints..."
    echo -e "${YELLOW}Service Health:${NC}"
    
    # Check OpenCode
    check_endpoint "OpenCode" "http://localhost:3000/health"
    
    # Check DGM
    check_endpoint "DGM" "http://localhost:8000/health"
    
    # Check Qdrant
    check_endpoint "Qdrant" "http://localhost:6333/health"
    
    # Check Redis (using ping)
    log_info "Checking Redis connectivity..."
    if docker-compose exec -T redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
        health_results["Redis"]="HEALTHY"
        echo -e "${GREEN}✓ Redis healthy${NC}"
        log_success "Redis is responding"
    else
        health_results["Redis"]="UNHEALTHY"
        echo -e "${RED}✗ Redis unhealthy${NC}"
        log_error "Redis is not responding"
    fi
    
    # Check PostgreSQL
    log_info "Checking PostgreSQL connectivity..."
    if docker-compose exec -T postgres pg_isready -U opencode_dgm 2>/dev/null | grep -q "accepting connections"; then
        health_results["PostgreSQL"]="HEALTHY"
        echo -e "${GREEN}✓ PostgreSQL healthy${NC}"
        log_success "PostgreSQL is accepting connections"
    else
        health_results["PostgreSQL"]="UNHEALTHY"
        echo -e "${RED}✗ PostgreSQL unhealthy${NC}"
        log_error "PostgreSQL is not accepting connections"
    fi
}

# Function to check data integrity
check_data_integrity() {
    log_info "Checking data integrity..."
    echo -e "${YELLOW}Data Integrity:${NC}"
    
    # Check session data
    local session_dir="$HOME/.local/share/opencode/project/storage/session"
    if [[ -d "$session_dir" ]]; then
        local session_count=$(find "$session_dir/message" -name "ses_*" 2>/dev/null | wc -l)
        local subsession_count=$(find "$session_dir/sub-sessions" -name "*.json" 2>/dev/null | wc -l)
        
        echo -e "${GREEN}✓ Session storage accessible${NC}"
        echo "  Sessions: $session_count"
        echo "  Sub-sessions: $subsession_count"
        log_success "Session data accessible: $session_count sessions, $subsession_count sub-sessions"
        health_results["session_data"]="ACCESSIBLE"
    else
        echo -e "${RED}✗ Session storage not found${NC}"
        log_error "Session storage directory not found: $session_dir"
        health_results["session_data"]="MISSING"
    fi
    
    # Check Qdrant collections
    if [[ "${health_results[Qdrant]}" == "HEALTHY" ]]; then
        local collections_response
        collections_response=$(curl -s "http://localhost:6333/collections" 2>/dev/null || echo '{"result":{"collections":[]}}')
        local collection_count=$(echo "$collections_response" | jq -r '.result.collections | length' 2>/dev/null || echo "0")
        
        if [[ "$collection_count" -gt 0 ]]; then
            echo -e "${GREEN}✓ Qdrant collections accessible${NC}"
            echo "  Collections: $collection_count"
            log_success "Qdrant collections accessible: $collection_count collections"
            health_results["qdrant_data"]="ACCESSIBLE"
        else
            echo -e "${YELLOW}⚠ No Qdrant collections found${NC}"
            log_warn "No Qdrant collections found"
            health_results["qdrant_data"]="EMPTY"
        fi
    else
        echo -e "${RED}✗ Cannot check Qdrant data (service unhealthy)${NC}"
        health_results["qdrant_data"]="INACCESSIBLE"
    fi
}

# Function to check system resources
check_resources() {
    log_info "Checking system resources..."
    echo -e "${YELLOW}System Resources:${NC}"
    
    # Check disk space
    local disk_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ "$disk_usage" -lt 90 ]]; then
        echo -e "${GREEN}✓ Disk space OK (${disk_usage}% used)${NC}"
        health_results["disk_space"]="OK"
    else
        echo -e "${RED}✗ Disk space critical (${disk_usage}% used)${NC}"
        health_results["disk_space"]="CRITICAL"
    fi
    
    # Check memory usage
    local mem_usage=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ "$mem_usage" -lt 90 ]]; then
        echo -e "${GREEN}✓ Memory usage OK (${mem_usage}% used)${NC}"
        health_results["memory"]="OK"
    else
        echo -e "${YELLOW}⚠ Memory usage high (${mem_usage}% used)${NC}"
        health_results["memory"]="HIGH"
    fi
    
    # Check Docker resources
    if command -v docker &> /dev/null; then
        local docker_df_output=$(docker system df --format "table {{.Type}}\t{{.Size}}\t{{.Reclaimable}}" 2>/dev/null || echo "Docker not accessible")
        echo "Docker Storage:"
        echo "$docker_df_output"
        log_info "Docker storage: $docker_df_output"
    fi
}

# Function to run quick functional tests
run_functional_tests() {
    log_info "Running functional tests..."
    echo -e "${YELLOW}Functional Tests:${NC}"
    
    # Test session creation (if possible)
    if [[ "${health_results[OpenCode]}" == "HEALTHY" ]]; then
        echo -e "${GREEN}✓ OpenCode service responsive${NC}"
    fi
    
    # Test Qdrant operations (if possible)
    if [[ "${health_results[Qdrant]}" == "HEALTHY" ]]; then
        # Try to get cluster info
        if curl -s "http://localhost:6333/cluster" > /dev/null 2>&1; then
            echo -e "${GREEN}✓ Qdrant cluster info accessible${NC}"
            health_results["qdrant_cluster"]="ACCESSIBLE"
        else
            echo -e "${YELLOW}⚠ Qdrant cluster info not accessible${NC}"
            health_results["qdrant_cluster"]="INACCESSIBLE"
        fi
    fi
}

# Function to generate health report
generate_health_report() {
    echo ""
    echo -e "${BLUE}=== Health Check Summary ===${NC}"
    
    local total_checks=0
    local healthy_checks=0
    local warning_checks=0
    local critical_checks=0
    
    for component in "${!health_results[@]}"; do
        local status="${health_results[$component]}"
        total_checks=$((total_checks + 1))
        
        case "$status" in
            "HEALTHY"|"RUNNING"|"ACCESSIBLE"|"OK")
                healthy_checks=$((healthy_checks + 1))
                echo -e "${GREEN}✓ $component: $status${NC}"
                ;;
            "HIGH"|"EMPTY"|"INACCESSIBLE")
                warning_checks=$((warning_checks + 1))
                echo -e "${YELLOW}⚠ $component: $status${NC}"
                ;;
            *)
                critical_checks=$((critical_checks + 1))
                echo -e "${RED}✗ $component: $status${NC}"
                ;;
        esac
    done
    
    echo ""
    echo "Summary:"
    echo "  Total checks: $total_checks"
    echo -e "  ${GREEN}Healthy: $healthy_checks${NC}"
    echo -e "  ${YELLOW}Warnings: $warning_checks${NC}"
    echo -e "  ${RED}Critical: $critical_checks${NC}"
    
    log_info "Health check summary: $total_checks total, $healthy_checks healthy, $warning_checks warnings, $critical_checks critical"
    
    # Overall system status
    if [[ $critical_checks -eq 0 ]]; then
        if [[ $warning_checks -eq 0 ]]; then
            echo -e "${GREEN}Overall Status: HEALTHY${NC}"
            log_success "Overall system status: HEALTHY"
            return 0
        else
            echo -e "${YELLOW}Overall Status: DEGRADED${NC}"
            log_warn "Overall system status: DEGRADED"
            return 1
        fi
    else
        echo -e "${RED}Overall Status: CRITICAL${NC}"
        log_error "Overall system status: CRITICAL"
        return 2
    fi
}

# Main health check function
main() {
    local start_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_info "Starting DGMSTT system health check..."
    
    # Run all health checks
    check_containers
    echo ""
    
    check_services
    echo ""
    
    check_data_integrity
    echo ""
    
    check_resources
    echo ""
    
    run_functional_tests
    echo ""
    
    # Generate final report
    generate_health_report
    
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    log_info "Health check completed. Start: $start_time, End: $end_time"
    
    echo ""
    echo "Detailed log: $LOG_FILE"
}

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -q, --quick         Quick health check (containers and endpoints only)"
    echo "  -v, --verbose       Verbose output"
    echo "  --timeout N         Set timeout for endpoint checks (default: 10s)"
    echo ""
    echo "Examples:"
    echo "  $0                  # Full health check"
    echo "  $0 --quick          # Quick health check"
    echo "  $0 --timeout 30     # Extended timeout"
}

# Parse command line arguments
QUICK_MODE=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            usage
            exit 0
            ;;
        -q|--quick)
            QUICK_MODE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Run health check
if $QUICK_MODE; then
    log_info "Running quick health check..."
    check_containers
    echo ""
    check_services
    echo ""
    generate_health_report
else
    main
fi