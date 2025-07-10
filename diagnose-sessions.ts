#!/usr/bin/env bun

import { Session } from './opencode/packages/opencode/src/session';
import { Global } from './opencode/packages/opencode/src/global';
import * as fs from 'fs/promises';
import * as path from 'path';

async function diagnoseSessionMessages() {
  console.log('Diagnosing session messages...');

  const sessions = [];

  // Get sessions from current project
  for await (const session of Session.list()) {
    sessions.push(session);
  }

  // Also look for sessions in the global data directory
  try {
    const projectsDir = path.join(Global.Path.data, 'project');
    const projectDirs = await fs.readdir(projectsDir).catch(() => []);

    for (const projectDir of projectDirs) {
      const sessionInfoDir = path.join(projectsDir, projectDir, 'storage', 'session', 'info');
      try {
        const sessionFiles = await fs.readdir(sessionInfoDir).catch(() => []);
        for (const sessionFile of sessionFiles) {
          if (sessionFile.endsWith('.json')) {
            try {
              const sessionData = await fs.readFile(
                path.join(sessionInfoDir, sessionFile),
                'utf-8',
              );
              const session = JSON.parse(sessionData);
              sessions.push(session);
            } catch (e) {
              // Skip invalid sessions
            }
          }
        }
      } catch (e) {
        // Skip inaccessible directories
      }
    }
  } catch (e) {
    console.log('Note: Only analyzing current project sessions');
  }

  console.log(`Found ${sessions.length} total sessions`);

  // Analyze messages from first 10 sessions
  let sessionCount = 0;
  const messagePatterns = new Map<string, number>();

  for (const session of sessions.slice(0, 10)) {
    try {
      const messages = await Session.messages(session.id);
      let userMessageCount = 0;

      console.log(`\nSession ${sessionCount + 1} (${session.id}):`);

      for (const msg of messages) {
        if (msg.role === 'user' && msg.parts) {
          for (const part of msg.parts) {
            if (part.type === 'text' && part.text) {
              userMessageCount++;

              // Show first 100 chars of each message
              console.log(`  Message ${userMessageCount}: ${part.text.substring(0, 100)}...`);

              // Look for common patterns
              const lowerText = part.text.toLowerCase();
              if (lowerText.includes('qdrant')) {
                const count = messagePatterns.get('qdrant') || 0;
                messagePatterns.set('qdrant', count + 1);
              }
              if (lowerText.includes('create') && lowerText.includes('agent')) {
                const count = messagePatterns.get('create_agents') || 0;
                messagePatterns.set('create_agents', count + 1);
              }
              if (lowerText.includes('use your')) {
                const count = messagePatterns.get('use_your') || 0;
                messagePatterns.set('use_your', count + 1);
              }
              if (lowerText.includes('first') && lowerText.includes('then')) {
                const count = messagePatterns.get('first_then') || 0;
                messagePatterns.set('first_then', count + 1);
              }
            }
          }
        }
      }

      console.log(`  Total user messages: ${userMessageCount}`);
      sessionCount++;
    } catch (e) {
      console.log(`  Error reading session: ${e}`);
    }
  }

  console.log('\n=== Pattern Summary ===');
  for (const [pattern, count] of messagePatterns) {
    console.log(`${pattern}: ${count} occurrences`);
  }
}

diagnoseSessionMessages();
