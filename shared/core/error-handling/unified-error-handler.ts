/**
 * Unified Error Handling System
 * Consolidates error handling across TypeScript and Python components
 */

import {
  ToolError,
  ToolExecutionResult,
  ToolExecutionStatus,
  ToolContext,
} from '../../types/typescript/tool.types';

export interface ErrorContext {
  toolId: string;
  language: 'typescript' | 'python';
  parameters: any;
  context: ToolContext;
  startTime: Date;
}

export interface ErrorHandler {
  canHandle(error: any): boolean;
  handle(error: any, context: ErrorContext): ToolError;
  priority: number; // Lower number = higher priority
}

export interface RetryStrategy {
  maxAttempts: number;
  backoffMultiplier: number;
  initialDelay: number;
  maxDelay: number;
  shouldRetry: (attempt: number, lastError: ToolError) => boolean;
}

/**
 * Base error handler with common functionality
 */
export abstract class BaseErrorHandler implements ErrorHandler {
  abstract canHandle(error: any): boolean;
  abstract handle(error: any, context: ErrorContext): ToolError;
  abstract priority: number;

  protected createToolError(
    code: string,
    message: string,
    details: any,
    retryable: boolean = false,
  ): ToolError {
    return {
      code,
      message,
      details,
      retryable,
      cause: details?.originalError || details?.original_error,
    };
  }
}

/**
 * Timeout error handler
 */
export class TimeoutErrorHandler extends BaseErrorHandler {
  priority = 1;

  canHandle(error: any): boolean {
    const errorStr = String(error?.message || error).toLowerCase();
    return (
      errorStr.includes('timeout') ||
      error?.code === 'ETIMEDOUT' ||
      error?.code === 'TIMEOUT_ERROR' ||
      (error instanceof Error && error.name === 'TimeoutError')
    );
  }

  handle(error: any, context: ErrorContext): ToolError {
    const duration = Date.now() - context.startTime.getTime();
    return this.createToolError(
      'TOOL_TIMEOUT',
      `Tool execution timed out after ${context.context.timeout}ms`,
      {
        toolId: context.toolId,
        timeout: context.context.timeout,
        duration,
        language: context.language,
      },
      true,
    );
  }
}

/**
 * Validation error handler
 */
export class ValidationErrorHandler extends BaseErrorHandler {
  priority = 2;

  canHandle(error: any): boolean {
    const errorStr = String(error?.message || error).toLowerCase();
    return (
      error?.name === 'ValidationError' ||
      error?.code === 'VALIDATION_ERROR' ||
      errorStr.includes('validation') ||
      errorStr.includes('invalid parameters')
    );
  }

  handle(error: any, context: ErrorContext): ToolError {
    return this.createToolError(
      'VALIDATION_ERROR',
      'Parameter validation failed',
      {
        toolId: context.toolId,
        parameters: context.parameters,
        validationErrors: error.errors || error.details || String(error),
        language: context.language,
      },
      false,
    );
  }
}

/**
 * Permission error handler
 */
export class PermissionErrorHandler extends BaseErrorHandler {
  priority = 3;

  canHandle(error: any): boolean {
    const errorStr = String(error?.message || error).toLowerCase();
    return (
      error?.code === 'EACCES' ||
      error?.code === 'EPERM' ||
      errorStr.includes('permission denied') ||
      errorStr.includes('access denied') ||
      error?.name === 'PermissionError'
    );
  }

  handle(error: any, context: ErrorContext): ToolError {
    return this.createToolError(
      'PERMISSION_DENIED',
      'Permission denied for tool execution',
      {
        toolId: context.toolId,
        operation: context.parameters,
        error: String(error),
        language: context.language,
      },
      false,
    );
  }
}

/**
 * Resource not found error handler
 */
export class ResourceErrorHandler extends BaseErrorHandler {
  priority = 4;

  canHandle(error: any): boolean {
    const errorStr = String(error?.message || error).toLowerCase();
    return (
      error?.code === 'ENOENT' ||
      error?.code === 'ENOTFOUND' ||
      errorStr.includes('not found') ||
      errorStr.includes('does not exist') ||
      error?.name === 'FileNotFoundError'
    );
  }

  handle(error: any, context: ErrorContext): ToolError {
    return this.createToolError(
      'RESOURCE_NOT_FOUND',
      'Required resource not found',
      {
        toolId: context.toolId,
        resource: error.path || error.filename || error.resource || 'unknown',
        error: String(error),
        language: context.language,
      },
      false,
    );
  }
}

/**
 * Language-specific execution error handler
 */
export class ExecutionErrorHandler extends BaseErrorHandler {
  priority = 5;

  canHandle(error: any): boolean {
    return (
      error?.code === 'PYTHON_EXECUTION_ERROR' ||
      error?.code === 'TYPESCRIPT_EXECUTION_ERROR' ||
      error?.source === 'python' ||
      error?.source === 'typescript'
    );
  }

