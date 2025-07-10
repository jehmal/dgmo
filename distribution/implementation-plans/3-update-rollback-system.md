# Update & Rollback System Implementation Plan

## Overview

Build a robust, atomic update system that enables seamless updates with instant rollback capability,
ensuring DGMO users never experience broken installations.

## Core Architecture

### 1. Version Management System

```typescript
// Version structure for binary releases
interface DGMOVersion {
  version: string; // Semantic version
  releaseDate: number;

  // Binary information
  binaries: {
    platform: string;
    arch: string;
    size: number;
    checksum: string;
    signature: string;
    downloadUrl: string;
  }[];

  // Update metadata
  updates: {
    from: string; // Previous version
    type: 'patch' | 'minor' | 'major';
    size: number; // Patch size
    changes: ChangeLog;
    riskLevel: 'low' | 'medium' | 'high';
  };

  // Evolution plugins included
  evolutions: {
    id: string;
    description: string;
    autoApply: boolean;
  }[];

  // Rollback information
  rollback: {
    supported: boolean;
    minVersion: string; // Minimum version can rollback to
    dataVersion: number; // Data format version
  };
}
```

### 2. Differential Update System

```typescript
// Binary diff generation and application
export class DifferentialUpdater {
  async generatePatch(
    fromBinary: Buffer,
    toBinary: Buffer,
    version: VersionInfo,
  ): Promise<PatchFile> {
    // Use bsdiff algorithm for binary patches
    const rawPatch = await bsdiff.diff(fromBinary, toBinary);

    // Compress patch
    const compressed = await this.compress(rawPatch);

    // Create patch file with metadata
    return {
      header: {
        magic: 'DGMO_PATCH_V1',
        fromVersion: version.from,
        toVersion: version.to,
        fromChecksum: await this.checksum(fromBinary),
        toChecksum: await this.checksum(toBinary),
        patchChecksum: await this.checksum(compressed),
        compression: 'zstd',
        size: compressed.length,
      },
      data: compressed,
      signature: await this.sign(compressed),
    };
  }

  async applyPatch(currentBinary: string, patch: PatchFile): Promise<void> {
    // Verify current binary
    const current = await fs.readFile(currentBinary);
    const currentChecksum = await this.checksum(current);

    if (currentChecksum !== patch.header.fromChecksum) {
      throw new Error('Binary checksum mismatch');
    }

    // Decompress patch
    const patchData = await this.decompress(patch.data);

    // Apply patch to temporary file
    const tempFile = `${currentBinary}.update`;
    const patched = await bsdiff.patch(current, patchData);
    await fs.writeFile(tempFile, patched);

    // Verify result
    const patchedChecksum = await this.checksum(patched);
    if (patchedChecksum !== patch.header.toChecksum) {
      await fs.unlink(tempFile);
      throw new Error('Patch verification failed');
    }

    // Atomic replacement
    await this.atomicReplace(currentBinary, tempFile);
  }

  private async atomicReplace(original: string, replacement: string) {
    // Platform-specific atomic replacement
    if (process.platform === 'win32') {
      // Windows: Use MoveFileEx with MOVEFILE_REPLACE_EXISTING
      await this.windowsAtomicReplace(original, replacement);
    } else {
      // Unix: Use rename (atomic on same filesystem)
      await fs.rename(replacement, original);
    }
  }
}
```

### 3. Snapshot-Based Rollback System

