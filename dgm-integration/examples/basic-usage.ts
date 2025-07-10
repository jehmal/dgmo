/**
 * Basic usage example for DGM Integration
 */

import { DGMBridge, PerformanceTracker, ToolSync, DGMConfig } from '../src';

async function main() {
  // Configuration
  const config: DGMConfig = {
    enabled: true,
    pythonPath: '/usr/bin/python3',  // or './dgm/venv/bin/python'
    agentPath: './dgm/coding_agent.py',
    evolutionSchedule: 'manual',
    trackingLevel: 'standard',
    autoApprove: false,
    maxExecutionTime: 30000
  };

  // Initialize components
  const bridge = new DGMBridge(config);
  const tracker = new PerformanceTracker('./dgm-data');
  const toolSync = new ToolSync('./shared-tools');

  try {
    // Start the bridge
    console.log('Initializing DGM bridge...');
    await bridge.initialize();
    console.log('Bridge initialized successfuly');

    // Track some tool executions
    console.log('\nTracking tool executions...');
    
    await tracker.track({
      toolName: 'bash',
      executionTime: 1.23,
      success: true,
      timestamp: new Date(),
      sessionId: 'test-session-1',
      parameters: { command: 'ls -la' }
    });

    await tracker.track({
      toolName: 'edit',
      executionTime: 0.45,
      success: false,
      errorType: 'FileNotFound',
      errorMessage: 'File not found: test.txt',
      timestamp: new Date(),
      sessionId: 'test-session-1',
      parameters: { command: 'edit', path: 'test.txt' }
    });

    // Get usage patterns
    console.log('\nAnalyzing usage patterns...');
    const patterns = await tracker.getUsagePatterns();
    console.log('Patterns:', JSON.stringify(patterns, null, 2));

    // Request evolution
    console.log('\nRequesting tool evolution...');
    const evolutionResult = await bridge.evolve(patterns);
    console.log('Evolution result:', JSON.stringify(evolutionResult, null, 2));

    // Save improvements for review
    if (evolutionResult.improvements.length > 0) {
      console.log('\nSaving improvements for review...');
      
      for (const improvement of evolutionResult.improvements) {
        const id = await toolSync.saveExperimentalImprovement(improvement);
        console.log(`Saved improvement ${id} for ${improvement.toolName}`);
      }
    }

    // Get summary
    console.log('\nPerformance summary:');
    const summary = await tracker.getSummary();
    console.log(JSON.stringify(summary, null, 2));

  } catch (error) {
    console.error('Error:', error);
  } finally {
    // Cleanup
    console.log('\nShutting down...');
    await bridge.shutdown();
    await tracker.stop();
    console.log('Shutdown complete');
  }
}

// Run the example
main().catch(console.error);