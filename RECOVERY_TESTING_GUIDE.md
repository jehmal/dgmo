# DGMSTT Recovery Testing Framework Guide

## Overview

The `test-recovery.sh` script provides comprehensive automated testing for all disaster recovery
procedures in the DGMSTT system. It validates that recovery procedures work correctly, benchmarks
performance, and ensures data integrity.

## Features

### 🔧 **Core Testing Capabilities**

- **Session Data Recovery**: Tests main session and sub-session recovery procedures
- **Qdrant Database Recovery**: Validates vector database backup and restore operations
- **Partial Corruption Recovery**: Tests system resilience to corrupted data
- **Cross-Platform Recovery**: Ensures recovery works across different platforms (Linux, WSL,
  Windows)
- **Performance Degradation Testing**: Validates recovery under resource constraints
- **Rollback Procedures**: Tests ability to rollback to previous stable states

### 📊 **Performance Benchmarking**

- Recovery time measurement
- Throughput analysis under load
- Resource utilization monitoring
- Performance trend analysis

### 🔍 **Data Integrity Validation**

- JSON file structure validation
- Checksum verification
- File completeness checks
- Cross-reference validation

### 📈 **Comprehensive Reporting**

- HTML reports with visual metrics
- JSON metrics for CI/CD integration
- Detailed logging for troubleshooting
- Performance trend analysis

## Quick Start

### Basic Usage

```bash
# Run all recovery tests
./test-recovery.sh

# Run quick tests only (skip performance tests)
./test-recovery.sh --quick

# Run specific test scenario
./test-recovery.sh --scenario session

# Generate test data only
./test-recovery.sh --generate-data

# CI/CD mode (non-interactive)
./test-recovery.sh --ci
```

### Test Scenarios

| Scenario      | Description                       | Duration       |
| ------------- | --------------------------------- | -------------- |
| `session`     | Session data recovery tests       | ~2-5 minutes   |
| `qdrant`      | Qdrant database recovery tests    | ~3-7 minutes   |
| `corruption`  | Partial corruption recovery tests | ~1-3 minutes   |
| `platform`    | Cross-platform recovery tests     | ~1-2 minutes   |
| `performance` | Performance degradation tests     | ~5-15 minutes  |
| `rollback`    | Rollback procedure tests          | ~2-4 minutes   |
| `all`         | All test scenarios (default)      | ~15-35 minutes |

## Configuration

### Environment Variables

```bash
# Qdrant server configuration
export QDRANT_URL="http://localhost:6333"

# Custom test directory
export TEST_DIR="/custom/test/path"

# Custom backup directory
export BACKUP_DIR="/custom/backup/path"
```

### Directory Structure

```
recovery-tests/
├── logs/                    # Test execution logs
├── reports/                 # HTML and JSON reports
├── temp/                    # Temporary files during testing
├── test-data/              # Generated test data
│   ├── sessions/           # Test session data
│   └── checksums.md5       # Data integrity checksums
└── backups/                # Test backups
```

## Test Scenarios Explained

### 1. Session Data Recovery (`session`)

**Purpose**: Validates that session data can be recovered from backups and consolidated correctly.

**What it tests**:

- Session consolidation using `consolidate-sessions.sh`
- Recovery of main sessions and sub-sessions
- Index file reconstruction
- Data integrity after recovery

**Success criteria**:

- All sessions recovered successfully
- Sub-sessions properly linked to parent sessions
- Index files correctly rebuilt
- No data corruption detected

### 2. Qdrant Database Recovery (`qdrant`)

**Purpose**: Ensures Qdrant vector database can be backed up and restored.

**What it tests**:

- Snapshot creation and download
- Collection deletion and recreation
- Data restoration from snapshots
- Vector search functionality after recovery

**Success criteria**:

- Snapshots created successfully
- Collections restored with correct point counts
- Vector search returns expected results
- No data loss during recovery

### 3. Partial Corruption Recovery (`corruption`)

**Purpose**: Tests system resilience when some data files are corrupted.

**What it tests**:

- Detection of corrupted JSON files
- Graceful handling of invalid data
- Recovery of valid data while skipping corrupted files
- Data integrity scoring

**Success criteria**:

- Corrupted files identified correctly
- Valid data recovered successfully
- Integrity score above threshold (95%)
- System continues functioning despite corruption

### 4. Cross-Platform Recovery (`platform`)

**Purpose**: Ensures recovery procedures work across different operating systems.

**What it tests**:

- Path normalization for different platforms
- File system compatibility
- WSL/Windows path conversion
- Platform-specific recovery scripts

**Success criteria**:

- Paths correctly normalized for current platform
- Recovery scripts execute without platform-specific errors
- Data accessible across platform boundaries
- Compatibility score above 80%

### 5. Performance Degradation Testing (`performance`)

**Purpose**: Validates recovery performance under resource constraints.

**What it tests**:

- Backup/restore performance with large files
- Memory usage during recovery
- Disk I/O performance
- Recovery time under load

**Success criteria**:

- Recovery completes within time thresholds
- Memory usage stays within limits
- Disk I/O performance acceptable
- No significant performance degradation

### 6. Rollback Procedures (`rollback`)

**Purpose**: Tests ability to rollback to previous stable states.

