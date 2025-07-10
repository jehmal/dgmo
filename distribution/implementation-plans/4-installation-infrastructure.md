# Installation Infrastructure Implementation Plan

## Overview

Create a seamless, single-command installation experience across all platforms with CDN
distribution, package manager integration, and automatic environment setup.

## Core Components

### 1. Universal Installer Script

```bash
#!/bin/sh
# Universal DGMO Installer - https://dgmo.ai/install
# Supports: Linux, macOS, Windows (WSL/Git Bash/MSYS2)

set -e

# Configuration
DGMO_VERSION="${DGMO_VERSION:-latest}"
DGMO_INSTALL_DIR="${DGMO_INSTALL_DIR:-}"
DGMO_CDN="https://cdn.dgmo.ai"
DGMO_API="https://api.dgmo.ai/v1"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log() { echo -e "${GREEN}[DGMO]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Detect system information
detect_platform() {
    local platform="unknown"
    local arch="unknown"

    # Detect OS
    case "$(uname -s)" in
        Linux*)
            platform="linux"
            # Check for specific distributions
            if [ -f /etc/os-release ]; then
                . /etc/os-release
                case "$ID" in
                    ubuntu|debian) DISTRO="debian" ;;
                    fedora|rhel|centos) DISTRO="redhat" ;;
                    arch|manjaro) DISTRO="arch" ;;
                    alpine) DISTRO="alpine" ;;
                    *) DISTRO="generic" ;;
                esac
            fi
            ;;
        Darwin*)
            platform="darwin"
            # Check for Homebrew
            if command -v brew >/dev/null 2>&1; then
                PACKAGE_MANAGER="brew"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)
            platform="windows"
            ;;
        *)
            error "Unsupported operating system: $(uname -s)"
            ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
        x86_64|amd64)
            arch="x64"
            ;;
        arm64|aarch64)
            arch="arm64"
            ;;
        armv7l)
            arch="arm"
            ;;
        *)
            error "Unsupported architecture: $(uname -m)"
            ;;
    esac

    echo "${platform}-${arch}"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check for curl or wget
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        error "Neither curl nor wget found. Please install one of them."
    fi

    # Check for tar
    if ! command -v tar >/dev/null 2>&1; then
        error "tar is required but not found. Please install it."
    fi

    # Check disk space (need at least 100MB)
    local available_space=$(df -k . | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt 102400 ]; then
        error "Insufficient disk space. At least 100MB required."
    fi
}

# Download file with progress
download() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --progress-bar "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget --quiet --show-progress "$url" -O "$output"
    else
        error "No download tool available"
    fi
}

# Verify checksum
verify_checksum() {
    local file="$1"
    local expected="$2"

    local actual=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$file" | cut -d' ' -f1)
    elif command -v shasum >/dev/null 2>&1; then
        actual=$(shasum -a 256 "$file" | cut -d' ' -f1)
    else
        warn "Cannot verify checksum - no SHA256 tool found"
        return 0
    fi

    if [ "$actual" != "$expected" ]; then
        error "Checksum verification failed"
    fi
}

# Get latest version info
get_version_info() {
    local platform="$1"
    local version="${DGMO_VERSION}"

    log "Fetching version information..."

    local version_url="${DGMO_API}/releases/${version}?platform=${platform}"
    local version_info=$(mktemp)

    download "$version_url" "$version_info"

    # Parse JSON response (portable way)
    DOWNLOAD_URL=$(grep -o '"url":"[^"]*' "$version_info" | cut -d'"' -f4)
    CHECKSUM=$(grep -o '"checksum":"[^"]*' "$version_info" | cut -d'"' -f4)
    VERSION=$(grep -o '"version":"[^"]*' "$version_info" | cut -d'"' -f4)

    rm -f "$version_info"

    if [ -z "$DOWNLOAD_URL" ]; then
        error "Failed to get download URL"
    fi
}

# Determine installation directory
get_install_dir() {
    if [ -n "$DGMO_INSTALL_DIR" ]; then
        echo "$DGMO_INSTALL_DIR"
        return
    fi

    # Default locations by platform
    case "$(uname -s)" in
        Linux*)
            if [ "$EUID" -eq 0 ]; then
                echo "/usr/local/bin"
            else
                echo "$HOME/.local/bin"
            fi
            ;;
        Darwin*)
            echo "/usr/local/bin"
            ;;
        MINGW*|MSYS*|CYGWIN*)
            echo "$HOME/bin"
            ;;
    esac
}

# Install binary
install_binary() {
    local platform="$1"
    local install_dir="$2"

    log "Downloading DGMO ${VERSION} for ${platform}..."

    # Create temp directory
    local temp_dir=$(mktemp -d)
    cd "$temp_dir"

    # Download binary
    local archive_name="dgmo-${platform}.tar.gz"
    download "$DOWNLOAD_URL" "$archive_name"

    # Verify checksum
    if [ -n "$CHECKSUM" ]; then
        log "Verifying checksum..."
        verify_checksum "$archive_name" "$CHECKSUM"
    fi

    # Extract binary
    log "Extracting..."
    tar -xzf "$archive_name"

    # Find the binary
    local binary_name="dgmo"
    if [ "$platform" = "windows-x64" ]; then
        binary_name="dgmo.exe"
    fi

    # Create install directory if needed
    mkdir -p "$install_dir"

    # Install binary
    log "Installing to ${install_dir}/${binary_name}..."

    if [ -w "$install_dir" ]; then
        mv "$binary_name" "$install_dir/"
        chmod +x "${install_dir}/${binary_name}"
    else
        # Need sudo
        log "Administrator access required..."
        sudo mv "$binary_name" "$install_dir/"
        sudo chmod +x "${install_dir}/${binary_name}"
    fi

    # Cleanup
    cd - >/dev/null
    rm -rf "$temp_dir"
}

# Setup shell integration
setup_shell_integration() {
    local install_dir="$1"
    local shell_rc=""

    # Detect shell
    case "$SHELL" in
        */bash)
            shell_rc="$HOME/.bashrc"
            ;;
        */zsh)
            shell_rc="$HOME/.zshrc"
            ;;
        */fish)
            shell_rc="$HOME/.config/fish/config.fish"
            ;;
        *)
            warn "Unknown shell: $SHELL"
            return
            ;;
    esac

    # Check if install_dir is in PATH
    if ! echo "$PATH" | grep -q "$install_dir"; then
        log "Adding $install_dir to PATH..."

        if [ "$SHELL" = "*/fish" ]; then
            echo "set -gx PATH $install_dir \$PATH" >> "$shell_rc"
        else
            echo "export PATH=\"$install_dir:\$PATH\"" >> "$shell_rc"
        fi

        warn "Please restart your shell or run: source $shell_rc"
    fi

    # Add completion
    log "Setting up shell completion..."
    "${install_dir}/dgmo" completion "$SHELL" > "${install_dir}/dgmo-completion"

    case "$SHELL" in
        */bash)
            echo "source ${install_dir}/dgmo-completion" >> "$shell_rc"
            ;;
        */zsh)
            echo "source ${install_dir}/dgmo-completion" >> "$shell_rc"
            ;;
        */fish)
            cp "${install_dir}/dgmo-completion" "$HOME/.config/fish/completions/dgmo.fish"
            ;;
    esac
}

# Post-installation setup
post_install() {
    local install_dir="$1"

    log "Running post-installation setup..."

    # Initialize DGMO
    "${install_dir}/dgmo" init --quiet

    # Check for updates
    "${install_dir}/dgmo" update --check

    # Show version
    "${install_dir}/dgmo" --version
}

# Main installation flow
main() {
    echo "DGMO Installer"
    echo "=============="
    echo ""

    # Check prerequisites
    check_prerequisites

    # Detect platform
    local platform=$(detect_platform)
    log "Detected platform: $platform"

    # Get version info
    get_version_info "$platform"

    # Get install directory
    local install_dir=$(get_install_dir)
    log "Install directory: $install_dir"

    # Install binary
    install_binary "$platform" "$install_dir"

    # Setup shell integration
    setup_shell_integration "$install_dir"

    # Post-installation
    post_install "$install_dir"

    echo ""
    log "DGMO ${VERSION} installed successfully!"
    log "Run 'dgmo --help' to get started"
    echo ""
}

# Run main function
main "$@"
```

