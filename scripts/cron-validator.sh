#!/bin/bash

# Comprehensive Cron Syntax Validator
# Author: DGMSTT Project
# Description: Validates cron expressions with comprehensive syntax checking,
#              human-readable descriptions, and advanced features
# Version: 1.0.0

set -euo pipefail

# Script configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="${SCRIPT_DIR}/../logs/cron-validator.log"

# Global variables
VERBOSE=false
QUIET=false
JSON_OUTPUT=false
TIMEZONE=""
SHOW_NEXT_RUNS=5
EXIT_CODE=0

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create log directory if it doesn't exist
    mkdir -p "$(dirname "$LOG_FILE")"
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    if [[ "$QUIET" == false ]]; then
        case "$level" in
            "ERROR")   echo -e "${RED}[ERROR]${NC} $message" >&2 ;;
            "WARN")    echo -e "${YELLOW}[WARN]${NC} $message" >&2 ;;
            "INFO")    echo -e "${GREEN}[INFO]${NC} $message" ;;
            "DEBUG")   [[ "$VERBOSE" == true ]] && echo -e "${BLUE}[DEBUG]${NC} $message" ;;
            *)         echo "$message" ;;
        esac
    fi
}

# Error handling
error_exit() {
    log "ERROR" "$1"
    exit "${2:-2}"
}

# Month name mappings
declare -A MONTH_NAMES=(
    ["JAN"]=1 ["FEB"]=2 ["MAR"]=3 ["APR"]=4 ["MAY"]=5 ["JUN"]=6
    ["JUL"]=7 ["AUG"]=8 ["SEP"]=9 ["OCT"]=10 ["NOV"]=11 ["DEC"]=12
    ["JANUARY"]=1 ["FEBRUARY"]=2 ["MARCH"]=3 ["APRIL"]=4
    ["JUNE"]=6 ["JULY"]=7 ["AUGUST"]=8 ["SEPTEMBER"]=9
    ["OCTOBER"]=10 ["NOVEMBER"]=11 ["DECEMBER"]=12
)

# Weekday name mappings
declare -A WEEKDAY_NAMES=(
    ["SUN"]=0 ["MON"]=1 ["TUE"]=2 ["WED"]=3 ["THU"]=4 ["FRI"]=5 ["SAT"]=6
    ["SUNDAY"]=0 ["MONDAY"]=1 ["TUESDAY"]=2 ["WEDNESDAY"]=3
    ["THURSDAY"]=4 ["FRIDAY"]=5 ["SATURDAY"]=6
)

# Cron shortcuts
declare -A CRON_SHORTCUTS=(
    ["@yearly"]="0 0 1 1 *"
    ["@annually"]="0 0 1 1 *"
    ["@monthly"]="0 0 1 * *"
    ["@weekly"]="0 0 * * 0"
    ["@daily"]="0 0 * * *"
    ["@midnight"]="0 0 * * *"
    ["@hourly"]="0 * * * *"
    ["@reboot"]="@reboot"
)

# Field validation ranges
declare -A FIELD_RANGES=(
    ["second"]="0-59"
    ["minute"]="0-59"
    ["hour"]="0-23"
    ["day"]="1-31"
    ["month"]="1-12"
    ["weekday"]="0-7"
)

# Field names for human-readable output
declare -A FIELD_NAMES=(
    [0]="second"
    [1]="minute"
    [2]="hour"
    [3]="day"
    [4]="month"
    [5]="weekday"
)

# Validation result structure
declare -A VALIDATION_RESULT=(
    ["valid"]=true
    ["warnings"]=""
    ["errors"]=""
    ["description"]=""
    ["next_runs"]=""
    ["frequency"]=""
    ["performance"]=""
)

# Convert named values to numbers
convert_named_values() {
    local field="$1"
    local value="$2"
    
    case "$field" in
        "month")
            if [[ -n "${MONTH_NAMES[$value]:-}" ]]; then
                echo "${MONTH_NAMES[$value]}"
                return 0
            fi
            ;;
        "weekday")
            if [[ -n "${WEEKDAY_NAMES[$value]:-}" ]]; then
                echo "${WEEKDAY_NAMES[$value]}"
                return 0
            fi
            ;;
    esac
    
    echo "$value"
}

