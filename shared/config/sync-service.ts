import { EventEmitter } from 'events';
import * as fs from 'fs/promises';
import * as path from 'path';
import { watch, FSWatcher } from 'chokidar';
import { DGMConfig, validateDGMConfig, mergeDGMConfig, DEFAULT_DGM_CONFIG } from './schema';

export interface ConfigChangeEvent {
  type: 'update' | 'validation_error';
  config?: DGMConfig;
  errors?: Array<{ field: string; message: string }>;
  source: 'file' | 'api' | 'env';
}

export class ConfigSyncService extends EventEmitter {
  private config: DGMConfig;
  private configPath: string;
  private watcher?: FSWatcher;
  private saveDebounceTimer?: NodeJS.Timeout;
  private readonly saveDebounceMs = 500;

  constructor(configPath?: string) {
    super();
    this.configPath = configPath || path.join(__dirname, 'dgm.json');
    this.config = DEFAULT_DGM_CONFIG;
  }

  async initialize(): Promise<void> {
    this.loadFromEnvironment();
    await this.loadFromFile();
    await this.startWatching();
  }

  getConfig(): DGMConfig {
    return { ...this.config };
  }

  async updateConfig(updates: Partial<DGMConfig>, source: 'api' | 'file' = 'api'): Promise<void> {
    const newConfig = mergeDGMConfig({ ...this.config, ...updates });

    const errors = validateDGMConfig(newConfig);
    if (errors.length > 0) {
      this.emit('change', {
        type: 'validation_error',
        errors,
        source,
      } as ConfigChangeEvent);
      throw new Error(
        `Configuration validation failed: ${errors.map((e) => e.message).join(', ')}`,
      );
    }

    this.config = newConfig;

    if (source === 'api') {
      await this.saveToFile();
    }

    this.emit('change', {
      type: 'update',
      config: this.getConfig(),
      source,
    } as ConfigChangeEvent);
  }

  private loadFromEnvironment(): void {
    const envConfig: Partial<DGMConfig> = {};

    if (process.env.DGM_ENABLED) {
      envConfig.enabled = process.env.DGM_ENABLED.toLowerCase() === 'true';
    }
    if (process.env.DGM_PYTHON_PATH) {
      envConfig.pythonPath = process.env.DGM_PYTHON_PATH;
    }
    if (process.env.DGM_PATH) {
      envConfig.dgmPath = process.env.DGM_PATH;
    }

    const evolutionSettings: Partial<DGMConfig['evolutionSettings']> = {};
    if (process.env.DGM_AUTO_APPROVE) {
      evolutionSettings.autoApprove = process.env.DGM_AUTO_APPROVE.toLowerCase() === 'true';
    }
    if (process.env.DGM_MAX_CONCURRENT_EVOLUTIONS) {
      evolutionSettings.maxConcurrentEvolutions = parseInt(
        process.env.DGM_MAX_CONCURRENT_EVOLUTIONS,
        10,
      );
    }
    if (process.env.DGM_PERFORMANCE_THRESHOLD) {
      evolutionSettings.performanceThreshold = parseFloat(process.env.DGM_PERFORMANCE_THRESHOLD);
    }
    if (Object.keys(evolutionSettings).length > 0) {
      envConfig.evolutionSettings = evolutionSettings as DGMConfig['evolutionSettings'];
    }

    const communicationSettings: Partial<DGMConfig['communication']> = {};
    if (process.env.DGM_TIMEOUT) {
      communicationSettings.timeout = parseInt(process.env.DGM_TIMEOUT, 10);
    }
    if (process.env.DGM_RETRY_ATTEMPTS) {
      communicationSettings.retryAttempts = parseInt(process.env.DGM_RETRY_ATTEMPTS, 10);
    }
    if (process.env.DGM_HEALTH_CHECK_INTERVAL) {
      communicationSettings.healthCheckInterval = parseInt(
        process.env.DGM_HEALTH_CHECK_INTERVAL,
        10,
      );
    }
    if (Object.keys(communicationSettings).length > 0) {
      envConfig.communication = communicationSettings as DGMConfig['communication'];
    }

    if (Object.keys(envConfig).length > 0) {
      this.config = mergeDGMConfig(envConfig);
    }
  }

  private async loadFromFile(): Promise<void> {
    try {
      const data = await fs.readFile(this.configPath, 'utf-8');
      const fileConfig = JSON.parse(data);

      const errors = validateDGMConfig(fileConfig);
      if (errors.length === 0) {
        this.config = mergeDGMConfig(fileConfig);
      } else {
        console.warn('Configuration file validation errors:', errors);
      }
    } catch (error) {
      if ((error as any).code !== 'ENOENT') {
        console.warn('Failed to load configuration file:', error);
      }
    }
  }

  private async saveToFile(): Promise<void> {
    if (this.saveDebounceTimer) {
      clearTimeout(this.saveDebounceTimer);
    }

    this.saveDebounceTimer = setTimeout(async () => {
      try {
        const dir = path.dirname(this.configPath);
        await fs.mkdir(dir, { recursive: true });

        await fs.writeFile(this.configPath, JSON.stringify(this.config, null, 2), 'utf-8');
      } catch (error) {
        console.error('Failed to save configuration:', error);
      }
    }, this.saveDebounceMs);
  }

  private async startWatching(): Promise<void> {
    try {
      await fs.access(this.configPath);
    } catch {
      await this.saveToFile();
    }

    this.watcher = watch(this.configPath, {
      persistent: true,
      ignoreInitial: true,
      awaitWriteFinish: {
        stabilityThreshold: 300,
        pollInterval: 100,
      },
    });

    this.watcher.on('change', async () => {
      await this.loadFromFile();
      this.emit('change', {
        type: 'update',
        config: this.getConfig(),
        source: 'file',
      } as ConfigChangeEvent);
    });
  }

  async stop(): Promise<void> {
    if (this.watcher) {
      await this.watcher.close();
    }
    if (this.saveDebounceTimer) {
      clearTimeout(this.saveDebounceTimer);
    }
  }

  exportForPython(): string {
    const pythonConfig = {
      enabled: this.config.enabled,
      python_path: this.config.pythonPath,
      dgm_path: this.config.dgmPath,
      evolution_settings: {
        auto_approve: this.config.evolutionSettings.autoApprove,
        max_concurrent_evolutions: this.config.evolutionSettings.maxConcurrentEvolutions,
        performance_threshold: this.config.evolutionSettings.performanceThreshold,
      },
      communication: {
        timeout: this.config.communication.timeout,
        retry_attempts: this.config.communication.retryAttempts,
        health_check_interval: this.config.communication.healthCheckInterval,
      },
    };
    return JSON.stringify(pythonConfig, null, 2);
  }
}