```typescript
// Comprehensive snapshot system for instant rollback
export class SnapshotManager {
  private snapshotDir = path.join(dgmoHome, '.snapshots');

  async createSnapshot(reason: string): Promise<Snapshot> {
    const snapshot: Snapshot = {
      id: generateId(),
      timestamp: Date.now(),
      reason,
      version: await this.getCurrentVersion(),

      // Snapshot components
      components: {
        binary: await this.snapshotBinary(),
        config: await this.snapshotConfig(),
        plugins: await this.snapshotPlugins(),
        data: await this.snapshotUserData(),
        evolutions: await this.snapshotEvolutions(),
      },

      // Metadata
      metadata: {
        size: 0, // Calculated below
        checksum: '',
        platform: process.platform,
        arch: process.arch,
      },
    };

    // Calculate total size
    snapshot.metadata.size = await this.calculateSize(snapshot.components);

    // Create snapshot archive
    const archivePath = await this.createArchive(snapshot);
    snapshot.metadata.checksum = await this.checksum(archivePath);

    // Save snapshot metadata
    await this.saveSnapshotMetadata(snapshot);

    // Cleanup old snapshots (keep last 5)
    await this.cleanupOldSnapshots(5);

    return snapshot;
  }

  async rollback(snapshotId: string): Promise<void> {
    // Load snapshot
    const snapshot = await this.loadSnapshot(snapshotId);

    // Verify snapshot integrity
    await this.verifySnapshot(snapshot);

    // Stop DGMO if running
    await this.stopDGMO();

    try {
      // Restore in reverse order of criticality
      await this.restoreComponent(snapshot.components.data, 'data');
      await this.restoreComponent(snapshot.components.evolutions, 'evolutions');
      await this.restoreComponent(snapshot.components.plugins, 'plugins');
      await this.restoreComponent(snapshot.components.config, 'config');
      await this.restoreComponent(snapshot.components.binary, 'binary');

      // Update version info
      await this.updateVersionInfo(snapshot.version);

      // Verify restoration
      await this.verifyRestoration();
    } catch (error) {
      // Rollback failed - try to restore from backup
      await this.emergencyRestore();
      throw error;
    }

    // Restart DGMO
    await this.startDGMO();
  }

  private async snapshotBinary(): Promise<ComponentSnapshot> {
    const binaryPath = process.execPath;
    const binaryData = await fs.readFile(binaryPath);

    return {
      type: 'binary',
      path: binaryPath,
      size: binaryData.length,
      checksum: await this.checksum(binaryData),
      data: await this.compress(binaryData),
    };
  }

  private async restoreComponent(component: ComponentSnapshot, type: string): Promise<void> {
    console.log(`Restoring ${type}...`);

    const data = await this.decompress(component.data);
    const checksum = await this.checksum(data);

    if (checksum !== component.checksum) {
      throw new Error(`${type} checksum mismatch during restore`);
    }

    // Atomic write with backup
    const backupPath = `${component.path}.backup`;

    try {
      // Backup current
      if (await fs.exists(component.path)) {
        await fs.rename(component.path, backupPath);
      }

      // Write new
      await fs.writeFile(component.path, data);

      // Remove backup on success
      if (await fs.exists(backupPath)) {
        await fs.unlink(backupPath);
      }
    } catch (error) {
      // Restore backup on failure
      if (await fs.exists(backupPath)) {
        await fs.rename(backupPath, component.path);
      }
      throw error;
    }
  }
}
```

### 4. Update Manager

```typescript
// Central update coordination
export class UpdateManager {
  private updater = new DifferentialUpdater();
  private snapshots = new SnapshotManager();
  private currentVersion: DGMOVersion;

  async checkForUpdates(): Promise<UpdateInfo | null> {
    try {
      // Check update server
      const response = await fetch('https://api.dgmo.ai/v1/updates/check', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-DGMO-Version': this.currentVersion.version,
          'X-Platform': process.platform,
          'X-Arch': process.arch,
        },
        body: JSON.stringify({
          version: this.currentVersion.version,
          evolutions: await this.getInstalledEvolutions(),
          telemetry: await this.getAnonymousTelemetry(),
        }),
      });

      if (!response.ok) return null;

      const updateInfo: UpdateInfo = await response.json();

      // Verify update signature
      if (!(await this.verifyUpdateSignature(updateInfo))) {
        throw new Error('Invalid update signature');
      }

      return updateInfo;
    } catch (error) {
      console.error('Update check failed:', error);
      return null;
    }
  }

  async downloadUpdate(update: UpdateInfo): Promise<UpdatePackage> {
    const package: UpdatePackage = {
      version: update.version,
      patches: [],
      evolutions: [],
    };

    // Download binary patch if needed
    if (update.binaryPatch) {
      const patch = await this.downloadPatch(update.binaryPatch);
      package.patches.push(patch);
    }

    // Download evolution plugins
    for (const evolution of update.evolutions) {
      const plugin = await this.downloadEvolution(evolution);
      package.evolutions.push(plugin);
    }

    return package;
  }

  async applyUpdate(package: UpdatePackage, options: UpdateOptions = {}): Promise<void> {
    // Create pre-update snapshot
    const snapshot = await this.snapshots.createSnapshot(`Pre-update to ${package.version}`);

    try {
      // Show update progress
      const progress = new UpdateProgress();

      // Apply binary patches
      for (const patch of package.patches) {
        progress.stage('Applying binary update...');
        await this.updater.applyPatch(process.execPath, patch);
      }

      // Install evolution plugins
      for (const evolution of package.evolutions) {
        if (options.autoApplyEvolutions || evolution.autoApply) {
          progress.stage(`Installing ${evolution.name}...`);
          await this.installEvolution(evolution);
        }
      }

      // Update version info
      await this.updateVersionInfo(package.version);

      // Verify update
      progress.stage('Verifying update...');
      await this.verifyUpdate(package.version);

      progress.complete('Update successful!');

      // Schedule restart if needed
      if (package.requiresRestart) {
        await this.scheduleRestart();
      }
    } catch (error) {
      // Rollback on failure
      console.error('Update failed, rolling back...', error);
      await this.snapshots.rollback(snapshot.id);
      throw error;
    }
  }

  async scheduleRestart(): Promise<void> {
    // Notify user
    await this.notifyUser({
      title: 'Restart Required',
      message: 'DGMO needs to restart to complete the update.',
      actions: [
        { label: 'Restart Now', action: 'restart' },
        { label: 'Restart Later', action: 'defer' },
      ],
    });
  }
}
```

