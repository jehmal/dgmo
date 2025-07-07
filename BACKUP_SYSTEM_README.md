# DGMSTT Backup System

A comprehensive, automated backup solution for the DGMSTT monorepo with intelligent scheduling,
compression, and monitoring capabilities.

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage Examples](#usage-examples)
- [Troubleshooting](#troubleshooting)
- [Performance Tuning](#performance-tuning)
- [Maintenance](#maintenance)
- [Recovery Procedures](#recovery-procedures)
- [Advanced Features](#advanced-features)

## Quick Start

### One-Command Installation

```bash
# Download and run the automated installer
curl -fsSL https://raw.githubusercontent.com/your-repo/dgmstt/main/setup-backup-system.sh | bash

# Or clone and run locally
git clone <your-repo>
cd dgmstt
chmod +x setup-backup-system.sh
./setup-backup-system.sh
```

### Immediate Backup

```bash
# Run a manual backup immediately
sudo /opt/dgmstt-backup/backup.sh

# Check backup status
sudo /opt/dgmstt-backup/backup.sh --status

# Verify latest backup
sudo /opt/dgmstt-backup/backup.sh --verify
```

## Installation

### Prerequisites

- Linux/Unix system with bash
- Root or sudo access
- Minimum 10GB free disk space
- Internet connection for dependency installation

### Supported Systems

- Ubuntu 18.04+
- Debian 9+
- CentOS 7+
- RHEL 7+
- Amazon Linux 2
- macOS 10.14+ (with Homebrew)

### Manual Installation

If you prefer manual installation over the automated script:

#### 1. Install Dependencies

**Ubuntu/Debian:**

```bash
sudo apt update
sudo apt install -y tar gzip cron logrotate rsync curl jq
```

**CentOS/RHEL:**

```bash
sudo yum install -y tar gzip cronie logrotate rsync curl jq
sudo systemctl enable crond
sudo systemctl start crond
```

**macOS:**

```bash
brew install gnu-tar gzip rsync curl jq
```

#### 2. Create Directory Structure

```bash
sudo mkdir -p /opt/dgmstt-backup/{scripts,config,logs,backups}
sudo mkdir -p /var/log/dgmstt-backup
sudo mkdir -p /etc/dgmstt-backup
```

#### 3. Set Permissions

```bash
sudo chown -R root:root /opt/dgmstt-backup
sudo chmod 755 /opt/dgmstt-backup
sudo chmod 700 /opt/dgmstt-backup/backups
sudo chmod 644 /opt/dgmstt-backup/config/*
sudo chmod 755 /opt/dgmstt-backup/scripts/*
```

#### 4. Copy Configuration Files

```bash
# Copy backup script
sudo cp backup.sh /opt/dgmstt-backup/scripts/
sudo chmod +x /opt/dgmstt-backup/scripts/backup.sh

# Copy configuration
sudo cp backup.conf /etc/dgmstt-backup/
sudo cp logrotate.conf /etc/logrotate.d/dgmstt-backup
```

#### 5. Setup Cron Job

```bash
# Add to root's crontab
sudo crontab -e

# Add this line for daily backups at 2 AM
0 2 * * * /opt/dgmstt-backup/scripts/backup.sh >/dev/null 2>&1
```

## Configuration

### Main Configuration File

Location: `/etc/dgmstt-backup/backup.conf`

```bash
# Source directory to backup
SOURCE_DIR="/path/to/dgmstt"

# Backup destination directory
BACKUP_DIR="/opt/dgmstt-backup/backups"

# Backup retention (days)
RETENTION_DAYS=30

# Compression level (1-9, 9 is highest)
COMPRESSION_LEVEL=6

# Maximum backup size (in MB, 0 = unlimited)
MAX_BACKUP_SIZE=5000

# Email notifications
ENABLE_EMAIL=true
EMAIL_RECIPIENT="admin@example.com"
SMTP_SERVER="localhost"

# Logging level (DEBUG, INFO, WARN, ERROR)
LOG_LEVEL="INFO"

# Exclude patterns (one per line)
EXCLUDE_PATTERNS=(
    "*.tmp"
    "*.log"
    "node_modules/*"
    ".git/*"
    "*.cache"
    "temp/*"
)

# Include only specific file types (empty = all files)
INCLUDE_PATTERNS=(
    "*.ts"
    "*.js"
    "*.json"
    "*.md"
    "*.yml"
    "*.yaml"
)

# Pre-backup commands
PRE_BACKUP_COMMANDS=(
    "echo 'Starting backup preparation'"
    "npm run build --if-present"
)

# Post-backup commands
POST_BACKUP_COMMANDS=(
    "echo 'Backup completed'"
    "curl -X POST https://healthchecks.io/ping/your-uuid"
)

# Backup verification
VERIFY_BACKUPS=true
VERIFY_SAMPLE_SIZE=10

# Performance settings
PARALLEL_COMPRESSION=true
CPU_LIMIT=80
IO_PRIORITY="best-effort"
```

### Environment-Specific Configurations

#### Development Environment

```bash
# /etc/dgmstt-backup/backup-dev.conf
SOURCE_DIR="/home/developer/dgmstt"
BACKUP_DIR="/home/developer/backups"
RETENTION_DAYS=7
COMPRESSION_LEVEL=3
ENABLE_EMAIL=false
LOG_LEVEL="DEBUG"
```

#### Production Environment

```bash
# /etc/dgmstt-backup/backup-prod.conf
SOURCE_DIR="/opt/dgmstt"
BACKUP_DIR="/backup/dgmstt"
RETENTION_DAYS=90
COMPRESSION_LEVEL=9
ENABLE_EMAIL=true
EMAIL_RECIPIENT="ops-team@company.com"
LOG_LEVEL="INFO"
VERIFY_BACKUPS=true
```

#### Staging Environment

```bash
# /etc/dgmstt-backup/backup-staging.conf
SOURCE_DIR="/opt/dgmstt-staging"
BACKUP_DIR="/backup/dgmstt-staging"
RETENTION_DAYS=14
COMPRESSION_LEVEL=6
ENABLE_EMAIL=true
EMAIL_RECIPIENT="dev-team@company.com"
LOG_LEVEL="INFO"
```

### Advanced Configuration Options

#### Custom Backup Schedules

```bash
# Multiple daily backups
0 2,14 * * * /opt/dgmstt-backup/scripts/backup.sh --config=production
30 8 * * * /opt/dgmstt-backup/scripts/backup.sh --config=development --quick

# Weekly full backup + daily incrementals
0 2 * * 0 /opt/dgmstt-backup/scripts/backup.sh --full
0 2 * * 1-6 /opt/dgmstt-backup/scripts/backup.sh --incremental

# Hourly backups during business hours
0 9-17 * * 1-5 /opt/dgmstt-backup/scripts/backup.sh --quick
```

#### Remote Backup Destinations

```bash
# S3 Configuration
AWS_BUCKET="my-dgmstt-backups"
AWS_REGION="us-west-2"
AWS_STORAGE_CLASS="STANDARD_IA"

# SFTP Configuration
SFTP_HOST="backup.example.com"
SFTP_USER="backup-user"
SFTP_PATH="/backups/dgmstt"
SFTP_KEY="/etc/dgmstt-backup/ssh-key"

# Rsync Configuration
RSYNC_HOST="backup.example.com"
RSYNC_USER="backup-user"
RSYNC_PATH="/backups/dgmstt"
RSYNC_OPTIONS="-avz --delete"
```

## Usage Examples

### Basic Operations

#### Manual Backup Execution

```bash
# Standard backup
sudo /opt/dgmstt-backup/scripts/backup.sh

# Quick backup (lower compression, faster)
sudo /opt/dgmstt-backup/scripts/backup.sh --quick

# Full backup (ignores incremental settings)
sudo /opt/dgmstt-backup/scripts/backup.sh --full

# Dry run (show what would be backed up)
sudo /opt/dgmstt-backup/scripts/backup.sh --dry-run

# Verbose output
sudo /opt/dgmstt-backup/scripts/backup.sh --verbose
```

#### Backup with Custom Configuration

```bash
# Use specific config file
sudo /opt/dgmstt-backup/scripts/backup.sh --config=/path/to/custom.conf

# Override specific settings
sudo /opt/dgmstt-backup/scripts/backup.sh --retention=60 --compression=9

# Backup to specific destination
sudo /opt/dgmstt-backup/scripts/backup.sh --destination=/custom/backup/path
```

### Status and Monitoring

#### Check Backup Status

```bash
# Overall status
sudo /opt/dgmstt-backup/scripts/backup.sh --status

# Detailed status with metrics
sudo /opt/dgmstt-backup/scripts/backup.sh --status --verbose

# JSON output for monitoring tools
sudo /opt/dgmstt-backup/scripts/backup.sh --status --json
```

#### List Available Backups

```bash
# List all backups
sudo /opt/dgmstt-backup/scripts/backup.sh --list

# List backups with sizes
sudo /opt/dgmstt-backup/scripts/backup.sh --list --details

# List backups from specific date range
sudo /opt/dgmstt-backup/scripts/backup.sh --list --from=2024-01-01 --to=2024-01-31
```

#### Verify Backup Integrity

```bash
# Verify latest backup
sudo /opt/dgmstt-backup/scripts/backup.sh --verify

# Verify specific backup
sudo /opt/dgmstt-backup/scripts/backup.sh --verify --backup=dgmstt-backup-20240115-020000.tar.gz

# Deep verification (extract and check all files)
sudo /opt/dgmstt-backup/scripts/backup.sh --verify --deep
```

### Restoration Procedures

#### Complete System Restoration

```bash
# Restore latest backup to original location
sudo /opt/dgmstt-backup/scripts/backup.sh --restore

# Restore specific backup
sudo /opt/dgmstt-backup/scripts/backup.sh --restore --backup=dgmstt-backup-20240115-020000.tar.gz

# Restore to different location
sudo /opt/dgmstt-backup/scripts/backup.sh --restore --destination=/tmp/restore

# Restore with confirmation prompts
sudo /opt/dgmstt-backup/scripts/backup.sh --restore --interactive
```

#### Selective File Restoration

```bash
# Restore specific files/directories
sudo /opt/dgmstt-backup/scripts/backup.sh --restore --files="src/config.json,docs/"

# Restore files matching pattern
sudo /opt/dgmstt-backup/scripts/backup.sh --restore --pattern="*.json"

# Preview what would be restored
sudo /opt/dgmstt-backup/scripts/backup.sh --restore --dry-run
```

### Maintenance Operations

#### Cleanup Old Backups

```bash
# Clean up based on retention policy
sudo /opt/dgmstt-backup/scripts/backup.sh --cleanup

# Force cleanup (ignore retention policy)
sudo /opt/dgmstt-backup/scripts/backup.sh --cleanup --force

# Clean up backups older than specific date
sudo /opt/dgmstt-backup/scripts/backup.sh --cleanup --older-than=2024-01-01
```

#### Log Management

```bash
# View recent backup logs
sudo tail -f /var/log/dgmstt-backup/backup.log

# View logs for specific date
sudo grep "2024-01-15" /var/log/dgmstt-backup/backup.log

# Rotate logs manually
sudo logrotate -f /etc/logrotate.d/dgmstt-backup

# Archive old logs
sudo /opt/dgmstt-backup/scripts/backup.sh --archive-logs
```

### Real-World Scenarios

#### Scenario 1: Development Workflow Integration

```bash
# Pre-commit backup
git add . && sudo /opt/dgmstt-backup/scripts/backup.sh --quick --tag="pre-commit-$(git rev-parse --short HEAD)"

# Before major changes
sudo /opt/dgmstt-backup/scripts/backup.sh --tag="before-refactor-$(date +%Y%m%d)"

# After successful deployment
sudo /opt/dgmstt-backup/scripts/backup.sh --tag="post-deploy-v1.2.3"
```

#### Scenario 2: Disaster Recovery Testing

```bash
# Create test backup
sudo /opt/dgmstt-backup/scripts/backup.sh --tag="disaster-recovery-test"

# Simulate disaster (move original)
sudo mv /opt/dgmstt /opt/dgmstt.backup

# Restore from backup
sudo /opt/dgmstt-backup/scripts/backup.sh --restore --backup=dgmstt-backup-disaster-recovery-test-*.tar.gz

# Verify restoration
sudo /opt/dgmstt-backup/scripts/backup.sh --verify --deep
```

#### Scenario 3: Migration to New Server

```bash
# On old server: Create migration backup
sudo /opt/dgmstt-backup/scripts/backup.sh --tag="migration-$(hostname)" --compress=9

# Transfer backup to new server
scp /opt/dgmstt-backup/backups/dgmstt-backup-migration-*.tar.gz newserver:/tmp/

# On new server: Install backup system
./setup-backup-system.sh

# Restore from migration backup
sudo /opt/dgmstt-backup/scripts/backup.sh --restore --backup=/tmp/dgmstt-backup-migration-*.tar.gz
```

#### Scenario 4: Automated Health Monitoring

```bash
# Create monitoring script
cat > /opt/dgmstt-backup/scripts/health-check.sh << 'EOF'
#!/bin/bash
STATUS=$(sudo /opt/dgmstt-backup/scripts/backup.sh --status --json)
LAST_BACKUP=$(echo "$STATUS" | jq -r '.last_backup_age_hours')

if [ "$LAST_BACKUP" -gt 25 ]; then
    echo "CRITICAL: Last backup is $LAST_BACKUP hours old"
    exit 2
elif [ "$LAST_BACKUP" -gt 24 ]; then
    echo "WARNING: Last backup is $LAST_BACKUP hours old"
    exit 1
else
    echo "OK: Last backup is $LAST_BACKUP hours old"
    exit 0
fi
EOF

# Add to cron for monitoring
echo "*/15 * * * * /opt/dgmstt-backup/scripts/health-check.sh" | sudo crontab -
```

## Troubleshooting

### Common Error Messages and Solutions

#### "Permission denied" Errors

**Error:** `tar: Cannot open: Permission denied`

**Causes:**

- Insufficient permissions to read source files
- SELinux/AppArmor restrictions
- Files in use by other processes

**Solutions:**

```bash
# Check file permissions
ls -la /path/to/source

# Run with proper permissions
sudo /opt/dgmstt-backup/scripts/backup.sh

# Check SELinux context
ls -Z /path/to/source
sudo setsebool -P use_nfs_home_dirs 1

# Stop services that might lock files
sudo systemctl stop your-app-service
sudo /opt/dgmstt-backup/scripts/backup.sh
sudo systemctl start your-app-service
```

#### "No space left on device" Errors

**Error:** `tar: write error: No space left on device`

**Diagnosis:**

```bash
# Check disk space
df -h /opt/dgmstt-backup/backups

# Check inode usage
df -i /opt/dgmstt-backup/backups

# Check for large files
du -sh /opt/dgmstt-backup/backups/*
```

**Solutions:**

```bash
# Clean up old backups
sudo /opt/dgmstt-backup/scripts/backup.sh --cleanup --force

# Move backups to larger disk
sudo mv /opt/dgmstt-backup/backups /larger/disk/path
sudo ln -s /larger/disk/path /opt/dgmstt-backup/backups

# Reduce compression level (faster, larger files)
sudo sed -i 's/COMPRESSION_LEVEL=9/COMPRESSION_LEVEL=3/' /etc/dgmstt-backup/backup.conf

# Enable backup size limits
sudo sed -i 's/MAX_BACKUP_SIZE=0/MAX_BACKUP_SIZE=2000/' /etc/dgmstt-backup/backup.conf
```

#### Cron Job Not Running

**Symptoms:**

- No recent backups
- No entries in cron logs

**Diagnosis:**

```bash
# Check if cron is running
sudo systemctl status cron

# Check crontab entries
sudo crontab -l

# Check cron logs
sudo grep CRON /var/log/syslog
sudo tail -f /var/log/cron
```

**Solutions:**

```bash
# Start cron service
sudo systemctl start cron
sudo systemctl enable cron

# Fix crontab syntax
sudo crontab -e
# Ensure proper format: minute hour day month weekday command

# Check script permissions
sudo chmod +x /opt/dgmstt-backup/scripts/backup.sh

# Test script manually
sudo /opt/dgmstt-backup/scripts/backup.sh --verbose
```

#### Backup Corruption Issues

**Error:** `tar: Unexpected EOF in archive`

**Diagnosis:**

```bash
# Test archive integrity
sudo tar -tzf /opt/dgmstt-backup/backups/corrupted-backup.tar.gz

# Check file size
ls -lh /opt/dgmstt-backup/backups/corrupted-backup.tar.gz

# Check system logs for errors
sudo dmesg | grep -i error
sudo journalctl -u backup.service
```

**Solutions:**

```bash
# Verify backup immediately after creation
sudo /opt/dgmstt-backup/scripts/backup.sh --verify

# Enable backup verification in config
sudo sed -i 's/VERIFY_BACKUPS=false/VERIFY_BACKUPS=true/' /etc/dgmstt-backup/backup.conf

# Use lower compression for reliability
sudo sed -i 's/COMPRESSION_LEVEL=9/COMPRESSION_LEVEL=6/' /etc/dgmstt-backup/backup.conf

# Check disk health
sudo smartctl -a /dev/sda
sudo fsck /dev/sda1
```

### Performance Issues

#### Slow Backup Performance

**Symptoms:**

- Backups taking too long
- High CPU/IO usage
- System unresponsive during backup

**Diagnosis:**

```bash
# Monitor backup process
sudo htop
sudo iotop
sudo iostat 1

# Check backup timing
sudo grep "Backup completed" /var/log/dgmstt-backup/backup.log | tail -5
```

**Solutions:**

```bash
# Reduce compression level
sudo sed -i 's/COMPRESSION_LEVEL=9/COMPRESSION_LEVEL=3/' /etc/dgmstt-backup/backup.conf

# Enable parallel compression
sudo sed -i 's/PARALLEL_COMPRESSION=false/PARALLEL_COMPRESSION=true/' /etc/dgmstt-backup/backup.conf

# Limit CPU usage
sudo sed -i 's/CPU_LIMIT=100/CPU_LIMIT=50/' /etc/dgmstt-backup/backup.conf

# Use ionice for lower IO priority
sudo sed -i 's/IO_PRIORITY="normal"/IO_PRIORITY="idle"/' /etc/dgmstt-backup/backup.conf

# Schedule during off-hours
sudo crontab -e
# Change from: 0 2 * * *
# To: 0 3 * * 0  (3 AM on Sundays only)
```

#### Memory Issues

**Error:** `Cannot allocate memory`

**Solutions:**

```bash
# Check available memory
free -h

# Reduce compression level
sudo sed -i 's/COMPRESSION_LEVEL=9/COMPRESSION_LEVEL=1/' /etc/dgmstt-backup/backup.conf

# Use streaming compression
sudo sed -i 's/PARALLEL_COMPRESSION=true/PARALLEL_COMPRESSION=false/' /etc/dgmstt-backup/backup.conf

# Split large backups
sudo /opt/dgmstt-backup/scripts/backup.sh --split-size=1000M
```

### Log Analysis Tips

#### Understanding Log Levels

```bash
# View only errors
sudo grep "ERROR" /var/log/dgmstt-backup/backup.log

# View warnings and errors
sudo grep -E "(WARN|ERROR)" /var/log/dgmstt-backup/backup.log

# View backup timing information
sudo grep "Backup completed" /var/log/dgmstt-backup/backup.log

# View file counts and sizes
sudo grep -E "(files processed|total size)" /var/log/dgmstt-backup/backup.log
```

#### Log Rotation Issues

```bash
# Check logrotate configuration
sudo cat /etc/logrotate.d/dgmstt-backup

# Test logrotate manually
sudo logrotate -d /etc/logrotate.d/dgmstt-backup

# Force log rotation
sudo logrotate -f /etc/logrotate.d/dgmstt-backup

# Check logrotate status
sudo cat /var/lib/logrotate/status | grep dgmstt
```

### Recovery Procedures

#### Emergency Recovery

When the backup system itself is corrupted:

```bash
# 1. Stop all backup processes
sudo pkill -f backup.sh

# 2. Check available backups
ls -la /opt/dgmstt-backup/backups/

# 3. Verify backup integrity
sudo tar -tzf /opt/dgmstt-backup/backups/latest-backup.tar.gz | head -10

# 4. Create emergency restore directory
sudo mkdir -p /tmp/emergency-restore

# 5. Extract backup
sudo tar -xzf /opt/dgmstt-backup/backups/latest-backup.tar.gz -C /tmp/emergency-restore

# 6. Verify extracted files
ls -la /tmp/emergency-restore/

# 7. Copy files back to original location
sudo cp -r /tmp/emergency-restore/* /original/location/
```

#### Partial Recovery

When only specific files are needed:

```bash
# List contents of backup
sudo tar -tzf backup.tar.gz | grep "specific-file"

# Extract specific files
sudo tar -xzf backup.tar.gz "path/to/specific/file"

# Extract directory
sudo tar -xzf backup.tar.gz "path/to/directory/"

# Extract with pattern
sudo tar -xzf backup.tar.gz --wildcards "*.json"
```

#### System Migration Recovery

```bash
# 1. Install backup system on new server
./setup-backup-system.sh

# 2. Transfer backup files
rsync -avz old-server:/opt/dgmstt-backup/backups/ /opt/dgmstt-backup/backups/

# 3. Update configuration for new environment
sudo nano /etc/dgmstt-backup/backup.conf

# 4. Test restoration
sudo /opt/dgmstt-backup/scripts/backup.sh --restore --dry-run

# 5. Perform actual restoration
sudo /opt/dgmstt-backup/scripts/backup.sh --restore

# 6. Verify restoration
sudo /opt/dgmstt-backup/scripts/backup.sh --verify --deep
```

## Performance Tuning

### Compression Optimization

#### Choosing Compression Levels

```bash
# Test different compression levels
for level in 1 3 6 9; do
    echo "Testing compression level $level"
    time sudo tar -czf test-$level.tar.gz --use-compress-program="gzip -$level" /path/to/test
    ls -lh test-$level.tar.gz
done

# Results analysis
# Level 1: Fastest, largest files
# Level 3: Good balance for most use cases
# Level 6: Default, good compression/speed ratio
# Level 9: Best compression, slowest
```

#### Advanced Compression Options

```bash
# Use pigz for parallel gzip compression
sudo apt install pigz
# In backup.conf:
COMPRESSION_PROGRAM="pigz -p 4"

# Use lz4 for very fast compression
sudo apt install lz4
COMPRESSION_PROGRAM="lz4 -1"

# Use zstd for modern compression
sudo apt install zstd
COMPRESSION_PROGRAM="zstd -3"
```

### I/O Optimization

#### Disk Performance Tuning

```bash
# Check current I/O scheduler
cat /sys/block/sda/queue/scheduler

# Set deadline scheduler for better backup performance
echo deadline | sudo tee /sys/block/sda/queue/scheduler

# Increase read-ahead for sequential reads
sudo blockdev --setra 8192 /dev/sda

# Monitor I/O during backup
sudo iotop -o -d 1
```

#### Network Optimization (for remote backups)

```bash
# Increase TCP buffer sizes
echo 'net.core.rmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.core.wmem_max = 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_rmem = 4096 87380 134217728' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_wmem = 4096 65536 134217728' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Use rsync with optimized options
RSYNC_OPTIONS="-avz --compress-level=3 --partial --inplace"
```

### Memory Optimization

#### Large File Handling

```bash
# For systems with limited memory
COMPRESSION_PROGRAM="gzip --rsyncable"
BACKUP_SPLIT_SIZE="1000M"

# Stream processing for very large files
TAR_OPTIONS="--checkpoint=10000 --checkpoint-action=dot"
```

#### Buffer Size Tuning

```bash
# Increase buffer sizes for better performance
TAR_BUFFER_SIZE="20480"  # 20MB buffer
COMPRESSION_BUFFER="8192"  # 8MB compression buffer
```

### Scheduling Optimization

#### Intelligent Scheduling

```bash
# Avoid peak hours
0 2 * * * /opt/dgmstt-backup/scripts/backup.sh  # 2 AM daily

# Weekend full backups, weekday incrementals
0 2 * * 0 /opt/dgmstt-backup/scripts/backup.sh --full
0 2 * * 1-6 /opt/dgmstt-backup/scripts/backup.sh --incremental

# Staggered backups for multiple systems
0 2 * * * sleep $((RANDOM % 3600)); /opt/dgmstt-backup/scripts/backup.sh
```

#### Load-Based Scheduling

```bash
# Only run backup if system load is low
0 2 * * * [ $(uptime | awk '{print $10}' | cut -d, -f1) -lt 2 ] && /opt/dgmstt-backup/scripts/backup.sh
```

## Maintenance

### Regular Health Checks

#### Daily Checks

```bash
# Create daily health check script
cat > /opt/dgmstt-backup/scripts/daily-check.sh << 'EOF'
#!/bin/bash

echo "=== DGMSTT Backup System Health Check ==="
echo "Date: $(date)"
echo

# Check last backup
LAST_BACKUP=$(sudo /opt/dgmstt-backup/scripts/backup.sh --status --json | jq -r '.last_backup')
echo "Last backup: $LAST_BACKUP"

# Check disk space
DISK_USAGE=$(df -h /opt/dgmstt-backup/backups | tail -1 | awk '{print $5}')
echo "Backup disk usage: $DISK_USAGE"

# Check backup count
BACKUP_COUNT=$(ls -1 /opt/dgmstt-backup/backups/*.tar.gz 2>/dev/null | wc -l)
echo "Total backups: $BACKUP_COUNT"

# Check for errors in logs
ERROR_COUNT=$(grep -c "ERROR" /var/log/dgmstt-backup/backup.log)
echo "Recent errors: $ERROR_COUNT"

# Verify latest backup
if sudo /opt/dgmstt-backup/scripts/backup.sh --verify --quiet; then
    echo "Latest backup: VERIFIED"
else
    echo "Latest backup: VERIFICATION FAILED"
fi

echo "=== End Health Check ==="
EOF

chmod +x /opt/dgmstt-backup/scripts/daily-check.sh

# Add to cron
echo "0 8 * * * /opt/dgmstt-backup/scripts/daily-check.sh | mail -s 'DGMSTT Backup Health Check' admin@example.com" | sudo crontab -
```

#### Weekly Maintenance

```bash
# Create weekly maintenance script
cat > /opt/dgmstt-backup/scripts/weekly-maintenance.sh << 'EOF'
#!/bin/bash

echo "=== Weekly Backup System Maintenance ==="

# Rotate logs
sudo logrotate -f /etc/logrotate.d/dgmstt-backup

# Clean up old backups
sudo /opt/dgmstt-backup/scripts/backup.sh --cleanup

# Verify random backup
RANDOM_BACKUP=$(ls /opt/dgmstt-backup/backups/*.tar.gz | shuf -n 1)
echo "Verifying random backup: $(basename $RANDOM_BACKUP)"
sudo /opt/dgmstt-backup/scripts/backup.sh --verify --backup="$RANDOM_BACKUP"

# Update backup statistics
sudo /opt/dgmstt-backup/scripts/backup.sh --stats > /var/log/dgmstt-backup/weekly-stats.log

# Check for system updates
if command -v apt >/dev/null; then
    sudo apt list --upgradable | grep -E "(tar|gzip|cron)"
elif command -v yum >/dev/null; then
    sudo yum check-update tar gzip cronie
fi

echo "=== Maintenance Complete ==="
EOF

chmod +x /opt/dgmstt-backup/scripts/weekly-maintenance.sh

# Add to cron for Sunday mornings
echo "0 6 * * 0 /opt/dgmstt-backup/scripts/weekly-maintenance.sh" | sudo crontab -
```

### Configuration Updates

#### Updating Backup Policies

```bash
# Backup current configuration
sudo cp /etc/dgmstt-backup/backup.conf /etc/dgmstt-backup/backup.conf.backup.$(date +%Y%m%d)

# Update retention policy
sudo sed -i 's/RETENTION_DAYS=30/RETENTION_DAYS=60/' /etc/dgmstt-backup/backup.conf

# Update compression settings
sudo sed -i 's/COMPRESSION_LEVEL=6/COMPRESSION_LEVEL=9/' /etc/dgmstt-backup/backup.conf

# Validate configuration
sudo /opt/dgmstt-backup/scripts/backup.sh --validate-config
```

#### Adding New Exclusions

```bash
# Add new exclusion patterns
cat >> /etc/dgmstt-backup/backup.conf << 'EOF'

# Additional exclusions added $(date)
EXCLUDE_PATTERNS+=(
    "*.pyc"
    "__pycache__/*"
    ".pytest_cache/*"
    "coverage/*"
)
EOF

# Test exclusions
sudo /opt/dgmstt-backup/scripts/backup.sh --dry-run --verbose | grep "Excluding"
```

### System Migration

#### Migrating to New Server

```bash
# 1. On old server: Create migration package
sudo tar -czf dgmstt-backup-migration.tar.gz \
    /opt/dgmstt-backup \
    /etc/dgmstt-backup \
    /var/log/dgmstt-backup \
    /etc/logrotate.d/dgmstt-backup

# 2. Transfer to new server
scp dgmstt-backup-migration.tar.gz newserver:/tmp/

# 3. On new server: Extract and setup
sudo tar -xzf /tmp/dgmstt-backup-migration.tar.gz -C /

# 4. Update paths in configuration
sudo sed -i 's|/old/path|/new/path|g' /etc/dgmstt-backup/backup.conf

# 5. Update crontab
sudo crontab -l > /tmp/crontab.backup
sudo crontab /tmp/crontab.backup

# 6. Test backup system
sudo /opt/dgmstt-backup/scripts/backup.sh --dry-run
```

#### Upgrading Backup System

```bash
# 1. Backup current installation
sudo tar -czf backup-system-backup-$(date +%Y%m%d).tar.gz \
    /opt/dgmstt-backup \
    /etc/dgmstt-backup

# 2. Download new version
wget https://github.com/your-repo/dgmstt/releases/latest/download/setup-backup-system.sh

# 3. Run upgrade
chmod +x setup-backup-system.sh
sudo ./setup-backup-system.sh --upgrade

# 4. Verify upgrade
sudo /opt/dgmstt-backup/scripts/backup.sh --version
sudo /opt/dgmstt-backup/scripts/backup.sh --test
```

### Monitoring Integration

#### Prometheus Metrics

```bash
# Create metrics exporter
cat > /opt/dgmstt-backup/scripts/metrics-exporter.sh << 'EOF'
#!/bin/bash

METRICS_FILE="/var/lib/prometheus/node-exporter/dgmstt-backup.prom"

# Get backup statistics
STATS=$(sudo /opt/dgmstt-backup/scripts/backup.sh --status --json)

# Export metrics
cat > "$METRICS_FILE" << METRICS
# HELP dgmstt_backup_last_success_timestamp Last successful backup timestamp
# TYPE dgmstt_backup_last_success_timestamp gauge
dgmstt_backup_last_success_timestamp $(echo "$STATS" | jq '.last_backup_timestamp')

# HELP dgmstt_backup_size_bytes Size of latest backup in bytes
# TYPE dgmstt_backup_size_bytes gauge
dgmstt_backup_size_bytes $(echo "$STATS" | jq '.latest_backup_size')

# HELP dgmstt_backup_duration_seconds Duration of latest backup in seconds
# TYPE dgmstt_backup_duration_seconds gauge
dgmstt_backup_duration_seconds $(echo "$STATS" | jq '.latest_backup_duration')

# HELP dgmstt_backup_files_total Total files in latest backup
# TYPE dgmstt_backup_files_total gauge
dgmstt_backup_files_total $(echo "$STATS" | jq '.latest_backup_files')
METRICS
EOF

chmod +x /opt/dgmstt-backup/scripts/metrics-exporter.sh

# Add to cron
echo "*/5 * * * * /opt/dgmstt-backup/scripts/metrics-exporter.sh" | sudo crontab -
```

#### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "DGMSTT Backup System",
    "panels": [
      {
        "title": "Backup Success Rate",
        "type": "stat",
        "targets": [
          {
            "expr": "rate(dgmstt_backup_last_success_timestamp[24h])"
          }
        ]
      },
      {
        "title": "Backup Size Trend",
        "type": "graph",
        "targets": [
          {
            "expr": "dgmstt_backup_size_bytes"
          }
        ]
      },
      {
        "title": "Backup Duration",
        "type": "graph",
        "targets": [
          {
            "expr": "dgmstt_backup_duration_seconds"
          }
        ]
      }
    ]
  }
}
```

## Advanced Features

### Incremental Backups

#### Setup Incremental Backup Chain

```bash
# Configure incremental backups
cat >> /etc/dgmstt-backup/backup.conf << 'EOF'

# Incremental backup settings
ENABLE_INCREMENTAL=true
INCREMENTAL_BASE_DIR="/opt/dgmstt-backup/incremental"
FULL_BACKUP_INTERVAL=7  # Days between full backups
EOF

# Create incremental backup schedule
sudo crontab -e
# Add these lines:
# 0 2 * * 0 /opt/dgmstt-backup/scripts/backup.sh --full
# 0 2 * * 1-6 /opt/dgmstt-backup/scripts/backup.sh --incremental
```

### Encryption

#### Setup Backup Encryption

```bash
# Install GPG
sudo apt install gnupg

# Generate backup key
sudo gpg --gen-key

# Configure encryption in backup.conf
cat >> /etc/dgmstt-backup/backup.conf << 'EOF'

# Encryption settings
ENABLE_ENCRYPTION=true
GPG_RECIPIENT="backup@example.com"
GPG_KEYRING="/etc/dgmstt-backup/keyring"
EOF

# Test encrypted backup
sudo /opt/dgmstt-backup/scripts/backup.sh --encrypt
```

### Cloud Integration

#### AWS S3 Integration

```bash
# Install AWS CLI
sudo apt install awscli

# Configure AWS credentials
sudo aws configure

# Add S3 settings to backup.conf
cat >> /etc/dgmstt-backup/backup.conf << 'EOF'

# S3 settings
ENABLE_S3_UPLOAD=true
S3_BUCKET="my-dgmstt-backups"
S3_REGION="us-west-2"
S3_STORAGE_CLASS="STANDARD_IA"
S3_ENCRYPTION="AES256"
EOF

# Test S3 upload
sudo /opt/dgmstt-backup/scripts/backup.sh --upload-s3
```

#### Google Cloud Storage Integration

```bash
# Install gsutil
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# Authenticate
gcloud auth login

# Configure GCS settings
cat >> /etc/dgmstt-backup/backup.conf << 'EOF'

# GCS settings
ENABLE_GCS_UPLOAD=true
GCS_BUCKET="my-dgmstt-backups"
GCS_STORAGE_CLASS="NEARLINE"
EOF
```

### Backup Validation

#### Automated Integrity Checking

```bash
# Create validation script
cat > /opt/dgmstt-backup/scripts/validate-backups.sh << 'EOF'
#!/bin/bash

BACKUP_DIR="/opt/dgmstt-backup/backups"
VALIDATION_LOG="/var/log/dgmstt-backup/validation.log"

echo "Starting backup validation: $(date)" >> "$VALIDATION_LOG"

for backup in "$BACKUP_DIR"/*.tar.gz; do
    if [ -f "$backup" ]; then
        echo "Validating: $(basename "$backup")" >> "$VALIDATION_LOG"

        # Check archive integrity
        if tar -tzf "$backup" >/dev/null 2>&1; then
            echo "  ✓ Archive integrity: PASS" >> "$VALIDATION_LOG"
        else
            echo "  ✗ Archive integrity: FAIL" >> "$VALIDATION_LOG"
            continue
        fi

        # Check file count
        FILE_COUNT=$(tar -tzf "$backup" | wc -l)
        echo "  Files: $FILE_COUNT" >> "$VALIDATION_LOG"

        # Check size
        SIZE=$(stat -c%s "$backup")
        echo "  Size: $SIZE bytes" >> "$VALIDATION_LOG"
    fi
done

echo "Validation completed: $(date)" >> "$VALIDATION_LOG"
EOF

chmod +x /opt/dgmstt-backup/scripts/validate-backups.sh

# Schedule weekly validation
echo "0 4 * * 0 /opt/dgmstt-backup/scripts/validate-backups.sh" | sudo crontab -
```

## Support and Contributing

### Getting Help

- **Documentation**: This README and inline help (`backup.sh --help`)
- **Logs**: Check `/var/log/dgmstt-backup/backup.log` for detailed information
- **Issues**: Report bugs and feature requests on GitHub
- **Community**: Join our Discord/Slack for community support

### Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Update documentation
6. Submit a pull request

### License

This backup system is released under the MIT License. See LICENSE file for details.

---

**Last Updated**: January 2024  
**Version**: 2.0.0  
**Maintainer**: DGMSTT Team
