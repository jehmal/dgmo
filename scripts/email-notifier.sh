#!/bin/bash

# ============================================================================
# Enterprise Email Notification System for Backup Monitoring
# ============================================================================
# A robust, production-ready email notification system that provides:
# - Multi-provider SMTP support with encryption
# - Rich HTML templates with fallback
# - Escalation policies and rate limiting
# - Security features and audit logging
# - Comprehensive error handling and retry logic
# ============================================================================

set -euo pipefail

# ============================================================================
# GLOBAL CONFIGURATION
# ============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
readonly CONFIG_FILE="${PROJECT_ROOT}/backup-config.conf"
readonly EMAIL_CONFIG_FILE="${PROJECT_ROOT}/email-config.conf"
readonly EMAIL_QUEUE_DIR="${PROJECT_ROOT}/email-queue"
readonly EMAIL_LOG_FILE="${PROJECT_ROOT}/logs/email-notifier.log"
readonly ESCALATION_STATE_FILE="${PROJECT_ROOT}/email-escalation.state"
readonly RATE_LIMIT_FILE="${PROJECT_ROOT}/email-rate-limit.state"

# Default SMTP settings
readonly DEFAULT_SMTP_PORT=587
readonly DEFAULT_SMTP_TIMEOUT=30
readonly DEFAULT_MAX_RETRIES=3
readonly DEFAULT_RETRY_DELAY=5
readonly DEFAULT_RATE_LIMIT=10  # emails per hour

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_CONFIG_ERROR=1
readonly EXIT_SMTP_ERROR=2
readonly EXIT_TEMPLATE_ERROR=3
readonly EXIT_SECURITY_ERROR=4
readonly EXIT_RATE_LIMIT=5

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] [$level] $message"
    
    echo "$log_entry" >&2
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$EMAIL_LOG_FILE")"
    echo "$log_entry" >> "$EMAIL_LOG_FILE"
    
    # Rotate log if it gets too large (10MB)
    if [[ -f "$EMAIL_LOG_FILE" ]] && [[ $(stat -f%z "$EMAIL_LOG_FILE" 2>/dev/null || stat -c%s "$EMAIL_LOG_FILE" 2>/dev/null || echo 0) -gt 10485760 ]]; then
        mv "$EMAIL_LOG_FILE" "${EMAIL_LOG_FILE}.old"
        touch "$EMAIL_LOG_FILE"
    fi
}

error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    log_message "ERROR" "$message"
    exit "$exit_code"
}

