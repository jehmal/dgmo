#!/usr/bin/env bun
/**
 * Test script to debug DGM bridge initialization
 */

import { spawn } from 'child_process';
import { Log } from './opencode/packages/opencode/src/util/log';

const log = Log.create({ service: 'test-dgm-bridge' });

async function testPythonBridge() {
  log.info('Testing Python bridge initialization...');

  // Test 1: Check if Python is accessible
  try {
    const pythonVersion = await new Promise<string>((resolve, reject) => {
      const proc = spawn('python3', ['--version']);
      let output = '';
      proc.stdout.on('data', (data) => (output += data.toString()));
      proc.on('close', (code) => {
        if (code === 0) resolve(output.trim());
        else reject(new Error(`Python check failed with code ${code}`));
      });
    });
    log.info('Python version:', { version: pythonVersion });
  } catch (error) {
    log.error('Python not accessible:', error);
    return;
  }

  // Test 2: Check if DGM module is accessible
  try {
    const moduleCheck = await new Promise<string>((resolve, reject) => {
      const proc = spawn('python3', ['-c', "import dgm.bridge.stdio_server; print('Module OK')"]);
      let output = '';
      let errorOutput = '';
      proc.stdout.on('data', (data) => (output += data.toString()));
      proc.stderr.on('data', (data) => (errorOutput += data.toString()));
      proc.on('close', (code) => {
        if (code === 0) resolve(output.trim());
        else reject(new Error(`Module check failed: ${errorOutput}`));
      });
    });
    log.info('DGM module check:', { result: moduleCheck });
  } catch (error) {
    log.error('DGM module not accessible:', error);
    return;
  }

  // Test 3: Try to spawn the stdio server
  log.info('Spawning stdio server...');
  const proc = spawn('python3', ['-m', 'dgm.bridge.stdio_server'], {
    stdio: ['pipe', 'pipe', 'pipe'],
    env: {
      ...process.env,
      PYTHONUNBUFFERED: '1',
      PYTHONPATH: process.cwd() + '/dgm',
    },
    cwd: process.cwd(),
  });

  let messageBuffer = '';
  let errorBuffer = '';

  proc.stdout.on('data', (data) => {
    messageBuffer += data.toString();
    const lines = messageBuffer.split('\n');
    messageBuffer = lines.pop() || '';

    for (const line of lines) {
      if (line.trim()) {
        log.info('Received from Python:', { message: line });
      }
    }
  });

  proc.stderr.on('data', (data) => {
    errorBuffer += data.toString();
    log.info('Python stderr:', { message: errorBuffer });
  });

  proc.on('error', (error) => {
    log.error('Process error:', error);
  });

  proc.on('exit', (code, signal) => {
    log.info('Process exited', { code, signal });
  });

  // Test 4: Send handshake
  await new Promise((resolve) => setTimeout(resolve, 1000)); // Wait for process to start

  log.info('Sending handshake...');
  const handshakeMessage =
    JSON.stringify({
      id: 'test-1',
      type: 'request',
      method: 'handshake',
      params: { version: '1.0' },
    }) + '\n';

  proc.stdin.write(handshakeMessage, (error) => {
    if (error) {
      log.error('Failed to send handshake:', error);
    } else {
      log.info('Handshake sent successfully');
    }
  });

  // Wait for response
  await new Promise((resolve) => setTimeout(resolve, 3000));

  // Cleanup
  proc.kill();
}

testPythonBridge().catch((error) => {
  log.error('Test failed:', error);
  process.exit(1);
});
