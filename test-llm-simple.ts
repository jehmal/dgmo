#!/usr/bin/env bun

// Simple test to verify LLM analyzer works
import { createAnthropic } from '@ai-sdk/anthropic';
import { generateText } from 'ai';

async function testSimpleLLM() {
  const apiKey = process.env.ANTHROPIC_API_KEY;

  if (!apiKey) {
    console.error('Please set ANTHROPIC_API_KEY environment variable');
    process.exit(1);
  }

  console.log('Testing simple LLM call...');

  try {
    const anthropic = createAnthropic({ apiKey });

    const { text } = await generateText({
      model: anthropic('claude-3-5-sonnet-20241022'),
      prompt: `Analyze these user messages and return ONLY valid JSON:
      
1. Use your qdrant to get context
2. Use your qdrant for understanding
3. Create 3 agents to work on this

Return JSON with structure:
{
  "patterns": [
    {
      "type": "workflow",
      "description": "pattern description",
      "frequency": 2,
      "examples": ["example1"],
      "confidence": 0.9
    }
  ]
}`,
      temperature: 0.3,
      maxTokens: 1000,
    });

    console.log('Raw response:', text);

    try {
      const parsed = JSON.parse(text);
      console.log('Parsed successfully:', JSON.stringify(parsed, null, 2));
    } catch (e) {
      console.error('Failed to parse:', e);

      // Try to extract JSON
      const jsonMatch = text.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        console.log('Extracted JSON:', jsonMatch[0]);
        const parsed = JSON.parse(jsonMatch[0]);
        console.log('Parsed extracted:', JSON.stringify(parsed, null, 2));
      }
    }
  } catch (error) {
    console.error('LLM call failed:', error);
  }
}

testSimpleLLM();
