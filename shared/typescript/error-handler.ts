/**
 * Common error handling utilities for DGMSTT TypeScript projects
 */

import { z, ZodError, ZodSchema } from 'zod';

/**
 * Base error class with structured data support
 */
export abstract class BaseError extends Error {
  abstract readonly code: string;
  abstract toJSON(): Record<string, unknown>;
}

/**
 * Create a typed error class with validation
 */
export function createErrorClass<T extends ZodSchema>(
  name: string,
  code: string,
  schema: T
) {
  return class extends BaseError {
    readonly code = code;
    
    constructor(
      public readonly data: z.input<T>,
      options?: ErrorOptions
    ) {
      super(`${name}: ${JSON.stringify(data)}`, options);
      this.name = name;
      
      // Validate data
      try {
        schema.parse(data);
      } catch (e) {
        throw new Error(`Invalid error data for ${name}: ${e}`);
      }
    }
    
    toJSON() {
      return {
        name: this.name,
        code: this.code,
        message: this.message,
        data: this.data,
      };
    }
    
    static isInstance(error: unknown): error is InstanceType<ReturnType<typeof createErrorClass>> {
      return error instanceof Error && error.name === name;
    }
  };
}

/**
 * Common error types
 */
export const ValidationError = createErrorClass(
  'ValidationError',
  'VALIDATION_ERROR',
  z.object({
    field: z.string(),
    message: z.string(),
    value: z.unknown().optional(),
  })
);

export const NetworkError = createErrorClass(
  'NetworkError',
  'NETWORK_ERROR',
  z.object({
    url: z.string(),
    method: z.string().optional(),
    statusCode: z.number().optional(),
    message: z.string(),
  })
);

export const TimeoutError = createErrorClass(
  'TimeoutError',
  'TIMEOUT_ERROR',
  z.object({
    operation: z.string(),
    timeoutMs: z.number(),
  })
);

/**
 * Safely execute an async operation with error handling
 */
export async function safeAsync<T>(
  operation: () => Promise<T>,
  fallback?: T
): Promise<{ data?: T; error?: Error }> {
  try {
    const data = await operation();
    return { data };
  } catch (error) {
    if (fallback !== undefined) {
      return { data: fallback, error: error as Error };
    }
    return { error: error as Error };
  }
}

/**
 * Retry an operation with exponential backoff
 */
export async function retryWithBackoff<T>(
  operation: () => Promise<T>,
  options: {
    maxAttempts?: number;
    initialDelayMs?: number;
    maxDelayMs?: number;
    shouldRetry?: (error: Error) => boolean;
  } = {}
): Promise<T> {
  const {
    maxAttempts = 3,
    initialDelayMs = 1000,
    maxDelayMs = 30000,
    shouldRetry = () => true,
  } = options;

  let lastError: Error;
  
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      return await operation();
    } catch (error) {
      lastError = error as Error;
      
      if (attempt === maxAttempts - 1 || !shouldRetry(lastError)) {
        throw lastError;
      }
      
      const delay = Math.min(
        initialDelayMs * Math.pow(2, attempt),
        maxDelayMs
      );
      
      await new Promise(resolve => setTimeout(resolve, delay));
    }
  }
  
  throw lastError!;
}

/**
 * Type guard for checking if an error has a specific code
 */
export function hasErrorCode(
  error: unknown,
  code: string
): error is Error & { code: string } {
  return (
    error instanceof Error &&
    'code' in error &&
    (error as any).code === code
  );
}

/**
 * Convert unknown error to Error instance
 */
export function toError(error: unknown): Error {
  if (error instanceof Error) {
    return error;
  }
  
  if (typeof error === 'string') {
    return new Error(error);
  }
  
  if (error && typeof error === 'object' && 'message' in error) {
    return new Error(String(error.message));
  }
  
  return new Error(String(error));
}

/**
 * Create a detailed error message with context
 */
export function createErrorMessage(
  operation: string,
  error: Error,
  context?: Record<string, unknown>
): string {
  const parts = [`${operation} failed: ${error.message}`];
  
  if (context && Object.keys(context).length > 0) {
    parts.push(`Context: ${JSON.stringify(context)}`);
  }
  
  if (error.stack) {
    parts.push(`Stack: ${error.stack}`);
  }
  
  return parts.join('\n');
}

/**
 * Error handler for JSON-RPC style errors
 */
export interface JsonRpcError {
  code: number;
  message: string;
  data?: unknown;
}

export class JsonRpcErrorResponse extends Error {
  constructor(
    public readonly error: JsonRpcError,
    public readonly id: string | number | null
  ) {
    super(error.message);
    this.name = 'JsonRpcError';
  }
  
  toJSON() {
    return {
      jsonrpc: '2.0',
      error: this.error,
      id: this.id,
    };
  }
}

/**
 * Standard JSON-RPC error codes
 */
export const JsonRpcErrorCode = {
  ParseError: -32700,
  InvalidRequest: -32600,
  MethodNotFound: -32601,
  InvalidParams: -32602,
  InternalError: -32603,
  ServerError: -32000,
} as const;

/**
 * Create standard JSON-RPC errors
 */
export const createJsonRpcError = {
  parseError: (id: string | number | null, data?: unknown) =>
    new JsonRpcErrorResponse(
      { code: JsonRpcErrorCode.ParseError, message: 'Parse error', data },
      id
    ),
    
  invalidRequest: (id: string | number | null, data?: unknown) =>
    new JsonRpcErrorResponse(
      { code: JsonRpcErrorCode.InvalidRequest, message: 'Invalid Request', data },
      id
    ),
    
  methodNotFound: (id: string | number | null, method?: string) =>
    new JsonRpcErrorResponse(
      { 
        code: JsonRpcErrorCode.MethodNotFound, 
        message: `Method not found${method ? `: ${method}` : ''}` 
      },
      id
    ),
    
  invalidParams: (id: string | number | null, data?: unknown) =>
    new JsonRpcErrorResponse(
      { code: JsonRpcErrorCode.InvalidParams, message: 'Invalid params', data },
      id
    ),
    
  internalError: (id: string | number | null, data?: unknown) =>
    new JsonRpcErrorResponse(
      { code: JsonRpcErrorCode.InternalError, message: 'Internal error', data },
      id
    ),
};