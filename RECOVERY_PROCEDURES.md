# DGMSTT Disaster Recovery Procedures

## Executive Summary

This document provides comprehensive disaster recovery procedures for the DGMSTT (Dynamic Generative
Multi-Session Task Tracker) system. The system consists of multiple interconnected components
including OpenCode, DGM Python services, Qdrant vector database, Redis cache, PostgreSQL database,
and session management systems.

### Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO)

| Scenario                 | RTO        | RPO        | Priority |
| ------------------------ | ---------- | ---------- | -------- |
| Complete System Failure  | 4 hours    | 1 hour     | Critical |
| Session Data Corruption  | 2 hours    | 15 minutes | High     |
| Qdrant Database Failure  | 1 hour     | 5 minutes  | High     |
| Partial Data Corruption  | 30 minutes | 5 minutes  | Medium   |
| Storage System Failure   | 3 hours    | 30 minutes | High     |
| Accidental Data Deletion | 1 hour     | 15 minutes | Medium   |
| System Migration/Upgrade | 6 hours    | Planned    | Low      |

## Quick Reference Guide - Emergency Response

### 🚨 IMMEDIATE ACTIONS (First 5 Minutes)

1. **Assess the situation**

   ```bash
   # Check system status
   docker-compose ps
   curl -f http://localhost:6333/health  # Qdrant health
   curl -f http://localhost:3000/health  # OpenCode health
   curl -f http://localhost:8000/health  # DGM health
   ```

2. **Stop further damage**

   ```bash
   # Stop all services if corruption suspected
   docker-compose down

   # Backup current state immediately
   ./qdrant-backup.sh --emergency
   ./consolidate-sessions.sh
   ```

3. **Notify stakeholders**
   - Alert development team
   - Document incident start time
   - Begin incident log

### 📞 Emergency Contacts

| Role                   | Contact   | Responsibility              |
| ---------------------- | --------- | --------------------------- |
| System Administrator   | Primary   | Infrastructure recovery     |
| Database Administrator | Primary   | Data recovery operations    |
| Development Lead       | Secondary | Application-level recovery  |
| DevOps Engineer        | Secondary | Container and orchestration |

## Detailed Recovery Procedures

### 1. Complete System Failure Recovery

**Scenario**: All services are down, containers won't start, or infrastructure is compromised.

**Prerequisites**:

- Access to backup storage
- Docker and Docker Compose installed
- Network connectivity restored
- Sufficient disk space (minimum 10GB free)

**Recovery Steps**:

1. **Environment Preparation**

   ```bash
   # Verify system requirements
   docker --version
   docker-compose --version
   df -h  # Check disk space

   # Clean up any corrupted containers
   docker system prune -f
   docker volume prune -f
   ```

2. **Infrastructure Recovery**

   ```bash
   # Navigate to project directory
   cd /mnt/c/Users/jehma/Desktop/AI/DGMSTT

   # Restore environment configuration
   cp .env.example .env
   # Edit .env with production values

   # Start core infrastructure first
   docker-compose up -d redis postgres

   # Wait for databases to be ready
   sleep 30

   # Verify database connectivity
   docker-compose exec postgres pg_isready
   docker-compose exec redis redis-cli ping
   ```

3. **Data Recovery**

   ```bash
   # Restore Qdrant data
   docker-compose up -d qdrant
   sleep 10

   # Restore from latest backup
   ./restore-qdrant-backup.sh --latest

   # Restore session data
   ./consolidate-sessions.sh --restore
   ```

4. **Application Recovery**

   ```bash
   # Start application services
   docker-compose up -d dgm opencode

   # Start reverse proxy
   docker-compose up -d nginx
   ```

5. **Validation**

   ```bash
   # Run health checks
   ./validate-system-health.sh

   # Test core functionality
   curl -f http://localhost:3000/health
   curl -f http://localhost:8000/health
   curl -f http://localhost:6333/health
   ```

**Rollback Procedure**: If recovery fails, restore from previous known good state:

```bash
docker-compose down
./restore-system-snapshot.sh --date YYYY-MM-DD
docker-compose up -d
```