validate_email() {
    local email="$1"
    if [[ ! "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        return 1
    fi
    return 0
}

sanitize_input() {
    local input="$1"
    # Remove potentially dangerous characters
    echo "$input" | sed 's/[;&|`$(){}[\]\\]//g' | tr -d '\n\r'
}

encrypt_credential() {
    local credential="$1"
    local key="${HOSTNAME:-localhost}-$(id -u)"
    echo "$credential" | openssl enc -aes-256-cbc -a -salt -pass pass:"$key" 2>/dev/null || echo "$credential"
}

decrypt_credential() {
    local encrypted="$1"
    local key="${HOSTNAME:-localhost}-$(id -u)"
    echo "$encrypted" | openssl enc -aes-256-cbc -d -a -pass pass:"$key" 2>/dev/null || echo "$encrypted"
}

# ============================================================================
# CONFIGURATION MANAGEMENT
# ============================================================================

load_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        log_message "WARNING" "Configuration file not found: $config_file"
        return 1
    fi
    
    # Parse configuration file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        [[ "$key" =~ ^\[.*\]$ ]] && continue
        
        # Remove leading/trailing whitespace
        key=$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Export as environment variable
        export "$key"="$value"
    done < "$config_file"
}

create_default_email_config() {
    cat > "$EMAIL_CONFIG_FILE" << 'EOF'
# ============================================================================
# Email Notification Configuration
# ============================================================================

[SMTP]
# SMTP Provider (gmail, outlook, sendgrid, custom)
SMTP_PROVIDER=custom

# SMTP Server Settings
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USE_TLS=true
SMTP_USE_SSL=false
SMTP_TIMEOUT=30

# Authentication
SMTP_AUTH_METHOD=plain
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=
SMTP_FROM_NAME=Backup System

# Connection Testing
SMTP_TEST_ON_START=true
SMTP_VERIFY_CERT=true

[TEMPLATES]
# Email Templates
TEMPLATE_DIR=templates
USE_HTML=true
USE_PLAIN_FALLBACK=true

# Subject Templates
SUBJECT_SUCCESS=✅ Backup Success - {HOSTNAME}
SUBJECT_FAILURE=❌ Backup Failed - {HOSTNAME}
SUBJECT_WARNING=⚠️ Backup Warning - {HOSTNAME}
SUBJECT_TEST=🔧 Email Test - {HOSTNAME}

[ESCALATION]
# Escalation Policy
ENABLE_ESCALATION=true
FAILURE_THRESHOLD=3
ESCALATION_RECIPIENTS=
ESCALATION_DELAY_HOURS=1
COOLDOWN_HOURS=24

# Notification Frequency
SUCCESS_FREQUENCY=daily
WARNING_FREQUENCY=immediate
FAILURE_FREQUENCY=immediate

[SECURITY]
# Security Settings
ENCRYPT_CREDENTIALS=true
RATE_LIMIT_ENABLED=true
MAX_EMAILS_PER_HOUR=10
AUDIT_ALL_ATTEMPTS=true
VALIDATE_RECIPIENTS=true

[RETRY]
# Retry Logic
MAX_RETRIES=3
RETRY_DELAY_SECONDS=5
EXPONENTIAL_BACKOFF=true
QUEUE_FAILED_EMAILS=true
EOF
    
    log_message "INFO" "Created default email configuration: $EMAIL_CONFIG_FILE"
}

# ============================================================================
# SMTP PROVIDER CONFIGURATIONS
# ============================================================================

configure_smtp_provider() {
    local provider="$1"
    
    case "$provider" in
        gmail)
            SMTP_HOST="smtp.gmail.com"
            SMTP_PORT=587
            SMTP_USE_TLS=true
            SMTP_USE_SSL=false
            SMTP_AUTH_METHOD="plain"
            ;;
        outlook)
            SMTP_HOST="smtp-mail.outlook.com"
            SMTP_PORT=587
            SMTP_USE_TLS=true
            SMTP_USE_SSL=false
            SMTP_AUTH_METHOD="plain"
            ;;
        sendgrid)
            SMTP_HOST="smtp.sendgrid.net"
            SMTP_PORT=587
            SMTP_USE_TLS=true
            SMTP_USE_SSL=false
            SMTP_AUTH_METHOD="plain"
            ;;
        custom)
            # Use configured values
            ;;
        *)
            error_exit "Unsupported SMTP provider: $provider" $EXIT_CONFIG_ERROR
            ;;
    esac
}

test_smtp_connection() {
    local host="$1"
    local port="$2"
    local timeout="${3:-30}"
    
    log_message "INFO" "Testing SMTP connection to $host:$port"
    
    if command -v nc >/dev/null 2>&1; then
        if timeout "$timeout" nc -z "$host" "$port" 2>/dev/null; then
            log_message "INFO" "SMTP connection test successful"
            return 0
        else
            log_message "ERROR" "SMTP connection test failed"
            return 1
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if timeout "$timeout" bash -c "echo quit | telnet $host $port" >/dev/null 2>&1; then
            log_message "INFO" "SMTP connection test successful"
            return 0
        else
            log_message "ERROR" "SMTP connection test failed"
            return 1
        fi
    else
        log_message "WARNING" "No network testing tools available (nc, telnet)"
        return 0
    fi
}

# ============================================================================
# EMAIL TEMPLATES
# ============================================================================

