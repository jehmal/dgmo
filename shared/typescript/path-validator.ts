/**
 * Path validation utilities for DGMSTT TypeScript projects
 */

import * as path from 'path';
import * as fs from 'fs';
import { promisify } from 'util';

const access = promisify(fs.access);
const stat = promisify(fs.stat);

/**
 * Path validation result
 */
export interface PathValidationResult {
  isValid: boolean;
  isAbsolute: boolean;
  exists: boolean;
  isFile?: boolean;
  isDirectory?: boolean;
  normalizedPath: string;
  error?: string;
}

/**
 * Validate a file or directory path
 */
export async function validatePath(
  inputPath: string,
  options: {
    mustExist?: boolean;
    mustBeFile?: boolean;
    mustBeDirectory?: boolean;
    allowRelative?: boolean;
  } = {}
): Promise<PathValidationResult> {
  const {
    mustExist = false,
    mustBeFile = false,
    mustBeDirectory = false,
    allowRelative = true,
  } = options;

  const result: PathValidationResult = {
    isValid: true,
    isAbsolute: path.isAbsolute(inputPath),
    exists: false,
    normalizedPath: path.normalize(inputPath),
  };

  // Check if path is absolute when required
  if (!allowRelative && !result.isAbsolute) {
    result.isValid = false;
    result.error = 'Path must be absolute';
    return result;
  }

  // Check if path exists
  try {
    await access(inputPath, fs.constants.F_OK);
    result.exists = true;

    const stats = await stat(inputPath);
    result.isFile = stats.isFile();
    result.isDirectory = stats.isDirectory();

    // Validate type constraints
    if (mustBeFile && !result.isFile) {
      result.isValid = false;
      result.error = 'Path must be a file';
    } else if (mustBeDirectory && !result.isDirectory) {
      result.isValid = false;
      result.error = 'Path must be a directory';
    }
  } catch (error) {
    if (mustExist) {
      result.isValid = false;
      result.error = 'Path does not exist';
    }
  }

  return result;
}

/**
 * Safely join path segments
 */
export function safeJoin(...segments: string[]): string {
  // Filter out empty segments and join
  const filtered = segments.filter(s => s && s.length > 0);
  if (filtered.length === 0) {
    return '.';
  }
  return path.join(...filtered);
}

/**
 * Get relative path from one path to another, handling edge cases
 */
export function safeRelative(from: string, to: string): string {
  try {
    // Normalize paths first
    const normalizedFrom = path.normalize(from);
    const normalizedTo = path.normalize(to);
    
    // If paths are identical, return '.'
    if (normalizedFrom === normalizedTo) {
      return '.';
    }
    
    return path.relative(normalizedFrom, normalizedTo);
  } catch (error) {
    // If relative path calculation fails, return the 'to' path
    return to;
  }
}

/**
 * Check if a path is within a directory (prevents directory traversal)
 */
export function isPathWithin(childPath: string, parentPath: string): boolean {
  const normalizedChild = path.resolve(childPath);
  const normalizedParent = path.resolve(parentPath);
  
  // Add separator to ensure exact directory match
  const parentWithSep = normalizedParent.endsWith(path.sep) 
    ? normalizedParent 
    : normalizedParent + path.sep;
    
  return normalizedChild.startsWith(parentWithSep) || normalizedChild === normalizedParent;
}

/**
 * Sanitize a filename to prevent security issues
 */
export function sanitizeFilename(filename: string): string {
  // Remove any path separators
  let sanitized = filename.replace(/[/\\]/g, '_');
  
  // Remove any potentially dangerous characters
  sanitized = sanitized.replace(/[<>:"|?*\x00-\x1f]/g, '_');
  
  // Remove leading/trailing dots and spaces
  sanitized = sanitized.replace(/^[\s.]+|[\s.]+$/g, '');
  
  // Limit length
  if (sanitized.length > 255) {
    const ext = path.extname(sanitized);
    const base = path.basename(sanitized, ext);
    sanitized = base.substring(0, 255 - ext.length) + ext;
  }
  
  // If empty after sanitization, provide default
  if (!sanitized) {
    sanitized = 'unnamed';
  }
  
  return sanitized;
}

/**
 * Resolve a path relative to a base directory
 */
export function resolveFromBase(basePath: string, targetPath: string): string {
  // If target is already absolute, return it normalized
  if (path.isAbsolute(targetPath)) {
    return path.normalize(targetPath);
  }
  
  // Otherwise resolve relative to base
  return path.resolve(basePath, targetPath);
}

/**
 * Get the common base directory of multiple paths
 */
export function getCommonBase(paths: string[]): string | null {
  if (paths.length === 0) {
    return null;
  }
  
  if (paths.length === 1) {
    return path.dirname(paths[0]);
  }
  
  // Normalize all paths
  const normalized = paths.map(p => path.normalize(p));
  
  // Split paths into segments
  const segments = normalized.map(p => p.split(path.sep));
  
  // Find common segments
  const commonSegments: string[] = [];
  const minLength = Math.min(...segments.map(s => s.length));
  
  for (let i = 0; i < minLength; i++) {
    const segment = segments[0][i];
    if (segments.every(s => s[i] === segment)) {
      commonSegments.push(segment);
    } else {
      break;
    }
  }
  
  // Join common segments
  if (commonSegments.length === 0) {
    return null;
  }
  
  return commonSegments.join(path.sep);
}

/**
 * Path validation options for batch operations
 */
export interface BatchPathValidationOptions {
  basePath?: string;
  allowedExtensions?: string[];
  excludePatterns?: RegExp[];
  maxDepth?: number;
}

/**
 * Validate multiple paths with common constraints
 */
export async function validatePaths(
  paths: string[],
  options: BatchPathValidationOptions = {}
): Promise<Map<string, PathValidationResult>> {
  const results = new Map<string, PathValidationResult>();
  
  for (const inputPath of paths) {
    let result = await validatePath(inputPath);
    
    // Apply additional constraints
    if (result.isValid && options.allowedExtensions && result.isFile) {
      const ext = path.extname(inputPath);
      if (!options.allowedExtensions.includes(ext)) {
        result.isValid = false;
        result.error = `Extension ${ext} not allowed`;
      }
    }
    
    if (result.isValid && options.excludePatterns) {
      for (const pattern of options.excludePatterns) {
        if (pattern.test(inputPath)) {
          result.isValid = false;
          result.error = `Path matches excluded pattern: ${pattern}`;
          break;
        }
      }
    }
    
    if (result.isValid && options.basePath) {
      if (!isPathWithin(inputPath, options.basePath)) {
        result.isValid = false;
        result.error = 'Path is outside allowed base directory';
      }
    }
    
    if (result.isValid && options.maxDepth !== undefined) {
      const relativePath = options.basePath 
        ? path.relative(options.basePath, inputPath)
        : inputPath;
      const depth = relativePath.split(path.sep).length;
      if (depth > options.maxDepth) {
        result.isValid = false;
        result.error = `Path exceeds maximum depth of ${options.maxDepth}`;
      }
    }
    
    results.set(inputPath, result);
  }
  
  return results;
}

/**
 * Create a path validator with preset options
 */
export function createPathValidator(defaultOptions: BatchPathValidationOptions) {
  return {
    async validate(inputPath: string): Promise<PathValidationResult> {
      const results = await validatePaths([inputPath], defaultOptions);
      return results.get(inputPath)!;
    },
    
    async validateMany(paths: string[]): Promise<Map<string, PathValidationResult>> {
      return validatePaths(paths, defaultOptions);
    },
  };
}