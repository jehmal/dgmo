#!/usr/bin/env bun

import { Session } from './opencode/packages/opencode/src/session';
import { SessionPerformance } from './opencode/packages/opencode/src/session/performance';
import { App } from './opencode/packages/opencode/src/app/app';
import { Storage } from './opencode/packages/opencode/src/storage/storage';

async function testSessionLoading() {
  console.log('Testing session loading...');

  // Initialize app context
  await App.provide({ cwd: process.cwd() }, async (app) => {
    console.log('App info:', {
      dataPath: app.path.data,
      root: app.path.root,
      cwd: app.path.cwd,
    });

    // Test 1: List sessions using Session.list()
    console.log('\n=== Testing Session.list() ===');
    let sessionCount = 0;
    for await (const session of Session.list()) {
      sessionCount++;
      if (sessionCount <= 3) {
        console.log(`Session ${sessionCount}:`, session.id);
      }
    }
    console.log(`Total sessions found via Session.list(): ${sessionCount}`);

    // Test 2: List sessions directly from storage
    console.log('\n=== Testing Storage.list() ===');
    let storageCount = 0;
    for await (const item of Storage.list('session/info')) {
      storageCount++;
      if (storageCount <= 3) {
        console.log(`Storage item ${storageCount}:`, item);
      }
    }
    console.log(`Total sessions found via Storage.list(): ${storageCount}`);

    // Test 3: Check performance data
    console.log('\n=== Testing Performance Data ===');
    let perfCount = 0;
    for await (const item of Storage.list('session/performance')) {
      perfCount++;
      if (perfCount <= 3) {
        console.log(`Performance item ${perfCount}:`, item);
      }
    }
    console.log(`Total performance reports found: ${perfCount}`);
  });
}

testSessionLoading().catch(console.error);
