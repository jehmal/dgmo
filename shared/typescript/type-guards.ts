/**
 * Type guard utilities for DGMSTT TypeScript projects
 */

/**
 * Check if a value is defined (not null or undefined)
 */
export function isDefined<T>(value: T | null | undefined): value is T {
  return value !== null && value !== undefined;
}

/**
 * Check if a value is a non-empty string
 */
export function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0;
}

/**
 * Check if a value is a valid number (not NaN)
 */
export function isValidNumber(value: unknown): value is number {
  return typeof value === 'number' && !isNaN(value) && isFinite(value);
}

/**
 * Check if a value is a plain object (not array, null, or other types)
 */
export function isPlainObject(value: unknown): value is Record<string, unknown> {
  return (
    value !== null &&
    typeof value === 'object' &&
    value.constructor === Object &&
    !Array.isArray(value)
  );
}

/**
 * Check if a value is an array of a specific type
 */
export function isArrayOf<T>(
  value: unknown,
  itemGuard: (item: unknown) => item is T
): value is T[] {
  return Array.isArray(value) && value.every(itemGuard);
}

/**
 * Check if an object has a specific property
 */
export function hasProperty<K extends PropertyKey>(
  obj: unknown,
  key: K
): obj is Record<K, unknown> {
  return isPlainObject(obj) && key in obj;
}

/**
 * Check if an object has multiple properties
 */
export function hasProperties<K extends PropertyKey>(
  obj: unknown,
  ...keys: K[]
): obj is Record<K, unknown> {
  return isPlainObject(obj) && keys.every(key => key in obj);
}

/**
 * Type guard for Error-like objects
 */
export interface ErrorLike {
  message: string;
  name?: string;
  stack?: string;
}

export function isErrorLike(value: unknown): value is ErrorLike {
  return (
    isPlainObject(value) &&
    'message' in value &&
    typeof value.message === 'string'
  );
}

/**
 * Type guard for JSON-RPC request
 */
export interface JsonRpcRequest {
  jsonrpc: '2.0';
  method: string;
  params?: unknown;
  id?: string | number | null;
}

export function isJsonRpcRequest(value: unknown): value is JsonRpcRequest {
  return (
    isPlainObject(value) &&
    value.jsonrpc === '2.0' &&
    isNonEmptyString(value.method)
  );
}

/**
 * Type guard for JSON-RPC response
 */
export interface JsonRpcResponse {
  jsonrpc: '2.0';
  result?: unknown;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
  id: string | number | null;
}

export function isJsonRpcResponse(value: unknown): value is JsonRpcResponse {
  return (
    isPlainObject(value) &&
    value.jsonrpc === '2.0' &&
    ('result' in value || 'error' in value) &&
    'id' in value
  );
}

/**
 * Type guard for promise-like objects
 */
export function isPromiseLike<T = unknown>(
  value: unknown
): value is PromiseLike<T> {
  return (
    value !== null &&
    typeof value === 'object' &&
    'then' in value &&
    typeof (value as any).then === 'function'
  );
}

/**
 * Type guard for async iterable
 */
export function isAsyncIterable<T = unknown>(
  value: unknown
): value is AsyncIterable<T> {
  return (
    value !== null &&
    typeof value === 'object' &&
    Symbol.asyncIterator in value &&
    typeof (value as any)[Symbol.asyncIterator] === 'function'
  );
}

/**
 * Create a type guard for objects with specific shape
 */
export function createObjectGuard<T extends Record<string, unknown>>(
  shape: { [K in keyof T]: (value: unknown) => value is T[K] }
): (value: unknown) => value is T {
  return (value: unknown): value is T => {
    if (!isPlainObject(value)) {
      return false;
    }
    
    for (const [key, guard] of Object.entries(shape)) {
      if (!(key in value) || !guard(value[key as keyof typeof value])) {
        return false;
      }
    }
    
    return true;
  };
}

/**
 * Create a type guard for union types
 */
export function createUnionGuard<T extends readonly unknown[]>(
  ...guards: { [K in keyof T]: (value: unknown) => value is T[K] }
): (value: unknown) => value is T[number] {
  return (value: unknown): value is T[number] => {
    return guards.some(guard => guard(value));
  };
}

/**
 * Type guard for nullable types
 */
export function isNullable<T>(
  value: unknown,
  guard: (value: unknown) => value is T
): value is T | null | undefined {
  return value === null || value === undefined || guard(value);
}

/**
 * Narrow an unknown value to a specific type or throw
 */
export function assertType<T>(
  value: unknown,
  guard: (value: unknown) => value is T,
  message?: string
): T {
  if (!guard(value)) {
    throw new TypeError(message || 'Type assertion failed');
  }
  return value;
}

/**
 * Type guard for functions
 */
export function isFunction(value: unknown): value is Function {
  return typeof value === 'function';
}

/**
 * Type guard for RegExp
 */
export function isRegExp(value: unknown): value is RegExp {
  return value instanceof RegExp;
}

/**
 * Type guard for Date
 */
export function isDate(value: unknown): value is Date {
  return value instanceof Date && !isNaN(value.getTime());
}

/**
 * Type guard for valid JSON values
 */
export type JsonValue = 
  | string 
  | number 
  | boolean 
  | null 
  | JsonObject 
  | JsonArray;

export interface JsonObject {
  [key: string]: JsonValue;
}

export interface JsonArray extends Array<JsonValue> {}

export function isJsonValue(value: unknown): value is JsonValue {
  if (value === null) return true;
  
  const type = typeof value;
  if (type === 'string' || type === 'number' || type === 'boolean') {
    return true;
  }
  
  if (Array.isArray(value)) {
    return value.every(isJsonValue);
  }
  
  if (isPlainObject(value)) {
    return Object.values(value).every(isJsonValue);
  }
  
  return false;
}

/**
 * Type refinement helpers
 */
export function refine<T, U extends T>(
  value: T,
  guard: (value: T) => value is U
): U | undefined {
  return guard(value) ? value : undefined;
}

export function refineOrThrow<T, U extends T>(
  value: T,
  guard: (value: T) => value is U,
  message?: string
): U {
  if (!guard(value)) {
    throw new TypeError(message || 'Type refinement failed');
  }
  return value;
}