#!/usr/bin/env bun

import { analyzePatternsWithLLM } from './opencode/packages/opencode/src/cli/cmd/evolve-llm-analyzer';

// Test messages that should trigger pattern detection
const testMessages = [
  // Qdrant context patterns
  'Use your qdrant to get context about the project structure',
  "First use your qdrant to understand what we've done so far",
  'Use your qdrant memory to get context for this task',
  'Check your qdrant to know the current state',

  // Prompting MCP patterns
  'Use your prompting mcp to optimize this approach',
  'Use your prompting techniques to refine this prompt',
  'Use your prompting mcp server to improve this',
  'Apply your prompting mcp to make this better',

  // Sequential workflow patterns
  'First analyze the code, then create tests for it',
  'Start by reading the file, then make the necessary changes',
  'Begin with understanding the architecture, then implement the feature',

  // Parallel agent patterns
  'Create 3 agents to analyze different aspects of this',
  'Create 5 agents to work on these tasks in parallel',
  'Make 4 agents to handle each component separately',

  // Memory patterns
  'Remember this configuration for future use',
  'Store this solution in your memory',
  'Remember to always check for permissions first',

  // Mixed patterns
  'Use your qdrant to get context, then create 3 agents to implement',
  'First use your prompting mcp to optimize, then execute the task',

  // Some noise messages
  'Just implement the feature',
  'Fix the bug in the code',
  'Update the documentation',
];

async function testLLMAnalysis() {
  console.log('Testing LLM Pattern Analysis...');
  console.log(`Analyzing ${testMessages.length} test messages`);

  // You'll need to provide your Anthropic API key
  const anthropicToken = process.env.ANTHROPIC_API_KEY;

  if (!anthropicToken) {
    console.error('Please set ANTHROPIC_API_KEY environment variable');
    process.exit(1);
  }

  try {
    const patterns = await analyzePatternsWithLLM(
      testMessages,
      anthropicToken,
      true, // verbose
    );

    console.log('\n=== Analysis Results ===');
    console.log(`Found ${patterns.length} patterns:`);

    for (const pattern of patterns) {
      console.log(`\n- Pattern: ${pattern.pattern}`);
      console.log(`  Formula: ${pattern.formula}`);
      console.log(`  Count: ${pattern.count}`);
      console.log(`  Automation: ${pattern.suggestedAutomation}`);
      if (pattern.examples.length > 0) {
        console.log(`  Examples:`);
        pattern.examples.forEach((ex, i) => {
          console.log(`    ${i + 1}. ${ex.substring(0, 60)}...`);
        });
      }
    }

    // Test if the patterns match what we expect
    const hasQdrantPattern = patterns.some(
      (p) => p.pattern.includes('qdrant') || p.formula.toLowerCase().includes('qdrant'),
    );
    const hasPromptingPattern = patterns.some(
      (p) => p.pattern.includes('prompt') || p.formula.toLowerCase().includes('prompt'),
    );
    const hasParallelPattern = patterns.some(
      (p) => p.pattern.includes('parallel') || p.pattern.includes('agents'),
    );

    console.log('\n=== Pattern Detection Validation ===');
    console.log(`✓ Qdrant patterns detected: ${hasQdrantPattern}`);
    console.log(`✓ Prompting patterns detected: ${hasPromptingPattern}`);
    console.log(`✓ Parallel agent patterns detected: ${hasParallelPattern}`);
  } catch (error) {
    console.error('Analysis failed:', error);
  }
}

testLLMAnalysis();