### 5. Self-Healing System

```typescript
// Automatic repair and recovery
export class SelfHealingSystem {
  async verify(): Promise<HealthStatus> {
    const status: HealthStatus = {
      healthy: true,
      issues: [],
      repairableIssues: [],
    };

    // Check binary integrity
    const binaryCheck = await this.verifyBinary();
    if (!binaryCheck.valid) {
      status.healthy = false;
      status.issues.push(binaryCheck.issue);
      if (binaryCheck.repairable) {
        status.repairableIssues.push(binaryCheck.issue);
      }
    }

    // Check configuration
    const configCheck = await this.verifyConfig();
    if (!configCheck.valid) {
      status.healthy = false;
      status.issues.push(configCheck.issue);
      status.repairableIssues.push(configCheck.issue);
    }

    // Check plugins
    const pluginChecks = await this.verifyPlugins();
    for (const check of pluginChecks) {
      if (!check.valid) {
        status.healthy = false;
        status.issues.push(check.issue);
        if (check.repairable) {
          status.repairableIssues.push(check.issue);
        }
      }
    }

    return status;
  }

  async repair(): Promise<RepairResult> {
    const result: RepairResult = {
      success: true,
      repaired: [],
      failed: [],
    };

    const status = await this.verify();

    for (const issue of status.repairableIssues) {
      try {
        await this.repairIssue(issue);
        result.repaired.push(issue);
      } catch (error) {
        result.success = false;
        result.failed.push({
          issue,
          error: error.message,
        });
      }
    }

    return result;
  }

  private async repairIssue(issue: HealthIssue): Promise<void> {
    switch (issue.type) {
      case 'binary_corruption':
        await this.repairBinary(issue);
        break;

      case 'config_invalid':
        await this.repairConfig(issue);
        break;

      case 'plugin_missing':
        await this.repairPlugin(issue);
        break;

      case 'permission_error':
        await this.repairPermissions(issue);
        break;
    }
  }

  private async repairBinary(issue: HealthIssue): Promise<void> {
    // Try to download fresh binary
    const version = await this.getCurrentVersion();
    const binaryUrl = await this.getBinaryUrl(version);

    const freshBinary = await this.downloadBinary(binaryUrl);

    // Verify fresh binary
    if (!(await this.verifyBinaryChecksum(freshBinary, version.checksum))) {
      throw new Error('Downloaded binary verification failed');
    }

    // Replace corrupted binary
    await this.replaceBinary(freshBinary);
  }
}
```

### 6. Update UI/UX

