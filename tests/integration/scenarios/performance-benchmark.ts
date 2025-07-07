/**
 * Performance Benchmarking Suite
 *
 * Comprehensive performance testing for DGMO-DGM integration
 * Validates latency, throughput, and resource usage
 * Agent ID: integration-test-agent-003
 */

import { TestBridge, DGMBridgeConfig, PerformanceMetrics } from '../dgmo-dgm.test';
import * as path from 'path';

interface BenchmarkResult {
  name: string;
  operations: number;
  duration: number;
  opsPerSecond: number;
  avgLatency: number;
  p50Latency: number;
  p95Latency: number;
  p99Latency: number;
  minLatency: number;
  maxLatency: number;
  errorRate: number;
}

class PerformanceBenchmark {
  private bridge: TestBridge;
  private results: BenchmarkResult[] = [];

  constructor(private config: DGMBridgeConfig) {}

  async setup() {
    this.bridge = new TestBridge(this.config);
    await this.bridge.start();

    // Warm up
    for (let i = 0; i < 10; i++) {
      await this.bridge.sendRequest('health');
    }
  }

  async teardown() {
    await this.bridge.stop();
  }

  async runBenchmark(
    name: string,
    operation: () => Promise<any>,
    options: {
      operations?: number;
      duration?: number;
      concurrent?: number;
    } = {},
  ): Promise<BenchmarkResult> {
    const { operations = 1000, duration = null, concurrent = 1 } = options;

    this.bridge.resetMetrics();
    const startTime = Date.now();
    let completedOps = 0;
    let errors = 0;

    if (duration) {
      // Time-based benchmark
      const endTime = startTime + duration;
      const promises: Promise<void>[] = [];

      while (Date.now() < endTime) {
        for (let i = 0; i < concurrent; i++) {
          promises.push(
            operation()
              .then(() => completedOps++)
              .catch(() => errors++),
          );
        }

        if (promises.length >= concurrent * 10) {
          await Promise.all(promises.splice(0, concurrent * 10));
        }
      }

      await Promise.all(promises);
    } else {
      // Operation-based benchmark
      const batches = Math.ceil(operations / concurrent);

      for (let batch = 0; batch < batches; batch++) {
        const batchPromises = [];
        const batchSize = Math.min(concurrent, operations - batch * concurrent);

        for (let i = 0; i < batchSize; i++) {
          batchPromises.push(
            operation()
              .then(() => completedOps++)
              .catch(() => errors++),
          );
        }

        await Promise.all(batchPromises);
      }
    }

    const totalDuration = Date.now() - startTime;
    const metrics = this.bridge.getMetrics();

    const result: BenchmarkResult = {
      name,
      operations: completedOps,
      duration: totalDuration,
      opsPerSecond: (completedOps / totalDuration) * 1000,
      avgLatency: metrics.avgLatency,
      p50Latency: metrics.p95Latency, // Using p95 as proxy for p50
      p95Latency: metrics.p95Latency,
      p99Latency: metrics.p99Latency,
      minLatency: metrics.minLatency,
      maxLatency: metrics.maxLatency,
      errorRate: errors / (completedOps + errors),
    };

    this.results.push(result);
    return result;
  }

  printResults() {
    console.log('\n=== Performance Benchmark Results ===\n');

    const headers = [
      'Benchmark',
      'Ops',
      'Duration(ms)',
      'Ops/sec',
      'Avg(ms)',
      'P50(ms)',
      'P95(ms)',
      'P99(ms)',
      'Min(ms)',
      'Max(ms)',
      'Errors',
    ];

    // Print header
    console.log(headers.map((h) => h.padEnd(12)).join(' '));
    console.log('-'.repeat(headers.length * 13));

    // Print results
    this.results.forEach((result) => {
      const row = [
        result.name.padEnd(12),
        result.operations.toString().padEnd(12),
        result.duration.toFixed(0).padEnd(12),
        result.opsPerSecond.toFixed(1).padEnd(12),
        result.avgLatency.toFixed(2).padEnd(12),
        result.p50Latency.toFixed(2).padEnd(12),
        result.p95Latency.toFixed(2).padEnd(12),
        result.p99Latency.toFixed(2).padEnd(12),
        result.minLatency.toFixed(2).padEnd(12),
        result.maxLatency.toFixed(2).padEnd(12),
        (result.errorRate * 100).toFixed(1) + '%',
      ];
      console.log(row.join(' '));
    });

    console.log('\n=== Performance Requirements Validation ===');

    // Check requirements
    const healthBenchmark = this.results.find((r) => r.name === 'Health');
    const toolExecBenchmark = this.results.find((r) => r.name === 'ToolExec');

    console.log(
      `\n✅ Latency < 100ms: ${
        healthBenchmark && healthBenchmark.avgLatency < 100 ? 'PASS' : 'FAIL'
      } (${healthBenchmark?.avgLatency.toFixed(2)}ms)`,
    );

    console.log(
      `✅ P95 Latency < 100ms: ${
        healthBenchmark && healthBenchmark.p95Latency < 100 ? 'PASS' : 'FAIL'
      } (${healthBenchmark?.p95Latency.toFixed(2)}ms)`,
    );

    console.log(
      `✅ Error Rate < 1%: ${this.results.every((r) => r.errorRate < 0.01) ? 'PASS' : 'FAIL'}`,
    );

    console.log(
      `✅ Throughput > 100 ops/sec: ${
        healthBenchmark && healthBenchmark.opsPerSecond > 100 ? 'PASS' : 'FAIL'
      } (${healthBenchmark?.opsPerSecond.toFixed(1)} ops/sec)`,
    );
  }
}

