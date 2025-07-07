# DGMSTT Backup Cron Management System

A comprehensive, production-ready solution for managing automated backups using cron jobs. This
system includes two main components:

1. **`install-backup-cron.sh`** - Cron job management script
2. **`backup.sh`** - Example backup script

## Features

### Core Functionality

- ✅ Safe cron job installation/uninstallment without duplicates
- ✅ Comprehensive cron syntax validation
- ✅ Optimal backup scheduling (2 AM daily by default)
- ✅ Graceful error handling for all conditions
- ✅ Status checking and enable/disable options
- ✅ Custom time scheduling support
- ✅ Environment variable handling
- ✅ Production-ready logging and monitoring

### Advanced Features

- 🔧 Command line options: install, uninstall, status, enable, disable, test
- 🕐 Flexible time formats: "HH:MM" or "MINUTE HOUR"
- 🌍 Full environment setup for cron execution
- 📝 Comprehensive error checking and user feedback
- 🔍 Backup script path validation
- ⚙️ Cron service availability checking
- 🗂️ Automatic log rotation and cleanup

## Quick Start

### 1. Installation with Defaults

```bash
# Install backup cron job (runs daily at 2:00 AM)
./install-backup-cron.sh install

# Check status
./install-backup-cron.sh status
```

### 2. Custom Installation

```bash
# Install with custom time (3:30 AM)
./install-backup-cron.sh install ./backup.sh "03:30"

# Install with different time format
./install-backup-cron.sh install ./backup.sh "30 3"
```

### 3. Management Operations

```bash
# Temporarily disable backup
./install-backup-cron.sh disable

# Re-enable backup
./install-backup-cron.sh enable

# Completely remove backup cron job
./install-backup-cron.sh uninstall
```

## Detailed Usage

### install-backup-cron.sh Commands

#### Install Command

```bash
# Basic installation (2:00 AM daily)
./install-backup-cron.sh install

# Custom script and time
./install-backup-cron.sh install /path/to/script.sh "04:15"

# With verbose output
./install-backup-cron.sh -v install

# Dry run (see what would happen)
./install-backup-cron.sh --dry-run install
```

#### Status Command

```bash
./install-backup-cron.sh status
```

**Output includes:**

- Current status (ENABLED/DISABLED/NOT INSTALLED)
- Schedule information
- Script path
- Log file locations
- Recent log entries
- Cron service status

#### Test Command

```bash
./install-backup-cron.sh test [script_path]
```

**Validates:**

- Cron service availability
- Crontab access permissions
- Log directory permissions
- Backup script existence and syntax
- Current cron job syntax (if exists)

#### Enable/Disable Commands

```bash
# Temporarily disable (comments out cron entry)
./install-backup-cron.sh disable

# Re-enable (uncomments cron entry)
./install-backup-cron.sh enable
```

#### Uninstall Command

```bash
# Completely remove backup cron job
./install-backup-cron.sh uninstall
```

### Time Format Options

The script supports two time formats:

1. **HH:MM Format** (24-hour)

   ```bash
   ./install-backup-cron.sh install script.sh "02:30"  # 2:30 AM
   ./install-backup-cron.sh install script.sh "14:45"  # 2:45 PM
   ```

2. **MINUTE HOUR Format** (cron standard)
   ```bash
   ./install-backup-cron.sh install script.sh "30 2"   # 2:30 AM
   ./install-backup-cron.sh install script.sh "45 14"  # 2:45 PM
   ```

## Error Handling

The system handles all common error conditions:

### System Errors

- ❌ **Cron service not running** - Checks and reports service status
- ❌ **Permission denied for crontab** - Validates user permissions
- ❌ **Log directory permissions** - Creates and validates log directories

### Configuration Errors

- ❌ **Invalid cron syntax** - Validates time format before installation
- ❌ **Missing backup script** - Checks script existence and permissions
- ❌ **Duplicate cron entries** - Prevents multiple installations

### Runtime Errors

- ❌ **Failed backup execution** - Comprehensive logging and error reporting
- ❌ **Disk space issues** - Backup script includes size monitoring
- ❌ **Network connectivity** - Graceful handling in backup operations

## File Structure

```
DGMSTT/
├── install-backup-cron.sh     # Main cron management script
├── backup.sh                  # Example backup script
├── BACKUP_CRON_README.md      # This documentation
└── ~/.backup-logs/            # Log directory (created automatically)
    ├── backup-cron.log        # Cron operation log
    ├── backup-errors.log      # Error log
    └── backup-output.log      # Backup script output
```

## Backup Script Features

The included `backup.sh` demonstrates a comprehensive backup solution:

### What Gets Backed Up

- 📁 **Project files**: package.json, tsconfig.json, README.md, etc.
- 📁 **Source directories**: src/, packages/, docs/, scripts/, shared/, protocol/
- 🔧 **Configuration files**: docker-compose.yml, Makefile, .env.example
- 📊 **Git information**: Current branch, commit hash, status, recent history

### Backup Features

