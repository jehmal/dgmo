/**
 * Load Testing Suite for DGMO-DGM Integration
 *
 * Tests system behavior under various load patterns
 * Agent ID: integration-test-agent-003
 */

import { TestBridge, DGMBridgeConfig } from '../dgmo-dgm.test';
import * as path from 'path';

interface LoadTestResult {
  pattern: string;
  totalRequests: number;
  successfulRequests: number;
  failedRequests: number;
  duration: number;
  requestsPerSecond: number;
  avgLatency: number;
  maxLatency: number;
  errorRate: number;
  concurrentUsers: number;
}

class LoadTester {
  private results: LoadTestResult[] = [];

  async runLoadTest(
    pattern: string,
    config: {
      users: number;
      rampUp: number;
      duration: number;
      requestsPerUser: number;
      bridgeConfig: DGMBridgeConfig;
    },
  ): Promise<LoadTestResult> {
    const bridges: TestBridge[] = [];
    const startTime = Date.now();
    let totalRequests = 0;
    let successfulRequests = 0;
    let failedRequests = 0;
    let maxLatency = 0;
    const latencies: number[] = [];

    // Create user connections with ramp-up
    for (let i = 0; i < config.users; i++) {
      const bridge = new TestBridge(config.bridgeConfig);
      await bridge.start();
      bridges.push(bridge);

      // Ramp-up delay
      if (i < config.users - 1) {
        await new Promise((resolve) => setTimeout(resolve, config.rampUp / config.users));
      }
    }

    // Run load test
    const userPromises = bridges.map(async (bridge, userIndex) => {
      const userStartTime = Date.now();

      while (Date.now() - userStartTime < config.duration) {
        for (let req = 0; req < config.requestsPerUser; req++) {
          const reqStartTime = Date.now();

          try {
            // Mix of operations
            const operations = [
              () => bridge.sendRequest('health'),
              () => bridge.sendRequest('tools.list'),
              () =>
                bridge.sendRequest('tools.execute', {
                  toolId: 'dgm.memory_store',
                  params: {
                    content: `Load test user ${userIndex} request ${req}`,
                    metadata: {
                      pattern,
                      user: userIndex,
                      timestamp: Date.now(),
                    },
                  },
                }),
              () =>
                bridge.sendRequest('tools.execute', {
                  toolId: 'dgm.memory_search',
                  params: {
                    query: 'load test',
                    limit: 5,
                  },
                }),
            ];

            const operation = operations[req % operations.length];
            await operation();

            const latency = Date.now() - reqStartTime;
            latencies.push(latency);
            maxLatency = Math.max(maxLatency, latency);
            successfulRequests++;
          } catch (error) {
            failedRequests++;
          }

          totalRequests++;

          // Think time between requests
          await new Promise((resolve) => setTimeout(resolve, 100));
        }
      }
    });

    await Promise.all(userPromises);

    // Cleanup
    await Promise.all(bridges.map((b) => b.stop()));

    const totalDuration = Date.now() - startTime;
    const avgLatency = latencies.reduce((a, b) => a + b, 0) / latencies.length;

    const result: LoadTestResult = {
      pattern,
      totalRequests,
      successfulRequests,
      failedRequests,
      duration: totalDuration,
      requestsPerSecond: (totalRequests / totalDuration) * 1000,
      avgLatency,
      maxLatency,
      errorRate: failedRequests / totalRequests,
      concurrentUsers: config.users,
    };

    this.results.push(result);
    return result;
  }

  printReport() {
    console.log('\n=== Load Test Report ===\n');

    this.results.forEach((result) => {
      console.log(`Pattern: ${result.pattern}`);
      console.log(`Concurrent Users: ${result.concurrentUsers}`);
      console.log(`Total Requests: ${result.totalRequests}`);
      console.log(`Successful: ${result.successfulRequests}`);
      console.log(`Failed: ${result.failedRequests}`);
      console.log(`Duration: ${(result.duration / 1000).toFixed(1)}s`);
      console.log(`Requests/sec: ${result.requestsPerSecond.toFixed(1)}`);
      console.log(`Avg Latency: ${result.avgLatency.toFixed(0)}ms`);
      console.log(`Max Latency: ${result.maxLatency.toFixed(0)}ms`);
      console.log(`Error Rate: ${(result.errorRate * 100).toFixed(2)}%`);
      console.log('---\n');
    });

    // Summary
    console.log('=== Load Test Summary ===');
    const allPassed = this.results.every((r) => r.errorRate < 0.05 && r.avgLatency < 1000);
    console.log(`Overall Result: ${allPassed ? 'PASS ✅' : 'FAIL ❌'}`);
  }
}

describe('Load Testing', () => {
  const loadTester = new LoadTester();
  const bridgeConfig: DGMBridgeConfig = {
    pythonPath: 'python3',
    bridgePath: path.join(__dirname, '../../../dgm/bridge'),
    host: 'localhost',
    port: 8080,
    timeout: 5000,
    healthCheckInterval: 60000,
    maxRetries: 3,
  };

  afterAll(() => {
    loadTester.printReport();
  });

  test('Steady Load Pattern', async () => {
    const result = await loadTester.runLoadTest('Steady Load', {
      users: 10,
      rampUp: 2000, // 2 seconds
      duration: 10000, // 10 seconds
      requestsPerUser: 5,
      bridgeConfig,
    });

    expect(result.errorRate).toBeLessThan(0.05);
    expect(result.avgLatency).toBeLessThan(500);
  }, 30000);

  test('Spike Load Pattern', async () => {
    const result = await loadTester.runLoadTest('Spike Load', {
      users: 25,
      rampUp: 500, // 0.5 seconds - rapid spike
      duration: 5000, // 5 seconds
      requestsPerUser: 3,
      bridgeConfig,
    });

    expect(result.errorRate).toBeLessThan(0.1);
    expect(result.maxLatency).toBeLessThan(5000);
  }, 20000);

  test('Gradual Ramp Pattern', async () => {
    const result = await loadTester.runLoadTest('Gradual Ramp', {
      users: 20,
      rampUp: 10000, // 10 seconds - slow ramp
      duration: 15000, // 15 seconds
      requestsPerUser: 4,
      bridgeConfig,
    });

    expect(result.errorRate).toBeLessThan(0.03);
    expect(result.avgLatency).toBeLessThan(300);
  }, 30000);

  test('Stress Test Pattern', async () => {
    const result = await loadTester.runLoadTest('Stress Test', {
      users: 50,
      rampUp: 5000, // 5 seconds
      duration: 10000, // 10 seconds
      requestsPerUser: 2,
      bridgeConfig,
    });

    // More relaxed criteria for stress test
    expect(result.errorRate).toBeLessThan(0.2);
    expect(result.requestsPerSecond).toBeGreaterThan(10);
  }, 30000);
});
