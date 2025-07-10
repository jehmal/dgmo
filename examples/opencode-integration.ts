import { 
  createCommandSystem, 
  CommandHandler,
  CommandResult,
  AsyncTask,
  Middleware 
} from '../src';

/**
 * Example of integrating the command routing system with OpenCode
 * This demonstrates how to handle various OpenCode-specific commands
 */

interface OpenCodeContext {
  workspaceId: string;
  projectPath: string;
  activeFile?: string;
  user: {
    id: string;
    role: string;
  };
}

async function setupOpenCodeIntegration(context: OpenCodeContext) {
  const system = createCommandSystem({
    parser: {
      defaultTimeout: 30000,
      confidenceThreshold: 0.4,
    },
    dispatcher: {
      maxConcurrent: 20,
      enableMetrics: true,
    },
  });

  // === OpenCode-specific Handlers ===

  const codeAnalysisHandler: CommandHandler = {
    name: 'codeAnalysisHandler',
    description: 'Analyzes code quality and suggests improvements',
    execute: async (command, ctx) => {
      const { filepath = context.activeFile, metrics = ['complexity', 'coverage'] } = command.parameters;
      
      ctx.logger.info(`Analyzing ${filepath} for metrics: ${metrics.join(', ')}`);
      
      // Simulate analysis
      const analysis = {
        filepath,
        metrics: {
          complexity: Math.floor(Math.random() * 20) + 1,
          coverage: Math.floor(Math.random() * 100),
          maintainability: Math.floor(Math.random() * 100),
        },
        issues: [
          { line: 42, severity: 'warning', message: 'Function too complex' },
          { line: 156, severity: 'info', message: 'Missing test coverage' },
        ],
        suggestions: [
          'Consider breaking down complex functions',
          'Add unit tests for uncovered code paths',
        ],
      };
      
      return {
        commandId: command.id,
        success: true,
        data: analysis,
        executionTime: 500,
        timestamp: new Date(),
      };
    },
  };

  const refactoringHandler: CommandHandler = {
    name: 'refactoringHandler',
    description: 'Performs code refactoring operations',
    execute: async (command, ctx) => {
      const { 
        type, 
        target, 
        newName, 
        scope = 'file' 
      } = command.parameters;
      
      // Validate refactoring request
      if (!type || !target) {
        return {
          commandId: command.id,
          success: false,
          error: {
            code: 'INVALID_PARAMS',
            message: 'Refactoring type and target are required',
            recoverable: true,
          },
          executionTime: 0,
          timestamp: new Date(),
        };
      }
      
      ctx.logger.info(`Refactoring: ${type} ${target} ${newName ? `to ${newName}` : ''}`);
      
      // Simulate refactoring
      const changes = {
        type,
        target,
        newName,
        scope,
        filesAffected: scope === 'project' ? 12 : 1,
        changes: [
          { file: 'src/index.ts', line: 10, before: target, after: newName || target },
          { file: 'src/utils.ts', line: 25, before: target, after: newName || target },
        ],
      };
      
      return {
        commandId: command.id,
        success: true,
        data: changes,
        executionTime: 1000,
        timestamp: new Date(),
      };
    },
  };

  const aiAssistHandler: CommandHandler = {
    name: 'aiAssistHandler',
    description: 'Provides AI-powered code assistance',
    execute: async (command, ctx) => {
      const { query, context: codeContext = '' } = command.parameters;
      
      // This is where you'd integrate with DGM or other AI services
      ctx.logger.info(`AI Assist: ${query}`);
      
      // Simulate AI response
      await new Promise(resolve => setTimeout(resolve, 1500));
      
      const response = {
        query,
        suggestions: [
          {
            type: 'code',
            content: `// Example implementation based on your query\nfunction example() {\n  // AI-generated code here\n}`,
            explanation: 'This implementation follows best practices for your use case',
          },
          {
            type: 'documentation',
            content: 'Consider using the Factory pattern for better flexibility',
            references: ['https://example.com/patterns/factory'],
          },
        ],
        confidence: 0.85,
      };
      
      return {
        commandId: command.id,
        success: true,
        data: response,
        executionTime: 1500,
        timestamp: new Date(),
      };
    },
  };

  const toolIntegrationHandler: CommandHandler = {
    name: 'toolIntegrationHandler',
    description: 'Integrates with external development tools',
    execute: async (command, ctx) => {
      const { tool, action, params = {} } = command.parameters;
      
      ctx.logger.info(`Tool integration: ${tool} - ${action}`);
      
      // Handle different tools
      switch (tool) {
        case 'git':
          return handleGitCommand(command, action, params);
        case 'docker':
          return handleDockerCommand(command, action, params);
        case 'test':
          return handleTestCommand(command, action, params);
        default:
          return {
            commandId: command.id,
            success: false,
            error: {
              code: 'UNKNOWN_TOOL',
              message: `Unknown tool: ${tool}`,
              recoverable: false,
            },
            executionTime: 0,
            timestamp: new Date(),
          };
      }
    },
  };

  // === Middleware for OpenCode ===

  const workspaceValidationMiddleware: Middleware = {
    name: 'workspaceValidation',
    execute: async (command, next) => {
      // Ensure command is executed in valid workspace context
      if (!context.workspaceId) {
        return {
          commandId: command.id,
          success: false,
          error: {
            code: 'NO_WORKSPACE',
            message: 'No active workspace found',
            recoverable: true,
          },
          executionTime: 0,
          timestamp: new Date(),
        };
      }
      
      // Add workspace context to command metadata
      command.metadata.workspaceId = context.workspaceId;
      command.metadata.projectPath = context.projectPath;
      
      return next();
    },
  };

  const permissionMiddleware: Middleware = {
    name: 'permissions',
    execute: async (command, next) => {
      const userRole = context.user.role;
      const requiredRole = command.metadata.requiredRole || 'user';
      
      const roleHierarchy: Record<string, number> = {
        'admin': 3,
        'developer': 2,
        'user': 1,
        'guest': 0,
      };
      
      if (roleHierarchy[userRole] < roleHierarchy[requiredRole]) {
        return {
          commandId: command.id,
          success: false,
          error: {
            code: 'INSUFFICIENT_PERMISSIONS',
            message: `This command requires ${requiredRole} role`,
            recoverable: false,
          },
          executionTime: 0,
          timestamp: new Date(),
        };
      }
      
      return next();
    },
  };

  // Register handlers
  system.registerHandler(codeAnalysisHandler);
  system.registerHandler(refactoringHandler);
  system.registerHandler(aiAssistHandler);
  system.registerHandler(toolIntegrationHandler);

  // Register middleware
  system.registerMiddleware(workspaceValidationMiddleware);
  system.registerMiddleware(permissionMiddleware);

  // Register routes
  system.registerRoute('code.analyze', 'codeAnalysisHandler', {
    middleware: ['workspaceValidation'],
    description: 'Analyze code quality',
  });

  system.registerRoute('code.refactor', 'refactoringHandler', {
    middleware: ['workspaceValidation', 'permissions'],
    description: 'Perform code refactoring',
  });

  system.registerRoute('ai.assist', 'aiAssistHandler', {
    middleware: ['workspaceValidation'],
    description: 'Get AI assistance',
  });

  system.registerRoute('tool.execute', 'toolIntegrationHandler', {
    middleware: ['workspaceValidation', 'permissions'],
    description: 'Execute external tools',
  });

  // Register custom intents for natural language
  system.commandParser.registerIntent('code.analyze',
    [
      /^analyze\s+(?:code\s+)?(?:in\s+)?(.+)$/i,
      /^check\s+code\s+quality\s+(?:of\s+)?(.+)$/i,
      /^what'?s?\s+wrong\s+with\s+(?:this\s+)?(?:code|file)?$/i,
    ],
    ['analyze', 'check', 'quality', 'metrics', 'complexity'],
    20
  );

  system.commandParser.registerIntent('ai.assist',
    [
      /^(?:ai\s+)?help\s+(?:me\s+)?(.+)$/i,
      /^how\s+(?:do\s+i|to)\s+(.+)$/i,
      /^explain\s+(.+)$/i,
      /^suggest\s+(?:a\s+)?(.+)$/i,
    ],
    ['help', 'assist', 'ai', 'explain', 'suggest', 'how'],
    25
  );

  return system;
}