  handle(error: any, context: ErrorContext): ToolError {
    const isRetryable = this.isRetryable(error);
    const code =
      context.language === 'python' ? 'PYTHON_EXECUTION_ERROR' : 'TYPESCRIPT_EXECUTION_ERROR';

    return this.createToolError(
      code,
      String(error?.message || error) || `${context.language} tool execution failed`,
      {
        toolId: context.toolId,
        language: context.language,
        traceback: this.extractTraceback(error),
        stack: error?.stack,
        originalError: String(error),
      },
      isRetryable,
    );
  }

  private extractTraceback(error: any): string[] {
    if (error.traceback) {
      return Array.isArray(error.traceback) ? error.traceback : error.traceback.split('\n');
    }

    const errorString = String(error);
    if (errorString.includes('Traceback')) {
      return errorString.split('\n').filter((line) => line.trim());
    }

    return [];
  }

  private isRetryable(error: any): boolean {
    const errorStr = String(error?.message || error).toLowerCase();

    // Don't retry syntax or import errors
    if (
      errorStr.includes('syntaxerror') ||
      errorStr.includes('importerror') ||
      errorStr.includes('modulenotfounderror') ||
      error instanceof TypeError ||
      error instanceof ReferenceError
    ) {
      return false;
    }

    // Retry network or temporary errors
    if (
      errorStr.includes('connection') ||
      errorStr.includes('timeout') ||
      errorStr.includes('temporary') ||
      error?.code === 'ECONNREFUSED' ||
      error?.code === 'ETIMEDOUT'
    ) {
      return true;
    }

    return false;
  }
}

/**
 * Default fallback error handler
 */
export class DefaultErrorHandler extends BaseErrorHandler {
  priority = 999; // Lowest priority (last resort)

  canHandle(error: any): boolean {
    return true;
  }

  handle(error: any, context: ErrorContext): ToolError {
    return this.createToolError(
      'UNKNOWN_ERROR',
      String(error?.message || error) || 'An unknown error occurred',
      {
        toolId: context.toolId,
        language: context.language,
        error: String(error),
        stack: error?.stack,
        type: error?.constructor?.name || typeof error,
      },
      false,
    );
  }
}

/**
 * Unified error handling middleware
 */
export class UnifiedErrorHandler {
  private handlers: ErrorHandler[] = [];

  constructor() {
    this.registerDefaultHandlers();
  }

  private registerDefaultHandlers(): void {
    this.addHandler(new TimeoutErrorHandler());
    this.addHandler(new ValidationErrorHandler());
    this.addHandler(new PermissionErrorHandler());
    this.addHandler(new ResourceErrorHandler());
    this.addHandler(new ExecutionErrorHandler());
    this.addHandler(new DefaultErrorHandler());
  }

  /**
   * Add a custom error handler
   */
  addHandler(handler: ErrorHandler): void {
    this.handlers.push(handler);
    this.handlers.sort((a, b) => a.priority - b.priority);
  }

  /**
   * Handle an error and convert to ToolExecutionResult
   */
  handleError(error: any, context: ErrorContext): ToolExecutionResult {
    const handler = this.handlers.find((h) => h.canHandle(error));
    if (!handler) {
      throw new Error('No error handler found - this should never happen');
    }

    const toolError = handler.handle(error, context);
    this.logError(toolError, context);

    const endTime = new Date();
    const duration = endTime.getTime() - context.startTime.getTime();

    return {
      toolId: context.toolId,
      executionId: `error_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      status: ToolExecutionStatus.ERROR,
      error: toolError,
      performance: {
        startTime: context.startTime.toISOString(),
        endTime: endTime.toISOString(),
        duration,
      },
    };
  }

  /**
   * Check if an error is retryable
   */
  isRetryable(error: ToolError): boolean {
    return error.retryable === true;
  }

  /**
   * Create a retry strategy for an error
   */
  createRetryStrategy(error: ToolError): RetryStrategy | null {
    if (!this.isRetryable(error)) {
      return null;
    }

    return {
      maxAttempts: 3,
      backoffMultiplier: 2,
      initialDelay: 1000,
      maxDelay: 30000,
      shouldRetry: (attempt: number, lastError: ToolError) => {
        return attempt < 3 && lastError.retryable === true;
      },
    };
  }

  /**
   * Log error for debugging
   */
  private logError(error: ToolError, context: ErrorContext): void {
    console.error(`[Unified Error Handler] ${error.code}: ${error.message}`, {
      toolId: context.toolId,
      language: context.language,
      retryable: error.retryable,
      details: error.details,
    });
  }
}

// Export singleton instance
export const unifiedErrorHandler = new UnifiedErrorHandler();

// Export factory function for cross-language compatibility
export function createErrorContext(
  toolId: string,
  language: 'typescript' | 'python',
  parameters: any,
  context: ToolContext,
  startTime?: Date,
): ErrorContext {
  return {
    toolId,
    language,
    parameters,
    context,
    startTime: startTime || new Date(),
  };
}