# Check if value is in valid range
is_in_range() {
    local field="$1"
    local value="$2"
    local range="${FIELD_RANGES[$field]}"
    local min="${range%-*}"
    local max="${range#*-}"
    
    if [[ "$value" =~ ^[0-9]+$ ]] && [[ "$value" -ge "$min" ]] && [[ "$value" -le "$max" ]]; then
        return 0
    fi
    
    # Special case for weekday: 7 is also valid (Sunday)
    if [[ "$field" == "weekday" ]] && [[ "$value" == "7" ]]; then
        return 0
    fi
    
    return 1
}

# Validate step values (e.g., */5, 1-10/2)
validate_step() {
    local field="$1"
    local expression="$2"
    
    if [[ "$expression" =~ ^(.+)/([0-9]+)$ ]]; then
        local base="${BASH_REMATCH[1]}"
        local step="${BASH_REMATCH[2]}"
        
        # Validate step value
        if [[ "$step" -eq 0 ]]; then
            VALIDATION_RESULT["errors"]+="Step value cannot be zero in field '$field'. "
            return 1
        fi
        
        # Validate base (can be *, range, or single value)
        if [[ "$base" == "*" ]]; then
            return 0
        elif [[ "$base" =~ ^([0-9]+)-([0-9]+)$ ]]; then
            local start="${BASH_REMATCH[1]}"
            local end="${BASH_REMATCH[2]}"
            
            if ! is_in_range "$field" "$start" || ! is_in_range "$field" "$end"; then
                VALIDATION_RESULT["errors"]+="Invalid range in step expression '$expression' for field '$field'. "
                return 1
            fi
            
            if [[ "$start" -gt "$end" ]]; then
                VALIDATION_RESULT["errors"]+="Invalid range: start ($start) > end ($end) in field '$field'. "
                return 1
            fi
        elif [[ "$base" =~ ^[0-9]+$ ]]; then
            if ! is_in_range "$field" "$base"; then
                VALIDATION_RESULT["errors"]+="Invalid base value '$base' in step expression for field '$field'. "
                return 1
            fi
        else
            VALIDATION_RESULT["errors"]+="Invalid step base '$base' in field '$field'. "
            return 1
        fi
    fi
    
    return 0
}

