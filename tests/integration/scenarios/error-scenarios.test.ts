/**
 * Error Scenario Coverage Tests
 *
 * Comprehensive testing of error handling and recovery mechanisms
 * Agent ID: integration-test-agent-003
 */

import { TestBridge, DGMBridgeConfig } from '../dgmo-dgm.test';
import { spawn } from 'child_process';
import * as path from 'path';

describe('Error Scenario Coverage', () => {
  let bridge: TestBridge;
  const config: DGMBridgeConfig = {
    pythonPath: 'python3',
    bridgePath: path.join(__dirname, '../../../dgm/bridge'),
    host: 'localhost',
    port: 8080,
    timeout: 5000,
    healthCheckInterval: 60000,
    maxRetries: 3,
  };

  beforeEach(async () => {
    bridge = new TestBridge(config);
    await bridge.start();
  });

  afterEach(async () => {
    if (bridge) {
      await bridge.stop().catch(() => {});
    }
  });

  describe('Communication Errors', () => {
    test('should handle malformed JSON in request', async () => {
      // Send malformed JSON directly
      const malformedRequests = [
        '{invalid json}',
        '{"jsonrpc": "2.0", "method": "test", id: missing_quotes}',
        '{"jsonrpc": "2.0", "method": "test", "id": "test", trailing_comma,}',
        'null',
        'undefined',
        '[]',
        '""',
      ];

      for (const malformed of malformedRequests) {
        bridge['process']?.stdin?.write(malformed + '\n');
      }

      // System should still be responsive
      await new Promise((resolve) => setTimeout(resolve, 100));
      const health = await bridge.sendRequest('health');
      expect(health.status).toBe('healthy');
    });

    test('should handle partial messages', async () => {
      // Send partial message
      bridge['process']?.stdin?.write('{"jsonrpc": "2.0", "method"');

      // Wait a bit
      await new Promise((resolve) => setTimeout(resolve, 100));

      // Complete the message
      bridge['process']?.stdin?.write(': "health", "id": "partial"}\n');

      // Should eventually process correctly
      const health = await bridge.sendRequest('health');
      expect(health.status).toBe('healthy');
    });

    test('should handle binary data in stream', async () => {
      // Send binary data
      const binaryData = Buffer.from([0x00, 0x01, 0x02, 0xff, 0xfe]);
      bridge['process']?.stdin?.write(binaryData);
      bridge['process']?.stdin?.write('\n');

      // Should recover
      await new Promise((resolve) => setTimeout(resolve, 100));
      const health = await bridge.sendRequest('health');
      expect(health.status).toBe('healthy');
    });
  });

  describe('Protocol Errors', () => {
    test('should handle missing jsonrpc version', async () => {
      const invalidMessage = JSON.stringify({
        method: 'health',
        id: 'no-version',
      });

      bridge['process']?.stdin?.write(invalidMessage + '\n');

      // Should handle gracefully
      await new Promise((resolve) => setTimeout(resolve, 100));
      const health = await bridge.sendRequest('health');
      expect(health.status).toBe('healthy');
    });

    test('should handle invalid method names', async () => {
      const invalidMethods = [
        '',
        ' ',
        'method with spaces',
        'method.with..dots',
        '.startingDot',
        'endingDot.',
        '123numeric',
        'special!@#$%chars',
        'very.long.method.name.that.exceeds.reasonable.limits.for.a.method.name.in.any.system',
      ];

      for (const method of invalidMethods) {
        try {
          await bridge.sendRequest(method);
        } catch (error) {
          expect(error.message).toMatch(/method|invalid/i);
        }
      }
    });

    test('should handle duplicate request IDs', async () => {
      // Manually send requests with same ID
      const duplicateId = 'duplicate-123';

      const promises = [bridge.sendRequest('health'), bridge.sendRequest('tools.list')];

      // Override IDs to be duplicate
      bridge['pendingRequests'].clear();
      promises.forEach((_, i) => {
        const request = {
          jsonrpc: '2.0' as const,
          method: i === 0 ? 'health' : 'tools.list',
          id: duplicateId,
        };
        bridge['process']?.stdin?.write(JSON.stringify(request) + '\n');
      });

      // At least one should succeed
      const results = await Promise.allSettled(promises);
      const succeeded = results.filter((r) => r.status === 'fulfilled');
      expect(succeeded.length).toBeGreaterThan(0);
    });
  });

  describe('Tool Execution Errors', () => {
    test('should handle tool timeout', async () => {
      // Create a bridge with very short timeout
      const timeoutBridge = new TestBridge({
        ...config,
        timeout: 100, // 100ms timeout
      });
      await timeoutBridge.start();

      try {
        // Request a slow operation
        await timeoutBridge.sendRequest('tools.execute', {
          toolId: 'dgm.slow_operation',
          params: { delay: 5000 },
        });
        fail('Should have timed out');
      } catch (error) {
        expect(error.message).toMatch(/timeout/i);
      }

      await timeoutBridge.stop();
    });

    test('should handle missing tool parameters', async () => {
      const invalidParams = [
        null,
        undefined,
        {},
        { toolId: 'dgm.memory_store' }, // missing params
        { params: { content: 'test' } }, // missing toolId
        { toolId: '', params: {} }, // empty toolId
      ];

      for (const params of invalidParams) {
        try {
          await bridge.sendRequest('tools.execute', params);
        } catch (error) {
          expect(error).toBeDefined();
        }
      }
    });

    test('should handle tool execution failures', async () => {
      // Execute tool that's designed to fail
      try {
        await bridge.sendRequest('tools.execute', {
          toolId: 'dgm.failing_tool',
          params: {
            error_type: 'runtime',
            message: 'Simulated tool failure',
          },
        });
      } catch (error) {
        expect(error.message).toMatch(/fail|error/i);
      }
    });
  });

  describe('Process Management Errors', () => {
    test('should handle Python process crash', async () => {
      // Kill the Python process
      const processId = bridge['process']?.pid;
      if (processId) {
        process.kill(processId, 'SIGKILL');
      }

      // Wait for exit
      await new Promise((resolve) => {
        bridge.once('exit', resolve);
      });

      // Subsequent requests should fail
      try {
        await bridge.sendRequest('health');
        fail('Should have failed after process crash');
      } catch (error) {
        expect(error).toBeDefined();
      }
    });

    test('should handle Python process hanging', async () => {
      // Send SIGSTOP to pause the process
      const processId = bridge['process']?.pid;
      if (processId && process.platform !== 'win32') {
        process.kill(processId, 'SIGSTOP');

        // Requests should timeout
        const timeoutBridge = new TestBridge({
          ...config,
          timeout: 1000,
        });

        try {
          await timeoutBridge.sendRequest('health');
          fail('Should have timed out');
        } catch (error) {
          expect(error.message).toMatch(/timeout/i);
        }

        // Resume process
        process.kill(processId, 'SIGCONT');
      }
    });

    test('should handle startup failures', async () => {
      // Try to start with invalid Python path
      const invalidBridge = new TestBridge({
        ...config,
        pythonPath: '/invalid/python/path',
      });

      try {
        await invalidBridge.start();
        fail('Should have failed to start');
      } catch (error) {
        expect(error).toBeDefined();
      }
    });
  });

  describe('Resource Exhaustion', () => {
    test('should handle memory pressure', async () => {
      // Send many large requests
      const promises = [];
      const largeData = 'x'.repeat(1024 * 1024); // 1MB

      for (let i = 0; i < 10; i++) {
        promises.push(
          bridge
            .sendRequest('tools.execute', {
              toolId: 'dgm.memory_store',
              params: {
                content: largeData + i,
                metadata: { index: i, size: largeData.length },
              },
            })
            .catch((e) => ({ error: e })),
        );
      }

      const results = await Promise.all(promises);
      const successful = results.filter((r) => !r.error).length;

      // At least some should succeed
      expect(successful).toBeGreaterThan(0);
    });

    test('should handle request queue overflow', async () => {
      // Send many requests without waiting
      const promises = [];

      for (let i = 0; i < 1000; i++) {
        promises.push(
          bridge
            .sendRequest('health')
            .then(() => ({ success: true }))
            .catch(() => ({ success: false })),
        );
      }

      const results = await Promise.all(promises);
      const successful = results.filter((r) => r.success).length;

      // Most should succeed
      expect(successful / results.length).toBeGreaterThan(0.9);
    });
  });

  describe('Recovery Mechanisms', () => {
    test('should recover from transient network issues', async () => {
      // Simulate network issue by sending garbage
      for (let i = 0; i < 5; i++) {
        bridge['process']?.stdin?.write('GARBAGE_DATA_' + i + '\n');
      }

      // Should still work after garbage
      const health = await bridge.sendRequest('health');
      expect(health.status).toBe('healthy');
    });

    test('should handle interleaved responses', async () => {
      // Send multiple requests rapidly
      const promises = [];

      for (let i = 0; i < 20; i++) {
        promises.push(bridge.sendRequest(i % 2 === 0 ? 'health' : 'tools.list'));
      }

      const results = await Promise.all(promises);

      // All should succeed despite potential interleaving
      expect(results.length).toBe(20);
      results.forEach((result, i) => {
        if (i % 2 === 0) {
          expect(result).toHaveProperty('status');
        } else {
          expect(result).toHaveProperty('tools');
        }
      });
    });

    test('should maintain state after errors', async () => {
      // Cause an error
      try {
        await bridge.sendRequest('invalid.method');
      } catch (error) {
        // Expected
      }

      // Store some data
      const storeResult = await bridge.sendRequest('tools.execute', {
        toolId: 'dgm.memory_store',
        params: {
          content: 'State after error',
          metadata: { test: 'recovery' },
        },
      });
      expect(storeResult.success).toBe(true);

      // Cause another error
      try {
        await bridge.sendRequest('another.invalid.method');
      } catch (error) {
        // Expected
      }

      // Data should still be searchable
      const searchResult = await bridge.sendRequest('tools.execute', {
        toolId: 'dgm.memory_search',
        params: {
          query: 'State after error',
          limit: 1,
        },
      });
      expect(searchResult.success).toBe(true);
    });
  });

  describe('Edge Case Error Combinations', () => {
    test('should handle errors during error handling', async () => {
      // Send request that will fail
      const promise1 = bridge.sendRequest('fail.method.1');

      // Immediately send another that will also fail
      const promise2 = bridge.sendRequest('fail.method.2');

      // Both should fail gracefully
      const results = await Promise.allSettled([promise1, promise2]);
      expect(results.every((r) => r.status === 'rejected')).toBe(true);

      // System should still work
      const health = await bridge.sendRequest('health');
      expect(health.status).toBe('healthy');
    });

    test('should handle rapid error recovery cycles', async () => {
      const results = [];

      for (let i = 0; i < 10; i++) {
        // Alternate between valid and invalid
        if (i % 2 === 0) {
          try {
            await bridge.sendRequest('invalid.method.' + i);
          } catch (error) {
            results.push({ type: 'error', index: i });
          }
        } else {
          const health = await bridge.sendRequest('health');
          results.push({ type: 'success', index: i, data: health });
        }
      }

      // Should have 5 errors and 5 successes
      const errors = results.filter((r) => r.type === 'error');
      const successes = results.filter((r) => r.type === 'success');

      expect(errors.length).toBe(5);
      expect(successes.length).toBe(5);
      expect(successes.every((s) => s.data.status === 'healthy')).toBe(true);
    });
  });

  describe('Error Reporting and Diagnostics', () => {
    test('should provide meaningful error messages', async () => {
      const testCases = [
        {
          method: 'nonexistent.method',
          expectedPattern: /method not found/i,
        },
        {
          method: 'tools.execute',
          params: { toolId: 'invalid.tool' },
          expectedPattern: /not found|invalid/i,
        },
        {
          method: 'tools.execute',
          params: { toolId: 'dgm.memory_store' },
          expectedPattern: /missing|required|parameter/i,
        },
      ];

      for (const testCase of testCases) {
        try {
          await bridge.sendRequest(testCase.method, testCase.params);
          fail('Should have thrown error');
        } catch (error) {
          expect(error.message).toMatch(testCase.expectedPattern);
        }
      }
    });

    test('should include error context and stack traces', async () => {
      try {
        await bridge.sendRequest('tools.execute', {
          toolId: 'dgm.error_with_context',
          params: {
            operation: 'complex_calculation',
            input: 'invalid_data',
          },
        });
      } catch (error) {
        // Should have meaningful context
        expect(error.message).toBeTruthy();
        expect(error.message.length).toBeGreaterThan(10);
      }
    });
  });
});
