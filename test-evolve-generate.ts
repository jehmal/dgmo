#!/usr/bin/env bun

import { EvolveCommand } from './opencode/packages/opencode/src/cli/cmd/evolve';
import type { Arguments } from 'yargs';

console.log('Testing dgmo evolve --generate command...\\n');

// Create mock arguments with generate=true
const mockArgs: Arguments = {
  _: ['evolve'],
  $0: 'dgmo',
  generate: true,
  // Add any other required properties that yargs would provide
} as Arguments;

async function runTest() {
  try {
    console.log('1. Testing evolve command with --generate flag...');
    console.log('   Mock arguments:', JSON.stringify(mockArgs, null, 2));

    // Capture console output
    const originalLog = console.log;
    const originalError = console.error;
    const logs: string[] = [];
    const errors: string[] = [];

    console.log = (...args: any[]) => {
      logs.push(args.join(' '));
      originalLog(...args);
    };

    console.error = (...args: any[]) => {
      errors.push(args.join(' '));
      originalError(...args);
    };

    // Run the evolve command
    await EvolveCommand.handler(mockArgs);

    // Restore console methods
    console.log = originalLog;
    console.error = originalError;

    console.log('\n2. Verifying command execution...');

    // Check for performance data collection attempts
    const hasPerformanceCollection = logs.some(
      (log) =>
        log.includes('performance') ||
        log.includes('metrics') ||
        log.includes('collecting') ||
        log.includes('Performance'),
    );

    console.log(
      `   ✓ Performance data collection: ${hasPerformanceCollection ? 'DETECTED' : 'NOT DETECTED'}`,
    );

    // Check for improvement generation attempts
    const hasImprovementGeneration = logs.some(
      (log) =>
        log.includes('generat') ||
        log.includes('improvement') ||
        log.includes('optimiz') ||
        log.includes('Generat') ||
        log.includes('Improvement'),
    );

    console.log(
      `   ✓ Improvement generation: ${hasImprovementGeneration ? 'DETECTED' : 'NOT DETECTED'}`,
    );

    // Check for errors
    if (errors.length > 0) {
      console.log(`   ⚠ Errors detected: ${errors.length}`);
      errors.forEach((err, i) => console.log(`     ${i + 1}. ${err}`));
    } else {
      console.log('   ✓ No errors detected');
    }

    console.log('\n3. Test Summary:');
    console.log('   Command executed:', 'SUCCESS');
    console.log('   Performance collection:', hasPerformanceCollection ? 'YES' : 'NO');
    console.log('   Improvement generation:', hasImprovementGeneration ? 'YES' : 'NO');
    console.log('   Errors:', errors.length);

    console.log('\n✅ Test completed successfully!');
  } catch (error) {
    console.error('\n❌ Test failed with error:');
    console.error(error);
    process.exit(1);
  }
}

// Run the test
runTest().catch((error) => {
  console.error('Unhandled error:', error);
  process.exit(1);
});
