#!/usr/bin/env bun
// DGMO Bun/TypeScript Bundling Script

import { build } from 'bun';
import { readdir, rm, mkdir, copyFile } from 'fs/promises';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, '../..');
const OPENCODE_DIR = join(PROJECT_ROOT, 'opencode/packages/opencode');
const BUILD_DIR = join(PROJECT_ROOT, 'distribution/build/bun');

// Clean build directory
console.log('🧹 Cleaning build directory...');
await rm(BUILD_DIR, { recursive: true, force: true });
await mkdir(BUILD_DIR, { recursive: true });

// Build configuration
const buildConfig = {
  entrypoints: [join(OPENCODE_DIR, 'src/index.ts')],
  outdir: BUILD_DIR,
  target: 'bun',
  format: 'esm',
  minify: true,
  sourcemap: 'none',
  splitting: false,

  // Bundle all dependencies except native modules
  external: [
    'fsevents', // macOS file watching
    'node-pty', // Terminal emulation
    '@napi-rs/*', // Native modules
  ],

  // Define environment variables
  define: {
    'process.env.NODE_ENV': '"production"',
    'process.env.DGMO_VERSION': `"${process.env.VERSION || 'dev'}"`,
  },
};

console.log('📦 Building TypeScript/Bun bundle...');

try {
  const result = await build(buildConfig);

  if (result.success) {
    console.log('✅ Build successful!');

    // Get bundle size
    const stats = await Bun.file(join(BUILD_DIR, 'index.js')).stat();
    const sizeMB = (stats.size / 1024 / 1024).toFixed(2);
    console.log(`📊 Bundle size: ${sizeMB} MB`);

    // Create standalone executable
    console.log('🔨 Creating standalone executable...');

    // Create a wrapper script that includes Bun runtime
    const wrapperScript = `#!/usr/bin/env bun
// DGMO Standalone Executable
// This file bundles the Bun runtime with the application

import { join } from "path";
import { fileURLToPath } from "url";
import { dirname } from "path";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Set production environment
process.env.NODE_ENV = "production";
process.env.DGMO_STANDALONE = "true";

// Import and run the main application
import("./index.js");
`;

    await Bun.write(join(BUILD_DIR, 'dgmo-bundle.js'), wrapperScript);

    // Copy essential files
    console.log('📄 Copying essential files...');
    const essentialFiles = ['package.json', 'README.md', 'LICENSE'];

    for (const file of essentialFiles) {
      try {
        await copyFile(join(OPENCODE_DIR, file), join(BUILD_DIR, file));
      } catch (e) {
        // File might not exist, that's okay
      }
    }

    // Create minimal package.json for standalone
    const minimalPackage = {
      name: 'dgmo',
      version: process.env.VERSION || 'dev',
      description: 'DGMO - AI-powered CLI with self-evolution',
      main: 'index.js',
      bin: {
        dgmo: './dgmo-bundle.js',
      },
      engines: {
        bun: '>=1.0.0',
      },
      dependencies: {
        // Only include runtime dependencies that couldn't be bundled
      },
    };

    await Bun.write(join(BUILD_DIR, 'package.json'), JSON.stringify(minimalPackage, null, 2));

    console.log('✨ Bun bundle created successfuly!');
    console.log(`📍 Location: ${BUILD_DIR}`);
  } else {
    console.error('❌ Build failed!');
    process.exit(1);
  }
} catch (error) {
  console.error('❌ Build error:', error);
  process.exit(1);
}