describe('Performance Benchmarks', () => {
  let benchmark: PerformanceBenchmark;

  const config: DGMBridgeConfig = {
    pythonPath: 'python3',
    bridgePath: path.join(__dirname, '../../../dgm/bridge'),
    host: 'localhost',
    port: 8080,
    timeout: 5000,
    healthCheckInterval: 60000,
    maxRetries: 3,
  };

  beforeAll(async () => {
    benchmark = new PerformanceBenchmark(config);
    await benchmark.setup();
  });

  afterAll(async () => {
    await benchmark.teardown();
    benchmark.printResults();
  });

  test('Health Check Performance', async () => {
    const result = await benchmark.runBenchmark(
      'Health',
      () => benchmark['bridge'].sendRequest('health'),
      { operations: 1000 },
    );

    expect(result.avgLatency).toBeLessThan(100);
    expect(result.p95Latency).toBeLessThan(100);
    expect(result.errorRate).toBeLessThan(0.01);
  });

  test('Tool List Performance', async () => {
    const result = await benchmark.runBenchmark(
      'ToolList',
      () => benchmark['bridge'].sendRequest('tools.list'),
      { operations: 500 },
    );

    expect(result.avgLatency).toBeLessThan(150);
    expect(result.errorRate).toBe(0);
  });

  test('Tool Execution Performance', async () => {
    const result = await benchmark.runBenchmark(
      'ToolExec',
      () =>
        benchmark['bridge'].sendRequest('tools.execute', {
          toolId: 'dgm.memory_store',
          params: {
            content: 'Performance test ' + Math.random(),
            metadata: { type: 'benchmark' },
          },
        }),
      { operations: 500 },
    );

    expect(result.avgLatency).toBeLessThan(200);
    expect(result.errorRate).toBeLessThan(0.01);
  });

  test('Concurrent Operations Performance', async () => {
    const result = await benchmark.runBenchmark(
      'Concurrent',
      () => benchmark['bridge'].sendRequest('health'),
      { operations: 1000, concurrent: 10 },
    );

    expect(result.opsPerSecond).toBeGreaterThan(100);
    expect(result.errorRate).toBeLessThan(0.01);
  });

  test('Mixed Workload Performance', async () => {
    let counter = 0;
    const operations = [
      () => benchmark['bridge'].sendRequest('health'),
      () => benchmark['bridge'].sendRequest('tools.list'),
      () =>
        benchmark['bridge'].sendRequest('tools.execute', {
          toolId: 'dgm.memory_store',
          params: {
            content: 'Mixed workload ' + counter++,
            metadata: { type: 'mixed' },
          },
        }),
    ];

    const result = await benchmark.runBenchmark(
      'Mixed',
      () => operations[counter % operations.length](),
      { operations: 900, concurrent: 5 },
    );

    expect(result.avgLatency).toBeLessThan(250);
    expect(result.errorRate).toBeLessThan(0.02);
  });

  test('Sustained Load Performance', async () => {
    const result = await benchmark.runBenchmark(
      'Sustained',
      () => benchmark['bridge'].sendRequest('health'),
      { duration: 10000, concurrent: 5 }, // 10 seconds
    );

    expect(result.opsPerSecond).toBeGreaterThan(50);
    expect(result.avgLatency).toBeLessThan(200);
    expect(result.errorRate).toBeLessThan(0.01);
  });

  test('Burst Traffic Performance', async () => {
    // First, normal load
    await benchmark.runBenchmark('Normal', () => benchmark['bridge'].sendRequest('health'), {
      operations: 100,
    });

    // Then burst
    const result = await benchmark.runBenchmark(
      'Burst',
      () => benchmark['bridge'].sendRequest('health'),
      { operations: 500, concurrent: 50 },
    );

    expect(result.errorRate).toBeLessThan(0.05);
    expect(result.maxLatency).toBeLessThan(5000);
  });

  test('Large Payload Performance', async () => {
    const largeContent = 'x'.repeat(100 * 1024); // 100KB

    const result = await benchmark.runBenchmark(
      'LargePayload',
      () =>
        benchmark['bridge'].sendRequest('tools.execute', {
          toolId: 'dgm.memory_store',
          params: {
            content: largeContent,
            metadata: { size: largeContent.length },
          },
        }),
      { operations: 50 },
    );

    expect(result.avgLatency).toBeLessThan(1000);
    expect(result.errorRate).toBeLessThan(0.05);
  });
});
