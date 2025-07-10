# DGMO Consumer Distribution Implementation Guide

## Executive Summary

Transform DGMO from a developer tool requiring source code access into a consumer-ready CLI that can
be installed with a single command and self-update using the evolution system.

## Current State vs Target State

### Current State

- Requires: Git, Bun, Go, Python, full source code
- Installation: Manual build process
- Updates: Manual git pull and rebuild
- Evolution: Modifies source files directly

### Target State

- Requires: Nothing (all bundled)
- Installation: `curl -sSL https://dgmo.ai/install | sh`
- Updates: `dgmo update` or automatic
- Evolution: Plugin-based improvements

## Implementation Phases

### Phase 1: Binary Packaging (Week 1-2)

#### 1.1 Create Standalone Binaries

```bash
# Go TUI Binary
cd packages/tui
GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o dgmo-tui-linux
GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o dgmo-tui-darwin
GOOS=windows GOARCH=amd64 go build -ldflags="-s -w" -o dgmo-tui-windows.exe
```

#### 1.2 Bundle TypeScript/Bun Runtime

```typescript
// packages/opencode/build.ts
import { build } from 'bun';

await build({
  entrypoints: ['./src/index.ts'],
  outdir: './dist',
  target: 'bun',
  format: 'esm',
  minify: true,
  sourcemap: 'none',
  // Bundle all dependencies
  external: [],
});
```

#### 1.3 Embed Python Bridge

```python
# packages/dgm-integration/freeze.py
import PyInstaller.__main__

PyInstaller.__main__.run([
    'python/bridge.py',
    '--onefile',
    '--name=dgm-bridge',
    '--hidden-import=dgm',
    '--add-data=dgm:dgm',
])
```

### Phase 2: Evolution System Adaptation (Week 3-4)

#### 2.1 Plugin Architecture

```typescript
// packages/opencode/src/evolution/plugin-system.ts
export interface EvolutionPlugin {
  id: string;
  version: string;
  type: 'optimization' | 'feature' | 'bugfix';

  // Plugin lifecycle
  install(): Promise<void>;
  activate(): Promise<void>;
  deactivate(): Promise<void>;
  uninstall(): Promise<void>;

  // Evolution hooks
  onToolExecute?(tool: string, args: any): any;
  onError?(error: Error): void;
  onPerformanceData?(data: PerformanceData): void;
}

export class PluginManager {
  private plugins: Map<string, EvolutionPlugin> = new Map();

  async loadPlugin(path: string): Promise<void> {
    const plugin = await import(path);
    await this.validatePlugin(plugin);
    await plugin.install();
    this.plugins.set(plugin.id, plugin);
  }

  async applyEvolution(improvement: GeneratedImprovement): Promise<void> {
    // Convert improvement to plugin
    const plugin = await this.createPluginFromImprovement(improvement);
    await this.loadPlugin(plugin);
  }
}
```

#### 2.2 Configuration-Based Improvements

```typescript
// evolution-config.json
{
  "version": "1.0.0",
  "improvements": [
    {
      "id": "retry-logic-v1",
      "type": "error-handler",
      "pattern": "ECONNREFUSED",
      "config": {
        "maxRetries": 3,
        "backoff": "exponential",
        "timeout": 5000
      }
    },
    {
      "id": "cache-optimization-v1",
      "type": "performance",
      "target": "file-operations",
      "config": {
        "cacheSize": "100MB",
        "ttl": 3600
      }
    }
  ]
}
```

### Phase 3: Update System (Week 5-6)

#### 3.1 Version Management

```typescript
// packages/opencode/src/update/version-manager.ts
export class VersionManager {
  private currentVersion: string;
  private updateChannel: 'stable' | 'beta' | 'nightly';

  async checkForUpdates(): Promise<UpdateInfo | null> {
    const response = await fetch('https://api.dgmo.ai/updates/check', {
      method: 'POST',
      body: JSON.stringify({
        version: this.currentVersion,
        channel: this.updateChannel,
        platform: process.platform,
        arch: process.arch,
      }),
    });

    return response.json();
  }

  async downloadUpdate(update: UpdateInfo): Promise<string> {
    // Download differential patch
    const patchPath = await this.downloadPatch(update.patchUrl);

    // Verify signature
    await this.verifySignature(patchPath, update.signature);

    return patchPath;
  }

  async applyUpdate(patchPath: string): Promise<void> {
    // Create backup
    await this.createBackup();

    try {
      // Apply patch
      await this.applyPatch(patchPath);

      // Restart with new version
      await this.restart();
    } catch (error) {
      // Rollback on failure
      await this.rollback();
      throw error;
    }
  }
}
```

#### 3.2 Rollback System

