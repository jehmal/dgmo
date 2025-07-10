// Test workflow pattern detection
import { analyzeUserMessagePatterns } from './opencode/packages/opencode/src/cli/cmd/evolve';

// Test data structure
const testData = {
  workflowPatterns: [],
  errorPatterns: [],
  toolStats: {},
  totalSamples: 0,
  successRate: 0,
  sessionCount: 0,
  timeRange: {
    start: new Date(),
    end: new Date(),
  },
};

// Test messages that should be detected
const testMessages = [
  'Use your qdrant to get context of what we are working on to do implement the new feature. Use your prompting mcp to optimize and refine your reasoning to complete the task.',
  'use your qdrant to understand the project structure for creating the API endpoints',
  'Use your prompting techniques to optimize the approach for refactoring this code',
  'First analyze the codebase then create a plan for implementation',
  'remember this pattern for future use',
  'store this solution in your memory',
  'create 3 agents to work on different parts of the feature',
  'search through all files for the configuration settings',
];

// Analyze each message
console.log('Testing workflow pattern detection:\n');
testMessages.forEach((msg, i) => {
  console.log(`Message ${i + 1}: "${msg.substring(0, 80)}..."`);
  analyzeUserMessagePatterns(testData, msg);
});

// Display results
console.log('\nDetected Patterns:');
testData.workflowPatterns.forEach((pattern) => {
  console.log(`\n- Pattern: ${pattern.pattern}`);
  console.log(`  Formula: ${pattern.formula}`);
  console.log(`  Count: ${pattern.count}`);
  console.log(`  Suggestion: ${pattern.suggestedAutomation}`);
});
