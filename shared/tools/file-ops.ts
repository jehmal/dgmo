/**
 * Unified File Operations Tools for DGMO-DGM Integration
 * Provides read, write, and edit functionality across both systems
 */

import { z } from 'zod';
import * as fs from 'fs/promises';
import * as path from 'path';
import { Tool, ToolContext } from '../types/typescript/tool.types';
import { Result } from '../types/typescript/base.types';

const MAX_READ_SIZE = 250 * 1024;
const DEFAULT_READ_LIMIT = 2000;
const MAX_LINE_LENGTH = 2000;

// ============= READ TOOL =============

export const readInputSchema = z.object({
  filePath: z.string().describe('The path to the file to read'),
  offset: z.number().describe('The line number to start reading from (0-based)').optional(),
  limit: z.number().describe('The number of lines to read (defaults to 2000)').optional(),
});

export type ReadInput = z.infer<typeof readInputSchema>;

export interface ReadOutput {
  content: string;
  lines: number;
  totalLines: number;
  path: string;
}

export async function readFile(
  params: ReadInput,
  context: ToolContext,
): Promise<Result<ReadOutput>> {
  try {
    let filePath = params.filePath;

    // Convert Windows paths to WSL format if needed
    const windowsPathMatch = filePath.match(/^([A-Za-z]):\\(.*)/);
    if (windowsPathMatch) {
      const drive = windowsPathMatch[1].toLowerCase();
      const pathPart = windowsPathMatch[2].replace(/\\/g, '/');
      filePath = `/mnt/${drive}/${pathPart}`;
    }

    if (!path.isAbsolute(filePath)) {
      filePath = path.join(process.cwd(), filePath);
    }

    // Check file exists
    try {
      const stats = await fs.stat(filePath);
      if (stats.size > MAX_READ_SIZE) {
        return {
          success: false,
          error: {
            code: 'FILE_TOO_LARGE',
            message: `File is too large (${stats.size} bytes). Maximum size is ${MAX_READ_SIZE} bytes`,
            recoverable: false,
          },
        };
      }
    } catch (error) {
      return {
        success: false,
        error: {
          code: 'FILE_NOT_FOUND',
          message: `File not found: ${filePath}`,
          recoverable: false,
        },
      };
    }

    const content = await fs.readFile(filePath, 'utf-8');
    const lines = content.split('\n');
    const limit = params.limit ?? DEFAULT_READ_LIMIT;
    const offset = params.offset || 0;

    const selectedLines = lines.slice(offset, offset + limit);
    const formattedLines = selectedLines.map((line, index) => {
      const lineNum = (index + offset + 1).toString().padStart(5, '0');
      const truncatedLine =
        line.length > MAX_LINE_LENGTH ? line.substring(0, MAX_LINE_LENGTH) + '...' : line;
      return `${lineNum}| ${truncatedLine}`;
    });

    const output: ReadOutput = {
      content: formattedLines.join('\n'),
      lines: selectedLines.length,
      totalLines: lines.length,
      path: filePath,
    };

    return {
      success: true,
      data: output,
      metadata: {
        id: context.messageId,
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        source: 'unified-read',
      },
    };
  } catch (error) {
    return {
      success: false,
      error: {
        code: 'READ_ERROR',
        message: error instanceof Error ? error.message : String(error),
        recoverable: false,
        details: error,
      },
    };
  }
}

// ============= WRITE TOOL =============

export const writeInputSchema = z.object({
  filePath: z
    .string()
    .describe('The absolute path to the file to write (must be absolute, not relative)'),
  content: z.string().describe('The content to write to the file'),
});

export type WriteInput = z.infer<typeof writeInputSchema>;

export interface WriteOutput {
  path: string;
  exists: boolean;
  size: number;
}

export async function writeFile(
  params: WriteInput,
  context: ToolContext,
): Promise<Result<WriteOutput>> {
  try {
    let filePath = params.filePath;

    if (!path.isAbsolute(filePath)) {
      filePath = path.join(process.cwd(), filePath);
    }

    // Check if file exists
    let exists = false;
    try {
      await fs.stat(filePath);
      exists = true;
    } catch {
      // File doesn't exist
    }

    // Ensure directory exists
    const dir = path.dirname(filePath);
    await fs.mkdir(dir, { recursive: true });

    // Write file
    await fs.writeFile(filePath, params.content, 'utf-8');

    const stats = await fs.stat(filePath);

    const output: WriteOutput = {
      path: filePath,
      exists,
      size: stats.size,
    };

    return {
      success: true,
      data: output,
      metadata: {
        id: context.messageId,
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        source: 'unified-write',
      },
    };
  } catch (error) {
    return {
      success: false,
      error: {
        code: 'WRITE_ERROR',
        message: error instanceof Error ? error.message : String(error),
        recoverable: false,
        details: error,
      },
    };
  }
}

// ============= EDIT TOOL =============

export const editInputSchema = z.object({
  filePath: z.string().describe('The absolute path to the file to modify'),
  oldString: z.string().describe('The text to replace'),
  newString: z.string().describe('The text to replace it with (must be different from old_string)'),
  replaceAll: z
    .boolean()
    .optional()
    .describe('Replace all occurrences of old_string (default false)'),
});