// Helper functions for tool integration
async function handleGitCommand(command: any, action: string, params: any): Promise<CommandResult> {
  const gitActions: Record<string, string> = {
    'status': 'git status',
    'commit': `git commit -m "${params.message || 'Update'}"`,
    'push': 'git push',
    'pull': 'git pull',
  };

  return {
    commandId: command.id,
    success: true,
    data: {
      tool: 'git',
      action,
      command: gitActions[action] || `git ${action}`,
      output: `Executed: ${gitActions[action] || `git ${action}`}`,
    },
    executionTime: 200,
    timestamp: new Date(),
  };
}

async function handleDockerCommand(command: any, action: string, params: any): Promise<CommandResult> {
  return {
    commandId: command.id,
    success: true,
    data: {
      tool: 'docker',
      action,
      params,
      output: `Docker ${action} executed successfuly`,
    },
    executionTime: 500,
    timestamp: new Date(),
  };
}

async function handleTestCommand(command: any, action: string, params: any): Promise<CommandResult> {
  return {
    commandId: command.id,
    success: true,
    data: {
      tool: 'test',
      action,
      params,
      results: {
        total: 42,
        passed: 40,
        failed: 2,
        coverage: 85,
      },
    },
    executionTime: 3000,
    timestamp: new Date(),
  };
}

// Example usage
async function demonstrateOpenCodeIntegration() {
  const context: OpenCodeContext = {
    workspaceId: 'ws-123',
    projectPath: '/home/user/project',
    activeFile: 'src/index.ts',
    user: {
      id: 'user-456',
      role: 'developer',
    },
  };

  const system = await setupOpenCodeIntegration(context);

  console.log('=== OpenCode Integration Examples ===\n');

  // Example 1: Code analysis
  console.log('1. Analyzing code:');
  const analysis = await system.execute('analyze code quality of src/utils.ts');
  console.log('Analysis results:', JSON.stringify(analysis.data, null, 2));
  console.log();

  // Example 2: AI assistance
  console.log('2. AI assistance:');
  const aiHelp = await system.execute('ai help me implement a singleton pattern in TypeScript');
  console.log('AI suggestions:', JSON.stringify(aiHelp.data, null, 2));
  console.log();

  // Example 3: Refactoring
  console.log('3. Code refactoring:');
  const refactor = await system.execute('refactor rename variable oldName to newName', {
    requiredRole: 'developer',
  });
  console.log('Refactoring result:', JSON.stringify(refactor.data, null, 2));
  console.log();

  // Example 4: Tool integration
  console.log('4. Git integration:');
  const gitStatus = await system.execute('execute tool git status');
  console.log('Git output:', JSON.stringify(gitStatus.data, null, 2));
  console.log();

  // Example 5: Natural language commands
  console.log('5. Natural language:');
  const nlCommand = await system.execute("what's wrong with this code");
  console.log('NL result:', JSON.stringify(nlCommand.data, null, 2));
}

// Run the demonstration
demonstrateOpenCodeIntegration().catch(console.error);