**What it tests**:

- Multiple backup version handling
- Automatic rollback when latest version is corrupted
- Version selection logic
- Data consistency after rollback

**Success criteria**:

- Corrupted versions detected automatically
- Rollback to previous stable version successful
- Data consistency maintained
- No data loss during rollback

## Understanding Test Results

### Test Status Codes

- **PASS**: Test completed successfully, all criteria met
- **FAIL**: Test failed to meet success criteria
- **SKIP**: Test skipped due to missing dependencies or conditions

### Performance Metrics

- **Duration**: Time taken to complete the test (seconds)
- **Throughput**: Data processed per second (MB/s)
- **Recovery Time**: Time to restore from backup (seconds)
- **Integrity Score**: Percentage of data successfully recovered (0.0-1.0)

### Report Files

#### HTML Report (`recovery-report-TIMESTAMP.html`)

- Visual dashboard with test results
- Performance charts and metrics
- Integrity scores with color coding
- Detailed test breakdown

#### JSON Metrics (`metrics-TIMESTAMP.json`)

- Machine-readable test results
- Performance data for trending
- Integration with monitoring systems
- CI/CD pipeline integration

#### Detailed Log (`recovery-test-TIMESTAMP.log`)

- Complete test execution log
- Debug information
- Error details and stack traces
- Timing information

## Integration with Existing Tools

### Session Management

- Uses `consolidate-sessions.sh` for session recovery
- Integrates with existing session storage structure
- Validates sub-session relationships
- Tests session index reconstruction

### Qdrant Integration

- Leverages `qdrant-backup.sh` for database backups
- Tests MCP server integration
- Validates vector search functionality
- Ensures embedding model compatibility

### CI/CD Integration

```yaml
# Example GitHub Actions workflow
name: Recovery Testing
on:
  schedule:
    - cron: '0 2 * * *' # Daily at 2 AM
  workflow_dispatch:

jobs:
  recovery-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Run Recovery Tests
        run: ./test-recovery.sh --ci
      - name: Upload Reports
        uses: actions/upload-artifact@v3
        with:
          name: recovery-reports
          path: recovery-tests/reports/
```

## Troubleshooting

### Common Issues

#### 1. Qdrant Connection Failed

```bash
# Check Qdrant status
curl http://localhost:6333/health

# Start Qdrant if needed
docker run -p 6333:6333 qdrant/qdrant
```

#### 2. Insufficient Disk Space

```bash
# Check available space
df -h

# Clean up old test data
rm -rf recovery-tests/temp/*
```

#### 3. Permission Errors

```bash
# Fix script permissions
chmod +x test-recovery.sh

# Fix directory permissions
chmod -R 755 recovery-tests/
```

#### 4. Missing Dependencies

```bash
# Install required tools
sudo apt-get update
sudo apt-get install curl jq bc

# Verify installation
./test-recovery.sh --help
```

### Debug Mode

```bash
# Enable verbose logging
./test-recovery.sh --verbose

# Skip cleanup to inspect test data
./test-recovery.sh --skip-cleanup

# Generate test data for manual inspection
./test-recovery.sh --generate-data
```

## Best Practices

### Regular Testing Schedule

1. **Daily**: Quick tests (`--quick`) in CI/CD
2. **Weekly**: Full test suite on staging environment
3. **Monthly**: Performance baseline updates
4. **Before releases**: Complete test suite with manual review

### Monitoring and Alerting

```bash
# Set up monitoring for test failures
./test-recovery.sh --ci
if [ $? -ne 0 ]; then
    # Send alert to monitoring system
    curl -X POST "https://monitoring.example.com/alert" \
         -d "Recovery tests failed - check reports"
fi
```

### Data Retention

- Keep test reports for at least 30 days
- Archive performance metrics for trend analysis
- Rotate test data to prevent disk space issues
- Backup test configurations and scripts

## Advanced Usage

### Custom Test Scenarios

Create custom test scenarios by extending the framework:

```bash
# Add custom test function
test_custom_scenario() {
    local test_name="custom_scenario"
    local start_time=$(date +%s)

    # Your custom test logic here

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    record_test_result "$test_name" "PASS" "$duration" "Custom test details"
}
```

### Performance Baselines

Establish performance baselines for your environment:

```bash
# Run baseline tests
./test-recovery.sh --scenario performance > baseline.log

# Compare against baseline
./test-recovery.sh --scenario performance | diff baseline.log -
```

### Integration Testing

Combine with other testing frameworks:

```bash
# Run recovery tests as part of larger test suite
./test-recovery.sh --ci --quick
pytest integration_tests/
./test-recovery.sh --scenario qdrant
```

## Support and Contributing

### Getting Help

1. Check the troubleshooting section above
2. Review test logs in `recovery-tests/logs/`
3. Run with `--verbose` for detailed output
4. Check existing issues in the project repository

### Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

### Reporting Issues

When reporting issues, include:

- Test scenario that failed
- Complete error logs
- System information (OS, versions)
- Steps to reproduce
- Expected vs actual behavior

---

**Note**: This testing framework is designed to be non-destructive and safe to run in production
environments. However, always test in a staging environment first and ensure you have proper backups
before running recovery tests.
