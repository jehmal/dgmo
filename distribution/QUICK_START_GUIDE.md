# DGMO Distribution System - Quick Start Guide

## For Developers: Getting Started

### Prerequisites

- Bun 1.0+
- Python 3.11+
- Go 1.21+
- Docker (for cross-platform builds)
- Node.js 18+ (for tooling)

### Initial Setup

```bash
# Clone the repository
git clone https://github.com/dgmo/dgmo.git
cd dgmo

# Install dependencies
make install

# Set up distribution tooling
cd distribution
bun install
```

### Building Your First Binary

```bash
# Build for current platform
make build-binary

# Build for all platforms
make build-all-platforms

# Test the binary
./dist/dgmo-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m) --version
```

### Testing the Distribution

```bash
# Run distribution tests
make test-distribution

# Test installation script locally
./distribution/test-installer.sh

# Test update mechanism
make test-updates
```

## Key Implementation Files

### 1. Binary Building

- `distribution/build/bun-bundler.ts` - Bun compilation logic
- `distribution/build/python-bundler.py` - Python embedding
- `distribution/build/go-builder.go` - Go compilation
- `distribution/build/cross-platform.ts` - Platform matrix

### 2. Evolution System

- `distribution/evolution/plugin-interface.ts` - Plugin API
- `distribution/evolution/adapter.ts` - Evolution converter
- `distribution/evolution/sandbox.ts` - Security sandbox
- `distribution/evolution/patcher.ts` - Binary patching

### 3. Update System

- `distribution/update/manager.ts` - Update coordination
- `distribution/update/differential.ts` - Patch generation
- `distribution/update/rollback.ts` - Snapshot system
- `distribution/update/self-heal.ts` - Auto-repair

### 4. Installation

- `distribution/install/install.sh` - Universal installer
- `distribution/install/install.ps1` - Windows installer
- `distribution/install/homebrew/dgmo.rb` - Homebrew formula
- `distribution/install/auto-config.ts` - Auto-configuration

## Development Workflow

### 1. Making Changes

```bash
# Create feature branch
git checkout -b feature/distribution-improvement

# Make changes
vim distribution/src/...

# Test locally
make test-distribution

# Build and test binary
make build-binary
./test-binary.sh
```

### 2. Testing Cross-Platform

```bash
# Use Docker for cross-platform testing
make docker-test-all

# Or test specific platform
make docker-test-windows
make docker-test-macos
make docker-test-linux
```

### 3. Creating a Release

```bash
# Tag version
git tag v1.0.0

# Build release binaries
make release

# Upload to CDN
make deploy-cdn

# Update package managers
make update-package-managers
```

## Architecture Decisions

### Why Bun for JavaScript?

- Single-file executable support
- Fast startup time
- Built-in TypeScript support
- Small binary size

### Why PyInstaller for Python?

- Mature and stable
- Cross-platform support
- Handles complex dependencies
- Good compression

### Why Plugin Architecture?

- Enables evolution without source
- Safe sandboxed execution
- Hot-reload capability
- User control over changes

### Why Differential Updates?

- Minimal download size
- Faster updates
- Reduced bandwidth
- Better user experience

## Common Tasks

### Adding a New Platform

1. Update build matrix in `cross-platform.ts`
2. Add platform-specific build logic
3. Create installer variant
4. Add to CI/CD matrix
5. Test thoroughly

### Creating a Plugin

```typescript
// Example plugin structure
export const myPlugin: EvolutionPlugin = {
  id: 'my-enhancement',
  version: '1.0.0',
  type: 'enhancement',

  lifecycle: {
    async install() {
      // Installation logic
    },

    async activate() {
      // Activation logic
    },

    async deactivate() {
      // Cleanup
    },
  },
};
```

### Testing Updates

```bash
# Create test versions
make create-test-versions

# Test update flow
./test-update-flow.sh v1.0.0 v1.0.1

# Test rollback
./test-rollback.sh v1.0.1 v1.0.0
```

## Debugging

### Binary Size Issues

```bash
# Analyze binary size
make analyze-binary-size

# Check what's included
make list-binary-contents

# Optimize size
make optimize-binary
```

### Update Failures

```bash
# Check update logs
dgmo logs --update

# Verify checksums
dgmo verify --checksums

# Force rollback
dgmo rollback --force
```

### Plugin Issues

```bash
# List plugins
dgmo plugin list

# Debug plugin
dgmo plugin debug <plugin-id>

# Disable plugin
dgmo plugin disable <plugin-id>
```

## CI/CD Integration

### GitHub Actions

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
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v3
      - name: Build Binary
        run: make build-binary
      - name: Upload Artifact
        uses: actions/upload-artifact@v3
```

## Monitoring & Analytics

### Key Metrics to Track

1. **Installation Metrics**
   - Success rate by platform
   - Installation time
   - Error reasons

2. **Update Metrics**
   - Update adoption rate
   - Success/failure ratio
   - Rollback frequency

3. **Evolution Metrics**
   - Plugin adoption
   - User acceptance rate
   - Performance improvements

### Setting Up Monitoring

```typescript
// Add telemetry
import { telemetry } from './telemetry';

telemetry.track('installation', {
  platform: process.platform,
  version: version,
  duration: installTime,
  success: true,
});
```

## Troubleshooting

### Common Issues

1. **Build Failures**
   - Check all dependencies installed
   - Verify correct versions
   - Check disk space

2. **Large Binary Size**
   - Run size analysis
   - Check for unnecessary dependencies
   - Verify tree-shaking working

3. **Update Issues**
   - Verify CDN accessibility
   - Check signatures valid
   - Ensure atomic writes

## Support

- Documentation: https://dgmo.ai/docs
- Issues: https://github.com/dgmo/dgmo/issues
- Discord: https://discord.gg/dgmo
- Email: support@dgmo.ai

## Next Steps

1. Review the implementation plans in detail
2. Set up your development environment
3. Start with the binary building system
4. Join the #distribution channel on Discord
5. Begin implementation!

Remember: The goal is to make DGMO installation and updates as simple as possible for end users
while maintaining the power of the evolution system.