### 2. Platform-Specific Installers

#### 2.1 Windows PowerShell Installer

```powershell
# install.ps1 - Windows PowerShell installer for DGMO
# Usage: iwr -useb https://dgmo.ai/install.ps1 | iex

$ErrorActionPreference = "Stop"

# Configuration
$DGMOVersion = if ($env:DGMO_VERSION) { $env:DGMO_VERSION } else { "latest" }
$InstallDir = if ($env:DGMO_INSTALL_DIR) { $env:DGMO_INSTALL_DIR } else { "$env:LOCALAPPDATA\DGMO\bin" }
$DGMOCDN = "https://cdn.dgmo.ai"
$DGMOAPI = "https://api.dgmo.ai/v1"

# Helper functions
function Write-Info($message) {
    Write-Host "[DGMO] " -ForegroundColor Green -NoNewline
    Write-Host $message
}

function Write-Error($message) {
    Write-Host "[ERROR] " -ForegroundColor Red -NoNewline
    Write-Host $message
    exit 1
}

function Write-Warning($message) {
    Write-Host "[WARN] " -ForegroundColor Yellow -NoNewline
    Write-Host $message
}

# Check prerequisites
function Test-Prerequisites {
    Write-Info "Checking prerequisites..."

    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Error "PowerShell 5.0 or higher is required"
    }

    # Check execution policy
    $executionPolicy = Get-ExecutionPolicy
    if ($executionPolicy -eq "Restricted") {
        Write-Warning "Execution policy is restricted. Attempting to bypass..."
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
    }

    # Check disk space
    $drive = (Get-Item $InstallDir -ErrorAction SilentlyContinue).PSDrive.Name
    if (-not $drive) { $drive = "C" }
    $freeSpace = (Get-PSDrive $drive).Free
    if ($freeSpace -lt 100MB) {
        Write-Error "Insufficient disk space. At least 100MB required."
    }
}

# Get version information
function Get-VersionInfo {
    Write-Info "Fetching version information..."

    $platform = "windows-x64"
    if ([Environment]::Is64BitOperatingSystem -eq $false) {
        Write-Error "32-bit Windows is not supported"
    }

    $versionUrl = "$DGMOAPI/releases/$DGMOVersion?platform=$platform"

    try {
        $response = Invoke-RestMethod -Uri $versionUrl -Method Get
        return @{
            Version = $response.version
            DownloadUrl = $response.url
            Checksum = $response.checksum
        }
    } catch {
        Write-Error "Failed to fetch version information: $_"
    }
}

# Download and verify file
function Get-DGMOBinary($versionInfo) {
    Write-Info "Downloading DGMO $($versionInfo.Version)..."

    $tempDir = New-TemporaryFile | %{ rm $_; mkdir $_ }
    $archivePath = Join-Path $tempDir "dgmo-windows-x64.zip"

    # Download with progress
    $progressPreference = 'Continue'
    Invoke-WebRequest -Uri $versionInfo.DownloadUrl -OutFile $archivePath

    # Verify checksum
    if ($versionInfo.Checksum) {
        Write-Info "Verifying checksum..."
        $actualChecksum = (Get-FileHash -Path $archivePath -Algorithm SHA256).Hash.ToLower()
        if ($actualChecksum -ne $versionInfo.Checksum) {
            Write-Error "Checksum verification failed"
        }
    }

    # Extract
    Write-Info "Extracting..."
    Expand-Archive -Path $archivePath -DestinationPath $tempDir -Force

    return Join-Path $tempDir "dgmo.exe"
}

# Install binary
function Install-Binary($binaryPath) {
    Write-Info "Installing to $InstallDir..."

    # Create directory
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # Copy binary
    $targetPath = Join-Path $InstallDir "dgmo.exe"
    Copy-Item -Path $binaryPath -Destination $targetPath -Force

    # Add to PATH if needed
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$InstallDir*") {
        Write-Info "Adding to PATH..."
        [Environment]::SetEnvironmentVariable(
            "Path",
            "$userPath;$InstallDir",
            "User"
        )
        $env:Path = "$env:Path;$InstallDir"
    }

    return $targetPath
}

# Setup Windows-specific features
function Setup-WindowsIntegration($dgmoPath) {
    Write-Info "Setting up Windows integration..."

    # Create Start Menu shortcut
    $startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
    $shortcutPath = Join-Path $startMenuPath "DGMO.lnk"

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $dgmoPath
    $shortcut.WorkingDirectory = $env:USERPROFILE
    $shortcut.IconLocation = $dgmoPath
    $shortcut.Description = "DGMO - Darwin Gödel Machine Orchestrator"
    $shortcut.Save()

    # Register protocol handler for dgmo://
    $regPath = "HKCU:\Software\Classes\dgmo"
    New-Item -Path $regPath -Force | Out-Null
    Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:DGMO Protocol"
    Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value ""

    $regCommand = "$regPath\shell\open\command"
    New-Item -Path $regCommand -Force | Out-Null
    Set-ItemProperty -Path $regCommand -Name "(Default)" -Value "`"$dgmoPath`" `"%1`""

    # Add context menu entry
    $regContext = "HKCU:\Software\Classes\Directory\Background\shell\DGMO"
    New-Item -Path $regContext -Force | Out-Null
    Set-ItemProperty -Path $regContext -Name "(Default)" -Value "Open DGMO here"
    Set-ItemProperty -Path $regContext -Name "Icon" -Value $dgmoPath

    $regContextCmd = "$regContext\command"
    New-Item -Path $regContextCmd -Force | Out-Null
    Set-ItemProperty -Path $regContextCmd -Name "(Default)" -Value "`"$dgmoPath`" init"
}

# Post-installation
function Complete-Installation($dgmoPath) {
    Write-Info "Running post-installation setup..."

    # Initialize DGMO
    & $dgmoPath init --quiet

    # Show version
    & $dgmoPath --version

    Write-Info "DGMO installed successfully!"
    Write-Info "Run 'dgmo --help' to get started"
    Write-Info ""
    Write-Warning "Please restart your terminal for PATH changes to take effect"
}

# Main installation
function Install-DGMO {
    Write-Host "DGMO Installer for Windows" -ForegroundColor Cyan
    Write-Host "=========================" -ForegroundColor Cyan
    Write-Host ""

    Test-Prerequisites

    $versionInfo = Get-VersionInfo
    $binaryPath = Get-DGMOBinary $versionInfo
    $installedPath = Install-Binary $binaryPath

    Setup-WindowsIntegration $installedPath
    Complete-Installation $installedPath

    # Cleanup
    Remove-Item -Path (Split-Path $binaryPath) -Recurse -Force
}

# Run installation
Install-DGMO
```