```typescript
// packages/opencode/src/update/rollback-manager.ts
export class RollbackManager {
  private snapshots: VersionSnapshot[] = [];

  async createSnapshot(): Promise<string> {
    const snapshot: VersionSnapshot = {
      id: crypto.randomUUID(),
      timestamp: Date.now(),
      version: await this.getCurrentVersion(),
      files: await this.snapshotFiles(),
      config: await this.snapshotConfig(),
      plugins: await this.snapshotPlugins(),
    };

    await this.saveSnapshot(snapshot);
    return snapshot.id;
  }

  async rollback(snapshotId?: string): Promise<void> {
    const snapshot = snapshotId
      ? await this.getSnapshot(snapshotId)
      : await this.getLatestSnapshot();

    // Restore files
    await this.restoreFiles(snapshot.files);

    // Restore config
    await this.restoreConfig(snapshot.config);

    // Restore plugins
    await this.restorePlugins(snapshot.plugins);

    // Restart
    await this.restart();
  }
}
```

### Phase 4: Installation Infrastructure (Week 7-8)

#### 4.1 Universal Installer Script

```bash
#!/bin/sh
# install.sh - Universal DGMO installer

set -e

# Detect OS and architecture
OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
  Linux*)   PLATFORM="linux" ;;
  Darwin*)  PLATFORM="darwin" ;;
  MINGW*|CYGWIN*|MSYS*) PLATFORM="windows" ;;
  *)        echo "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *)        echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Download URL
DOWNLOAD_URL="https://github.com/sst/dgmo/releases/latest/download/dgmo-${PLATFORM}-${ARCH}"

# Installation directory
INSTALL_DIR="${DGMO_INSTALL_DIR:-$HOME/.dgmo}"
BIN_DIR="${DGMO_BIN_DIR:-$HOME/.local/bin}"

# Create directories
mkdir -p "$INSTALL_DIR" "$BIN_DIR"

# Download binary
echo "Downloading DGMO for $PLATFORM/$ARCH..."
curl -fsSL "$DOWNLOAD_URL" -o "$INSTALL_DIR/dgmo"
chmod +x "$INSTALL_DIR/dgmo"

# Create symlink
ln -sf "$INSTALL_DIR/dgmo" "$BIN_DIR/dgmo"

# Add to PATH if needed
case "$SHELL" in
  */bash)
    PROFILE="$HOME/.bashrc"
    ;;
  */zsh)
    PROFILE="$HOME/.zshrc"
    ;;
  *)
    PROFILE="$HOME/.profile"
    ;;
esac

if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  echo "export PATH=\"$BIN_DIR:\$PATH\"" >> "$PROFILE"
  echo "Added $BIN_DIR to PATH in $PROFILE"
fi

# Initialize DGMO
"$INSTALL_DIR/dgmo" init

echo "DGMO installed successfully!"
echo "Run 'dgmo' to get started"
```

#### 4.2 GitHub Release Automation

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: ubuntu-latest
            platform: linux
            arch: amd64
          - os: macos-latest
            platform: darwin
            arch: amd64
          - os: windows-latest
            platform: windows
            arch: amd64

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v3

      - name: Setup Bun
        uses: oven-sh/setup-bun@v1

      - name: Setup Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Build
        run: |
          make build-release PLATFORM=${{ matrix.platform }} ARCH=${{ matrix.arch }}

      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: dgmo-${{ matrix.platform }}-${{ matrix.arch }}
          path: dist/dgmo-${{ matrix.platform }}-${{ matrix.arch }}

  release:
    needs: build
    runs-on: ubuntu-latest

    steps:
      - name: Download artifacts
        uses: actions/download-artifact@v3

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: |
            dgmo-*/dgmo-*
          generate_release_notes: true
```

## Implementation Checklist

### Week 1-2: Binary Packaging

- [ ] Create Go build scripts for all platforms
- [ ] Bundle Bun runtime with TypeScript
- [ ] Package Python bridge
- [ ] Test standalone binaries
- [ ] Optimize binary sizes

### Week 3-4: Evolution Adaptation

- [ ] Design plugin interface
- [ ] Implement plugin loader
- [ ] Convert improvements to plugins
- [ ] Create plugin registry
- [ ] Test plugin system

### Week 5-6: Update System

- [ ] Implement version checker
- [ ] Create differential update system
- [ ] Build rollback mechanism
- [ ] Add update UI/UX
- [ ] Test update scenarios

### Week 7-8: Distribution

- [ ] Create installer scripts
- [ ] Setup GitHub releases
- [ ] Configure CDN
- [ ] Create documentation
- [ ] Launch beta program

## Success Metrics

1. **Installation Time**: < 30 seconds on average connection
2. **Binary Size**: < 50MB compressed
3. **Update Size**: < 5MB for typical updates
4. **Evolution Application**: < 1 second per improvement
5. **Rollback Time**: < 10 seconds
6. **Platform Coverage**: 95% of developer machines

## Next Steps

1. **Immediate**: Start with Go binary compilation
2. **This Week**: Create proof-of-concept plugin system
3. **Next Week**: Build update mechanism prototype
4. **Month 1**: Beta release with core features
5. **Month 2**: Production release with full evolution support

This transformation will make DGMO as easy to install and use as popular tools like Docker, Rust, or
Node.js, while maintaining its unique self-improving capabilities.