export type EditInput = z.infer<typeof editInputSchema>;

export interface EditOutput {
  path: string;
  replacements: number;
  diff: string;
}

export async function editFile(
  params: EditInput,
  context: ToolContext,
): Promise<Result<EditOutput>> {
  try {
    if (params.oldString === params.newString) {
      return {
        success: false,
        error: {
          code: 'INVALID_EDIT',
          message: 'oldString and newString must be different',
          recoverable: false,
        },
      };
    }

    let filePath = params.filePath;

    if (!path.isAbsolute(filePath)) {
      filePath = path.join(process.cwd(), filePath);
    }

    // Read file
    let content: string;
    try {
      content = await fs.readFile(filePath, 'utf-8');
    } catch (error) {
      return {
        success: false,
        error: {
          code: 'FILE_NOT_FOUND',
          message: `File not found: ${filePath}`,
          recoverable: false,
        },
      };
    }

    // Perform replacement
    let newContent: string;
    let replacements = 0;

    if (params.replaceAll) {
      const regex = new RegExp(escapeRegExp(params.oldString), 'g');
      newContent = content.replace(regex, () => {
        replacements++;
        return params.newString;
      });
    } else {
      const index = content.indexOf(params.oldString);
      if (index !== -1) {
        newContent =
          content.substring(0, index) +
          params.newString +
          content.substring(index + params.oldString.length);
        replacements = 1;
      } else {
        newContent = content;
      }
    }

    if (replacements === 0) {
      return {
        success: false,
        error: {
          code: 'STRING_NOT_FOUND',
          message: `String not found in file: ${params.oldString}`,
          recoverable: false,
        },
      };
    }

    // Write file
    await fs.writeFile(filePath, newContent, 'utf-8');

    // Create simple diff
    const diff = createSimpleDiff(content, newContent, filePath);

    const output: EditOutput = {
      path: filePath,
      replacements,
      diff,
    };

    return {
      success: true,
      data: output,
      metadata: {
        id: context.messageId,
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        source: 'unified-edit',
      },
    };
  } catch (error) {
    return {
      success: false,
      error: {
        code: 'EDIT_ERROR',
        message: error instanceof Error ? error.message : String(error),
        recoverable: false,
        details: error,
      },
    };
  }
}