#### 2.2 macOS Homebrew Formula

```ruby
# dgmo.rb - Homebrew formula for DGMO
class Dgmo < Formula
  desc "Darwin Gödel Machine Orchestrator - Self-improving AI development tool"
  homepage "https://dgmo.ai"
  version "1.0.0"

  if OS.mac? && Hardware::CPU.intel?
    url "https://cdn.dgmo.ai/releases/v#{version}/dgmo-darwin-x64.tar.gz"
    sha256 "abc123..." # Actual checksum here
  elsif OS.mac? && Hardware::CPU.arm?
    url "https://cdn.dgmo.ai/releases/v#{version}/dgmo-darwin-arm64.tar.gz"
    sha256 "def456..." # Actual checksum here
  elsif OS.linux? && Hardware::CPU.intel?
    url "https://cdn.dgmo.ai/releases/v#{version}/dgmo-linux-x64.tar.gz"
    sha256 "ghi789..." # Actual checksum here
  elsif OS.linux? && Hardware::CPU.arm?
    url "https://cdn.dgmo.ai/releases/v#{version}/dgmo-linux-arm64.tar.gz"
    sha256 "jkl012..." # Actual checksum here
  end

  def install
    bin.install "dgmo"

    # Install shell completions
    bash_completion.install "completions/dgmo.bash" => "dgmo"
    zsh_completion.install "completions/dgmo.zsh" => "_dgmo"
    fish_completion.install "completions/dgmo.fish"

    # Install man pages
    man1.install "man/dgmo.1"
  end

  def post_install
    # Initialize DGMO home directory
    dgmo_home = var/"dgmo"
    dgmo_home.mkpath

    # Create initial configuration
    (dgmo_home/"config.json").write <<~EOS
      {
        "version": "#{version}",
        "telemetry": true,
        "autoUpdate": true
      }
    EOS
  end

  def caveats
    <<~EOS
      DGMO has been installed successfully!

      To get started:
        dgmo init        # Initialize a new project
        dgmo --help      # Show available commands

      Configuration is stored in:
        #{var}/dgmo

      To enable auto-updates:
        dgmo config set autoUpdate true
    EOS
  end

  test do
    system "#{bin}/dgmo", "--version"
    assert_match "DGMO v#{version}", shell_output("#{bin}/dgmo --version")
  end
end
```