# Validate range expressions (e.g., 1-5, MON-FRI)
validate_range() {
    local field="$1"
    local expression="$2"
    
    if [[ "$expression" =~ ^(.+)-(.+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        
        # Convert named values
        start=$(convert_named_values "$field" "$start")
        end=$(convert_named_values "$field" "$end")
        
        if ! is_in_range "$field" "$start" || ! is_in_range "$field" "$end"; then
            VALIDATION_RESULT["errors"]+="Invalid range values in '$expression' for field '$field'. "
            return 1
        fi
        
        if [[ "$start" -gt "$end" ]]; then
            VALIDATION_RESULT["errors"]+="Invalid range: start ($start) > end ($end) in field '$field'. "
            return 1
        fi
    fi
    
    return 0
}

# Validate list expressions (e.g., 1,3,5)
validate_list() {
    local field="$1"
    local expression="$2"
    
    IFS=',' read -ra VALUES <<< "$expression"
    for value in "${VALUES[@]}"; do
        value=$(echo "$value" | xargs) # trim whitespace
        
        # Handle different value types
        if [[ "$value" == "*" ]] || [[ "$value" == "?" ]]; then
            continue
        elif [[ "$value" =~ / ]]; then
            validate_step "$field" "$value" || return 1
        elif [[ "$value" =~ - ]]; then
            validate_range "$field" "$value" || return 1
        else
            # Single value
            value=$(convert_named_values "$field" "$value")
            if ! is_in_range "$field" "$value"; then
                VALIDATION_RESULT["errors"]+="Invalid value '$value' for field '$field'. "
                return 1
            fi
        fi
    done
    
    return 0
}

# Validate special characters (L, W, #)
validate_special_chars() {
    local field="$1"
    local expression="$2"
    
    # L (last) - only valid for day and weekday fields
    if [[ "$expression" =~ L ]]; then
        if [[ "$field" != "day" ]] && [[ "$field" != "weekday" ]]; then
            VALIDATION_RESULT["errors"]+="'L' modifier only valid for day and weekday fields, found in '$field'. "
            return 1
        fi
        
        # Validate L usage patterns
        if [[ "$field" == "weekday" ]] && [[ "$expression" =~ ^[0-7]L$ ]]; then
            # Valid: 5L (last Friday)
            local day="${expression%L}"
            if ! is_in_range "weekday" "$day"; then
                VALIDATION_RESULT["errors"]+="Invalid weekday '$day' with L modifier. "
                return 1
            fi
        elif [[ "$field" == "day" ]] && [[ "$expression" == "L" ]]; then
            # Valid: L (last day of month)
            :
        else
            VALIDATION_RESULT["errors"]+="Invalid L modifier usage: '$expression' in field '$field'. "
            return 1
        fi
    fi
    
    # W (weekday) - only valid for day field
    if [[ "$expression" =~ W ]]; then
        if [[ "$field" != "day" ]]; then
            VALIDATION_RESULT["errors"]+="'W' modifier only valid for day field, found in '$field'. "
            return 1
        fi
        
        if [[ "$expression" =~ ^([0-9]+)W$ ]]; then
            local day="${BASH_REMATCH[1]}"
            if ! is_in_range "day" "$day"; then
                VALIDATION_RESULT["errors"]+="Invalid day '$day' with W modifier. "
                return 1
            fi
        elif [[ "$expression" != "LW" ]]; then
            VALIDATION_RESULT["errors"]+="Invalid W modifier usage: '$expression'. "
            return 1
        fi
    fi
    
    # # (nth occurrence) - only valid for weekday field
    if [[ "$expression" =~ \# ]]; then
        if [[ "$field" != "weekday" ]]; then
            VALIDATION_RESULT["errors"]+="'#' modifier only valid for weekday field, found in '$field'. "
            return 1
        fi
        
        if [[ "$expression" =~ ^([0-7])#([1-5])$ ]]; then
            local day="${BASH_REMATCH[1]}"
            local occurrence="${BASH_REMATCH[2]}"
            
            if ! is_in_range "weekday" "$day"; then
                VALIDATION_RESULT["errors"]+="Invalid weekday '$day' with # modifier. "
                return 1
            fi
            
            if [[ "$occurrence" -lt 1 ]] || [[ "$occurrence" -gt 5 ]]; then
                VALIDATION_RESULT["errors"]+="Invalid occurrence '$occurrence' with # modifier (must be 1-5). "
                return 1
            fi
        else
            VALIDATION_RESULT["errors"]+="Invalid # modifier usage: '$expression'. "
            return 1
        fi
    fi
    
    return 0
}

# Validate a single cron field
validate_field() {
    local field_name="$1"
    local field_value="$2"
    
    log "DEBUG" "Validating field '$field_name' with value '$field_value'"
    
    # Handle special characters first
    validate_special_chars "$field_name" "$field_value" || return 1
    
    # Handle basic cases
    if [[ "$field_value" == "*" ]] || [[ "$field_value" == "?" ]]; then
        return 0
    fi
    
    # Validate complex expressions
    validate_list "$field_name" "$field_value" || return 1
    
    return 0
}

# Check for logical inconsistencies
check_logical_consistency() {
    local -a fields=("$@")
    local day_field="${fields[3]:-*}"
    local weekday_field="${fields[5]:-*}"
    
    # Check day and weekday field conflict
    if [[ "$day_field" != "*" ]] && [[ "$day_field" != "?" ]] && 
       [[ "$weekday_field" != "*" ]] && [[ "$weekday_field" != "?" ]]; then
        VALIDATION_RESULT["warnings"]+="Both day-of-month and day-of-week specified. This may not behave as expected. "
    fi
    
    # Check for impossible dates
    local month_field="${fields[4]:-*}"
    if [[ "$day_field" =~ ^[0-9]+$ ]] && [[ "$month_field" =~ ^[0-9]+$ ]]; then
        local day="$day_field"
        local month="$month_field"
        
        # Check for obviously invalid dates
        if [[ "$month" == "2" ]] && [[ "$day" -gt "29" ]]; then
            VALIDATION_RESULT["warnings"]+="February $day is invalid (even in leap years). "
        elif [[ "$month" == "2" ]] && [[ "$day" == "29" ]]; then
            VALIDATION_RESULT["warnings"]+="February 29 only exists in leap years. "
        elif [[ "$month" =~ ^(4|6|9|11)$ ]] && [[ "$day" == "31" ]]; then
            local month_name
            case "$month" in
                4) month_name="April" ;;
                6) month_name="June" ;;
                9) month_name="September" ;;
                11) month_name="November" ;;
            esac
            VALIDATION_RESULT["warnings"]+="$month_name $day is invalid (month has only 30 days). "
        fi
    fi
}

# Generate human-readable description
generate_description() {
    local -a fields=("$@")
    local description=""
    local has_seconds=false
    
    # Determine if we have seconds field
    if [[ ${#fields[@]} -eq 6 ]]; then
        has_seconds=true
    fi
    
    # Build description parts
    local time_part=""
    local date_part=""
    
    if [[ "$has_seconds" == true ]]; then
        local second="${fields[0]}"
        local minute="${fields[1]}"
        local hour="${fields[2]}"
        local day="${fields[3]}"
        local month="${fields[4]}"
        local weekday="${fields[5]}"
        
        # Time description
        if [[ "$hour" == "*" ]] && [[ "$minute" == "*" ]] && [[ "$second" == "*" ]]; then
            time_part="every second"
        elif [[ "$hour" == "*" ]] && [[ "$minute" == "*" ]]; then
            time_part="every minute at second $second"
        elif [[ "$hour" == "*" ]]; then
            time_part="every hour at $minute:$second"
        else
            time_part="at $hour:$minute:$second"
        fi
    else
        local minute="${fields[0]}"
        local hour="${fields[1]}"
        local day="${fields[2]}"
        local month="${fields[3]}"
        local weekday="${fields[4]}"
        
        # Time description
        if [[ "$hour" == "*" ]] && [[ "$minute" == "*" ]]; then
            time_part="every minute"
        elif [[ "$hour" == "*" ]]; then
            time_part="every hour at minute $minute"
        else
            time_part="at $hour:$minute"
        fi
    fi
    
    # Date description
    if [[ "$day" == "*" ]] && [[ "$month" == "*" ]] && [[ "$weekday" == "*" ]]; then
        date_part="every day"
    elif [[ "$weekday" != "*" ]] && [[ "$weekday" != "?" ]]; then
        date_part="on $(describe_weekday "$weekday")"
        if [[ "$month" != "*" ]]; then
            date_part+=" in $(describe_month "$month")"
        fi
    elif [[ "$day" != "*" ]] && [[ "$day" != "?" ]]; then
        if [[ "$month" != "*" ]]; then
            date_part="on day $day of $(describe_month "$month")"
        else
            date_part="on day $day of every month"
        fi
    elif [[ "$month" != "*" ]]; then
        date_part="in $(describe_month "$month")"
    fi
    
    description="Run $time_part $date_part"
    VALIDATION_RESULT["description"]="$description"
}

# Describe weekday values
describe_weekday() {
    local weekday="$1"
    case "$weekday" in
        0|7) echo "Sunday" ;;
        1) echo "Monday" ;;
        2) echo "Tuesday" ;;
        3) echo "Wednesday" ;;
        4) echo "Thursday" ;;
        5) echo "Friday" ;;
        6) echo "Saturday" ;;
        *) echo "weekday $weekday" ;;
    esac
}