### 2. Session Data Corruption/Loss Recovery

**Scenario**: Session files are corrupted, missing, or inconsistent across storage locations.

**Recovery Steps**:

1. **Immediate Assessment**

   ```bash
   # Check session storage locations
   find ~/.local/share/opencode/project -name "ses_*" -type f | wc -l

   # Verify session integrity
   ./validate-sessions.sh --check-integrity

   # Identify corruption scope
   ./analyze-session-corruption.sh
   ```

2. **Data Recovery**

   ```bash
   # Stop services to prevent further corruption
   docker-compose stop opencode dgm

   # Backup current state
   cp -r ~/.local/share/opencode/project/storage/session \
        ~/.local/share/opencode/project/storage/session.corrupted.$(date +%Y%m%d-%H%M%S)

   # Restore from consolidated backup
   ./consolidate-sessions.sh --restore --source backup

   # Rebuild session indices
   ./rebuild-session-indices.sh
   ```

3. **Validation and Restart**

   ```bash
   # Validate restored sessions
   ./validate-sessions.sh --full-check

   # Restart services
   docker-compose start opencode dgm

   # Test session functionality
   ./test-session-operations.sh
   ```

### 3. Qdrant Database Failure Recovery

**Scenario**: Qdrant vector database is corrupted, inaccessible, or data is lost.

**Recovery Steps**:

1. **Immediate Response**

   ```bash
   # Check Qdrant status
   curl -f http://localhost:6333/health || echo "Qdrant is down"

   # Stop Qdrant service
   docker-compose stop qdrant

   # Backup current data directory (if accessible)
   docker run --rm -v qdrant_storage:/source -v $(pwd)/emergency_backup:/backup \
     alpine tar czf /backup/qdrant-emergency-$(date +%Y%m%d-%H%M%S).tar.gz -C /source .
   ```

2. **Database Recovery**

   ```bash
   # Remove corrupted data
   docker volume rm qdrant_storage

   # Recreate Qdrant service
   docker-compose up -d qdrant
   sleep 10

   # Restore from latest snapshot
   ./qdrant-backup.sh --restore --latest

   # Verify collections
   curl -s http://localhost:6333/collections | jq '.result.collections[].name'
   ```

3. **Data Validation**

   ```bash
   # Test vector operations
   ./test-qdrant-operations.sh

   # Verify memory storage functionality
   ./test-memory-storage.sh

   # Rebuild indices if needed
   ./rebuild-qdrant-indices.sh
   ```

### 4. Partial Data Corruption Recovery

**Scenario**: Specific collections, sessions, or data segments are corrupted while the rest of the
system functions.

**Recovery Steps**:

1. **Identify Corruption Scope**

   ```bash
   # Run comprehensive data integrity check
   ./check-data-integrity.sh --full-scan

   # Identify affected components
   ./identify-corruption-scope.sh
   ```

2. **Selective Recovery**

   ```bash
   # For corrupted Qdrant collections
   ./restore-qdrant-collection.sh --collection AgentMemories --from-backup

   # For corrupted sessions
   ./restore-sessions.sh --session-id ses_XXXXXX --from-backup

   # For corrupted sub-sessions
   ./restore-subsessions.sh --parent-session ses_XXXXXX
   ```

3. **Incremental Validation**
   ```bash
   # Validate specific components
   ./validate-component.sh --component qdrant
   ./validate-component.sh --component sessions
   ./validate-component.sh --component subsessions
   ```

### 5. Storage System Failure Recovery

**Scenario**: Underlying storage system fails, Docker volumes are corrupted, or filesystem issues
occur.

**Recovery Steps**:

1. **Storage Assessment**

   ```bash
   # Check filesystem health
   df -h
   fsck /dev/sda1  # Adjust device as needed

   # Check Docker storage
   docker system df
   docker volume ls
   ```

2. **Emergency Data Extraction**

   ```bash
   # Extract data from failing volumes
   ./extract-docker-volumes.sh --emergency

   # Create temporary storage
   mkdir -p /tmp/dgmstt-recovery

   # Copy critical data
   cp -r ~/.local/share/opencode/project /tmp/dgmstt-recovery/
   ./qdrant-backup.sh --output /tmp/dgmstt-recovery/qdrant-backup
   ```

