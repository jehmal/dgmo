/**
 * Configuration Migration Tool
 * Helps migrate existing configurations to the new unified format
 */

import * as fs from 'fs/promises';
import * as path from 'path';
import { DGMConfig, mergeDGMConfig, validateDGMConfig } from './schema';

export interface MigrationResult {
  success: boolean;
  migratedConfig?: DGMConfig;
  errors?: string[];
  warnings?: string[];
}

export class ConfigMigration {
  /**
   * Migrate from old DGMO config format to new unified format
   */
  static async migrateFromDGMO(oldConfigPath: string): Promise<MigrationResult> {
    const warnings: string[] = [];
    const errors: string[] = [];

    try {
      const oldConfig = JSON.parse(await fs.readFile(oldConfigPath, 'utf-8'));

      // Extract DGM-related config from old format
      const dgmConfig: Partial<DGMConfig> = {};

      // Check for dgm section in old config
      if (oldConfig.dgm) {
        dgmConfig.enabled = oldConfig.dgm.enabled ?? false;
        dgmConfig.pythonPath = oldConfig.dgm.pythonPath;
        dgmConfig.dgmPath = oldConfig.dgm.dgmPath;

        // Map old timeout/retry fields to new structure
        if (
          oldConfig.dgm.timeout ||
          oldConfig.dgm.maxRetries ||
          oldConfig.dgm.healthCheckInterval
        ) {
          dgmConfig.communication = {
            timeout: oldConfig.dgm.timeout ?? 30000,
            retryAttempts: oldConfig.dgm.maxRetries ?? 3,
            healthCheckInterval: oldConfig.dgm.healthCheckInterval ?? 60000,
          };
        }

        // Evolution settings might not exist in old format
        dgmConfig.evolutionSettings = {
          autoApprove: false,
          maxConcurrentEvolutions: 5,
          performanceThreshold: 0.8,
        };
        warnings.push('Evolution settings set to defaults - please review');
      } else {
        warnings.push('No DGM configuration found in old config - using defaults');
      }

      // Merge with defaults and validate
      const migratedConfig = mergeDGMConfig(dgmConfig);
      const validationErrors = validateDGMConfig(migratedConfig);

      if (validationErrors.length > 0) {
        errors.push(...validationErrors.map((e) => `${e.field}: ${e.message}`));
        return { success: false, errors, warnings };
      }

      return {
        success: true,
        migratedConfig,
        warnings,
      };
    } catch (error) {
      errors.push(`Failed to read old config: ${error}`);
      return { success: false, errors };
    }
  }

  /**
   * Migrate from Python bridge config to unified format
   */
  static async migrateFromBridge(bridgeConfigPath: string): Promise<MigrationResult> {
    const warnings: string[] = [];
    const errors: string[] = [];

    try {
      // Read Python file and extract config values
      const configContent = await fs.readFile(bridgeConfigPath, 'utf-8');

      // Parse Python dataclass values (simple regex approach)
      const extractValue = (pattern: RegExp): string | undefined => {
        const match = configContent.match(pattern);
        return match ? match[1] : undefined;
      };

      const dgmConfig: Partial<DGMConfig> = {
        enabled: true, // Bridge config implies DGM is enabled
        dgmPath:
          extractValue(/dgm_path:\s*str\s*=\s*"([^"]+)"/) ||
          '/mnt/c/Users/jehma/Desktop/AI/DGMSTT/dgm',
        pythonPath: 'python3', // Not in bridge config
        evolutionSettings: {
          autoApprove: false,
          maxConcurrentEvolutions:
            parseInt(extractValue(/max_iterations:\s*int\s*=\s*(\d+)/) || '100') / 20, // Approximate
          performanceThreshold:
            1 - parseFloat(extractValue(/mutation_rate:\s*float\s*=\s*([\d.]+)/) || '0.1'),
        },
        communication: {
          timeout: parseInt(extractValue(/subprocess_timeout:\s*int\s*=\s*(\d+)/) || '300') * 1000, // Convert to ms
          retryAttempts: 3, // Not in bridge config
          healthCheckInterval: 60000, // Not in bridge config
        },
      };

      warnings.push('Some values were approximated or set to defaults during migration');

      const migratedConfig = mergeDGMConfig(dgmConfig);
      const validationErrors = validateDGMConfig(migratedConfig);

      if (validationErrors.length > 0) {
        errors.push(...validationErrors.map((e) => `${e.field}: ${e.message}`));
        return { success: false, errors, warnings };
      }

      return {
        success: true,
        migratedConfig,
        warnings,
      };
    } catch (error) {
      errors.push(`Failed to read bridge config: ${error}`);
      return { success: false, errors };
    }
  }

  /**
   * Merge multiple config sources into unified format
   */
  static async mergeConfigs(
    sources: Array<{ path: string; type: 'dgmo' | 'bridge' | 'json' }>,
  ): Promise<MigrationResult> {
    const warnings: string[] = [];
    const errors: string[] = [];
    let mergedConfig: Partial<DGMConfig> = {};

    for (const source of sources) {
      try {
        let sourceConfig: Partial<DGMConfig> | undefined;

        switch (source.type) {
          case 'dgmo':
            const dgmoResult = await this.migrateFromDGMO(source.path);
            if (dgmoResult.success && dgmoResult.migratedConfig) {
              sourceConfig = dgmoResult.migratedConfig;
              warnings.push(...(dgmoResult.warnings || []));
            } else {
              errors.push(...(dgmoResult.errors || []));
            }
            break;

          case 'bridge':
            const bridgeResult = await this.migrateFromBridge(source.path);
            if (bridgeResult.success && bridgeResult.migratedConfig) {
              sourceConfig = bridgeResult.migratedConfig;
              warnings.push(...(bridgeResult.warnings || []));
            } else {
              errors.push(...(bridgeResult.errors || []));
            }
            break;

          case 'json':
            try {
              sourceConfig = JSON.parse(await fs.readFile(source.path, 'utf-8'));
            } catch (e) {
              errors.push(`Failed to read JSON config from ${source.path}: ${e}`);
            }
            break;
        }

        if (sourceConfig) {
          mergedConfig = { ...mergedConfig, ...sourceConfig };
        }
      } catch (error) {
        errors.push(`Failed to process ${source.type} config at ${source.path}: ${error}`);
      }
    }

    if (errors.length > 0) {
      return { success: false, errors, warnings };
    }

    const finalConfig = mergeDGMConfig(mergedConfig);
    const validationErrors = validateDGMConfig(finalConfig);

    if (validationErrors.length > 0) {
      errors.push(...validationErrors.map((e) => `${e.field}: ${e.message}`));
      return { success: false, errors, warnings };
    }

    return {
      success: true,
      migratedConfig: finalConfig,
      warnings,
    };
  }

  /**
   * Save migrated config to file
   */
  static async saveMigratedConfig(config: DGMConfig, outputPath: string): Promise<void> {
    const dir = path.dirname(outputPath);
    await fs.mkdir(dir, { recursive: true });
    await fs.writeFile(outputPath, JSON.stringify(config, null, 2), 'utf-8');
  }
}