# Describe month values
describe_month() {
    local month="$1"
    case "$month" in
        1) echo "January" ;;
        2) echo "February" ;;
        3) echo "March" ;;
        4) echo "April" ;;
        5) echo "May" ;;
        6) echo "June" ;;
        7) echo "July" ;;
        8) echo "August" ;;
        9) echo "September" ;;
        10) echo "October" ;;
        11) echo "November" ;;
        12) echo "December" ;;
        *) echo "month $month" ;;
    esac
}

# Calculate next execution times
calculate_next_runs() {
    local cron_expr="$1"
    local count="${2:-5}"
    
    # This is a simplified implementation
    # In a production environment, you might want to use a more sophisticated
    # cron parsing library or external tool
    
    log "DEBUG" "Calculating next $count execution times for: $cron_expr"
    
    # For now, we'll provide a placeholder implementation
    VALIDATION_RESULT["next_runs"]="Next execution calculation requires external cron library"
}

# Analyze performance characteristics
analyze_performance() {
    local -a fields=("$@")
    local frequency_score=0
    local performance_notes=""
    
    # Calculate approximate frequency
    for field in "${fields[@]}"; do
        if [[ "$field" == "*" ]]; then
            ((frequency_score += 10))
        elif [[ "$field" =~ \* ]]; then
            ((frequency_score += 5))
        elif [[ "$field" =~ , ]]; then
            local count=$(echo "$field" | tr ',' '\n' | wc -l)
            ((frequency_score += count))
        else
            ((frequency_score += 1))
        fi
    done
    
    if [[ "$frequency_score" -gt 50 ]]; then
        performance_notes="High frequency execution - monitor system resources"
    elif [[ "$frequency_score" -gt 20 ]]; then
        performance_notes="Medium frequency execution"
    else
        performance_notes="Low frequency execution"
    fi
    
    VALIDATION_RESULT["frequency"]="Score: $frequency_score"
    VALIDATION_RESULT["performance"]="$performance_notes"
}