```typescript
// User-friendly update experience
export class UpdateUI {
  async promptForUpdate(update: UpdateInfo): Promise<UpdateDecision> {
    const ui = new InteractiveUI();

    // Show update details
    ui.showUpdateInfo({
      currentVersion: this.currentVersion,
      newVersion: update.version,
      changes: update.changelog,
      size: update.downloadSize,
      evolutions: update.evolutions.map((e) => ({
        name: e.name,
        description: e.description,
        risk: e.riskLevel,
      })),
    });

    // Get user decision
    const decision = await ui.prompt({
      message: 'Would you like to update now?',
      choices: [
        { value: 'now', label: 'Update Now' },
        { value: 'later', label: 'Remind Me Later' },
        { value: 'skip', label: 'Skip This Version' },
        { value: 'auto', label: 'Always Auto-Update' },
      ],
    });

    // Handle evolution choices
    if (decision === 'now' && update.evolutions.length > 0) {
      const evolutionChoices = await ui.multiSelect({
        message: 'Select evolutions to apply:',
        choices: update.evolutions.map((e) => ({
          value: e.id,
          label: e.name,
          hint: e.description,
          checked: e.autoApply,
        })),
      });

      return {
        action: 'update',
        evolutions: evolutionChoices,
      };
    }

    return { action: decision };
  }

  showProgress(progress: UpdateProgress): void {
    // Real-time progress display
    const bar = new ProgressBar({
      format: 'Updating DGMO [:bar] :percent :stage',
      total: progress.total,
      width: 40,
    });

    progress.on('progress', (current, stage) => {
      bar.update(current, { stage });
    });

    progress.on('complete', (message) => {
      bar.terminate();
      console.log(chalk.green('✓'), message);
    });

    progress.on('error', (error) => {
      bar.terminate();
      console.log(chalk.red('✗'), error.message);
    });
  }
}
```

### 7. Background Update Service

```typescript
// Automatic update checking and downloading
export class BackgroundUpdateService {
  private interval: NodeJS.Timer;
  private updateManager = new UpdateManager();

  async start(): Promise<void> {
    // Check on startup
    await this.checkAndNotify();

    // Check periodically (every 6 hours)
    this.interval = setInterval(() => this.checkAndNotify(), 6 * 60 * 60 * 1000);

    // Check on network reconnect
    this.watchNetworkStatus();
  }

  private async checkAndNotify(): Promise<void> {
    const update = await this.updateManager.checkForUpdates();

    if (!update) return;

    // Check user preferences
    const prefs = await this.getUserPreferences();

    if (prefs.autoUpdate === 'all') {
      // Auto-update everything
      await this.autoUpdate(update);
    } else if (prefs.autoUpdate === 'security') {
      // Auto-update security fixes only
      if (update.type === 'security') {
        await this.autoUpdate(update);
      } else {
        await this.notifyUser(update);
      }
    } else {
      // Manual updates only
      await this.notifyUser(update);
    }
  }

  private async autoUpdate(update: UpdateInfo): Promise<void> {
    try {
      // Download in background
      const package = await this.updateManager.downloadUpdate(update);

      // Apply at convenient time
      await this.scheduleUpdate(package);
    } catch (error) {
      // Fall back to manual update
      await this.notifyUser(update);
    }
  }

  private async scheduleUpdate(package: UpdatePackage): Promise<void> {
    // Wait for idle time
    await this.waitForIdle();

    // Apply update
    await this.updateManager.applyUpdate(package, {
      autoApplyEvolutions: true,
    });
  }
}
```

## Implementation Timeline

### Week 1: Core Infrastructure

- Version management system
- Snapshot manager implementation
- Basic rollback functionality

### Week 2: Differential Updates

- Binary diff algorithm integration
- Patch generation and application
- Compression optimization

### Week 3: Update Manager

- Update checking API
- Download management
- Update application logic

### Week 4: Self-Healing

- Health verification system
- Automatic repair mechanisms
- Recovery procedures

### Week 5: UI/UX & Background Service

- Interactive update UI
- Progress tracking
- Background service
- Auto-update logic

## Success Metrics

1. **Update Success Rate**: > 99.5%
2. **Rollback Success Rate**: 100%
3. **Update Size**: < 10MB for minor updates
4. **Update Time**: < 30 seconds
5. **Downtime**: Zero downtime updates
6. **Recovery Success**: 100% from corrupted installations

## Security Considerations

1. **Signed Updates**: All updates cryptographically signed
2. **Checksum Verification**: Multiple checksum points
3. **Secure Channel**: TLS 1.3 for all downloads
4. **Rollback Protection**: Prevent downgrade attacks
5. **Integrity Monitoring**: Continuous binary verification
