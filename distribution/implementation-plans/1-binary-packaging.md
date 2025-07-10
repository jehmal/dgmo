# Binary Packaging System Implementation Plan

## Overview

Transform DGMO's multi-language codebase (TypeScript, Python, Go) into platform-specific binaries
that can run without any runtime dependencies.

## Technical Architecture

### 1. Build Pipeline Architecture

```yaml
Build Stages:
  1. Dependency Resolution:
    - Lock all npm/pip/go dependencies
    - Download and cache dependencies
    - Verify checksums

  2. Compilation:
    TypeScript:
      - Compile to ES2022 target
      - Bundle with Bun
      - Tree-shake unused code

    Python:
      - Compile to bytecode
      - Bundle with PyInstaller
      - Include only used stdlib modules

    Go:
      - Static compilation
      - CGO_ENABLED=0 for portability
      - Strip debug symbols

  3. Runtime Embedding:
    - Bun single-executable compilation
    - Python interpreter embedding
    - Static linking of Go components

  4. Platform Packaging:
    - Code signing
    - Installer generation
    - Compression
```

### 2. Runtime Bundle Structure

```
dgmo-binary
├── executable-header
├── embedded-resources/
│   ├── node-runtime/      # Bun runtime
│   ├── python-runtime/    # Embedded Python
│   ├── native-libs/       # Go components
│   └── assets/           # Static resources
├── application-code/
│   ├── cli-entry.js      # Main entry point
│   ├── core-modules.js   # Bundled TS/JS
│   ├── python-modules/   # Python bytecode
│   └── plugins/          # Core plugins
└── metadata/
    ├── version.json
    ├── checksums.sha256
    └── signature.sig
```

### 3. Implementation Steps

#### Step 1: Bun Single-Executable Setup

```typescript
// build/bun-bundler.ts
import { $ } from 'bun';

export async function buildBunExecutable(platform: string, arch: string) {
  const entryPoint = './src/cli/index.ts';
  const outputName = `dgmo-${platform}-${arch}`;

  // Compile TypeScript and bundle
  await $`bun build ${entryPoint} --compile --target=bun --outfile=${outputName}`;

  // Embed additional resources
  await embedResources(outputName, {
    'python-runtime': await buildPythonRuntime(),
    'go-components': await buildGoComponents(),
    'core-plugins': await bundleCorePlugins(),
  });
}

async function embedResources(binary: string, resources: Record<string, Buffer>) {
  // Use Bun's embedding API to include resources
  const exe = await Bun.file(binary).arrayBuffer();
  const builder = new ExecutableBuilder(exe);

  for (const [name, data] of Object.entries(resources)) {
    builder.addResource(name, data);
  }

  await Bun.write(binary, builder.build());
}
```

#### Step 2: Python Runtime Embedding

```python
# build/python_bundler.py
import PyInstaller.__main__
import sys
import os

def build_python_runtime():
    """Bundle Python runtime with DGM modules"""

    # PyInstaller spec file
    spec_content = '''
# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['../dgm/src/main.py'],
    pathex=['../dgm/src'],
    binaries=[],
    datas=[
        ('../dgm/src/agents', 'agents'),
        ('../dgm/src/tools', 'tools'),
        ('../dgm/src/evolution', 'evolution'),
    ],
    hiddenimports=[
        'anthropic',
        'openai',
        'numpy',
        'pandas',
        'pydantic',
        'fastapi',
        'uvicorn'
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['tkinter', 'matplotlib', 'test'],
    noarchive=False,
    optimize=2,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='dgm-runtime',
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    onefile=True
)
'''

    # Write spec file
    with open('dgm-runtime.spec', 'w') as f:
        f.write(spec_content)

    # Run PyInstaller
    PyInstaller.__main__.run([
        'dgm-runtime.spec',
        '--clean',
        '--noconfirm'
    ])
```

#### Step 3: Go Component Compilation

```go
// build/go_builder.go
package main

import (
    "fmt"
    "os"
    "os/exec"
    "runtime"
)

func buildGoComponents(platform, arch string) error {
    // Set build environment
    env := os.Environ()
    env = append(env,
        fmt.Sprintf("GOOS=%s", platform),
        fmt.Sprintf("GOARCH=%s", arch),
        "CGO_ENABLED=0", // Static linking
    )

    // Build flags for optimization
    ldflags := "-s -w" // Strip debug info

    // Build each component
    components := []string{
        "./src/native/file-watcher",
        "./src/native/process-manager",
        "./src/native/system-info",
    }

    for _, component := range components {
        cmd := exec.Command("go", "build",
            "-ldflags", ldflags,
            "-o", fmt.Sprintf("dist/%s", filepath.Base(component)),
            component,
        )
        cmd.Env = env

        if err := cmd.Run(); err != nil {
            return fmt.Errorf("failed to build %s: %w", component, err)
        }
    }

    return nil
}
```