3. **Storage Rebuild**

   ```bash
   # Stop all services
   docker-compose down

   # Remove corrupted volumes
   docker volume prune -f

   # Recreate storage infrastructure
   docker-compose up -d --force-recreate

   # Restore data
   ./restore-from-emergency-backup.sh --source /tmp/dgmstt-recovery
   ```

### 6. Accidental Data Deletion Recovery

**Scenario**: Important data has been accidentally deleted by user action or script error.

**Recovery Steps**:

1. **Immediate Stop**

   ```bash
   # Stop all write operations immediately
   docker-compose stop opencode dgm

   # Prevent further changes
   chmod -w ~/.local/share/opencode/project/storage/session/*
   ```

2. **Assess Deletion Scope**

   ```bash
   # Check what was deleted
   ./analyze-deletion.sh --timestamp "$(date -d '1 hour ago')"

   # Check backup availability
   ./list-available-backups.sh
   ```

3. **Selective Restore**

   ```bash
   # Restore specific deleted items
   ./restore-deleted-data.sh --type sessions --before-time "$(date -d '2 hours ago')"
   ./restore-deleted-data.sh --type qdrant-collections --before-time "$(date -d '2 hours ago')"

   # Verify restoration
   ./verify-restored-data.sh
   ```

### 7. System Migration/Upgrade Recovery

**Scenario**: Planned migration or upgrade fails, requiring rollback to previous version.

**Recovery Steps**:

1. **Pre-Migration Snapshot**

   ```bash
   # Create complete system snapshot
   ./create-system-snapshot.sh --name "pre-migration-$(date +%Y%m%d)"

   # Backup all data
   ./full-system-backup.sh --migration-prep
   ```

2. **Migration Rollback**

   ```bash
   # Stop new version
   docker-compose down

   # Restore previous version
   git checkout previous-stable-tag

   # Restore data
   ./restore-system-snapshot.sh --name "pre-migration-$(date +%Y%m%d)"

   # Start previous version
   docker-compose up -d
   ```

3. **Post-Rollback Validation**

   ```bash
   # Comprehensive system test
   ./run-system-tests.sh --full-suite

   # Verify data integrity
   ./validate-all-data.sh
   ```

## Prerequisites and Dependencies

### System Requirements

**Minimum Hardware**:

- CPU: 4 cores
- RAM: 8GB
- Storage: 50GB free space
- Network: 100Mbps

**Software Dependencies**:

- Docker Engine 20.10+
- Docker Compose 2.0+
- curl, jq, bash 4.0+
- Git 2.20+

### Network Requirements

**Ports Required**:

- 3000: OpenCode service
- 8000: DGM Python service
- 6333: Qdrant vector database
- 6379: Redis cache
- 5432: PostgreSQL database
- 80/443: Nginx reverse proxy

**External Dependencies**:

- Anthropic API access
- OpenAI API access (optional)
- Internet connectivity for container images

### Backup Storage Requirements

**Local Storage**:

- Minimum 100GB for full backups
- SSD recommended for performance
- RAID configuration preferred

**Remote Storage** (Recommended):

- Cloud storage (AWS S3, Google Cloud, Azure)
- Network-attached storage (NAS)
- Automated backup rotation

## Recovery Validation Procedures

### Health Check Scripts

1. **System Health Validation**

   ```bash
   #!/bin/bash
   # validate-system-health.sh

   echo "=== DGMSTT System Health Check ==="

   # Check container status
   echo "Container Status:"
   docker-compose ps

   # Check service endpoints
   echo "Service Health:"
   curl -f http://localhost:3000/health && echo "✓ OpenCode healthy"
   curl -f http://localhost:8000/health && echo "✓ DGM healthy"
   curl -f http://localhost:6333/health && echo "✓ Qdrant healthy"

   # Check data integrity
   echo "Data Integrity:"
   ./validate-sessions.sh --quick
   ./validate-qdrant-data.sh --quick

   echo "=== Health Check Complete ==="
   ```