### 3. CDN Infrastructure

```typescript
// cdn-infrastructure.ts
export const cdnConfig = {
  provider: 'cloudflare',

  zones: {
    'cdn.dgmo.ai': {
      origin: 's3://dgmo-releases',

      caching: {
        // Installer scripts - short cache
        '/install': '5m',
        '/install.sh': '5m',
        '/install.ps1': '5m',

        // Latest version info - very short cache
        '/releases/latest/*': '1m',

        // Specific versions - permanent cache
        '/releases/v*/*': '1y',

        // Patches - medium cache
        '/patches/*': '1h',

        // Evolution plugins
        '/evolution/verified/*': '1d',
        '/evolution/experimental/*': '1h',
      },

      headers: {
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
      },
    },
  },

  security: {
    // Rate limiting
    rateLimit: {
      '/install*': '100/hour/ip',
      '/releases/*': '1000/hour/ip',
      '/api/*': '100/hour/key',
    },

    // DDoS protection
    ddosProtection: {
      enabled: true,
      sensitivity: 'high',
    },

    // Geo-blocking (if needed)
    geoBlocking: {
      enabled: false,
      allowedCountries: [],
    },
  },

  performance: {
    // Edge locations
    edgeLocations: [
      'us-east',
      'us-west',
      'eu-west',
      'eu-central',
      'asia-pacific',
      'asia-south',
      'south-america',
    ],

    // Compression
    compression: {
      enabled: true,
      types: ['text/plain', 'application/json', 'application/octet-stream'],
    },

    // HTTP/3 support
    http3: true,
  },
};

// CDN deployment script
export async function deployCDN() {
  const cf = new CloudflareAPI(process.env.CF_API_KEY);

  // Create zone if not exists
  const zone = await cf.createZone('cdn.dgmo.ai');

  // Configure caching rules
  for (const [path, ttl] of Object.entries(cdnConfig.zones['cdn.dgmo.ai'].caching)) {
    await cf.createPageRule(zone.id, {
      targets: [
        {
          target: 'url',
          constraint: {
            operator: 'matches',
            value: `*cdn.dgmo.ai${path}`,
          },
        },
      ],
      actions: [
        {
          id: 'cache_level',
          value: 'cache_everything',
        },
        {
          id: 'edge_cache_ttl',
          value: parseTTL(ttl),
        },
      ],
    });
  }

  // Configure security
  await cf.configureRateLimit(zone.id, cdnConfig.security.rateLimit);
  await cf.enableDDoSProtection(zone.id, cdnConfig.security.ddosProtection);

  // Enable performance features
  await cf.enableHTTP3(zone.id);
  await cf.enableCompression(zone.id);
}
```