#### Step 4: Cross-Platform Build Matrix

```typescript
// build/cross-platform.ts
interface BuildTarget {
  platform: NodeJS.Platform;
  arch: string;
  bunTarget: string;
  pythonTarget: string;
  goTarget: string;
}

const BUILD_MATRIX: BuildTarget[] = [
  {
    platform: 'win32',
    arch: 'x64',
    bunTarget: 'bun-windows-x64',
    pythonTarget: 'win_amd64',
    goTarget: 'windows/amd64',
  },
  {
    platform: 'darwin',
    arch: 'x64',
    bunTarget: 'bun-darwin-x64',
    pythonTarget: 'macosx_10_9_x86_64',
    goTarget: 'darwin/amd64',
  },
  {
    platform: 'darwin',
    arch: 'arm64',
    bunTarget: 'bun-darwin-arm64',
    pythonTarget: 'macosx_11_0_arm64',
    goTarget: 'darwin/arm64',
  },
  {
    platform: 'linux',
    arch: 'x64',
    bunTarget: 'bun-linux-x64',
    pythonTarget: 'linux_x86_64',
    goTarget: 'linux/amd64',
  },
];

export async function buildAllPlatforms() {
  for (const target of BUILD_MATRIX) {
    console.log(`Building for ${target.platform}-${target.arch}...`);

    await Promise.all([
      buildBunExecutable(target),
      buildPythonRuntime(target),
      buildGoComponents(target),
    ]);

    await packageBinary(target);
  }
}
```

#### Step 5: Binary Packaging and Compression

```typescript
// build/packager.ts
import { createWriteStream } from 'fs'
import { pipeline } from 'stream/promises'
import { createGzip } from 'zlib'
import { create as createTar } from 'tar'

export async function packageBinary(target: BuildTarget) {
  const binaryName = `dgmo-${target.platform}-${target.arch}`

  // Platform-specific packaging
  switch (target.platform) {
    case 'win32':
      await createWindowsInstaller(binaryName)
      break

    case 'darwin':
      await createMacOSBundle(binaryName)
      break

    case 'linux':
      await createLinuxPackages(binaryName)
      break
  }

  // Create compressed archive
  await compressBinary(binaryName)
}

async function createWindowsInstaller(binaryName: string) {
  // Create NSIS installer script
  const nsisScript = `
!include "MUI2.nsh"

Name "DGMO"
OutFile "${binaryName}-installer.exe"
InstallDir "$PROGRAMFILES64\\DGMO"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_LANGUAGE "English"

Section "DGMO CLI"
  SetOutPath $INSTDIR
  File "${binaryName}.exe"

  ; Add to PATH
  EnVar::SetHKLM
  EnVar::AddValue "PATH" "$INSTDIR"

  ; Create uninstaller
  WriteUninstaller "$INSTDIR\\Uninstall.exe"

  ; Registry entries
  WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\DGMO" \\
                   "DisplayName" "DGMO CLI"
  WriteRegStr HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\DGMO" \\
                   "UninstallString" "$INSTDIR\\Uninstall.exe"
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\\${binaryName}.exe"
  Delete "$INSTDIR\\Uninstall.exe"
  RMDir "$INSTDIR"

  ; Remove from PATH
  EnVar::SetHKLM
  EnVar::DeleteValue "PATH" "$INSTDIR"

  ; Remove registry entries
  DeleteRegKey HKLM "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\DGMO"
SectionEnd
`

  await Bun.write(`${binaryName}.nsi`, nsisScript)
  await $`makensis ${binaryName}.nsi`
}

async function createMacOSBundle(binaryName: string) {
  // Create .app bundle structure
  const appName = 'DGMO.app'
  await $`mkdir -p ${appName}/Contents/{MacOS,Resources}`

  // Copy binary
  await $`cp ${binaryName} ${appName}/Contents/MacOS/dgmo`
  await $`chmod +x ${appName}/Contents/MacOS/dgmo`

  // Create Info.plist
  const infoPlist = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>dgmo</string>
  <key>CFBundleIdentifier</key>
  <string>ai.dgmo.cli</string>
  <key>CFBundleName</key>
  <string>DGMO</string>
  <key>CFBundleVersion</key>
  <string>1.0.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
</dict>
</plist>`

  await Bun.write(`${appName}/Contents/Info.plist`, infoPlist)

  // Create DMG
  await $`hdiutil create -volname "DGMO" -srcfolder ${appName} -ov -format UDZO ${binaryName}.dmg`
}