- 🗂️ **Organized storage**: Timestamped backup directories
- 📋 **Manifest creation**: Detailed backup inventory
- 🧹 **Automatic cleanup**: Removes backups older than 7 days
- 📏 **Size reporting**: Shows backup size and contents
- 🔍 **Verification**: Validates backup completion

### Backup Location

```
~/backups/dgmstt/YYYYMMDD_HHMMSS/
├── package.json
├── tsconfig.json
├── src/
├── packages/
├── docs/
├── git-info.txt           # Git repository information
└── MANIFEST.txt           # Backup inventory and metadata
```

## Environment Variables

Customize behavior with environment variables:

```bash
# Custom backup script path
export BACKUP_SCRIPT_PATH="/path/to/custom/backup.sh"

# Custom log directory
export BACKUP_LOG_DIR="/custom/log/directory"

# Default cron time (MINUTE HOUR format)
export CRON_TIME="0 3"  # 3:00 AM
```

## Cron Job Details

### Generated Cron Entry

```bash
# DGMSTT Backup Job - Managed by install-backup-cron.sh
0 2 * * * PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/bin:/usr/bin:/bin; HOME=/home/user; SHELL=/bin/bash; "/path/to/backup.sh" >> "/home/user/.backup-logs/backup-cron.log" 2>> "/home/user/.backup-logs/backup-errors.log"
```

### Environment Setup

- **PATH**: Comprehensive PATH including system directories
- **HOME**: User home directory
- **SHELL**: Bash shell for script execution
- **Logging**: Separate logs for output and errors

## Troubleshooting

### Common Issues

#### 1. Cron Service Not Running

```bash
# Check service status
sudo systemctl status cron

# Start cron service
sudo systemctl start cron
sudo systemctl enable cron
```

#### 2. Permission Denied

```bash
# Check crontab permissions
ls -la /var/spool/cron/crontabs/

# Fix permissions if needed
sudo chown $USER:crontab /var/spool/cron/crontabs/$USER
sudo chmod 600 /var/spool/cron/crontabs/$USER
```

#### 3. Script Not Executable

```bash
# Make scripts executable
chmod +x install-backup-cron.sh
chmod +x backup.sh
```

#### 4. Log Directory Issues

```bash
# Create log directory manually
mkdir -p ~/.backup-logs
chmod 755 ~/.backup-logs
```

### Debugging

#### Enable Verbose Mode

```bash
./install-backup-cron.sh -v status
./install-backup-cron.sh -v install
```

#### Check Logs

```bash
# View cron operation log
tail -f ~/.backup-logs/backup-cron.log

# View error log
tail -f ~/.backup-logs/backup-errors.log

# View backup output
tail -f ~/.backup-logs/backup-output.log
```

#### Test Configuration

```bash
# Run comprehensive tests
./install-backup-cron.sh test

# Test backup script manually
./backup.sh
```

## Advanced Configuration

### Custom Backup Script

Create your own backup script following this template:

```bash
#!/bin/bash
set -euo pipefail

# Your backup logic here
echo "Starting custom backup..."

# Exit with appropriate code
exit 0  # Success
# exit 1  # Failure
```

### Multiple Backup Jobs

Install multiple backup jobs with different schedules:

```bash
# Daily backup at 2 AM
./install-backup-cron.sh install daily-backup.sh "02:00"

# Weekly backup at 3 AM (modify script to add weekly identifier)
./install-backup-cron.sh install weekly-backup.sh "03:00"
```

### Integration with Monitoring

Add monitoring hooks to your backup script:

```bash
# Send notification on completion
curl -X POST "https://monitoring.example.com/backup-complete" \
     -d "status=success&timestamp=$(date)"

# Log to external system
logger "DGMSTT backup completed successfully"
```

## Security Considerations

### File Permissions

- Scripts should be executable only by owner: `chmod 700`
- Log files should be readable only by owner: `chmod 600`
- Backup directories should have restricted access: `chmod 750`

### Sensitive Data

- Never include passwords or API keys in backup scripts
- Use environment variables for sensitive configuration
- Consider encrypting backup archives for sensitive projects

### Network Security

- Use secure protocols (HTTPS, SFTP) for remote backups
- Validate SSL certificates in backup scripts
- Implement proper authentication for remote storage

## Performance Optimization

### Large Projects

- Use incremental backups for large codebases
- Implement compression for backup archives
- Consider using rsync for efficient file synchronization

### Resource Management

- Schedule backups during low-usage periods
- Monitor disk space before creating backups
- Implement backup rotation to manage storage

## License and Support

This backup system is part of the DGMSTT project. For issues or feature requests:

1. Check the troubleshooting section above
2. Review log files for error details
3. Test configuration with `./install-backup-cron.sh test`
4. Create an issue in the project repository

## Version History

- **v1.0** - Initial release with comprehensive cron management
  - Full cron job lifecycle management
  - Robust error handling and validation
  - Production-ready logging and monitoring
  - Flexible time scheduling options
  - Example backup script with git integration
