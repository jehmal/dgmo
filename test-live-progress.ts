#!/usr/bin/env bun

/**
 * Test script to demonstrate live task progress updates
 * This simulates the Claude Code style progress display
 */

import { ProgressSummarizer } from './opencode/packages/opencode/src/events/detailed-task-events';

// Simulate different tool invocations with progress
const testScenarios = [
  {
    agentName: 'Agent 1',
    tool: 'grep',
    parameters: { pattern: 'function.*export', include: '*.ts' },
    phase: 'context-gathering',
    elapsed: 1500,
  },
  {
    agentName: 'Agent 2',
    tool: 'read',
    parameters: { filePath: '/src/components/TaskProgress.tsx', limit: 100 },
    phase: 'processing',
    elapsed: 3200,
  },
  {
    agentName: 'Agent 3',
    tool: 'write',
    parameters: { filePath: '/src/enhanced-progress.ts' },
    phase: 'finalizing',
    elapsed: 5800,
  },
  {
    agentName: 'Agent 1',
    tool: 'bash',
    parameters: { command: 'npm run build', description: 'Building project' },
    phase: 'processing',
    elapsed: 12000,
  },
  {
    agentName: 'Agent 2',
    tool: 'task',
    parameters: {
      description: 'Implement UI components',
      prompt: 'Create React components for the new progress display system',
    },
    phase: 'processing',
    elapsed: 8500,
  },
];

console.log('🚀 Live Task Progress Demo - Claude Code Style\n');
console.log('='.repeat(60));

testScenarios.forEach((scenario, index) => {
  console.log(`\n📋 Scenario ${index + 1}:`);
  console.log('-'.repeat(40));

  const summaryLines = ProgressSummarizer.generateTaskSummary(
    scenario.agentName,
    scenario.tool,
    scenario.parameters,
    scenario.phase,
    scenario.elapsed,
  );

  // Display the 1-3 line summary (Claude Code style)
  summaryLines.forEach((line, lineIndex) => {
    if (lineIndex === 0) {
      console.log(`${line}`);
    } else {
      console.log(`${line}`);
    }
  });

  console.log();
  console.log(`📊 Tool: ${scenario.tool}`);
  console.log(`⏱️  Elapsed: ${scenario.elapsed}ms`);
  console.log(`🔄 Phase: ${scenario.phase}`);
});

console.log('\n' + '='.repeat(60));
console.log('✅ Demo complete! This shows how progress updates will appear in real-time.');
console.log('📝 Each scenario demonstrates different tool activities with contextual messages.');
console.log("🎯 The format matches Claude Code's 1-3 line progress display style.");