### 4. Package Manager Integration

#### 4.1 APT Repository (Debian/Ubuntu)

```bash
#!/bin/bash
# setup-apt-repo.sh - Setup APT repository for DGMO

# Create GPG key for signing
gpg --batch --generate-key <<EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: DGMO Release Signing Key
Name-Email: releases@dgmo.ai
Expire-Date: 2y
%commit
EOF

# Export public key
gpg --armor --export releases@dgmo.ai > dgmo-archive-key.asc

# Create repository structure
mkdir -p apt-repo/{conf,db,dists,pool}

# Create distributions file
cat > apt-repo/conf/distributions <<EOF
Origin: DGMO
Label: DGMO
Codename: stable
Architectures: amd64 arm64
Components: main
Description: DGMO Official Repository
SignWith: releases@dgmo.ai
EOF

# Add packages to repository
for deb in dist/*.deb; do
    reprepro -b apt-repo includedeb stable "$deb"
done

# Generate repository metadata
reprepro -b apt-repo export

# Sync to S3
aws s3 sync apt-repo/ s3://apt.dgmo.ai/ --delete

# Create installation instructions
cat > install-apt.sh <<'EOF'
#!/bin/bash
# Add DGMO APT repository

# Add GPG key
curl -fsSL https://apt.dgmo.ai/dgmo-archive-key.asc | sudo apt-key add -

# Add repository
echo "deb https://apt.dgmo.ai stable main" | sudo tee /etc/apt/sources.list.d/dgmo.list

# Update and install
sudo apt update
sudo apt install dgmo
EOF
```

