/**
 * Unified Bash Tool Implementation for DGMO-DGM Integration
 * Provides identical functionality across TypeScript and Python environments
 */

import { z } from 'zod';
import { spawn } from 'child_process';
import { Tool, ToolContext } from '../types/typescript/tool.types';
import { Result } from '../types/typescript/base.types';

const MAX_OUTPUT_LENGTH = 30000;
const BANNED_COMMANDS = [
  'alias',
  'curl',
  'curlie',
  'wget',
  'axel',
  'aria2c',
  'nc',
  'telnet',
  'lynx',
  'w3m',
  'links',
  'httpie',
  'xh',
  'http-prompt',
  'chrome',
  'firefox',
  'safari',
];
const DEFAULT_TIMEOUT = 1 * 60 * 1000;
const MAX_TIMEOUT = 10 * 60 * 1000;

// Input schema for bash tool
export const bashInputSchema = z.object({
  command: z.string().describe('The command to execute'),
  timeout: z
    .number()
    .min(0)
    .max(MAX_TIMEOUT)
    .describe('Optional timeout in milliseconds')
    .optional(),
  description: z
    .string()
    .describe('Clear, concise description of what this command does in 5-10 words'),
});

export type BashInput = z.infer<typeof bashInputSchema>;

export interface BashOutput {
  stdout: string;
  stderr: string;
  exitCode: number | null;
  description: string;
  command: string;
}

/**
 * Execute bash command with proper error handling and output capture
 */
export async function executeBashCommand(
  params: BashInput,
  context: ToolContext,
): Promise<Result<BashOutput>> {
  try {
    // Validate banned commands
    const timeout = Math.min(params.timeout ?? DEFAULT_TIMEOUT, MAX_TIMEOUT);
    if (BANNED_COMMANDS.some((item) => params.command.startsWith(item))) {
      return {
        success: false,
        error: {
          code: 'BANNED_COMMAND',
          message: `Command '${params.command}' is not allowed`,
          recoverable: false,
        },
      };
    }

    // Get working directory from context or use process.cwd()
    const cwd = (context.metadata.get('cwd') as string) || process.cwd();

    return new Promise((resolve) => {
      let stdout = '';
      let stderr = '';
      let killed = false;

      const proc = spawn('bash', ['-c', params.command], {
        cwd,
        env: process.env,
        signal: context.abortSignal,
      });

      // Set timeout
      const timeoutId = setTimeout(() => {
        killed = true;
        proc.kill('SIGTERM');
        setTimeout(() => {
          if (!proc.killed) {
            proc.kill('SIGKILL');
          }
        }, 5000);
      }, timeout);

      // Capture stdout
      proc.stdout.on('data', (data) => {
        stdout += data.toString();
        if (stdout.length > MAX_OUTPUT_LENGTH) {
          stdout = stdout.substring(0, MAX_OUTPUT_LENGTH) + '\n... (output truncated)';
        }
      });

      // Capture stderr
      proc.stderr.on('data', (data) => {
        stderr += data.toString();
        if (stderr.length > MAX_OUTPUT_LENGTH) {
          stderr = stderr.substring(0, MAX_OUTPUT_LENGTH) + '\n... (output truncated)';
        }
      });

      // Handle process exit
      proc.on('exit', (code) => {
        clearTimeout(timeoutId);

        if (killed) {
          resolve({
            success: false,
            error: {
              code: 'TIMEOUT',
              message: `Command timed out after ${timeout}ms`,
              recoverable: true,
              details: { stdout, stderr },
            },
          });
          return;
        }

        const result: BashOutput = {
          stdout,
          stderr,
          exitCode: code,
          description: params.description,
          command: params.command,
        };

        resolve({
          success: true,
          data: result,
          metadata: {
            id: context.messageId,
            version: '1.0.0',
            timestamp: new Date().toISOString(),
            source: 'unified-bash',
          },
        });
      });

      // Handle process error
      proc.on('error', (error) => {
        clearTimeout(timeoutId);
        resolve({
          success: false,
          error: {
            code: 'EXECUTION_ERROR',
            message: error.message,
            recoverable: true,
            details: { error: error.toString() },
          },
        });
      });
    });
  } catch (error) {
    return {
      success: false,
      error: {
        code: 'UNEXPECTED_ERROR',
        message: error instanceof Error ? error.message : String(error),
        recoverable: false,
        details: error,
      },
    };
  }
}

/**
 * Format bash output for display
 */
export function formatBashOutput(output: BashOutput): string {
  const parts = [
    '<stdout>',
    output.stdout || '',
    '</stdout>',
    '<stderr>',
    output.stderr || '',
    '</stderr>',
  ];

  if (output.exitCode !== 0) {
    parts.push(`<exit_code>${output.exitCode}</exit_code>`);
  }

  return parts.join('\n');
}

/**
 * Create unified bash tool definition
 */
export const bashTool: Tool = {
  id: 'bash',
  name: 'bash',
  description: 'Execute bash commands with timeout and output capture',
  version: '1.0.0',
  category: 'utility',
  language: 'typescript',
  inputSchema: {
    type: 'object',
    properties: {
      command: { type: 'string', description: 'The command to execute' },
      timeout: {
        type: 'number',
        minimum: 0,
        maximum: MAX_TIMEOUT,
        description: 'Optional timeout in milliseconds',
      },
      description: {
        type: 'string',
        description: 'Clear, concise description of what this command does in 5-10 words',
      },
    },
    required: ['command', 'description'],
  },
  outputSchema: {
    type: 'object',
    properties: {
      stdout: { type: 'string' },
      stderr: { type: 'string' },
      exitCode: { type: ['number', 'null'] },
      description: { type: 'string' },
      command: { type: 'string' },
    },
    required: ['stdout', 'stderr', 'exitCode', 'description', 'command'],
  },
  metadata: {
    id: 'unified-bash',
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    source: 'shared',
  },
};

/**
 * Bash tool handler for unified registry
 */
export async function bashToolHandler(
  input: BashInput,
  context: ToolContext,
): Promise<Result<any>> {
  const result = await executeBashCommand(input, context);

  if (result.success && result.data) {
    return {
      ...result,
      data: {
        output: formatBashOutput(result.data),
        metadata: {
          ...result.data,
          title: result.data.command,
        },
      },
    };
  }

  return result;
}

// Export for DGMO compatibility
export const BashTool = {
  id: 'bash',
  description: bashTool.description,
  parameters: bashInputSchema,
  async execute(params: BashInput, ctx: any) {
    const context: ToolContext = {
      sessionId: ctx.sessionID,
      messageId: ctx.messageID,
      abortSignal: ctx.abort,
      timeout: params.timeout || DEFAULT_TIMEOUT,
      metadata: new Map([['cwd', ctx.cwd || process.cwd()]]),
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

    const result = await bashToolHandler(params, context);

    if (result.success) {
      return result.data;
    }

    throw new Error(result.error?.message || 'Bash execution failed');
  },
};