2. **Data Integrity Validation**

   ```bash
   #!/bin/bash
   # validate-data-integrity.sh

   echo "=== Data Integrity Validation ==="

   # Session validation
   session_count=$(find ~/.local/share/opencode/project/storage/session/message -name "ses_*" | wc -l)
   echo "Sessions found: $session_count"

   # Sub-session validation
   subsession_count=$(find ~/.local/share/opencode/project/storage/session/sub-sessions -name "*.json" | wc -l)
   echo "Sub-sessions found: $subsession_count"

   # Qdrant validation
   collections=$(curl -s http://localhost:6333/collections | jq -r '.result.collections[].name' | wc -l)
   echo "Qdrant collections: $collections"

   # Cross-reference validation
   ./cross-validate-data.sh

   echo "=== Validation Complete ==="
   ```

### Performance Benchmarks

**Recovery Time Benchmarks**:

- Container restart: < 2 minutes
- Database restoration: < 30 minutes
- Full system recovery: < 4 hours
- Data validation: < 15 minutes

**Performance Metrics**:

- Session access time: < 100ms
- Vector search response: < 500ms
- Memory storage operation: < 200ms
- Cross-service communication: < 50ms

## Operational Guides

### Pre-Recovery Checklist

- [ ] Incident documented with timestamp
- [ ] Stakeholders notified
- [ ] Current system state backed up
- [ ] Recovery environment prepared
- [ ] Required credentials available
- [ ] Network connectivity verified
- [ ] Sufficient storage space confirmed
- [ ] Recovery team assembled

### Recovery Team Roles and Responsibilities

**Incident Commander**:

- Overall recovery coordination
- Stakeholder communication
- Decision making authority
- Progress tracking

**System Administrator**:

- Infrastructure recovery
- Container orchestration
- Network configuration
- Storage management

**Database Administrator**:

- Data recovery operations
- Backup restoration
- Data integrity validation
- Performance optimization

**Application Developer**:

- Application-level troubleshooting
- Code-related issues
- Configuration management
- Testing and validation

### Communication Procedures During Recovery

**Communication Channels**:

1. Primary: Slack #incident-response
2. Secondary: Email distribution list
3. Emergency: Phone tree

**Update Frequency**:

- Every 15 minutes during active recovery
- Every 30 minutes during validation
- Immediate updates for major milestones

**Status Report Template**:

```
INCIDENT UPDATE - [TIMESTAMP]
Status: [IN_PROGRESS/RESOLVED/ESCALATED]
Current Action: [DESCRIPTION]
ETA: [ESTIMATED_COMPLETION]
Next Update: [TIMESTAMP]
Issues: [ANY_BLOCKERS]
```

### Post-Recovery Validation

**Validation Checklist**:

- [ ] All services responding to health checks
- [ ] Data integrity verified
- [ ] Performance within acceptable limits
- [ ] User functionality tested
- [ ] Monitoring systems operational
- [ ] Backup systems functional
- [ ] Documentation updated

**User Acceptance Testing**:

1. Session creation and management
2. Sub-session functionality
3. Memory storage and retrieval
4. Cross-service communication
5. Data persistence verification

### Lessons Learned Documentation

**Post-Incident Review Template**:

```markdown
# Incident Post-Mortem: [INCIDENT_ID]

## Incident Summary

- **Date/Time**:
- **Duration**:
- **Impact**:
- **Root Cause**:

## Timeline

- [TIME]: Incident detected
- [TIME]: Response initiated
- [TIME]: Recovery completed
- [TIME]: Service restored

## What Went Well

-

## What Could Be Improved

-

## Action Items

- [ ]
- [ ]

## Prevention Measures

-
```

## Technical Specifications

### System Architecture Overview

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   OpenCode      │    │      DGM        │    │     Qdrant      │
│   (TypeScript)  │◄──►│   (Python)      │◄──►│  (Vector DB)    │
│   Port: 3000    │    │   Port: 8000    │    │   Port: 6333    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
         ┌─────────────────┐    ┌─────────────────┐
         │     Redis       │    │   PostgreSQL    │
         │   (Cache)       │    │  (Persistent)   │
         │   Port: 6379    │    │   Port: 5432    │
         └─────────────────┘    └─────────────────┘
