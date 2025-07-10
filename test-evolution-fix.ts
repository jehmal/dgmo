#!/usr/bin/env bun

import { Session } from './opencode/packages/opencode/src/session';
import { SessionPerformance } from './opencode/packages/opencode/src/session/performance';
import { App } from './opencode/packages/opencode/src/app/app';
import { UI } from './opencode/packages/opencode/src/cli/ui';

async function testEvolutionDataCollection() {
  console.log('Testing evolution data collection with session message analysis...');

  await App.provide({ cwd: process.cwd() }, async (app) => {
    const data = {
      totalSamples: 0,
      toolStats: {} as Record<string, any>,
      errorPatterns: [] as any[],
      successRate: 0,
      sessionCount: 0,
      timeRange: {
        start: new Date(),
        end: new Date(),
      },
    };

    // Analyze first 20 sessions
    const sessions = [];
    for await (const session of Session.list()) {
      sessions.push(session);
      if (sessions.length >= 20) break;
    }

    console.log(`\nAnalyzing ${sessions.length} sessions...`);

    for (const session of sessions) {
      // First try performance report
      const report = await SessionPerformance.loadReport(session.id);
      if (report) {
        console.log(`✓ Session ${session.id} has performance report`);
        continue;
      }

      // Analyze messages directly
      try {
        const messages = await Session.messages(session.id);
        let toolUseCount = 0;

        for (const msg of messages) {
          if (msg.role === 'assistant' && msg.metadata?.tool) {
            for (const [_, toolData] of Object.entries(msg.metadata.tool)) {
              const toolName = toolData.title || 'unknown';

              if (!data.toolStats[toolName]) {
                data.toolStats[toolName] = {
                  count: 0,
                  successRate: 1.0,
                  avgDuration: 0,
                  errors: [],
                };
              }

              data.toolStats[toolName].count++;
              data.totalSamples++;
              toolUseCount++;

              if (toolData['error']) {
                data.toolStats[toolName].errors.push(toolData['message'] || 'Unknown error');
              }
            }
          }
        }

        if (toolUseCount > 0) {
          data.sessionCount++;
          console.log(`✓ Session ${session.id}: ${toolUseCount} tool uses found`);
        }
      } catch (e) {
        console.log(`✗ Session ${session.id}: Failed to analyze`);
      }
    }

    // Display results
    console.log('\n=== Evolution Data Summary ===');
    console.log(`Total samples: ${data.totalSamples}`);
    console.log(`Sessions with data: ${data.sessionCount}`);
    console.log(`\nTool Usage:`);

    const sortedTools = Object.entries(data.toolStats)
      .sort((a: any, b: any) => b[1].count - a[1].count)
      .slice(0, 10);

    for (const [tool, stats] of sortedTools) {
      const successRate =
        stats.count > 0
          ? (((stats.count - stats.errors.length) / stats.count) * 100).toFixed(0)
          : 100;
      console.log(`  ${tool}: ${stats.count} uses (${successRate}% success)`);
    }

    if (data.totalSamples >= 10) {
      console.log('\n✅ Sufficient data for evolution analysis!');
      console.log('The evolution system should now work with this data.');
    } else {
      console.log('\n⚠️  Need more data for evolution (10+ samples required)');
    }
  });
}

testEvolutionDataCollection().catch(console.error);
