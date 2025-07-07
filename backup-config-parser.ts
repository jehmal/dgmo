import * as fs from 'fs';
import * as path from 'path';
import * as os from 'os';

/**
 * Configuration validation error with detailed context
 */
export class ConfigValidationError extends Error {
  constructor(
    public readonly field: string,
    public readonly value: any,
    public readonly reason: string,
    public readonly suggestion?: string,
  ) {
    super(
      `Configuration error in ${field}: ${reason}${suggestion ? ` Suggestion: ${suggestion}` : ''}`,
    );
    this.name = 'ConfigValidationError';
  }
}

/**
 * Backup system configuration interface with all required settings
 */
export interface BackupConfig {
  // Path settings
  sourceDir: string;
  backupDir: string;
  logDir: string;
  lockFile: string;

  // Retention settings
  retentionDays: number;
  maxBackups: number;
  minFreeSpaceGB: number;

  // Compression settings
  compressionLevel: number;
  excludePatterns: string[];
  verifyIntegrity: boolean;

  // Notification settings
  emailOnFailure: boolean;
  emailAddress: string;
  smtpServer: string;
  notificationLevel: 'DEBUG' | 'INFO' | 'WARNING' | 'ERROR' | 'CRITICAL';

  // Logging settings
  logLevel: 'DEBUG' | 'INFO' | 'WARNING' | 'ERROR' | 'CRITICAL';
  maxLogSizeMB: number;
  logRetentionCount: number;
  timestampFormat: string;
}

/**
 * Default configuration values with secure and practical defaults
 */
const DEFAULT_CONFIG: BackupConfig = {
  // Paths
  sourceDir: '~/.opencode/sessions',
  backupDir: '~/backups/sessions',
  logDir: '~/backups/logs',
  lockFile: '/tmp/session-backup.lock',

  // Retention
  retentionDays: 30,
  maxBackups: 100,
  minFreeSpaceGB: 5,

  // Compression
  compressionLevel: 6,
  excludePatterns: ['*.tmp', '*.log', '*.cache', '*.swp', '*~', '.DS_Store', 'Thumbs.db'],
  verifyIntegrity: true,

  // Notifications
  emailOnFailure: false,
  emailAddress: '',
  smtpServer: '',
  notificationLevel: 'ERROR',

  // Logging
  logLevel: 'INFO',
  maxLogSizeMB: 10,
  logRetentionCount: 5,
  timestampFormat: '%Y-%m-%d %H:%M:%S',
};

/**
 * Validation ranges for numeric configuration values
 */
const VALIDATION_RANGES = {
  retentionDays: { min: 1, max: 365 },
  maxBackups: { min: 5, max: 1000 },
  minFreeSpaceGB: { min: 1, max: 100 },
  compressionLevel: { min: 1, max: 9 },
  maxLogSizeMB: { min: 1, max: 100 },
  logRetentionCount: { min: 1, max: 20 },
};

/**
 * Valid log levels in order of severity
 */
const VALID_LOG_LEVELS = ['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'] as const;

/**
 * Comprehensive backup configuration parser and validator
 */
export class BackupConfigParser {
  private config: BackupConfig;
  private configPath: string;
  private validationErrors: ConfigValidationError[] = [];

  constructor(configPath: string = './backup-config.conf') {
    this.configPath = configPath;
    this.config = { ...DEFAULT_CONFIG };
  }

  /**
   * Load and parse configuration file with comprehensive validation
   */
  public async loadConfig(): Promise<BackupConfig> {
    try {
      // Check if config file exists
      if (!fs.existsSync(this.configPath)) {
        console.warn(`Configuration file not found at ${this.configPath}, using defaults`);
        await this.createDefaultConfigFile();
        return this.validateAndProcessConfig();
      }

      // Read and parse configuration file
      const configContent = fs.readFileSync(this.configPath, 'utf-8');
      this.parseConfigContent(configContent);

      return this.validateAndProcessConfig();
    } catch (error) {
      throw new Error(
        `Failed to load configuration: ${error instanceof Error ? error.message : String(error)}`,
      );
    }
  }