create_email_templates() {
    local template_dir="${PROJECT_ROOT}/templates"
    mkdir -p "$template_dir"
    
    # HTML Success Template
    cat > "$template_dir/success.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { background-color: #28a745; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; }
        .status { font-size: 24px; font-weight: bold; color: #28a745; margin-bottom: 20px; }
        .details { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 15px 0; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; }
        .metric-label { font-weight: bold; color: #666; }
        .metric-value { color: #333; }
        .footer { background-color: #f8f9fa; padding: 15px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>✅ Backup Completed Successfully</h1>
        </div>
        <div class="content">
            <div class="status">Backup Status: SUCCESS</div>
            <div class="details">
                <div class="metric">
                    <span class="metric-label">Hostname:</span>
                    <span class="metric-value">{HOSTNAME}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Timestamp:</span>
                    <span class="metric-value">{TIMESTAMP}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Backup Size:</span>
                    <span class="metric-value">{BACKUP_SIZE}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Duration:</span>
                    <span class="metric-value">{DURATION}</span>
                </div>
            </div>
            <div class="details">
                <h3>Backup Details</h3>
                <p>{DETAILS}</p>
            </div>
        </div>
        <div class="footer">
            <p>This is an automated message from the backup monitoring system.</p>
        </div>
    </div>
</body>
</html>
EOF

    # HTML Failure Template
    cat > "$template_dir/failure.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { background-color: #dc3545; color: white; padding: 20px; text-align: center; }
        .content { padding: 20px; }
        .status { font-size: 24px; font-weight: bold; color: #dc3545; margin-bottom: 20px; }
        .details { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 15px 0; }
        .error { background-color: #f8d7da; border: 1px solid #f5c6cb; color: #721c24; padding: 15px; border-radius: 5px; margin: 15px 0; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; }
        .metric-label { font-weight: bold; color: #666; }
        .metric-value { color: #333; }
        .footer { background-color: #f8f9fa; padding: 15px; text-align: center; color: #666; font-size: 12px; }
        .urgent { color: #dc3545; font-weight: bold; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>❌ Backup Failed</h1>
        </div>
        <div class="content">
            <div class="status">Backup Status: <span class="urgent">FAILURE</span></div>
            <div class="details">
                <div class="metric">
                    <span class="metric-label">Hostname:</span>
                    <span class="metric-value">{HOSTNAME}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Timestamp:</span>
                    <span class="metric-value">{TIMESTAMP}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Duration:</span>
                    <span class="metric-value">{DURATION}</span>
                </div>
            </div>
            <div class="error">
                <h3>Error Details</h3>
                <p>{DETAILS}</p>
            </div>
            <div class="details">
                <h3>Recommended Actions</h3>
                <ul>
                    <li>Check disk space on backup destination</li>
                    <li>Verify source directory accessibility</li>
                    <li>Review backup logs for detailed error information</li>
                    <li>Contact system administrator if problem persists</li>
                </ul>
            </div>
        </div>
        <div class="footer">
            <p>This is an automated message from the backup monitoring system.</p>
            <p class="urgent">Immediate attention required!</p>
        </div>
    </div>
</body>
</html>
EOF

    # Plain Text Templates
    cat > "$template_dir/success.txt" << 'EOF'
BACKUP SUCCESS NOTIFICATION
===========================

Backup Status: SUCCESS
Hostname: {HOSTNAME}
Timestamp: {TIMESTAMP}
Backup Size: {BACKUP_SIZE}
Duration: {DURATION}

Details:
{DETAILS}

This is an automated message from the backup monitoring system.
EOF

    cat > "$template_dir/failure.txt" << 'EOF'
BACKUP FAILURE NOTIFICATION
===========================

Backup Status: FAILURE
Hostname: {HOSTNAME}
Timestamp: {TIMESTAMP}
Duration: {DURATION}

Error Details:
{DETAILS}

Recommended Actions:
- Check disk space on backup destination
- Verify source directory accessibility
- Review backup logs for detailed error information
- Contact system administrator if problem persists

This is an automated message from the backup monitoring system.
IMMEDIATE ATTENTION REQUIRED!
EOF

    cat > "$template_dir/warning.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background-color: #f5f5f5; }
        .container { max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { background-color: #ffc107; color: #212529; padding: 20px; text-align: center; }
        .content { padding: 20px; }
        .status { font-size: 24px; font-weight: bold; color: #ffc107; margin-bottom: 20px; }
        .details { background-color: #f8f9fa; padding: 15px; border-radius: 5px; margin: 15px 0; }
        .warning { background-color: #fff3cd; border: 1px solid #ffeaa7; color: #856404; padding: 15px; border-radius: 5px; margin: 15px 0; }
        .metric { display: inline-block; margin: 10px 20px 10px 0; }
        .metric-label { font-weight: bold; color: #666; }
        .metric-value { color: #333; }
        .footer { background-color: #f8f9fa; padding: 15px; text-align: center; color: #666; font-size: 12px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>⚠️ Backup Warning</h1>
        </div>
        <div class="content">
            <div class="status">Backup Status: WARNING</div>
            <div class="details">
                <div class="metric">
                    <span class="metric-label">Hostname:</span>
                    <span class="metric-value">{HOSTNAME}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Timestamp:</span>
                    <span class="metric-value">{TIMESTAMP}</span>
                </div>
                <div class="metric">
                    <span class="metric-label">Duration:</span>
                    <span class="metric-value">{DURATION}</span>
                </div>
            </div>
            <div class="warning">
                <h3>Warning Details</h3>
                <p>{DETAILS}</p>
            </div>
        </div>
        <div class="footer">
            <p>This is an automated message from the backup monitoring system.</p>
        </div>
    </div>
</body>
</html>
EOF

    cat > "$template_dir/warning.txt" << 'EOF'
BACKUP WARNING NOTIFICATION
===========================

Backup Status: WARNING
Hostname: {HOSTNAME}
Timestamp: {TIMESTAMP}
Duration: {DURATION}

Warning Details:
{DETAILS}

This is an automated message from the backup monitoring system.
EOF

    log_message "INFO" "Created email templates in $template_dir"
}

substitute_template_variables() {
    local template="$1"
    local hostname="${HOSTNAME:-$(hostname)}"
    local timestamp="${2:-$(date '+%Y-%m-%d %H:%M:%S')}"
    local status="${3:-UNKNOWN}"
    local details="${4:-No details provided}"
    local backup_size="${5:-Unknown}"
    local duration="${6:-Unknown}"
    
    # Sanitize inputs
    hostname=$(sanitize_input "$hostname")
    details=$(sanitize_input "$details")
    backup_size=$(sanitize_input "$backup_size")
    duration=$(sanitize_input "$duration")
    
    echo "$template" | \
        sed "s/{HOSTNAME}/$hostname/g" | \
        sed "s/{TIMESTAMP}/$timestamp/g" | \
        sed "s/{STATUS}/$status/g" | \
        sed "s/{DETAILS}/$details/g" | \
        sed "s/{BACKUP_SIZE}/$backup_size/g" | \
        sed "s/{DURATION}/$duration/g"
}

# ============================================================================
# RATE LIMITING AND ESCALATION
# ============================================================================

check_rate_limit() {
    local max_emails="${MAX_EMAILS_PER_HOUR:-$DEFAULT_RATE_LIMIT}"
    local current_hour=$(date '+%Y%m%d%H')
    local rate_limit_file="$RATE_LIMIT_FILE"
    
    if [[ ! -f "$rate_limit_file" ]]; then
        echo "0:$current_hour" > "$rate_limit_file"
        return 0
    fi
    
    local count_hour
    IFS=':' read -r count_hour stored_hour < "$rate_limit_file"
    
    if [[ "$stored_hour" != "$current_hour" ]]; then
        # New hour, reset counter
        echo "1:$current_hour" > "$rate_limit_file"
        return 0
    fi
    
    if [[ "$count_hour" -ge "$max_emails" ]]; then
        log_message "WARNING" "Rate limit exceeded: $count_hour emails sent this hour"
        return 1
    fi
    
    # Increment counter
    echo "$((count_hour + 1)):$current_hour" > "$rate_limit_file"
    return 0
}

update_escalation_state() {
    local status="$1"  # success, failure, warning
    local escalation_file="$ESCALATION_STATE_FILE"
    
    if [[ "$status" == "success" ]]; then
        # Reset failure counter on success
        echo "0:$(date '+%s')" > "$escalation_file"
        return 0
    fi
    
    local failure_count=0
    local last_failure=0
    
    if [[ -f "$escalation_file" ]]; then
        IFS=':' read -r failure_count last_failure < "$escalation_file"
    fi
    
    if [[ "$status" == "failure" ]]; then
        failure_count=$((failure_count + 1))
        last_failure=$(date '+%s')
        echo "$failure_count:$last_failure" > "$escalation_file"
    fi
    
    echo "$failure_count"
}

should_escalate() {
    local failure_count="$1"
    local threshold="${FAILURE_THRESHOLD:-3}"
    local delay_hours="${ESCALATION_DELAY_HOURS:-1}"
    local cooldown_hours="${COOLDOWN_HOURS:-24}"
    local escalation_file="$ESCALATION_STATE_FILE"
    
    if [[ "$failure_count" -lt "$threshold" ]]; then
        return 1
    fi
    
    # Check if we're in cooldown period
    local last_escalation_file="${escalation_file}.last"
    if [[ -f "$last_escalation_file" ]]; then
        local last_escalation
        last_escalation=$(cat "$last_escalation_file")
        local current_time=$(date '+%s')
        local time_diff=$((current_time - last_escalation))
        local cooldown_seconds=$((cooldown_hours * 3600))
        
        if [[ "$time_diff" -lt "$cooldown_seconds" ]]; then
            log_message "INFO" "Escalation in cooldown period"
            return 1
        fi
    fi
    
    # Record escalation time
    date '+%s' > "$last_escalation_file"
    return 0
}

# ============================================================================
# EMAIL SENDING FUNCTIONS
# ============================================================================

send_email_sendmail() {
    local to="$1"
    local subject="$2"
    local body="$3"
    local content_type="${4:-text/plain}"
    local from="${SMTP_FROM_EMAIL:-backup@$(hostname)}"
    local from_name="${SMTP_FROM_NAME:-Backup System}"
    
    if ! command -v sendmail >/dev/null 2>&1; then
        log_message "ERROR" "sendmail not available"
        return 1
    fi
    
    local email_message
    email_message=$(cat << EOF
From: $from_name <$from>
To: $to
Subject: $subject
Content-Type: $content_type; charset=UTF-8
Date: $(date -R)

$body
EOF
)
    
    if echo "$email_message" | sendmail "$to"; then
        log_message "INFO" "Email sent successfully via sendmail to $to"
        return 0
    else
        log_message "ERROR" "Failed to send email via sendmail to $to"
        return 1
    fi
}

send_email_smtp() {
    local to="$1"
    local subject="$2"
    local body="$3"
    local content_type="${4:-text/plain}"
    
    local host="${SMTP_HOST:-localhost}"
    local port="${SMTP_PORT:-$DEFAULT_SMTP_PORT}"
    local username="${SMTP_USERNAME:-}"
    local password="${SMTP_PASSWORD:-}"
    local from="${SMTP_FROM_EMAIL:-backup@$(hostname)}"
    local from_name="${SMTP_FROM_NAME:-Backup System}"
    local use_tls="${SMTP_USE_TLS:-true}"
    local auth_method="${SMTP_AUTH_METHOD:-plain}"
    
    # Decrypt password if encrypted
    if [[ -n "$password" ]] && [[ "${ENCRYPT_CREDENTIALS:-true}" == "true" ]]; then
        password=$(decrypt_credential "$password")
    fi
    
    # Create temporary file for email content
    local temp_email
    temp_email=$(mktemp)
    trap "rm -f '$temp_email'" EXIT
    
    cat > "$temp_email" << EOF
From: $from_name <$from>
To: $to
Subject: $subject
Content-Type: $content_type; charset=UTF-8
Date: $(date -R)

$body
EOF
    
    # Use curl for SMTP if available
    if command -v curl >/dev/null 2>&1; then
        local curl_opts=(
            --mail-from "$from"
            --mail-rcpt "$to"
            --upload-file "$temp_email"
        )
        
        if [[ "$use_tls" == "true" ]]; then
            curl_opts+=(--ssl-reqd)
        fi
        
        if [[ -n "$username" ]] && [[ -n "$password" ]]; then
            curl_opts+=(--user "$username:$password")
        fi
        
        local smtp_url="smtp://$host:$port"
        if [[ "$use_tls" == "true" ]]; then
            smtp_url="smtps://$host:$port"
        fi
        
        if curl "${curl_opts[@]}" "$smtp_url" 2>/dev/null; then
            log_message "INFO" "Email sent successfully via SMTP to $to"
            return 0
        else
            log_message "ERROR" "Failed to send email via SMTP to $to"
            return 1
        fi
    else
        log_message "ERROR" "curl not available for SMTP sending"
        return 1
    fi
}

queue_email() {
    local to="$1"
    local subject="$2"
    local body="$3"
    local content_type="${4:-text/plain}"
    local priority="${5:-normal}"
    
    mkdir -p "$EMAIL_QUEUE_DIR"
    
    local queue_file="$EMAIL_QUEUE_DIR/$(date '+%Y%m%d_%H%M%S')_$(uuidgen 2>/dev/null || echo $RANDOM).email"
    
    cat > "$queue_file" << EOF
TO=$to
SUBJECT=$subject
CONTENT_TYPE=$content_type
PRIORITY=$priority
TIMESTAMP=$(date '+%s')
---
$body
EOF
    
    log_message "INFO" "Email queued: $queue_file"
}

process_email_queue() {
    local queue_dir="$EMAIL_QUEUE_DIR"
    
    if [[ ! -d "$queue_dir" ]]; then
        return 0
    fi
    
    local processed=0
    local failed=0
    
    for email_file in "$queue_dir"/*.email; do
        [[ ! -f "$email_file" ]] && continue
        
        log_message "INFO" "Processing queued email: $(basename "$email_file")"
        
        local to subject content_type priority body
        local in_body=false
        
        while IFS= read -r line; do
            if [[ "$line" == "---" ]]; then
                in_body=true
                continue
            fi
            
            if [[ "$in_body" == "true" ]]; then
                body+="$line"$'\n'
            else
                case "$line" in
                    TO=*) to="${line#TO=}" ;;
                    SUBJECT=*) subject="${line#SUBJECT=}" ;;
                    CONTENT_TYPE=*) content_type="${line#CONTENT_TYPE=}" ;;
                    PRIORITY=*) priority="${line#PRIORITY=}" ;;
                esac
            fi
        done < "$email_file"
        
        if send_email_with_retry "$to" "$subject" "$body" "$content_type"; then
            rm -f "$email_file"
            ((processed++))
            log_message "INFO" "Processed queued email successfully"
        else
            ((failed++))
            log_message "ERROR" "Failed to process queued email"
        fi
    done
    
    if [[ "$processed" -gt 0 ]] || [[ "$failed" -gt 0 ]]; then
        log_message "INFO" "Queue processing complete: $processed sent, $failed failed"
    fi
}

send_email_with_retry() {
    local to="$1"
    local subject="$2"
    local body="$3"
    local content_type="${4:-text/plain}"
    local max_retries="${MAX_RETRIES:-$DEFAULT_MAX_RETRIES}"
    local retry_delay="${RETRY_DELAY_SECONDS:-$DEFAULT_RETRY_DELAY}"
    local exponential_backoff="${EXPONENTIAL_BACKOFF:-true}"
    
    local attempt=1
    local current_delay="$retry_delay"
    
    while [[ "$attempt" -le "$max_retries" ]]; do
        log_message "INFO" "Email attempt $attempt/$max_retries to $to"
        
        # Try SMTP first, fallback to sendmail
        if send_email_smtp "$to" "$subject" "$body" "$content_type" || \
           send_email_sendmail "$to" "$subject" "$body" "$content_type"; then
            log_message "INFO" "Email sent successfully on attempt $attempt"
            return 0
        fi
        
        if [[ "$attempt" -lt "$max_retries" ]]; then
            log_message "WARNING" "Email attempt $attempt failed, retrying in ${current_delay}s"
            sleep "$current_delay"
            
            if [[ "$exponential_backoff" == "true" ]]; then
                current_delay=$((current_delay * 2))
            fi
        fi
        
        ((attempt++))
    done
    
    log_message "ERROR" "All email attempts failed for $to"
    
    # Queue email if retry failed and queuing is enabled
    if [[ "${QUEUE_FAILED_EMAILS:-true}" == "true" ]]; then
        queue_email "$to" "$subject" "$body" "$content_type" "high"
    fi
    
    return 1
}

# ============================================================================
# MAIN NOTIFICATION FUNCTIONS
# ============================================================================

send_notification() {
    local notification_type="$1"  # success, failure, warning, test
    local details="$2"
    local backup_size="${3:-}"
    local duration="${4:-}"
    
    # Load configurations
    load_config "$CONFIG_FILE" || true
    load_config "$EMAIL_CONFIG_FILE" || true
    
    # Check if notifications are enabled
    if [[ "${EMAIL_ON_FAILURE:-false}" != "true" ]] && [[ "$notification_type" != "test" ]]; then
        log_message "INFO" "Email notifications disabled"
        return 0
    fi
    
    # Validate email address
    local email_address="${EMAIL_ADDRESS:-}"
    if [[ -z "$email_address" ]]; then
        log_message "WARNING" "No email address configured"
        return 0
    fi
    
    if ! validate_email "$email_address"; then
        error_exit "Invalid email address: $email_address" $EXIT_CONFIG_ERROR
    fi
    
    # Check rate limiting
    if [[ "${RATE_LIMIT_ENABLED:-true}" == "true" ]] && ! check_rate_limit; then
        log_message "WARNING" "Rate limit exceeded, skipping notification"
        return $EXIT_RATE_LIMIT
    fi
    
    # Update escalation state
    local failure_count
    failure_count=$(update_escalation_state "$notification_type")
    
    # Configure SMTP provider
    local smtp_provider="${SMTP_PROVIDER:-custom}"
    configure_smtp_provider "$smtp_provider"
    
    # Test SMTP connection if enabled
    if [[ "${SMTP_TEST_ON_START:-true}" == "true" ]] && [[ "$notification_type" != "test" ]]; then
        if ! test_smtp_connection "${SMTP_HOST:-localhost}" "${SMTP_PORT:-$DEFAULT_SMTP_PORT}"; then
            log_message "WARNING" "SMTP connection test failed, attempting to send anyway"
        fi
    fi
    
    # Prepare email content
    local template_dir="${PROJECT_ROOT}/${TEMPLATE_DIR:-templates}"
    local use_html="${USE_HTML:-true}"
    local hostname="${HOSTNAME:-$(hostname)}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Select subject template
    local subject
    case "$notification_type" in
        success)
            subject="${SUBJECT_SUCCESS:-✅ Backup Success - {HOSTNAME}}"
            ;;
        failure)
            subject="${SUBJECT_FAILURE:-❌ Backup Failed - {HOSTNAME}}"
            ;;
        warning)
            subject="${SUBJECT_WARNING:-⚠️ Backup Warning - {HOSTNAME}}"
            ;;
        test)
            subject="${SUBJECT_TEST:-🔧 Email Test - {HOSTNAME}}"
            ;;
        *)
            subject="Backup Notification - {HOSTNAME}"
            ;;
    esac
    
    subject=$(substitute_template_variables "$subject" "$timestamp" "$notification_type" "$details" "$backup_size" "$duration")
    
    # Prepare email body
    local body content_type
    
    if [[ "$use_html" == "true" ]] && [[ -f "$template_dir/$notification_type.html" ]]; then
        body=$(cat "$template_dir/$notification_type.html")
        content_type="text/html"
    elif [[ -f "$template_dir/$notification_type.txt" ]]; then
        body=$(cat "$template_dir/$notification_type.txt")
        content_type="text/plain"
    else
        # Fallback to simple text
        body="Backup Notification\n\nStatus: $notification_type\nHostname: $hostname\nTimestamp: $timestamp\nDetails: $details"
        content_type="text/plain"
    fi
    
    body=$(substitute_template_variables "$body" "$timestamp" "$notification_type" "$details" "$backup_size" "$duration")
    
    # Send primary notification
    local recipients=("$email_address")
    
    # Add escalation recipients if needed
    if [[ "${ENABLE_ESCALATION:-true}" == "true" ]] && [[ "$notification_type" == "failure" ]]; then
        if should_escalate "$failure_count"; then
            local escalation_recipients="${ESCALATION_RECIPIENTS:-}"
            if [[ -n "$escalation_recipients" ]]; then
                IFS=',' read -ra ESCALATION_EMAILS <<< "$escalation_recipients"
                for email in "${ESCALATION_EMAILS[@]}"; do
                    email=$(echo "$email" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    if validate_email "$email"; then
                        recipients+=("$email")
                    fi
                done
                log_message "WARNING" "Escalating to ${#recipients[@]} recipients after $failure_count failures"
            fi
        fi
    fi
    
    # Send to all recipients
    local success_count=0
    local total_recipients=${#recipients[@]}
    
    for recipient in "${recipients[@]}"; do
        if send_email_with_retry "$recipient" "$subject" "$body" "$content_type"; then
            ((success_count++))
        fi
    done
    
    if [[ "$success_count" -eq "$total_recipients" ]]; then
        log_message "INFO" "Notification sent successfully to all $total_recipients recipients"
        return 0
    elif [[ "$success_count" -gt 0 ]]; then
        log_message "WARNING" "Notification sent to $success_count/$total_recipients recipients"
        return 0
    else
        log_message "ERROR" "Failed to send notification to any recipients"
        return $EXIT_SMTP_ERROR
    fi
}

# ============================================================================
# COMMAND LINE INTERFACE
# ============================================================================

show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME [COMMAND] [OPTIONS]

COMMANDS:
    test                    Send test email to verify configuration
    success [details]       Send success notification
    failure [details]       Send failure notification  
    warning [details]       Send warning notification
    queue-process          Process queued emails
    config-create          Create default configuration files
    config-test            Test SMTP configuration
    
OPTIONS:
    --size SIZE            Backup size for success notifications
    --duration DURATION    Backup duration
    --help                 Show this help message

EXAMPLES:
    $SCRIPT_NAME test
    $SCRIPT_NAME success "Backup completed successfully" --size "150MB" --duration "5m 30s"
    $SCRIPT_NAME failure "Disk space insufficient"
    $SCRIPT_NAME warning "Backup took longer than usual" --duration "45m 12s"
    $SCRIPT_NAME queue-process

CONFIGURATION:
    Configuration is read from:
    - $CONFIG_FILE (main backup config)
    - $EMAIL_CONFIG_FILE (email-specific config)
    
    Use '$SCRIPT_NAME config-create' to generate default configurations.

EXIT CODES:
    0  Success
    1  Configuration error
    2  SMTP error
    3  Template error
    4  Security error
    5  Rate limit exceeded
EOF
}

main() {
    local command="${1:-}"
    local details="${2:-}"
    local backup_size=""
    local duration=""
    
    # Parse command line options
    shift 2>/dev/null || shift 1>/dev/null || true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --size)
                backup_size="$2"
                shift 2
                ;;
            --duration)
                duration="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_message "WARNING" "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    case "$command" in
        test)
            log_message "INFO" "Sending test email notification"
            send_notification "test" "This is a test email from the backup notification system"
            ;;
        success)
            log_message "INFO" "Sending success notification"
            send_notification "success" "${details:-Backup completed successfully}" "$backup_size" "$duration"
            ;;
        failure)
            log_message "INFO" "Sending failure notification"
            send_notification "failure" "${details:-Backup failed}" "" "$duration"
            ;;
        warning)
            log_message "INFO" "Sending warning notification"
            send_notification "warning" "${details:-Backup warning}" "" "$duration"
            ;;
        queue-process)
            log_message "INFO" "Processing email queue"
            process_email_queue
            ;;
        config-create)
            log_message "INFO" "Creating default configuration files"
            create_default_email_config
            create_email_templates
            ;;
        config-test)
            log_message "INFO" "Testing SMTP configuration"
            load_config "$EMAIL_CONFIG_FILE" || error_exit "Failed to load email configuration" $EXIT_CONFIG_ERROR
            configure_smtp_provider "${SMTP_PROVIDER:-custom}"
            test_smtp_connection "${SMTP_HOST:-localhost}" "${SMTP_PORT:-$DEFAULT_SMTP_PORT}"
            ;;
        "")
            log_message "ERROR" "No command specified"
            show_usage
            exit $EXIT_CONFIG_ERROR
            ;;
        *)
            log_message "ERROR" "Unknown command: $command"
            show_usage
            exit $EXIT_CONFIG_ERROR
            ;;
    esac
}

# ============================================================================
# SCRIPT EXECUTION
# ============================================================================

# Ensure script is not run as root for security
if [[ $EUID -eq 0 ]]; then
    error_exit "This script should not be run as root for security reasons" $EXIT_SECURITY_ERROR
fi

# Create necessary directories
mkdir -p "$(dirname "$EMAIL_LOG_FILE")"
mkdir -p "$EMAIL_QUEUE_DIR"

# Set secure permissions
chmod 700 "$(dirname "$EMAIL_LOG_FILE")" 2>/dev/null || true
chmod 700 "$EMAIL_QUEUE_DIR" 2>/dev/null || true

# Main execution
main "$@"