```

### Backup Format Specifications

**Qdrant Snapshots**:

- Format: Binary snapshot files
- Naming: `{collection}_{timestamp}.snapshot`
- Compression: Native Qdrant compression
- Retention: 14 days default

**Session Data**:

- Format: JSON files
- Structure: Hierarchical directory structure
- Naming: `ses_{session_id}` for sessions
- Backup: Tar.gz archives with timestamps

**Configuration Files**:

- Format: YAML/JSON
- Location: Version controlled in Git
- Backup: Included in system snapshots

### Recovery Environment Setup

**Development Environment**:

```bash
# Clone repository
git clone https://github.com/your-org/dgmstt.git
cd dgmstt

# Setup environment
cp .env.example .env.development
docker-compose -f docker-compose.dev.yml up -d

# Restore development data
./restore-dev-data.sh
```

**Production Environment**:

```bash
# Production deployment
docker-compose -f docker-compose.prod.yml up -d

# Production data restoration
./restore-production-data.sh --verify-checksums
```

### Integration with Existing Tools

**Session Management Scripts**:

- `consolidate-sessions.sh`: Session data consolidation
- `workaround-subsessions.sh`: Sub-session handling
- `debug-subsessions-wsl.sh`: WSL-specific debugging

**Qdrant Configuration**:

- Collection: `AgentMemories`
- Vector size: 384 dimensions
- Distance metric: Cosine similarity
- Named vector: `fast-all-minilm-l6-v2`

**MCP Server Setup**:

- Embedding model: FastEmbed all-MiniLM-L6-v2
- Vector storage: Qdrant collections
- Memory format: Structured text with metadata

**Subsession Handling**:

- Storage: JSON files in sub-sessions directory
- Indexing: Separate index files for fast lookup
- Hierarchy: Parent-child relationship tracking

## Emergency Scripts Reference

### Quick Recovery Commands

```bash
# Emergency system stop
docker-compose down --remove-orphans

# Emergency backup
./qdrant-backup.sh --emergency && ./consolidate-sessions.sh

# Quick health check
curl -f http://localhost:3000/health && curl -f http://localhost:8000/health && curl -f http://localhost:6333/health

# Emergency restore
./restore-latest-backup.sh --force

# System restart
docker-compose up -d --force-recreate
```

### Monitoring Commands

```bash
# Container status
docker-compose ps

# Resource usage
docker stats

# Log monitoring
docker-compose logs -f --tail=100

# Disk usage
df -h && docker system df

# Network connectivity
docker-compose exec opencode ping dgm
docker-compose exec dgm ping qdrant
```

## Appendices

### Appendix A: Error Code Reference

| Error Code | Description                   | Recovery Action             |
| ---------- | ----------------------------- | --------------------------- |
| SYS-001    | Container startup failure     | Check logs, restart service |
| SYS-002    | Database connection timeout   | Verify network, restart DB  |
| SYS-003    | Storage volume corruption     | Restore from backup         |
| DATA-001   | Session corruption detected   | Run session validation      |
| DATA-002   | Qdrant collection missing     | Restore collection backup   |
| NET-001    | Service communication failure | Check network configuration |

### Appendix B: Contact Information

**Emergency Contacts**:

- System Administrator: [CONTACT_INFO]
- Database Administrator: [CONTACT_INFO]
- Development Lead: [CONTACT_INFO]
- DevOps Engineer: [CONTACT_INFO]

**Vendor Support**:

- Docker Support: [CONTACT_INFO]
- Cloud Provider: [CONTACT_INFO]
- Monitoring Service: [CONTACT_INFO]

### Appendix C: Change Log

| Version | Date       | Changes         | Author      |
| ------- | ---------- | --------------- | ----------- |
| 1.0     | 2025-01-06 | Initial version | System Team |

---

**Document Classification**: Internal Use Only  
**Last Updated**: 2025-01-06  
**Next Review**: 2025-04-06  
**Owner**: DGMSTT Operations Team
