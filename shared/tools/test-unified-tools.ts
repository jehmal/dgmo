/**
 * Test script for unified tools
 * Verifies that bash, read, write, and edit tools work correctly
 */

import { bashToolHandler, BashTool } from './bash';
import {
  readToolHandler,
  writeToolHandler,
  editToolHandler,
  ReadTool,
  WriteTool,
  EditTool,
} from './file-ops';
import { ToolContext } from '../types/typescript/tool.types';

// Create a mock context
const mockContext: ToolContext = {
  sessionId: 'test-session',
  messageId: 'test-message',
  abortSignal: new AbortController().signal,
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

async function testBashTool() {
  console.log('\n=== Testing Bash Tool ===');

  // Test simple command
  const result = await bashToolHandler(
    {
      command: 'echo "Hello from unified bash tool"',
      description: 'Test echo command',
    },
    mockContext,
  );

  console.log('Result:', result);

  // Test DGMO compatibility
  const dgmoResult = await BashTool.execute(
    {
      command: 'pwd',
      description: 'Get current directory',
    },
    {
      sessionID: 'dgmo-test',
      messageID: 'dgmo-msg',
      abort: new AbortController().signal,
    },
  );

  console.log('DGMO Result:', dgmoResult);
}

async function testFileOps() {
  console.log('\n=== Testing File Operations ===');

  const testFile = '/tmp/unified-test.txt';

  // Test write
  console.log('\n--- Testing Write ---');
  const writeResult = await writeToolHandler(
    {
      filePath: testFile,
      content: 'Hello from unified tools!\nThis is line 2.\nThis is line 3.',
    },
    mockContext,
  );
  console.log('Write Result:', writeResult);

  // Test read
  console.log('\n--- Testing Read ---');
  const readResult = await readToolHandler(
    {
      filePath: testFile,
      limit: 2,
    },
    mockContext,
  );
  console.log('Read Result:', readResult);

  // Test edit
  console.log('\n--- Testing Edit ---');
  const editResult = await editToolHandler(
    {
      filePath: testFile,
      oldString: 'Hello',
      newString: 'Greetings',
      replaceAll: false,
    },
    mockContext,
  );
  console.log('Edit Result:', editResult);

  // Test DGMO compatibility
  console.log('\n--- Testing DGMO Compatibility ---');
  const dgmoWriteResult = await WriteTool.execute(
    {
      filePath: '/tmp/dgmo-test.txt',
      content: 'DGMO compatibility test',
    },
    {
      sessionID: 'dgmo-test',
      messageID: 'dgmo-msg',
      abort: new AbortController().signal,
    },
  );
  console.log('DGMO Write Result:', dgmoWriteResult);
}

async function main() {
  try {
    await testBashTool();
    await testFileOps();
    console.log('\n✅ All tests completed successfully!');
  } catch (error) {
    console.error('\n❌ Test failed:', error);
    process.exit(1);
  }
}

// Run tests
main();
