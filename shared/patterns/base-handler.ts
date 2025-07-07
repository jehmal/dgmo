/**
 * Standardized Base Handler Pattern
 * Provides consistent architecture across all handlers
 */

export interface HandlerContext {
  id: string;
  timestamp: Date;
  metadata?: Record<string, any>;
}

export interface HandlerResult<T = any> {
  success: boolean;
  data?: T;
  error?: Error;
  metadata?: Record<string, any>;
}

export interface ValidationRule<T> {
  validate: (input: T) => boolean;
  message: string;
}

export abstract class BaseHandler<TInput, TOutput> {
  protected readonly handlerName: string;

  constructor(handlerName: string) {
    this.handlerName = handlerName;
  }

  /**
   * Main handler method - template pattern
   */
  async handle(input: TInput, context: HandlerContext): Promise<HandlerResult<TOutput>> {
    try {
      this.validateInput(input);
      const result = await this.execute(input, context);
      return this.createSuccessResult(result, context);
    } catch (error) {
      return this.createErrorResult(error as Error, context);
    }
  }

  /**
   * Abstract method for actual execution
   */
  protected abstract execute(input: TInput, context: HandlerContext): Promise<TOutput>;

  /**
   * Input validation - override for custom validation
   */
  protected validateInput(input: TInput): void {
    if (input === null || input === undefined) {
      throw new Error(`${this.handlerName}: Input cannot be null or undefined`);
    }
  }

  /**
   * Create success result with consistent format
   */
  protected createSuccessResult(data: TOutput, context: HandlerContext): HandlerResult<TOutput> {
    return {
      success: true,
      data,
      metadata: {
        handlerName: this.handlerName,
        executionTime: Date.now() - context.timestamp.getTime(),
        ...context.metadata,
      },
    };
  }

  /**
   * Create error result with consistent format
   */
  protected createErrorResult(error: Error, context: HandlerContext): HandlerResult<TOutput> {
    return {
      success: false,
      error,
      metadata: {
        handlerName: this.handlerName,
        executionTime: Date.now() - context.timestamp.getTime(),
        errorType: error.constructor.name,
        ...context.metadata,
      },
    };
  }

  /**
   * Utility method for complex validation
   */
  protected validateWithRules<T>(input: T, rules: ValidationRule<T>[]): void {
    for (const rule of rules) {
      if (!rule.validate(input)) {
        throw new Error(`${this.handlerName}: ${rule.message}`);
      }
    }
  }
}

/**
 * Factory for creating handler contexts
 */
export function createHandlerContext(metadata?: Record<string, any>): HandlerContext {
  return {
    id: `ctx_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    timestamp: new Date(),
    metadata,
  };
}