#### 4.2 YUM/DNF Repository (RHEL/Fedora)

```bash
#!/bin/bash
# setup-yum-repo.sh - Setup YUM repository for DGMO

# Create repository structure
mkdir -p yum-repo/{x86_64,aarch64,SRPMS,repodata}

# Copy RPMs
cp dist/*x86_64.rpm yum-repo/x86_64/
cp dist/*aarch64.rpm yum-repo/aarch64/

# Create repository metadata
createrepo yum-repo/x86_64/
createrepo yum-repo/aarch64/

# Sign RPMs
for rpm in yum-repo/*/*.rpm; do
    rpm --addsign "$rpm"
done

# Create .repo file
cat > dgmo.repo <<EOF
[dgmo]
name=DGMO Official Repository
baseurl=https://yum.dgmo.ai/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://yum.dgmo.ai/RPM-GPG-KEY-dgmo
EOF

# Sync to S3
aws s3 sync yum-repo/ s3://yum.dgmo.ai/ --delete
```

### 5. Auto-Configuration System

```typescript
// auto-config.ts - Automatic environment configuration
export class AutoConfigurator {
  async configure(): Promise<ConfigResult> {
    const config: ConfigResult = {
      shell: await this.detectShell(),
      editor: await this.detectEditor(),
      terminal: await this.detectTerminal(),
      gitConfig: await this.detectGitConfig(),
      sshKeys: await this.detectSSHKeys(),
      apiKeys: await this.detectAPIKeys(),
    };

    // Apply configurations
    await this.configureShell(config.shell);
    await this.configureEditor(config.editor);
    await this.configureGit(config.gitConfig);

    return config;
  }

  private async detectShell(): Promise<ShellConfig> {
    const shell = process.env.SHELL || '';
    const shellName = path.basename(shell);

    return {
      name: shellName,
      configFile: this.getShellConfigFile(shellName),
      completionSupport: ['bash', 'zsh', 'fish'].includes(shellName),
    };
  }

  private async configureShell(shell: ShellConfig): Promise<void> {
    if (!shell.completionSupport) return;

    // Generate completion script
    const completion = await this.generateCompletion(shell.name);

    // Install completion
    switch (shell.name) {
      case 'bash':
        await this.installBashCompletion(completion);
        break;
      case 'zsh':
        await this.installZshCompletion(completion);
        break;
      case 'fish':
        await this.installFishCompletion(completion);
        break;
    }

    // Add aliases
    await this.addShellAliases(shell);
  }

  private async detectAPIKeys(): Promise<APIKeys> {
    const keys: APIKeys = {};

    // Check environment variables
    const keyPatterns = {
      openai: /^OPENAI_API_KEY$/,
      anthropic: /^ANTHROPIC_API_KEY$/,
      github: /^GITHUB_TOKEN$/,
    };

    for (const [name, pattern] of Object.entries(keyPatterns)) {
      for (const envVar of Object.keys(process.env)) {
        if (pattern.test(envVar)) {
          keys[name] = { source: 'env', variable: envVar };
        }
      }
    }

    // Check common config files
    const configFiles = [
      { path: '~/.config/openai/api_key', key: 'openai' },
      { path: '~/.anthropic/api_key', key: 'anthropic' },
    ];

    for (const { path, key } of configFiles) {
      const fullPath = os.homedir() + path.slice(1);
      if (await fs.exists(fullPath)) {
        keys[key] = { source: 'file', path: fullPath };
      }
    }

    return keys;
  }
}
```