// Helper functions
function escapeRegExp(string: string): string {
  return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function createSimpleDiff(oldContent: string, newContent: string, filePath: string): string {
  const oldLines = oldContent.split('\n');
  const newLines = newContent.split('\n');

  let diff = `--- ${filePath}\n+++ ${filePath}\n`;

  // Simple line-by-line comparison
  const maxLines = Math.max(oldLines.length, newLines.length);
  for (let i = 0; i < maxLines; i++) {
    if (i >= oldLines.length) {
      diff += `+${newLines[i]}\n`;
    } else if (i >= newLines.length) {
      diff += `-${oldLines[i]}\n`;
    } else if (oldLines[i] !== newLines[i]) {
      diff += `-${oldLines[i]}\n`;
      diff += `+${newLines[i]}\n`;
    }
  }

  return diff;
}

// Tool definitions
export const readTool: Tool = {
  id: 'read',
  name: 'read',
  description: 'Read contents of a file with line numbers',
  version: '1.0.0',
  category: 'file-system',
  language: 'typescript',
  inputSchema: {
    type: 'object',
    properties: {
      filePath: { type: 'string', description: 'The path to the file to read' },
      offset: { type: 'number', description: 'The line number to start reading from (0-based)' },
      limit: { type: 'number', description: 'The number of lines to read (defaults to 2000)' },
    },
    required: ['filePath'],
  },
  outputSchema: {
    type: 'object',
    properties: {
      content: { type: 'string' },
      lines: { type: 'number' },
      totalLines: { type: 'number' },
      path: { type: 'string' },
    },
    required: ['content', 'lines', 'totalLines', 'path'],
  },
  metadata: {
    id: 'unified-read',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    source: 'shared',
  },
};

export const writeTool: Tool = {
  id: 'write',
  name: 'write',
  description: 'Write content to a file',
  version: '1.0.0',
  category: 'file-system',
  language: 'typescript',
  inputSchema: {
    type: 'object',
    properties: {
      filePath: { type: 'string', description: 'The absolute path to the file to write' },
      content: { type: 'string', description: 'The content to write to the file' },
    },
    required: ['filePath', 'content'],
  },
  outputSchema: {
    type: 'object',
    properties: {
      path: { type: 'string' },
      exists: { type: 'boolean' },
      size: { type: 'number' },
    },
    required: ['path', 'exists', 'size'],
  },
  metadata: {
    id: 'unified-write',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    source: 'shared',
  },
};

export const editTool: Tool = {
  id: 'edit',
  name: 'edit',
  description: 'Edit a file by replacing text',
  version: '1.0.0',
  category: 'file-system',
  language: 'typescript',
  inputSchema: {
    type: 'object',
    properties: {
      filePath: { type: 'string', description: 'The absolute path to the file to modify' },
      oldString: { type: 'string', description: 'The text to replace' },
      newString: { type: 'string', description: 'The text to replace it with' },
      replaceAll: { type: 'boolean', description: 'Replace all occurrences (default false)' },
    },
    required: ['filePath', 'oldString', 'newString'],
  },
  outputSchema: {
    type: 'object',
    properties: {
      path: { type: 'string' },
      replacements: { type: 'number' },
      diff: { type: 'string' },
    },
    required: ['path', 'replacements', 'diff'],
  },
  metadata: {
    id: 'unified-edit',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    source: 'shared',
  },
};

// Tool handlers
export async function readToolHandler(
  input: ReadInput,
  context: ToolContext,
): Promise<Result<any>> {
  const result = await readFile(input, context);

  if (result.success && result.data) {
    let output = '<file>\n';
    output += result.data.content;

    if (result.data.totalLines > result.data.lines + (input.offset || 0)) {
      output += `\n\n(File has more lines. Use 'offset' parameter to read beyond line ${
        result.data.lines + (input.offset || 0)
      })`;
    }
    output += '\n</file>';

    return {
      ...result,
      data: {
        output,
        metadata: {
          preview: result.data.content.split('\n').slice(0, 20).join('\n'),
          title: path.basename(result.data.path),
        },
      },
    };
  }

  return result;
}

export async function writeToolHandler(
  input: WriteInput,
  context: ToolContext,
): Promise<Result<any>> {
  const result = await writeFile(input, context);

  if (result.success && result.data) {
    return {
      ...result,
      data: {
        output: '',
        metadata: {
          filepath: result.data.path,
          exists: result.data.exists,
          title: path.basename(result.data.path),
        },
      },
    };
  }

  return result;
}

export async function editToolHandler(
  input: EditInput,
  context: ToolContext,
): Promise<Result<any>> {
  const result = await editFile(input, context);

  if (result.success && result.data) {
    return {
      ...result,
      data: {
        output: result.data.diff,
        metadata: {
          filepath: result.data.path,
          replacements: result.data.replacements,
          title: path.basename(result.data.path),
        },
      },
    };
  }

  return result;
}

// DGMO compatibility exports
export const ReadTool = {
  id: 'read',
  description: readTool.description,
  parameters: readInputSchema,
  async execute(params: ReadInput, ctx: any) {
    const context: ToolContext = {
      sessionId: ctx.sessionID,
      messageId: ctx.messageID,
      abortSignal: ctx.abort,
      timeout: 30000,
      metadata: new Map(),
      environment: process.env as Record<string, string>,
      logger: {
        debug: (message: string, data?: any) => console.debug(message, data),
        info: (message: string, data?: any) => console.info(message, data),
        warn: (message: string, data?: any) => console.warn(message, data),
        error: (message: string, error?: any) => console.error(message, error),
        metric: (name: string, value: number, tags?: Record<string, string>) =>
          console.log(`METRIC: ${name}=${value}`, tags),
      },
    };

    const result = await readToolHandler(params, context);

    if (result.success) {
      return result.data;
    }

    throw new Error(result.error?.message || 'Read failed');
  },
};

export const WriteTool = {
  id: 'write',
  description: writeTool.description,
  parameters: writeInputSchema,
  async execute(params: WriteInput, ctx: any) {
    const context: ToolContext = {
      sessionId: ctx.sessionID,
      messageId: ctx.messageID,
      abortSignal: ctx.abort,
      timeout: 30000,
      metadata: new Map(),
      environment: process.env as Record<string, string>,
      logger: {
        debug: (message: string, data?: any) => console.debug(message, data),
        info: (message: string, data?: any) => console.info(message, data),
        warn: (message: string, data?: any) => console.warn(message, data),
        error: (message: string, error?: any) => console.error(message, error),
        metric: (name: string, value: number, tags?: Record<string, string>) =>
          console.log(`METRIC: ${name}=${value}`, tags),
      },
    };

    const result = await writeToolHandler(params, context);

    if (result.success) {
      return result.data;
    }

    throw new Error(result.error?.message || 'Write failed');
  },
};

export const EditTool = {
  id: 'edit',
  description: editTool.description,
  parameters: editInputSchema,
  async execute(params: EditInput, ctx: any) {
    const context: ToolContext = {
      sessionId: ctx.sessionID,
      messageId: ctx.messageID,
      abortSignal: ctx.abort,
      timeout: 30000,
      metadata: new Map(),
      environment: process.env as Record<string, string>,
      logger: {
        debug: (message: string, data?: any) => console.debug(message, data),
        info: (message: string, data?: any) => console.info(message, data),
        warn: (message: string, data?: any) => console.warn(message, data),
        error: (message: string, error?: any) => console.error(message, error),
        metric: (name: string, value: number, tags?: Record<string, string>) =>
          console.log(`METRIC: ${name}=${value}`, tags),
      },
    };

    const result = await editToolHandler(params, context);

    if (result.success) {
      return result.data;
    }

    throw new Error(result.error?.message || 'Edit failed');
  },
};