  /**
   * Parse configuration file content into config object
   */
  private parseConfigContent(content: string): void {
    const lines = content.split('\n');
    let currentSection = '';

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();

      // Skip comments and empty lines
      if (!line || line.startsWith('#')) continue;

      // Handle section headers
      if (line.startsWith('[') && line.endsWith(']')) {
        currentSection = line.slice(1, -1).toUpperCase();
        continue;
      }

      // Parse key=value pairs
      const equalIndex = line.indexOf('=');
      if (equalIndex === -1) continue;

      const key = line.slice(0, equalIndex).trim();
      const value = line.slice(equalIndex + 1).trim();

      this.setConfigValue(currentSection, key, value, i + 1);
    }
  }

  /**
   * Set configuration value based on section and key
   */
  private setConfigValue(section: string, key: string, value: string, lineNumber: number): void {
    try {
      switch (section) {
        case 'PATHS':
          this.setPathValue(key, value);
          break;
        case 'RETENTION':
          this.setRetentionValue(key, value);
          break;
        case 'COMPRESSION':
          this.setCompressionValue(key, value);
          break;
        case 'NOTIFICATIONS':
          this.setNotificationValue(key, value);
          break;
        case 'LOGGING':
          this.setLoggingValue(key, value);
          break;
        default:
          console.warn(`Unknown section [${section}] at line ${lineNumber}`);
      }
    } catch (error) {
      if (error instanceof ConfigValidationError) {
        this.validationErrors.push(error);
      } else {
        console.warn(`Error parsing ${key} at line ${lineNumber}: ${error}`);
      }
    }
  }

  /**
   * Set path configuration values
   */
  private setPathValue(key: string, value: string): void {
    const expandedPath = this.expandPath(value);

    switch (key) {
      case 'SOURCE_DIR':
        this.config.sourceDir = expandedPath;
        break;
      case 'BACKUP_DIR':
        this.config.backupDir = expandedPath;
        break;
      case 'LOG_DIR':
        this.config.logDir = expandedPath;
        break;
      case 'LOCK_FILE':
        this.config.lockFile = expandedPath;
        break;
    }
  }

  /**
   * Set retention configuration values
   */
  private setRetentionValue(key: string, value: string): void {
    switch (key) {
      case 'RETENTION_DAYS':
        this.config.retentionDays = this.parseAndValidateNumber(
          key,
          value,
          VALIDATION_RANGES.retentionDays,
        );
        break;
      case 'MAX_BACKUPS':
        this.config.maxBackups = this.parseAndValidateNumber(
          key,
          value,
          VALIDATION_RANGES.maxBackups,
        );
        break;
      case 'MIN_FREE_SPACE_GB':
        this.config.minFreeSpaceGB = this.parseAndValidateNumber(
          key,
          value,
          VALIDATION_RANGES.minFreeSpaceGB,
        );
        break;
    }
  }

  /**
   * Set compression configuration values
   */
  private setCompressionValue(key: string, value: string): void {
    switch (key) {
      case 'COMPRESSION_LEVEL':
        this.config.compressionLevel = this.parseAndValidateNumber(
          key,
          value,
          VALIDATION_RANGES.compressionLevel,
        );
        break;
      case 'EXCLUDE_PATTERNS':
        this.config.excludePatterns = value
          .split(',')
          .map((p) => p.trim())
          .filter((p) => p);
        break;
      case 'VERIFY_INTEGRITY':
        this.config.verifyIntegrity = this.parseBoolean(key, value);
        break;
    }
  }

  /**
   * Set notification configuration values
   */
  private setNotificationValue(key: string, value: string): void {
    switch (key) {
      case 'EMAIL_ON_FAILURE':
        this.config.emailOnFailure = this.parseBoolean(key, value);
        break;
      case 'EMAIL_ADDRESS':
        this.config.emailAddress = value;
        if (value && !this.isValidEmail(value)) {
          throw new ConfigValidationError(
            key,
            value,
            'Invalid email format',
            'Use format: user@domain.com',
          );
        }
        break;
      case 'SMTP_SERVER':
        this.config.smtpServer = value;
        break;
      case 'NOTIFICATION_LEVEL':
        if (!VALID_LOG_LEVELS.includes(value.toUpperCase() as any)) {
          throw new ConfigValidationError(
            key,
            value,
            `Invalid notification level`,
            `Valid levels: ${VALID_LOG_LEVELS.join(', ')}`,
          );
        }
        this.config.notificationLevel = value.toUpperCase() as any;
        break;
    }
  }

  /**
   * Set logging configuration values
   */
  private setLoggingValue(key: string, value: string): void {
    switch (key) {
      case 'LOG_LEVEL':
        if (!VALID_LOG_LEVELS.includes(value.toUpperCase() as any)) {
          throw new ConfigValidationError(
            key,
            value,
            `Invalid log level`,
            `Valid levels: ${VALID_LOG_LEVELS.join(', ')}`,
          );
        }
        this.config.logLevel = value.toUpperCase() as any;
        break;
      case 'MAX_LOG_SIZE_MB':
        this.config.maxLogSizeMB = this.parseAndValidateNumber(
          key,
          value,
          VALIDATION_RANGES.maxLogSizeMB,
        );
        break;
      case 'LOG_RETENTION_COUNT':
        this.config.logRetentionCount = this.parseAndValidateNumber(
          key,
          value,
          VALIDATION_RANGES.logRetentionCount,
        );
        break;
      case 'TIMESTAMP_FORMAT':
        this.config.timestampFormat = value;
        break;
    }
  }

  /**
   * Validate and process final configuration
   */
  private async validateAndProcessConfig(): Promise<BackupConfig> {
    // Report any parsing errors
    if (this.validationErrors.length > 0) {
      const errorMessages = this.validationErrors.map((e) => e.message).join('\n');
      throw new Error(`Configuration validation failed:\n${errorMessages}`);
    }

    // Validate paths and create directories if needed
    await this.validateAndCreatePaths();

    // Validate cross-field dependencies
    this.validateDependencies();

    // Auto-detect source directory if using default
    await this.autoDetectSourceDir();

    return this.config;
  }

  /**
   * Validate paths and create directories if they don't exist
   */
  private async validateAndCreatePaths(): Promise<void> {
    const pathsToValidate = [
      { path: this.config.backupDir, name: 'BACKUP_DIR', create: true },
      { path: this.config.logDir, name: 'LOG_DIR', create: true },
      { path: path.dirname(this.config.lockFile), name: 'LOCK_FILE directory', create: true },
    ];

    for (const { path: dirPath, name, create } of pathsToValidate) {
      try {
        if (!fs.existsSync(dirPath)) {
          if (create) {
            fs.mkdirSync(dirPath, { recursive: true, mode: 0o750 });
            console.log(`Created directory: ${dirPath}`);
          } else {
            throw new ConfigValidationError(
              name,
              dirPath,
              'Directory does not exist',
              'Create the directory or update the configuration',
            );
          }
        }

        // Check if path is writable
        fs.accessSync(dirPath, fs.constants.W_OK);
      } catch (error) {
        if (error instanceof ConfigValidationError) {
          throw error;
        }
        throw new ConfigValidationError(
          name,
          dirPath,
          `Cannot access or create directory: ${error}`,
          'Check permissions and disk space',
        );
      }
    }

    // Validate source directory exists (don't create it)
    if (!fs.existsSync(this.config.sourceDir)) {
      throw new ConfigValidationError(
        'SOURCE_DIR',
        this.config.sourceDir,
        'Source directory does not exist',
        'Verify the path or check if opencode is properly installed',
      );
    }
  }

  /**
   * Validate cross-field dependencies and logical constraints
   */
  private validateDependencies(): void {
    // Email notification validation
    if (this.config.emailOnFailure) {
      if (!this.config.emailAddress) {
        throw new ConfigValidationError(
          'EMAIL_ADDRESS',
          '',
          'Email address required when EMAIL_ON_FAILURE is true',
          'Set EMAIL_ADDRESS or disable EMAIL_ON_FAILURE',
        );
      }
      if (!this.config.smtpServer) {
        console.warn('SMTP_SERVER not configured, will use system default for email notifications');
      }
    }

    // Retention logic validation
    if (this.config.retentionDays < 1) {
      throw new ConfigValidationError(
        'RETENTION_DAYS',
        this.config.retentionDays,
        'Must retain backups for at least 1 day',
        'Set RETENTION_DAYS to 1 or higher',
      );
    }

    // Disk space validation
    if (this.config.minFreeSpaceGB < 1) {
      throw new ConfigValidationError(
        'MIN_FREE_SPACE_GB',
        this.config.minFreeSpaceGB,
        'Must require at least 1GB free space',
        'Set MIN_FREE_SPACE_GB to 1 or higher for system stability',
      );
    }
  }

  /**
   * Auto-detect opencode session directory if using default
   */
  private async autoDetectSourceDir(): Promise<void> {
    if (this.config.sourceDir === this.expandPath('~/.opencode/sessions')) {
      // Try to find opencode installation
      const possiblePaths = [
        this.expandPath('~/.opencode/sessions'),
        this.expandPath('~/.config/opencode/sessions'),
        '/usr/local/share/opencode/sessions',
        '/opt/opencode/sessions',
      ];

      for (const possiblePath of possiblePaths) {
        if (fs.existsSync(possiblePath)) {
          this.config.sourceDir = possiblePath;
          console.log(`Auto-detected opencode sessions directory: ${possiblePath}`);
          break;
        }
      }
    }
  }

  /**
   * Create default configuration file
   */
  private async createDefaultConfigFile(): Promise<void> {
    try {
      const defaultConfigPath = path.join(__dirname, 'backup-config.conf');
      if (fs.existsSync(defaultConfigPath)) {
        fs.copyFileSync(defaultConfigPath, this.configPath);
        console.log(`Created default configuration file: ${this.configPath}`);
      }
    } catch (error) {
      console.warn(`Could not create default config file: ${error}`);
    }
  }

  /**
   * Expand ~ to home directory in paths
   */
  private expandPath(filePath: string): string {
    if (filePath.startsWith('~/')) {
      return path.join(os.homedir(), filePath.slice(2));
    }
    return path.resolve(filePath);
  }

  /**
   * Parse and validate numeric values with range checking
   */
  private parseAndValidateNumber(
    key: string,
    value: string,
    range: { min: number; max: number },
  ): number {
    const num = parseInt(value, 10);

    if (isNaN(num)) {
      throw new ConfigValidationError(
        key,
        value,
        'Must be a valid number',
        `Expected integer between ${range.min} and ${range.max}`,
      );
    }

    if (num < range.min || num > range.max) {
      throw new ConfigValidationError(
        key,
        value,
        `Must be between ${range.min} and ${range.max}`,
        `Current value ${num} is outside acceptable range`,
      );
    }

    return num;
  }

  /**
   * Parse boolean values with flexible input handling
   */
  private parseBoolean(key: string, value: string): boolean {
    const lowerValue = value.toLowerCase();

    if (['true', '1', 'yes', 'on', 'enabled'].includes(lowerValue)) {
      return true;
    }

    if (['false', '0', 'no', 'off', 'disabled'].includes(lowerValue)) {
      return false;
    }

    throw new ConfigValidationError(
      key,
      value,
      'Must be a valid boolean value',
      'Use: true/false, 1/0, yes/no, on/off, enabled/disabled',
    );
  }

  /**
   * Validate email address format
   */
  private isValidEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }

  /**
   * Get current configuration (for testing/debugging)
   */
  public getConfig(): BackupConfig {
    return { ...this.config };
  }

  /**
   * Validate configuration without loading from file (for testing)
   */
  public static validateConfig(config: Partial<BackupConfig>): ConfigValidationError[] {
    const parser = new BackupConfigParser();
    parser.config = { ...DEFAULT_CONFIG, ...config };

    try {
      parser.validateDependencies();
      return [];
    } catch (error) {
      if (error instanceof ConfigValidationError) {
        return [error];
      }
      return [
        new ConfigValidationError(
          'unknown',
          '',
          error instanceof Error ? error.message : String(error),
        ),
      ];
    }
  }
}