### 6. First-Run Experience

```typescript
// first-run.ts - Initial setup wizard
export class FirstRunWizard {
  async run(): Promise<void> {
    console.log(
      chalk.cyan(`
    ╔══════════════════════════════════════╗
    ║     Welcome to DGMO v${version}     ║
    ║  Darwin Gödel Machine Orchestrator   ║
    ╚══════════════════════════════════════╝
    `),
    );

    // Check if first run
    if (await this.hasExistingConfig()) {
      return;
    }

    console.log("\nLet's set up DGMO for first use...\n");

    // Interactive setup
    const answers = await inquirer.prompt([
      {
        type: 'confirm',
        name: 'telemetry',
        message: 'Help improve DGMO by sharing anonymous usage data?',
        default: true,
      },
      {
        type: 'confirm',
        name: 'autoUpdate',
        message: 'Enable automatic updates?',
        default: true,
      },
      {
        type: 'list',
        name: 'aiProvider',
        message: 'Select your preferred AI provider:',
        choices: [
          { name: 'OpenAI (GPT-4)', value: 'openai' },
          { name: 'Anthropic (Claude)', value: 'anthropic' },
          { name: 'Local Model', value: 'local' },
          { name: 'Configure Later', value: 'none' },
        ],
      },
    ]);

    // Configure AI provider
    if (answers.aiProvider !== 'none') {
      await this.configureAIProvider(answers.aiProvider);
    }

    // Save configuration
    await this.saveConfig({
      version,
      telemetry: answers.telemetry,
      autoUpdate: answers.autoUpdate,
      aiProvider: answers.aiProvider,
      firstRun: false,
    });

    // Show next steps
    console.log(chalk.green('\n✓ Setup complete!\n'));
    console.log('Next steps:');
    console.log('  1. Run "dgmo init" to create a new project');
    console.log('  2. Run "dgmo evolve --analyze" to analyze your workflow');
    console.log('  3. Run "dgmo --help" to see all commands\n');
  }

  private async configureAIProvider(provider: string): Promise<void> {
    switch (provider) {
      case 'openai':
        await this.configureOpenAI();
        break;
      case 'anthropic':
        await this.configureAnthropic();
        break;
      case 'local':
        await this.configureLocalModel();
        break;
    }
  }
}
```

## Implementation Timeline

### Week 1: Core Installer Scripts

- Universal shell installer
- Windows PowerShell installer
- Platform detection logic
- Basic installation flow

### Week 2: Package Manager Integration

- Homebrew formula
- APT repository setup
- YUM/DNF repository
- Package building automation

### Week 3: CDN Infrastructure

- CloudFlare setup
- S3 bucket configuration
- Distribution pipeline
- Security configuration

### Week 4: Auto-Configuration

- Environment detection
- Shell integration
- API key discovery
- First-run wizard

### Week 5: Testing & Polish

- Cross-platform testing
- Installation verification
- Documentation
- Launch preparation

## Success Metrics

1. **Installation Success Rate**: > 99%
2. **Installation Time**: < 30 seconds
3. **Platform Coverage**: 95% of developer machines
4. **Zero Dependencies**: No prerequisites required
5. **Configuration Success**: 90% auto-configured
6. **First-Run Completion**: 95% complete setup