# Main validation function
validate_cron_expression() {
    local cron_expr="$1"
    
    log "INFO" "Validating cron expression: $cron_expr"
    
    # Reset validation result
    VALIDATION_RESULT["valid"]=true
    VALIDATION_RESULT["warnings"]=""
    VALIDATION_RESULT["errors"]=""
    VALIDATION_RESULT["description"]=""
    VALIDATION_RESULT["next_runs"]=""
    VALIDATION_RESULT["frequency"]=""
    VALIDATION_RESULT["performance"]=""
    
    # Check for cron shortcuts
    if [[ -n "${CRON_SHORTCUTS[$cron_expr]:-}" ]]; then
        if [[ "$cron_expr" == "@reboot" ]]; then
            VALIDATION_RESULT["description"]="Run at system startup"
            VALIDATION_RESULT["performance"]="System startup trigger"
            return 0
        else
            # Expand shortcut and validate
            local expanded="${CRON_SHORTCUTS[$cron_expr]}"
            log "DEBUG" "Expanding shortcut '$cron_expr' to '$expanded'"
            validate_cron_expression "$expanded"
            return $?
        fi
    fi
    
    # Split expression into fields
    IFS=' ' read -ra FIELDS <<< "$cron_expr"
    local field_count=${#FIELDS[@]}
    
    # Validate field count
    if [[ "$field_count" -ne 5 ]] && [[ "$field_count" -ne 6 ]]; then
        VALIDATION_RESULT["valid"]=false
        VALIDATION_RESULT["errors"]+="Invalid field count: expected 5 or 6 fields, got $field_count. "
        return 1
    fi
    
    # Validate each field
    local field_names=()
    if [[ "$field_count" -eq 6 ]]; then
        field_names=("second" "minute" "hour" "day" "month" "weekday")
    else
        field_names=("minute" "hour" "day" "month" "weekday")
    fi
    
    for i in "${!FIELDS[@]}"; do
        local field_name="${field_names[$i]}"
        local field_value="${FIELDS[$i]}"
        
        if ! validate_field "$field_name" "$field_value"; then
            VALIDATION_RESULT["valid"]=false
        fi
    done
    
    # Check logical consistency
    check_logical_consistency "${FIELDS[@]}"
    
    # Generate description if valid
    if [[ "${VALIDATION_RESULT["valid"]}" == true ]]; then
        generate_description "${FIELDS[@]}"
        calculate_next_runs "$cron_expr" "$SHOW_NEXT_RUNS"
        analyze_performance "${FIELDS[@]}"
    fi
    
    # Set exit code based on validation result
    if [[ "${VALIDATION_RESULT["valid"]}" == false ]]; then
        EXIT_CODE=2
    elif [[ -n "${VALIDATION_RESULT["warnings"]}" ]]; then
        EXIT_CODE=1
    fi
    
    return 0
}

# Output results in JSON format
output_json() {
    local cron_expr="$1"
    
    cat << EOF
{
  "expression": "$cron_expr",
  "valid": ${VALIDATION_RESULT["valid"]},
  "errors": [$(echo "${VALIDATION_RESULT["errors"]}" | sed 's/\. /", "/g' | sed 's/^/"/; s/"$//')],
  "warnings": [$(echo "${VALIDATION_RESULT["warnings"]}" | sed 's/\. /", "/g' | sed 's/^/"/; s/"$//')],
  "description": "${VALIDATION_RESULT["description"]}",
  "next_runs": "${VALIDATION_RESULT["next_runs"]}",
  "frequency": "${VALIDATION_RESULT["frequency"]}",
  "performance": "${VALIDATION_RESULT["performance"]}",
  "exit_code": $EXIT_CODE
}
EOF
}

# Output results in human-readable format
output_human() {
    local cron_expr="$1"
    
    echo -e "${CYAN}Cron Expression:${NC} $cron_expr"
    echo ""
    
    if [[ "${VALIDATION_RESULT["valid"]}" == true ]]; then
        echo -e "${GREEN}✓ Valid${NC}"
        
        if [[ -n "${VALIDATION_RESULT["description"]}" ]]; then
            echo -e "${BLUE}Description:${NC} ${VALIDATION_RESULT["description"]}"
        fi
        
        if [[ -n "${VALIDATION_RESULT["frequency"]}" ]]; then
            echo -e "${BLUE}Frequency:${NC} ${VALIDATION_RESULT["frequency"]}"
        fi
        
        if [[ -n "${VALIDATION_RESULT["performance"]}" ]]; then
            echo -e "${BLUE}Performance:${NC} ${VALIDATION_RESULT["performance"]}"
        fi
        
        if [[ -n "${VALIDATION_RESULT["next_runs"]}" ]]; then
            echo -e "${BLUE}Next Runs:${NC} ${VALIDATION_RESULT["next_runs"]}"
        fi
    else
        echo -e "${RED}✗ Invalid${NC}"
    fi
    
    if [[ -n "${VALIDATION_RESULT["errors"]}" ]]; then
        echo ""
        echo -e "${RED}Errors:${NC}"
        echo "${VALIDATION_RESULT["errors"]}" | sed 's/\. /\n  • /g' | sed 's/^/  • /'
    fi
    
    if [[ -n "${VALIDATION_RESULT["warnings"]}" ]]; then
        echo ""
        echo -e "${YELLOW}Warnings:${NC}"
        echo "${VALIDATION_RESULT["warnings"]}" | sed 's/\. /\n  • /g' | sed 's/^/  • /'
    fi
    
    echo ""
}

# Show help
show_help() {
    cat << EOF
${CYAN}Cron Syntax Validator${NC}

${YELLOW}USAGE:${NC}
    $SCRIPT_NAME [OPTIONS] [CRON_EXPRESSION]
    echo "CRON_EXPRESSION" | $SCRIPT_NAME [OPTIONS]

${YELLOW}DESCRIPTION:${NC}
    Validates cron expressions with comprehensive syntax checking, human-readable
    descriptions, and advanced features including timezone awareness and performance analysis.

${YELLOW}OPTIONS:${NC}
    -h, --help              Show this help message
    -v, --verbose           Enable verbose output
    -q, --quiet             Suppress all output except errors
    -j, --json              Output results in JSON format
    -t, --timezone TZ       Set timezone for calculations (e.g., UTC, America/New_York)
    -n, --next-runs N       Number of next execution times to show (default: 5)

${YELLOW}EXIT CODES:${NC}
    0    Valid cron expression
    1    Valid with warnings
    2    Invalid cron expression

${YELLOW}SUPPORTED FORMATS:${NC}
    5-field: minute hour day month weekday
    6-field: second minute hour day month weekday

${YELLOW}FIELD RANGES:${NC}
    second:   0-59
    minute:   0-59
    hour:     0-23
    day:      1-31
    month:    1-12 (or JAN-DEC)
    weekday:  0-7 (0 and 7 are Sunday, or SUN-SAT)

${YELLOW}SPECIAL CHARACTERS:${NC}
    *    Any value
    ?    Any value (alternative to *)
    ,    List separator (e.g., 1,3,5)
    -    Range (e.g., 1-5)
    /    Step values (e.g., */5, 1-10/2)
    L    Last (day of month or weekday)
    W    Weekday (nearest weekday to given date)
    #    Nth occurrence (e.g., 2#1 = first Tuesday)

${YELLOW}SHORTCUTS:${NC}
    @yearly, @annually    0 0 1 1 *
    @monthly              0 0 1 * *
    @weekly               0 0 * * 0
    @daily, @midnight     0 0 * * *
    @hourly               0 * * * *
    @reboot               Run at startup

${YELLOW}EXAMPLES:${NC}
    # Basic validation
    $SCRIPT_NAME "0 2 * * *"
    
    # Verbose output with JSON format
    $SCRIPT_NAME -v -j "*/15 9-17 * * 1-5"
    
    # Validate from stdin
    echo "0 0 1 1 *" | $SCRIPT_NAME
    
    # Check shortcut
    $SCRIPT_NAME "@daily"
    
    # Complex expression with special characters
    $SCRIPT_NAME "0 9 1-7 * MON#1"
    
    # 6-field format with seconds
    $SCRIPT_NAME "30 0 2 * * *"

${YELLOW}ADVANCED FEATURES:${NC}
    • Timezone-aware calculations
    • Leap year validation
    • Performance impact analysis
    • Conflict detection
    • Human-readable descriptions
    • Next execution time predictions

${YELLOW}EXAMPLES OF SPECIAL EXPRESSIONS:${NC}
    "0 0 L * *"           Last day of every month
    "0 0 15W * *"         Nearest weekday to 15th
    "0 0 * * 5L"          Last Friday of every month
    "0 9 * * MON#1"       First Monday of every month
    "*/30 9-17 * * 1-5"   Every 30 minutes, 9-5, weekdays

For more information, see the project documentation.
EOF
}

# Parse command line arguments
parse_arguments() {
    local cron_expr=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -t|--timezone)
                TIMEZONE="$2"
                shift 2
                ;;
            -n|--next-runs)
                SHOW_NEXT_RUNS="$2"
                shift 2
                ;;
            -*)
                error_exit "Unknown option: $1"
                ;;
            *)
                # This is the cron expression
                cron_expr="$1"
                shift
                ;;
        esac
    done
    
    echo "$cron_expr"
}

# Main function
main() {
    local cron_expr=""
    
    # Parse arguments
    cron_expr=$(parse_arguments "$@")
    
    # If no expression provided as argument, read from stdin
    if [[ -z "$cron_expr" ]]; then
        if [[ -t 0 ]]; then
            # No stdin input and no argument
            error_exit "No cron expression provided. Use -h for help."
        else
            # Read from stdin
            read -r cron_expr
        fi
    fi
    
    # Validate the expression
    validate_cron_expression "$cron_expr"
    
    # Output results
    if [[ "$JSON_OUTPUT" == true ]]; then
        output_json "$cron_expr"
    else
        output_human "$cron_expr"
    fi
    
    exit $EXIT_CODE
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi