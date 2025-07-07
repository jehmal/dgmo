/**
 * Unified Tool Registry for cross-language tool management
 * Supports both DGMO and DGM tools with seamless integration
 */

import {
  Tool,
  ToolCategory,
  ToolFilter,
  ToolHandler,
  ToolContext,
  ToolError,
} from '../types/typescript/tool.types';
import { Language, Result, ErrorInfo, Metadata } from '../types/typescript/base.types';
import { TypeScriptPythonAdapter } from './typescript-adapter';
import { TypeConverter } from './type-converter';

// DGMO Tool Interface (from OpenCode)
export interface DGMOTool {
  id: string;
  description: string;
  parameters: any; // Zod schema or similar
  execute(
    args: any,
    ctx: DGMOContext,
  ): Promise<{
    metadata: Record<string, any>;
    output: string;
  }>;
}

export interface DGMOContext {
  sessionID: string;
  messageID: string;
  abort: AbortSignal;
  metadata(meta: Record<string, any>): void;
}

// DGM Tool Interface (from Python)
export interface DGMTool {
  name: string;
  description: string;
  inputSchema: Record<string, unknown>;
  outputSchema?: Record<string, unknown>;
  category?: string;
  tags?: string[];
}

// Unified Tool Registration
export interface ToolRegistration {
  tool: Tool;
  handler: ToolHandler;
  source: 'local' | 'remote' | 'dgmo' | 'dgm';
  module?: string;
  originalTool?: DGMOTool | DGMTool;
}

export class UnifiedToolRegistry {
  private static instance: UnifiedToolRegistry;
  private tools = new Map<string, Map<Language, ToolRegistration>>();
  private initialized = false;

  private constructor() {}

  static getInstance(): UnifiedToolRegistry {
    if (!this.instance) {
      this.instance = new UnifiedToolRegistry();
    }
    return this.instance;
  }

  async initialize(): Promise<void> {
    if (this.initialized) {
      return;
    }

    // Initialize adapters
    await TypeScriptPythonAdapter.initialize();

    // Load built-in tools
    await this.loadBuiltInTools();

    this.initialized = true;
  }

  /**
   * Register a tool with unified interface
   */
  async register(
    tool: Tool,
    handler: ToolHandler,
    module?: string,
    originalTool?: DGMOTool | DGMTool,
  ): Promise<void> {
    const languageMap = this.tools.get(tool.id) || new Map<Language, ToolRegistration>();

    languageMap.set(tool.language, {
      tool,
      handler,
      source: originalTool
        ? isDGMOTool(originalTool)
          ? 'dgmo'
          : 'dgm'
        : module
          ? 'remote'
          : 'local',
      module,
      originalTool,
    });

    this.tools.set(tool.id, languageMap);

    // If it's a Python tool, make it available to TypeScript
    if (tool.language === 'python' && module) {
      await TypeScriptPythonAdapter.registerPythonTool({
        module,
        info: {
          name: tool.id,
          description: tool.description,
          input_schema: tool.inputSchema,
        },
      });
    }
  }

  /**
   * Register a DGMO tool (from OpenCode)
   */
  async registerDGMOTool(toolDef: DGMOTool): Promise<void> {
    const tool: Tool = {
      id: toolDef.id,
      name: toolDef.id,
      description: toolDef.description || '',
      version: '1.0.0',
      category: this.inferCategory(toolDef.id),
      language: 'typescript',
      inputSchema: this.convertDGMOParametersToJsonSchema(toolDef.parameters),
      metadata: {
        id: `dgmo-${toolDef.id}`,
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        source: 'dgmo',
      },
    };

    const handler: ToolHandler = async (input: any, context: ToolContext): Promise<Result<any>> => {
      try {
        // Create DGMO context from unified context
        const dgmoContext: DGMOContext = {
          sessionID: context.sessionId,
          messageID: context.messageId,
          abort: context.abortSignal,
          metadata: (meta: Record<string, any>) => {
            Object.entries(meta).forEach(([key, value]) => {
              context.metadata.set(key, value);
            });
          },
        };

        const result = await toolDef.execute(input, dgmoContext);

        return {
          success: true,
          data: result,
          metadata: {
            id: context.messageId,
            version: '1.0.0',
            timestamp: new Date().toISOString(),
            source: 'dgmo',
            ...Object.fromEntries(context.metadata),
          },
        };
      } catch (error) {
        const errorInfo: ErrorInfo = {
          code: 'DGMO_TOOL_ERROR',
          message: error instanceof Error ? error.message : String(error),
          recoverable: true,
          details: error,
        };

        return {
          success: false,
          error: errorInfo,
        };
      }
    };

    await this.register(tool, handler, undefined, toolDef);
  }

  /**
   * Register a DGM tool (from Python)
   */
  async registerDGMTool(toolDef: DGMTool, module: string): Promise<void> {
    const tool: Tool = {
      id: toolDef.name,
      name: toolDef.name,
      description: toolDef.description,
      version: '1.0.0',
      category: (toolDef.category as ToolCategory) || this.inferCategory(toolDef.name),
      language: 'python',
      inputSchema: toolDef.inputSchema,
      outputSchema: toolDef.outputSchema,
      metadata: {
        id: `dgm-${toolDef.name}`,
        version: '1.0.0',
        timestamp: new Date().toISOString(),
        source: 'dgm',
        tags: toolDef.tags,
      },
    };

    const handler: ToolHandler = async (input: any, context: ToolContext): Promise<Result<any>> => {
      try {
        // Convert TypeScript input to Python format
        const pythonInput = TypeConverter.typeScriptToPython(input);

        // Execute via adapter
        const result = await TypeScriptPythonAdapter.executePythonTool(
          module,
          toolDef.name,
          pythonInput,
          {
            sessionId: context.sessionId,
            messageId: context.messageId,
            timeout: context.timeout,
          },
        );

        // Convert Python result back to TypeScript
        const tsResult = TypeConverter.pythonToTypeScript(result);

        return {
          success: true,
          data: tsResult,
          metadata: {
            id: context.messageId,
            version: '1.0.0',
            timestamp: new Date().toISOString(),
            source: 'dgm',
          },
        };
      } catch (error) {
        const errorInfo: ErrorInfo = {
          code: 'DGM_TOOL_ERROR',
          message: error instanceof Error ? error.message : String(error),
          recoverable: true,
          details: error,
        };

        return {
          success: false,
          error: errorInfo,
        };
      }
    };

    await this.register(tool, handler, module, toolDef);
  }

  /**
   * Unregister a tool
   */
  async unregister(toolId: string, language?: Language): Promise<void> {
    if (language) {
      const languageMap = this.tools.get(toolId);
      if (languageMap) {
        languageMap.delete(language);
        if (languageMap.size === 0) {
          this.tools.delete(toolId);
        }
      }
    } else {
      this.tools.delete(toolId);
    }
  }

  /**
   * Get a tool by ID and optionally language
   */
  async get(toolId: string, language?: Language): Promise<Tool | undefined> {
    const languageMap = this.tools.get(toolId);
    if (!languageMap) {
      return undefined;
    }

    if (language) {
      const registration = languageMap.get(language);
      return registration?.tool;
    }

    // Return the first available tool
    const firstRegistration = languageMap.values().next().value;
    return firstRegistration?.tool;
  }

  /**
   * Get tool handler
   */
  getHandler(toolId: string, language: Language): ToolHandler | undefined {
    const languageMap = this.tools.get(toolId);
    if (!languageMap) {
      return undefined;
    }

    const registration = languageMap.get(language);
    return registration?.handler;
  }

  /**
   * List tools with optional filter
   */
  async list(filter?: ToolFilter): Promise<Tool[]> {
    const tools: Tool[] = [];

    for (const languageMap of this.tools.values()) {
      for (const registration of languageMap.values()) {
        const tool = registration.tool;

        // Apply filters
        if (filter) {
          if (filter.category && tool.category !== filter.category) {
            continue;
          }
          if (filter.language && tool.language !== filter.language) {
            continue;
          }
          if (filter.tags && filter.tags.length > 0) {
            const toolTags = (tool.metadata?.tags as string[]) || [];
            if (!filter.tags.some((tag) => toolTags.includes(tag))) {
              continue;
            }
          }
        }

        tools.push(tool);
      }
    }

    return tools;
  }

  /**
   * Search tools by query
   */
  async search(query: string): Promise<Tool[]> {
    const lowerQuery = query.toLowerCase();
    const tools: Tool[] = [];

    for (const languageMap of this.tools.values()) {
      for (const registration of languageMap.values()) {
        const tool = registration.tool;

        // Search in name, description, and category
        if (
          tool.name.toLowerCase().includes(lowerQuery) ||
          tool.description.toLowerCase().includes(lowerQuery) ||
          tool.category.toLowerCase().includes(lowerQuery)
        ) {
          tools.push(tool);
        }
      }
    }

    return tools;
  }

  /**
   * Load built-in tools
   */
  private async loadBuiltInTools(): Promise<void> {
    // Load TypeScript tools from OpenCode
    await this.loadOpenCodeTools();

    // Load Python tools from DGM
    await this.loadDGMTools();
  }

  /**
   * Load OpenCode tools
   */
  private async loadOpenCodeTools(): Promise<void> {
    try {
      // Dynamically import OpenCode tools
      const toolModules = [
        '../../opencode/packages/opencode/src/tool/bash',
        '../../opencode/packages/opencode/src/tool/edit',
        '../../opencode/packages/opencode/src/tool/read',
        '../../opencode/packages/opencode/src/tool/write',
        '../../opencode/packages/opencode/src/tool/ls',
        '../../opencode/packages/opencode/src/tool/grep',
        '../../opencode/packages/opencode/src/tool/glob',
      ];

      for (const modulePath of toolModules) {
        try {
          const module = await import(modulePath);
          if (module.default || module.BashTool || module.EditTool) {
            // Extract tool info and register
            const tool = module.default || module.BashTool || module.EditTool;
            if (tool && tool.id) {
              await this.registerDGMOTool(tool);
            }
          }
        } catch (error) {
          console.warn(`Failed to load OpenCode tool from ${modulePath}:`, error);
        }
      }
    } catch (error) {
      console.error('Failed to load OpenCode tools:', error);
    }
  }

  /**
   * Load DGM tools
   */
  private async loadDGMTools(): Promise<void> {
    try {
      const toolModules = [
        { path: '/mnt/c/Users/jehma/Desktop/AI/DGMSTT/dgm/tools/bash.py', name: 'bash' },
        { path: '/mnt/c/Users/jehma/Desktop/AI/DGMSTT/dgm/tools/edit.py', name: 'edit' },
      ];

      for (const { path, name } of toolModules) {
        try {
          // Load tool info from Python module
          const toolInfo = await TypeScriptPythonAdapter.loadPythonModule(path);
          if (toolInfo) {
            await this.registerDGMTool(
              {
                name,
                description: toolInfo.description || '',
                inputSchema: toolInfo.input_schema || {},
                outputSchema: toolInfo.output_schema,
                category: toolInfo.category,
                tags: toolInfo.tags,
              },
              path,
            );
          }
        } catch (error) {
          console.warn(`Failed to load DGM tool from ${path}:`, error);
        }
      }
    } catch (error) {
      console.error('Failed to load DGM tools:', error);
    }
  }

  /**
   * Infer tool category from ID
   */
  private inferCategory(toolId: string): ToolCategory {
    const categoryMap: Record<string, ToolCategory> = {
      bash: 'utility',
      edit: 'file-system',
      read: 'file-system',
      write: 'file-system',
      ls: 'file-system',
      grep: 'text-processing',
      glob: 'file-system',
      patch: 'file-system',
      multiedit: 'file-system',
    };

    return categoryMap[toolId] || 'utility';
  }

  /**
   * Convert DGMO parameters (Zod schema) to JSON Schema
   */
  private convertDGMOParametersToJsonSchema(parameters: any): any {
    // If it's already a JSON schema, return it
    if (parameters && typeof parameters === 'object' && 'type' in parameters) {
      return parameters;
    }

    // If it has a _def property, it might be a Zod schema
    if (parameters && parameters._def) {
      return TypeConverter.zodToJsonSchema(parameters);
    }

    // Default fallback
    return {
      type: 'object',
      properties: {},
      additionalProperties: true,
    };
  }

  /**
   * Get available languages for a tool
   */
  getAvailableLanguages(toolId: string): Language[] {
    const languageMap = this.tools.get(toolId);
    if (!languageMap) {
      return [];
    }

    return Array.from(languageMap.keys());
  }

  /**
   * Check if a tool supports a specific language
   */
  supportsLanguage(toolId: string, language: Language): boolean {
    const languageMap = this.tools.get(toolId);
    if (!languageMap) {
      return false;
    }

    return languageMap.has(language);
  }

  /**
   * Execute a tool with automatic language selection
   */
  async execute(
    toolId: string,
    input: any,
    context: ToolContext,
    preferredLanguage?: Language,
  ): Promise<Result<any>> {
    const languageMap = this.tools.get(toolId);
    if (!languageMap) {
      return {
        success: false,
        error: {
          code: 'TOOL_NOT_FOUND',
          message: `Tool ${toolId} not found`,
          recoverable: false,
        },
      };
    }

    // Try preferred language first
    if (preferredLanguage) {
      const registration = languageMap.get(preferredLanguage);
      if (registration) {
        return registration.handler(input, context);
      }
    }

    // Fall back to first available
    const firstRegistration = languageMap.values().next().value;
    if (firstRegistration) {
      return firstRegistration.handler(input, context);
    }

    return {
      success: false,
      error: {
        code: 'NO_HANDLER_FOUND',
        message: `No handler found for tool ${toolId}`,
        recoverable: false,
      },
    };
  }

  /**
   * Validate tool input against schema
   */
  async validateInput(toolId: string, input: any, language?: Language): Promise<Result<any>> {
    const tool = await this.get(toolId, language);
    if (!tool) {
      return {
        success: false,
        error: {
          code: 'TOOL_NOT_FOUND',
          message: `Tool ${toolId} not found`,
          recoverable: false,
        },
      };
    }

    try {
      // Validate against JSON schema
      const valid = await TypeConverter.validateAndCoerce(
        input,
        tool.inputSchema,
        language === 'python' ? 'typescript' : 'python',
      );

      return {
        success: true,
        data: valid,
      };
    } catch (error) {
      return {
        success: false,
        error: {
          code: 'VALIDATION_ERROR',
          message: error instanceof Error ? error.message : 'Input validation failed',
          recoverable: false,
          details: error,
        },
      };
    }
  }

  /**
   * Get tool discovery information
   */
  async discover(): Promise<{
    totalTools: number;
    byLanguage: Record<Language, number>;
    byCategory: Record<ToolCategory, number>;
    bySource: Record<string, number>;
  }> {
    const stats = {
      totalTools: 0,
      byLanguage: {} as Record<Language, number>,
      byCategory: {} as Record<ToolCategory, number>,
      bySource: {} as Record<string, number>,
    };

    for (const languageMap of this.tools.values()) {
      for (const [language, registration] of languageMap.entries()) {
        stats.totalTools++;

        // Count by language
        stats.byLanguage[language] = (stats.byLanguage[language] || 0) + 1;

        // Count by category
        const category = registration.tool.category;
        stats.byCategory[category] = (stats.byCategory[category] || 0) + 1;

        // Count by source
        const source = registration.source;
        stats.bySource[source] = (stats.bySource[source] || 0) + 1;
      }
    }

    return stats;
  }
}

// Helper function to check if a tool is a DGMO tool
function isDGMOTool(tool: any): tool is DGMOTool {
  return 'execute' in tool && typeof tool.execute === 'function';
}

// Export singleton instance
export const toolRegistry = UnifiedToolRegistry.getInstance();
