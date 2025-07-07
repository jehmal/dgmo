# DGMSTT Disaster Recovery Troubleshooting Guide

This is the comprehensive troubleshooting guide for resolving disaster recovery issues in the DGMSTT
(Distributed General Multi-Session Task Tool) system. Use this as your go-to resource for diagnosing
and resolving critical recovery problems.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Diagnostic Procedures](#diagnostic-procedures)
3. [Common Issues](#common-issues)
4. [Error Message Catalog](#error-message-catalog)
5. [Performance Troubleshooting](#performance-troubleshooting)
6. [Advanced Recovery](#advanced-recovery)
7. [Escalation Procedures](#escalation-procedures)

---

## Quick Reference

### Emergency Commands

```bash
# Quick system health check
bun run quick-check.ts

# Comprehensive diagnostics
bun run diagnose-subsessions.ts

# Monitor system in real-time
bun run realtime-monitor.ts

# Emergency session recovery
bun run session-manager.ts --recover

# Qdrant health check
curl http://localhost:6333/health
```

### Critical File Locations

```
~/.local/share/opencode/User/workspaceStorage/*/dgmo/
├── sessions/                    # Session storage
├── storage/
│   ├── session/
│   │   ├── sub-sessions/       # Sub-session data
│   │   └── sub-session-index/  # Parent-child mappings
│   └── qdrant/                 # Vector database backups
└── logs/                       # System logs
```

### Status Indicators

| Symbol | Meaning              | Action Required     |
| ------ | -------------------- | ------------------- |
| ✅     | System healthy       | None                |
| ⚠️     | Warning condition    | Monitor closely     |
| ❌     | Critical failure     | Immediate action    |
| 🔄     | Recovery in progress | Wait for completion |
| 🚨     | Emergency state      | Follow escalation   |

---

## Diagnostic Procedures

### 1. System Health Assessment

#### Basic Health Check

```bash
# Run comprehensive system check
bun run quick-check.ts

# Expected output:
# ✅ App initialization successful
# ✅ Storage paths accessible
# ✅ Session management working
# ✅ Sub-session tracking active
```

#### Storage Verification

```bash
# Check storage integrity
bun run diagnose-subsessions.ts

# Verify Qdrant connection
curl -X GET http://localhost:6333/collections
```

#### Session Consistency Check

```bash
# Verify session-subsession relationships
bun run verify-subsessions-now.ts

# Check for orphaned sessions
bun run find-empty-json.ts
```

### 2. Log Analysis Techniques

#### System Logs

```bash
# View recent system logs
tail -f ~/.local/share/opencode/User/workspaceStorage/*/dgmo/logs/system.log

# Search for specific errors
grep -i "error\|failed\|exception" ~/.local/share/opencode/User/workspaceStorage/*/dgmo/logs/*.log
```

#### Debug Logging

```bash
# Enable debug mode
DEBUG=* dgmo

# Trace specific components
DEBUG=session:* dgmo
DEBUG=storage:* dgmo
DEBUG=qdrant:* dgmo
```

### 3. Data Integrity Verification

#### Session Data Validation

```bash
# Check session file integrity
bun run verify-context.ts

# Validate JSON structure
bun run debug-json-error.ts
```

#### Qdrant Data Verification

```bash
# Check collection health
curl -X GET http://localhost:6333/collections/AgentMemories

# Verify point count
curl -X POST http://localhost:6333/collections/AgentMemories/points/count \
  -H "Content-Type: application/json" \
  -d '{"exact": true}'
```

---

## Common Issues

### 1. Session Recovery Failures

#### Symptoms

- Sessions not loading on startup
- "Session not found" errors
- Incomplete session restoration

#### Root Causes & Solutions

**Missing Session Files**

```bash
# Diagnosis
ls -la ~/.local/share/opencode/User/workspaceStorage/*/dgmo/sessions/

# Recovery
bun run session-manager.ts --recover-missing
```

**Corrupted Session Data**

```bash
# Diagnosis
bun run debug-json-error.ts

# Recovery
bun run repair-indexes.ts
```

**Storage Path Mismatch**

```bash
# Diagnosis
bun run verify-context.ts

# Fix
export OPENCODE_DATA_PATH="/correct/path"
bun run fix-subsessions.bat
```

### 2. Qdrant Restoration Issues

#### Symptoms

- Vector search not working
- Memory retrieval failures
- Collection access errors

#### Root Causes & Solutions

**Qdrant Service Down**

```bash
# Check service status
curl http://localhost:6333/health

# Restart service
docker restart qdrant-container
# OR
systemctl restart qdrant
```

**Collection Configuration Mismatch**

```bash
# Check collection config
curl -X GET http://localhost:6333/collections/AgentMemories

# Recreate with correct config
curl -X DELETE http://localhost:6333/collections/AgentMemories
curl -X PUT http://localhost:6333/collections/AgentMemories \
  -H "Content-Type: application/json" \
  -d '{"vectors": {"fast-all-minilm-l6-v2": {"size": 384, "distance": "Cosine"}}}'
```

**Data Corruption**

```bash
# Backup current data
bun run qdrant-backup.sh

# Restore from backup
curl -X POST http://localhost:6333/collections/AgentMemories/snapshots/recover \
  -H "Content-Type: application/json" \
  -d '{"location": "/path/to/backup.snapshot"}'
```

### 3. Data Corruption Problems

#### Symptoms

- JSON parsing errors
- Incomplete data retrieval
- Inconsistent state

#### Root Causes & Solutions

**Empty JSON Files**

```bash
# Find empty files
bun run find-empty-json.ts

# Repair
bun run repair-indexes.ts
```

**Encoding Issues**

```bash
# Check file encoding
file ~/.local/share/opencode/User/workspaceStorage/*/dgmo/sessions/*

# Convert if needed
iconv -f ISO-8859-1 -t UTF-8 corrupted_file > fixed_file
```

**Partial Write Failures**

```bash
# Check disk space
df -h ~/.local/share/opencode/

# Check permissions
ls -la ~/.local/share/opencode/User/workspaceStorage/*/dgmo/
```

### 4. Permission and Access Issues

#### Symptoms

- "Permission denied" errors
- Cannot write to storage
- Access forbidden messages

#### Root Causes & Solutions

**File Permissions**

```bash
# Check permissions
ls -la ~/.local/share/opencode/User/workspaceStorage/*/dgmo/

# Fix permissions
chmod -R 755 ~/.local/share/opencode/User/workspaceStorage/*/dgmo/
chown -R $USER:$USER ~/.local/share/opencode/User/workspaceStorage/*/dgmo/
```

**Directory Access**

```bash
# Ensure directories exist
mkdir -p ~/.local/share/opencode/User/workspaceStorage/*/dgmo/{sessions,storage,logs}

# Set proper ownership
chown -R $USER:$USER ~/.local/share/opencode/
```

### 5. Network and Connectivity Problems

#### Symptoms

- Qdrant connection timeouts
- MCP server unreachable
- API endpoint failures

#### Root Causes & Solutions

**Port Conflicts**

```bash
# Check port usage
netstat -tulpn | grep :6333
lsof -i :6333

# Kill conflicting processes
sudo kill -9 $(lsof -t -i:6333)
```

**Firewall Issues**

```bash
# Check firewall rules
sudo ufw status
sudo iptables -L

# Allow Qdrant port
sudo ufw allow 6333
```

**DNS Resolution**

```bash
# Test connectivity
ping localhost
curl -v http://localhost:6333/health

# Check hosts file
cat /etc/hosts
```

### 6. Storage and Disk Space Issues

#### Symptoms

- "No space left on device"
- Write operations failing
- Slow performance

#### Root Causes & Solutions

**Disk Space**

```bash
# Check available space
df -h ~/.local/share/opencode/

# Clean up old sessions
bun run consolidate-sessions.sh

# Archive old data
tar -czf backup-$(date +%Y%m%d).tar.gz ~/.local/share/opencode/User/workspaceStorage/*/dgmo/sessions/
```

**Inode Exhaustion**

```bash
# Check inode usage
df -i ~/.local/share/opencode/

# Clean up small files
find ~/.local/share/opencode/ -type f -size 0 -delete
```

### 7. Configuration Mismatches

#### Symptoms

- Settings not persisting
- Unexpected behavior
- Feature not working

#### Root Causes & Solutions

**Missing Configuration Files**

```bash
# Check config files
ls -la ~/.local/share/opencode/User/workspaceStorage/*/dgmo/.opencode/

# Create missing configs
bun run debug-json-error.ts
```

**Version Mismatches**

```bash
# Check versions
dgmo --version
bun --version

# Update if needed
npm update -g dgmo
```

---

## Error Message Catalog

### Session Errors

| Error Message                            | Cause                        | Solution                           |
| ---------------------------------------- | ---------------------------- | ---------------------------------- |
| `Session not found: ses_*`               | Missing session file         | Run `session-manager.ts --recover` |
| `Cannot read property 'id' of undefined` | Corrupted session data       | Run `repair-indexes.ts`            |
| `JSON.parse error at position *`         | Invalid JSON in session file | Run `debug-json-error.ts`          |
| `Permission denied: /.../sessions/`      | File permission issue        | Fix with `chmod -R 755`            |

### Qdrant Errors

| Error Message                                     | Cause                 | Solution                  |
| ------------------------------------------------- | --------------------- | ------------------------- |
| `Connection refused: localhost:6333`              | Qdrant service down   | Restart Qdrant service    |
| `Collection not found: AgentMemories`             | Missing collection    | Recreate collection       |
| `Vector dimension mismatch`                       | Wrong embedding model | Update collection config  |
| `Not existing vector name: fast-all-minilm-l6-v2` | Named vector missing  | Create with named vectors |

### Storage Errors

| Error Message                       | Cause                 | Solution                  |
| ----------------------------------- | --------------------- | ------------------------- |
| `ENOENT: no such file or directory` | Missing storage path  | Create directories        |
| `ENOSPC: no space left on device`   | Disk full             | Clean up old data         |
| `EMFILE: too many open files`       | File descriptor limit | Increase ulimit           |
| `EACCES: permission denied`         | Permission issue      | Fix ownership/permissions |

### Sub-Session Errors

| Error Message                        | Cause               | Solution                      |
| ------------------------------------ | ------------------- | ----------------------------- |
| `No sub-sessions found for parent *` | Missing index file  | Run `diagnose-subsessions.ts` |
| `Sub-session index corrupted`        | Corrupted index     | Rebuild index                 |
| `Task tool execution failed`         | Task creation error | Check task tool logs          |
| `Agent creation timeout`             | Resource exhaustion | Check system resources        |

---

## Performance Troubleshooting

### 1. Slow Session Loading

#### Diagnosis

```bash
# Monitor session loading time
time bun run quick-check.ts

# Check session file sizes
du -sh ~/.local/share/opencode/User/workspaceStorage/*/dgmo/sessions/*
```

#### Solutions

```bash
# Archive old sessions
bun run consolidate-sessions.sh

# Optimize storage
bun run repair-indexes.ts

# Increase memory limits
export NODE_OPTIONS="--max-old-space-size=4096"
```

### 2. Qdrant Query Performance

#### Diagnosis

```bash
# Test query performance
curl -X POST http://localhost:6333/collections/AgentMemories/points/search \
  -H "Content-Type: application/json" \
  -d '{"vector": [0.1, 0.2, 0.3], "limit": 10}' \
  -w "Time: %{time_total}s\n"
```

#### Solutions

```bash
# Optimize collection
curl -X POST http://localhost:6333/collections/AgentMemories/index

# Increase Qdrant memory
# Edit docker-compose.yml or systemd service
```

### 3. Memory Usage Issues

#### Diagnosis

```bash
# Monitor memory usage
ps aux | grep -E "(dgmo|qdrant|node)"
free -h
```

#### Solutions

```bash
# Restart services
sudo systemctl restart qdrant
pkill -f dgmo && dgmo

# Optimize garbage collection
export NODE_OPTIONS="--max-old-space-size=2048 --gc-interval=100"
```

---

## Advanced Recovery

### 1. Manual Session Recovery

#### Complete Session Rebuild

```bash
#!/bin/bash
# manual-session-recovery.sh

echo "Starting manual session recovery..."

# Backup current state
cp -r ~/.local/share/opencode/User/workspaceStorage/*/dgmo/sessions/ \
      ~/.local/share/opencode/User/workspaceStorage/*/dgmo/sessions.backup.$(date +%Y%m%d)

# Rebuild session index
bun run repair-indexes.ts

# Verify integrity
bun run verify-subsessions-now.ts

echo "Manual recovery complete"
```

#### Selective Session Recovery

```bash
# Recover specific session
SESSION_ID="ses_8265d514cffeJtVYlbD526eTCt"
bun run session-manager.ts --recover-session $SESSION_ID

# Verify recovery
bun run quick-check.ts --session $SESSION_ID
```

### 2. Qdrant Data Salvage

#### Export All Data

```bash
# Create snapshot
curl -X POST http://localhost:6333/collections/AgentMemories/snapshots

# List snapshots
curl -X GET http://localhost:6333/collections/AgentMemories/snapshots

# Download snapshot
curl -X GET http://localhost:6333/collections/AgentMemories/snapshots/{snapshot_name} \
  --output backup.snapshot
```

#### Rebuild Collection

```bash
#!/bin/bash
# rebuild-qdrant.sh

echo "Rebuilding Qdrant collection..."

# Delete existing collection
curl -X DELETE http://localhost:6333/collections/AgentMemories

# Recreate with proper config
curl -X PUT http://localhost:6333/collections/AgentMemories \
  -H "Content-Type: application/json" \
  -d '{
    "vectors": {
      "fast-all-minilm-l6-v2": {
        "size": 384,
        "distance": "Cosine"
      }
    }
  }'

# Restore from snapshot if available
if [ -f "backup.snapshot" ]; then
  curl -X POST http://localhost:6333/collections/AgentMemories/snapshots/recover \
    -H "Content-Type: application/json" \
    -d '{"location": "./backup.snapshot"}'
fi

echo "Qdrant rebuild complete"
```

### 3. Emergency Workarounds

#### Bypass Qdrant for Critical Operations

```bash
# Disable Qdrant temporarily
export DISABLE_QDRANT=true
dgmo --no-memory

# Use local file-based memory
export MEMORY_BACKEND=file
dgmo
```

#### Session-less Operation Mode

```bash
# Start in stateless mode
dgmo --stateless

# Use temporary session
dgmo --temp-session
```

### 4. Data Migration Procedures

#### Migrate to New Storage Location

```bash
#!/bin/bash
# migrate-storage.sh

OLD_PATH="~/.local/share/opencode/User/workspaceStorage/old"
NEW_PATH="~/.local/share/opencode/User/workspaceStorage/new"

# Create new structure
mkdir -p "$NEW_PATH/dgmo"

# Copy data
cp -r "$OLD_PATH/dgmo/sessions" "$NEW_PATH/dgmo/"
cp -r "$OLD_PATH/dgmo/storage" "$NEW_PATH/dgmo/"

# Update configuration
export OPENCODE_DATA_PATH="$NEW_PATH"

# Verify migration
bun run verify-context.ts
```

---

## Escalation Procedures

### 1. When to Escalate

Escalate immediately for:

- **Data Loss**: Critical session or memory data is permanently lost
- **System Corruption**: Multiple components failing simultaneously
- **Security Breach**: Unauthorized access or data exposure
- **Performance Degradation**: System unusable for >30 minutes
- **Recovery Failure**: Standard procedures don't resolve the issue

### 2. Information to Gather

Before escalating, collect:

#### System Information

```bash
# System details
uname -a
df -h
free -h
ps aux | grep -E "(dgmo|qdrant|node)"

# DGMO version and config
dgmo --version
cat ~/.local/share/opencode/User/workspaceStorage/*/dgmo/.opencode/config.json
```

#### Error Details

```bash
# Recent logs
tail -100 ~/.local/share/opencode/User/workspaceStorage/*/dgmo/logs/system.log

# Error traces
grep -A 10 -B 10 "ERROR\|FATAL" ~/.local/share/opencode/User/workspaceStorage/*/dgmo/logs/*.log
```

#### Diagnostic Output

```bash
# Run full diagnostics
bun run diagnose-subsessions.ts > diagnostic-report.txt 2>&1
bun run quick-check.ts >> diagnostic-report.txt 2>&1
```

### 3. Emergency Response Protocols

#### Severity Levels

**P0 - Critical (Immediate Response)**

- Complete system failure
- Data corruption affecting multiple users
- Security incidents

**P1 - High (4-hour Response)**

- Single-user data loss
- Performance severely degraded
- Core features non-functional

**P2 - Medium (24-hour Response)**

- Minor feature issues
- Performance slightly degraded
- Workarounds available

**P3 - Low (72-hour Response)**

- Enhancement requests
- Documentation issues
- Non-critical bugs

#### Contact Procedures

1. **Internal Escalation**
   - Create detailed issue report
   - Include all diagnostic information
   - Specify severity level
   - Provide reproduction steps

2. **External Support**
   - GitHub Issues: https://github.com/sst/dgmo/issues
   - Include diagnostic report
   - Tag with appropriate severity
   - Follow up within 24 hours

3. **Emergency Contacts**
   - For P0 issues: Create GitHub issue with "CRITICAL" tag
   - Include phone contact if available
   - Escalate through appropriate channels

### 4. Recovery Documentation

After resolution, document:

#### Incident Report

```markdown
# Incident Report: [Date] - [Brief Description]

## Summary

- **Start Time**: [timestamp]
- **End Time**: [timestamp]
- **Duration**: [duration]
- **Severity**: [P0/P1/P2/P3]

## Impact

- **Users Affected**: [number/description]
- **Services Affected**: [list]
- **Data Loss**: [yes/no/details]

## Root Cause

[Detailed analysis of what caused the issue]

## Resolution

[Step-by-step description of how it was resolved]

## Prevention

[Changes made to prevent recurrence]

## Lessons Learned

[Key takeaways and improvements]
```

#### Update Procedures

- Update this troubleshooting guide with new solutions
- Add new error messages to the catalog
- Document any new diagnostic procedures
- Share knowledge with the team

---

## Appendix

### A. Diagnostic Script Reference

#### Core Diagnostic Scripts

| Script                      | Purpose                     | Usage                               |
| --------------------------- | --------------------------- | ----------------------------------- |
| `quick-check.ts`            | Basic health check          | `bun run quick-check.ts`            |
| `diagnose-subsessions.ts`   | Sub-session diagnostics     | `bun run diagnose-subsessions.ts`   |
| `debug-json-error.ts`       | JSON file validation        | `bun run debug-json-error.ts`       |
| `repair-indexes.ts`         | Rebuild corrupted indexes   | `bun run repair-indexes.ts`         |
| `verify-subsessions-now.ts` | Session consistency check   | `bun run verify-subsessions-now.ts` |
| `realtime-monitor.ts`       | Real-time system monitoring | `bun run realtime-monitor.ts`       |
| `session-manager.ts`        | Session recovery operations | `bun run session-manager.ts --help` |

#### Monitoring and Tracing Scripts

| Script                       | Purpose                        | Usage                                |
| ---------------------------- | ------------------------------ | ------------------------------------ |
| `monitor-subsessions.ts`     | Monitor sub-session creation   | `bun run monitor-subsessions.ts`     |
| `monitor-subsessions-wsl.ts` | WSL-specific monitoring        | `bun run monitor-subsessions-wsl.ts` |
| `monitor-task-tool.ts`       | Task tool execution monitoring | `bun run monitor-task-tool.ts`       |
| `trace-subsessions.ts`       | Trace sub-session operations   | `bun run trace-subsessions.ts`       |
| `trace-task-execution.ts`    | Trace task execution flow      | `bun run trace-task-execution.ts`    |
| `trace-storage.ts`           | Trace storage operations       | `bun run trace-storage.ts`           |

#### Specialized Diagnostic Tools

| Script                        | Purpose                        | Usage                                 |
| ----------------------------- | ------------------------------ | ------------------------------------- |
| `check-subsessions-simple.ts` | Simple sub-session check       | `bun run check-subsessions-simple.ts` |
| `check-task-tool.ts`          | Task tool functionality check  | `bun run check-task-tool.ts`          |
| `check-temp-dirs.ts`          | Temporary directory validation | `bun run check-temp-dirs.ts`          |
| `find-empty-json.ts`          | Find corrupted JSON files      | `bun run find-empty-json.ts`          |
| `find-main-sessions.ts`       | Locate main session files      | `bun run find-main-sessions.ts`       |
| `find-my-subsessions.ts`      | Find user's sub-sessions       | `bun run find-my-subsessions.ts`      |

#### Recovery and Repair Scripts

| Script                    | Purpose                  | Usage                       |
| ------------------------- | ------------------------ | --------------------------- |
| `fix-subsessions.bat`     | Windows sub-session fix  | `./fix-subsessions.bat`     |
| `fix-and-run-tui.sh`      | Fix TUI and restart      | `./fix-and-run-tui.sh`      |
| `fix-app-init.sh`         | Fix app initialization   | `./fix-app-init.sh`         |
| `apply-fix-to-system.sh`  | Apply system-wide fixes  | `./apply-fix-to-system.sh`  |
| `consolidate-sessions.sh` | Consolidate session data | `./consolidate-sessions.sh` |

#### Test and Validation Scripts

| Script                | Purpose                        | Usage                   |
| --------------------- | ------------------------------ | ----------------------- |
| `test-subsessions.sh` | Test sub-session functionality | `./test-subsessions.sh` |
| `test-vision.sh`      | Test vision capabilities       | `./test-vision.sh`      |
| `test-visual-mode.sh` | Test visual mode integration   | `./test-visual-mode.sh` |
| `test-fix.sh`         | Test applied fixes             | `./test-fix.sh`         |

### B. Configuration Templates

#### Minimal Working Configuration

```json
// .opencode/config.json
{
  "agentMode": "all-tools",
  "experimental": {
    "mcp": true
  }
}
```

#### Qdrant Collection Configuration

```json
{
  "vectors": {
    "fast-all-minilm-l6-v2": {
      "size": 384,
      "distance": "Cosine"
    }
  }
}
```

### C. Common File Paths

```
# Main storage locations
~/.local/share/opencode/User/workspaceStorage/*/dgmo/

# Session files
sessions/ses_*/

# Sub-session data
storage/session/sub-sessions/
storage/session/sub-session-index/

# Configuration
.opencode/config.json
.opencode/app.json

# Logs
logs/system.log
logs/error.log
```

### D. Useful Commands

```bash
# Quick system status
curl -s http://localhost:6333/health && echo "Qdrant: ✅" || echo "Qdrant: ❌"

# Count sessions
ls ~/.local/share/opencode/User/workspaceStorage/*/dgmo/sessions/ | wc -l

# Check storage usage
du -sh ~/.local/share/opencode/User/workspaceStorage/*/dgmo/

# Monitor logs in real-time
tail -f ~/.local/share/opencode/User/workspaceStorage/*/dgmo/logs/system.log

# Test MCP connection
echo '{"jsonrpc": "2.0", "method": "ping", "id": 1}' | nc localhost 3000
```

### E. Known Issue Patterns and Validated Solutions

#### Sub-Session Tracking Issues

**Pattern**: Sub-sessions created but not visible in TUI

- **Root Cause**: Storage location mismatch between task tool and TUI
- **Validated Solution**: Run `diagnose-subsessions.ts` to identify storage paths
- **Prevention**: Ensure consistent use of `App.info().path.data`

#### Vision Capability Problems

**Pattern**: "I cannot see images" despite successful loading

- **Root Cause**: Wrong model or using "Read" command for images
- **Validated Solution**: Use vision-capable model and avoid "Read" for images
- **Prevention**: Use "analyze", "look at", or "describe" commands for images

#### JSON Parsing Errors

**Pattern**: `JSON.parse error at position *` during startup

- **Root Cause**: Empty or corrupted configuration files
- **Validated Solution**: Run `debug-json-error.ts` to recreate missing configs
- **Prevention**: Regular backup of configuration files

#### Qdrant Collection Mismatches

**Pattern**: `Not existing vector name: fast-all-minilm-l6-v2`

- **Root Cause**: MCP server expects named vectors but collection has default
- **Validated Solution**: Recreate collection with named vector configuration
- **Prevention**: Always use named vectors when creating collections

#### Storage Permission Issues

**Pattern**: `EACCES: permission denied` on session operations

- **Root Cause**: Incorrect file ownership or permissions
- **Validated Solution**: Fix with `chmod -R 755` and `chown -R $USER:$USER`
- **Prevention**: Run DGMO with consistent user permissions

---

_This troubleshooting guide is a living document. Please update it with new issues and solutions as
they are discovered._

**Last Updated**: July 6, 2025  
**Version**: 1.0  
**Maintainer**: DGMSTT Development Team
