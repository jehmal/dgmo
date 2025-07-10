#!/usr/bin/env bun

import { Session } from './opencode/packages/opencode/src/session';
import { SessionPerformance } from './opencode/packages/opencode/src/session/performance';
import { App } from './opencode/packages/opencode/src/app/app';
import { Storage } from './opencode/packages/opencode/src/storage/storage';
import { PerformanceTracker } from './opencode/packages/opencode/src/dgm-integration';

// This script demonstrates the fix for the evolution data loading issue

async function generateMockPerformanceData() {
  console.log('Generating mock performance data for existing sessions...');

  await App.provide({ cwd: process.cwd() }, async (app) => {
    let sessionCount = 0;
    let generatedCount = 0;

    // Process first 10 sessions to demonstrate the fix
    for await (const session of Session.list()) {
      sessionCount++;
      if (sessionCount > 10) break;

      // Check if performance data already exists
      const existingReport = await SessionPerformance.loadReport(session.id);
      if (existingReport) {
        console.log(`Session ${session.id} already has performance data`);
        continue;
      }

      // Generate mock performance data based on session messages
      const messages = await Session.messages(session.id);
      if (messages.length === 0) continue;

      // Create a performance tracker and simulate some metrics
      const tracker = new PerformanceTracker();

      // Analyze messages to extract tool usage
      for (const msg of messages) {
        if (msg.role === 'assistant' && msg.metadata?.tool) {
          for (const [toolId, toolData] of Object.entries(msg.metadata.tool)) {
            const toolName = toolData.title || 'unknown';
            const duration =
              toolData.time?.end && toolData.time?.start
                ? toolData.time.end - toolData.time.start
                : 100;
            const success = !toolData.error;

            // Track the operation
            tracker.trackOperation({
              type: toolName as any,
              duration,
              success,
              metadata: {
                sessionId: session.id,
                messageId: msg.id,
                error: toolData.error ? toolData.message : undefined,
              },
            });
          }
        }
      }

      // Save the performance report
      const report = tracker.getReport();
      if (report.totalOperations > 0) {
        await SessionPerformance.saveReport(session.id, report);
        generatedCount++;
        console.log(
          `Generated performance data for session ${session.id}: ${report.totalOperations} operations`,
        );
      }
    }

    console.log(`\nSummary:`);
    console.log(`- Total sessions checked: ${sessionCount}`);
    console.log(`- Performance reports generated: ${generatedCount}`);
    console.log(`\nNow you can run 'opencode evolve' to see the data!`);
  });
}

// Run the fix
generateMockPerformanceData().catch(console.error);