async function createLinuxPackages(binaryName: string) {
  // Create AppImage
  const appDir = `${binaryName}.AppDir`
  await $`mkdir -p ${appDir}/{usr/bin,usr/share/applications}`

  // Copy binary
  await $`cp ${binaryName} ${appDir}/usr/bin/dgmo`
  await $`chmod +x ${appDir}/usr/bin/dgmo`

  // Create desktop entry
  const desktopEntry = `[Desktop Entry]
Name=DGMO
Exec=dgmo
Type=Application
Categories=Development;
`

  await Bun.write(`${appDir}/usr/share/applications/dgmo.desktop`, desktopEntry)

  // Create AppRun script
  const appRun = `#!/bin/bash
SELF=$(readlink -f "$0")
HERE=${SELF%/*}
export PATH="${HERE}/usr/bin:${PATH}"
exec "${HERE}/usr/bin/dgmo" "$@"
`

  await Bun.write(`${appDir}/AppRun`, appRun)
  await $`chmod +x ${appDir}/AppRun`

  // Build AppImage
  await $`appimagetool ${appDir} ${binaryName}.AppImage`

  // Create .deb package
  await createDebPackage(binaryName)

  // Create .rpm package
  await createRpmPackage(binaryName)
}
```

### 4. Build Automation

```yaml
# .github/workflows/build-release.yml
name: Build Release Binaries

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    strategy:
      matrix:
        include:
          - os: windows-latest
            platform: win32
            arch: x64
          - os: macos-latest
            platform: darwin
            arch: x64
          - os: macos-latest
            platform: darwin
            arch: arm64
          - os: ubuntu-latest
            platform: linux
            arch: x64

    runs-on: ${{ matrix.os }}

    steps:
      - uses: actions/checkout@v4

      - name: Setup Bun
        uses: oven-sh/setup-bun@v1

      - name: Setup Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Setup Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'

      - name: Install dependencies
        run: |
          bun install
          pip install pyinstaller

      - name: Build binary
        run: |
          bun run build:binary --platform=${{ matrix.platform }} --arch=${{ matrix.arch }}

      - name: Sign binary (Windows)
        if: matrix.platform == 'win32'
        run: |
          signtool sign /f ${{ secrets.WINDOWS_CERT }} /p ${{ secrets.WINDOWS_CERT_PASSWORD }} /t http://timestamp.digicert.com dgmo-*.exe

      - name: Sign binary (macOS)
        if: matrix.platform == 'darwin'
        run: |
          codesign --deep --force --verify --verbose --sign "${{ secrets.APPLE_DEVELOPER_ID }}" dgmo-*

      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: dgmo-${{ matrix.platform }}-${{ matrix.arch }}
          path: |
            dgmo-*
            *.dmg
            *.AppImage
            *.deb
            *.rpm
            *.exe
```

### 5. Size Optimization Strategies

1. **JavaScript Bundle Optimization**
   - Tree shaking with Bun
   - Minification and dead code elimination
   - Lazy loading of features
   - Code splitting for plugins

2. **Python Runtime Optimization**
   - Exclude unused stdlib modules
   - Compile to optimized bytecode
   - Strip docstrings in production
   - Use UPX compression

3. **Binary Compression**
   - UPX for executable compression
   - 7-Zip for distribution archives
   - Platform-specific optimizations

### 6. Testing Strategy

```typescript
// test/binary-tests.ts
describe('Binary Package Tests', () => {
  test('Binary starts without dependencies', async () => {
    // Test in Docker container with no Node/Python/Go
    const result = await runInCleanEnvironment('./dgmo --version');
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain('DGMO v');
  });

  test('All core commands work', async () => {
    const commands = ['init', 'evolve', 'update', 'help'];
    for (const cmd of commands) {
      const result = await runBinary(`./dgmo ${cmd} --help`);
      expect(result.exitCode).toBe(0);
    }
  });

  test('Binary size is within limits', async () => {
    const stats = await fs.stat('./dgmo');
    const sizeMB = stats.size / 1024 / 1024;
    expect(sizeMB).toBeLessThan(50); // 50MB limit
  });
});
```

## Success Criteria

1. **Binary Size**: < 50MB compressed per platform
2. **Startup Time**: < 500ms to first prompt
3. **Memory Usage**: < 100MB baseline
4. **No External Dependencies**: Runs on clean OS install
5. **Cross-Platform**: Works on Windows 10+, macOS 10.15+, Linux (glibc 2.17+)

## Timeline

- Week 1: Bun executable bundling + Go compilation
- Week 2: Python runtime embedding + testing
- Week 3: Platform packaging + installers
- Week 4: CI/CD setup + release automation
- Week 5: Testing + optimization
