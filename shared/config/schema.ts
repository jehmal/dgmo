/**
 * Shared configuration schema for DGMO-DGM integration
 */

export interface DGMEvolutionSettings {
  autoApprove: boolean;
  maxConcurrentEvolutions: number;
  performanceThreshold: number;
}

export interface DGMCommunicationSettings {
  timeout: number;
  retryAttempts: number;
  healthCheckInterval: number;
}

export interface DGMConfig {
  enabled: boolean;
  pythonPath?: string;
  dgmPath: string;
  evolutionSettings: DGMEvolutionSettings;
  communication: DGMCommunicationSettings;
}

export interface ConfigValidationError {
  field: string;
  message: string;
}

export function validateDGMConfig(config: Partial<DGMConfig>): ConfigValidationError[] {
  const errors: ConfigValidationError[] = [];

  if (config.evolutionSettings) {
    const { maxConcurrentEvolutions, performanceThreshold } = config.evolutionSettings;

    if (maxConcurrentEvolutions !== undefined && maxConcurrentEvolutions < 1) {
      errors.push({
        field: 'evolutionSettings.maxConcurrentEvolutions',
        message: 'Must be at least 1',
      });
    }

    if (
      performanceThreshold !== undefined &&
      (performanceThreshold < 0 || performanceThreshold > 1)
    ) {
      errors.push({
        field: 'evolutionSettings.performanceThreshold',
        message: 'Must be between 0 and 1',
      });
    }
  }

  if (config.communication) {
    const { timeout, retryAttempts, healthCheckInterval } = config.communication;

    if (timeout !== undefined && timeout < 1000) {
      errors.push({
        field: 'communication.timeout',
        message: 'Must be at least 1000ms',
      });
    }

    if (retryAttempts !== undefined && retryAttempts < 0) {
      errors.push({
        field: 'communication.retryAttempts',
        message: 'Cannot be negative',
      });
    }

    if (healthCheckInterval !== undefined && healthCheckInterval < 5000) {
      errors.push({
        field: 'communication.healthCheckInterval',
        message: 'Must be at least 5000ms',
      });
    }
  }

  return errors;
}

export const DEFAULT_DGM_CONFIG: DGMConfig = {
  enabled: false,
  pythonPath: 'python3',
  dgmPath: process.env.DGM_PATH || '/mnt/c/Users/jehma/Desktop/AI/DGMSTT/dgm',
  evolutionSettings: {
    autoApprove: false,
    maxConcurrentEvolutions: 5,
    performanceThreshold: 0.8,
  },
  communication: {
    timeout: 30000,
    retryAttempts: 3,
    healthCheckInterval: 60000,
  },
};

export function mergeDGMConfig(partial: Partial<DGMConfig>): DGMConfig {
  return {
    ...DEFAULT_DGM_CONFIG,
    ...partial,
    evolutionSettings: {
      ...DEFAULT_DGM_CONFIG.evolutionSettings,
      ...(partial.evolutionSettings || {}),
    },
    communication: {
      ...DEFAULT_DGM_CONFIG.communication,
      ...(partial.communication || {}),
    },
  };
}
