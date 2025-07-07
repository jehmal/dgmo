#!/usr/bin/env python3
"""
Simple performance test for the TypeScript-Python bridge
Tests the stdio_server directly to measure baseline performance
"""

import sys
import json
import time
import asyncio
import statistics
from typing import List, Dict, Any

# Add the dgm module to Python path
sys.path.insert(0, '/mnt/c/Users/jehma/Desktop/AI/DGMSTT')

from dgm.bridge.stdio_server import DGMBridgeSTDIOServer, Message

class BridgePerformanceTester:
    def __init__(self):
        self.server = DGMBridgeSTDIOServer()
        self.results: Dict[str, List[float]] = {
            'handshake': [],
            'health': [],
            'tools_list': [],
            'tool_execute': []
        }
    
    async def measure_operation(self, operation_name: str, message: Message, iterations: int = 100):
        """Measure the latency of a single operation"""
        times = []
        
        for _ in range(iterations):
            start_time = time.perf_counter()
            response = await self.server.handle_message(message)
            end_time = time.perf_counter()
            
            if response:
                times.append((end_time - start_time) * 1000)  # Convert to ms
        
        self.results[operation_name] = times
        return times
    
    async def run_benchmarks(self):
        """Run all performance benchmarks"""
        print("=== DGM Bridge Performance Test ===\n")
        
        # 1. Test handshake
        print("Testing handshake operation...")
        handshake_msg = Message(
            id="test-1",
            type="request",
            method="handshake",
            params={"version": "1.0"}
        )
        await self.measure_operation('handshake', handshake_msg)
        
        # 2. Test health check
        print("Testing health check operation...")
        health_msg = Message(
            id="test-2",
            type="request",
            method="health"
        )
        await self.measure_operation('health', health_msg)
        
        # 3. Test tools list
        print("Testing tools list operation...")
        tools_msg = Message(
            id="test-3",
            type="request",
            method="tools.list"
        )
        await self.measure_operation('tools_list', tools_msg)
        
        # 4. Test tool execution
        print("Testing tool execution...")
        execute_msg = Message(
            id="test-4",
            type="request",
            method="tools.execute",
            params={
                "toolId": "memory_search",
                "params": {"query": "test"},
                "context": {}
            }
        )
        await self.measure_operation('tool_execute', execute_msg, iterations=50)
        
        # Print results
        self.print_results()
    
    def print_results(self):
        """Print benchmark results"""
        print("\n=== Performance Results ===\n")
        
        for operation, times in self.results.items():
            if not times:
                continue
                
            avg_time = statistics.mean(times)
            min_time = min(times)
            max_time = max(times)
            p50 = statistics.median(times)
            p95 = statistics.quantiles(times, n=20)[18] if len(times) > 20 else max_time
            p99 = statistics.quantiles(times, n=100)[98] if len(times) > 100 else max_time
            
            status = "✅ PASSED" if avg_time < 100 else "❌ FAILED"
            
            print(f"{status} {operation}:")
            print(f"  Average: {avg_time:.2f}ms (target: <100ms)")
            print(f"  Min: {min_time:.2f}ms")
            print(f"  Max: {max_time:.2f}ms")
            print(f"  P50: {p50:.2f}ms")
            print(f"  P95: {p95:.2f}ms")
            print(f"  P99: {p99:.2f}ms")
            print()
    
    async def test_startup_time(self):
        """Test server initialization time"""
        print("\nTesting startup time...")
        
        times = []
        for i in range(5):
            start_time = time.perf_counter()
            server = DGMBridgeSTDIOServer()
            # Simulate initialization
            await server.send_message(Message(
                id='init',
                type='event',
                method='server.started',
                params={'version': '1.0'}
            ))
            end_time = time.perf_counter()
            times.append((end_time - start_time) * 1000)
            
            print(f"  Iteration {i+1}: {times[-1]:.2f}ms")
        
        avg_startup = statistics.mean(times)
        status = "✅ PASSED" if avg_startup < 2000 else "❌ FAILED"
        print(f"\n{status} Average startup time: {avg_startup:.2f}ms (target: <2000ms)")
    
    async def test_memory_overhead(self):
        """Test memory usage"""
        import psutil
        import os
        
        print("\nTesting memory overhead...")
        
        process = psutil.Process(os.getpid())
        baseline_memory = process.memory_info().rss / 1024 / 1024  # MB
        
        # Create server and perform operations
        server = DGMBridgeSTDIOServer()
        for i in range(100):
            msg = Message(
                id=f"mem-test-{i}",
                type="request",
                method="health"
            )
            await server.handle_message(msg)
        
        current_memory = process.memory_info().rss / 1024 / 1024  # MB
        memory_increase = current_memory - baseline_memory
        
        status = "✅ PASSED" if memory_increase < 50 else "❌ FAILED"
        print(f"{status} Memory increase: {memory_increase:.2f}MB (target: <50MB)")
        print(f"  Baseline: {baseline_memory:.2f}MB")
        print(f"  Current: {current_memory:.2f}MB")

async def main():
    tester = BridgePerformanceTester()
    
    # Run main benchmarks
    await tester.run_benchmarks()
    
    # Test startup time
    await tester.test_startup_time()
    
    # Test memory overhead
    await tester.test_memory_overhead()
    
    print("\n=== Recommendations ===")
    
    # Analyze results and provide recommendations
    avg_latencies = {op: statistics.mean(times) for op, times in tester.results.items() if times}
    overall_avg = statistics.mean(avg_latencies.values())
    
    if overall_avg > 50:
        print("- Consider implementing connection pooling for Python processes")
        print("- Investigate using MessagePack instead of JSON for serialization")
    
    if any(avg > 100 for avg in avg_latencies.values()):
        print("- Some operations exceed 100ms target latency")
        print("- Profile Python code to identify bottlenecks")
        print("- Consider caching frequently accessed data")
    
    print("\nBenchmark complete!")

if __name__ == "__main__":
    asyncio.run(main())