/**
 * Convenience function to load and validate backup configuration
 */
export async function loadBackupConfig(configPath?: string): Promise<BackupConfig> {
  const parser = new BackupConfigParser(configPath);
  return await parser.loadConfig();
}

/**
 * Convenience function to create a configuration file with defaults
 */
export function createDefaultConfig(outputPath: string = './backup-config.conf'): void {
  const configContent = `# This is a generated backup configuration file
# Edit the values below to customize your backup settings

[PATHS]
SOURCE_DIR=~/.opencode/sessions
BACKUP_DIR=~/backups/sessions
LOG_DIR=~/backups/logs
LOCK_FILE=/tmp/session-backup.lock

[RETENTION]
RETENTION_DAYS=30
MAX_BACKUPS=100
MIN_FREE_SPACE_GB=5

[COMPRESSION]
COMPRESSION_LEVEL=6
EXCLUDE_PATTERNS=*.tmp,*.log,*.cache,*.swp,*~,.DS_Store,Thumbs.db
VERIFY_INTEGRITY=true

[NOTIFICATIONS]
EMAIL_ON_FAILURE=false
EMAIL_ADDRESS=
SMTP_SERVER=
NOTIFICATION_LEVEL=ERROR

[LOGGING]
LOG_LEVEL=INFO
MAX_LOG_SIZE_MB=10
LOG_RETENTION_COUNT=5
TIMESTAMP_FORMAT=%Y-%m-%d %H:%M:%S
`;

  fs.writeFileSync(outputPath, configContent);
  console.log(`Created default configuration file: ${outputPath}`);
}
