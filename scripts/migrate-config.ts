#!/usr/bin/env bun
/**
 * Configuration Migration Script
 * Migrates existing configurations to the new unified format
 */

import { ConfigMigration } from '../shared/config/migration';
import * as path from 'path';
import * as fs from 'fs/promises';

async function main() {
  console.log('🔄 Starting configuration migration...\n');

  const sources = [];

  // Check for existing DGMO config
  const dgmoConfigPath = path.join(process.cwd(), 'dgmo.json');
  try {
    await fs.access(dgmoConfigPath);
    sources.push({ path: dgmoConfigPath, type: 'dgmo' as const });
    console.log('✅ Found DGMO config:', dgmoConfigPath);
  } catch {
    console.log('ℹ️  No DGMO config found');
  }

  // Check for existing bridge config
  const bridgeConfigPath = path.join(process.cwd(), 'dgm', 'bridge', 'config.py');
  try {
    await fs.access(bridgeConfigPath);
    sources.push({ path: bridgeConfigPath, type: 'bridge' as const });
    console.log('✅ Found bridge config:', bridgeConfigPath);
  } catch {
    console.log('ℹ️  No bridge config found');
  }

  // Check for existing shared config
  const sharedConfigPath = path.join(process.cwd(), 'shared', 'config', 'dgm.json');
  try {
    await fs.access(sharedConfigPath);
    sources.push({ path: sharedConfigPath, type: 'json' as const });
    console.log('✅ Found shared config:', sharedConfigPath);
  } catch {
    console.log('ℹ️  No shared config found');
  }

  if (sources.length === 0) {
    console.log('\n❌ No configuration files found to migrate');
    process.exit(1);
  }

  console.log(`\n📋 Migrating ${sources.length} configuration source(s)...`);

  // Perform migration
  const result = await ConfigMigration.mergeConfigs(sources);

  if (!result.success) {
    console.error('\n❌ Migration failed:');
    result.errors?.forEach((error) => console.error('  -', error));
    process.exit(1);
  }

  // Display warnings
  if (result.warnings && result.warnings.length > 0) {
    console.log('\n⚠️  Warnings:');
    result.warnings.forEach((warning) => console.log('  -', warning));
  }

  // Save migrated config
  const outputPath = path.join(process.cwd(), 'shared', 'config', 'dgm.json');
  await ConfigMigration.saveMigratedConfig(result.migratedConfig!, outputPath);

  console.log('\n✅ Migration completed successfully!');
  console.log('📁 New configuration saved to:', outputPath);
  console.log('\n📝 Configuration summary:');
  console.log(JSON.stringify(result.migratedConfig, null, 2));

  // Create backup of old configs
  const backupDir = path.join(
    process.cwd(),
    '.config-backup',
    new Date().toISOString().split('T')[0],
  );
  await fs.mkdir(backupDir, { recursive: true });

  for (const source of sources) {
    const backupPath = path.join(backupDir, path.basename(source.path));
    try {
      await fs.copyFile(source.path, backupPath);
      console.log(`📦 Backed up ${source.path} to ${backupPath}`);
    } catch (e) {
      console.warn(`⚠️  Could not backup ${source.path}:`, e);
    }
  }

  console.log('\n🎉 Configuration migration complete!');
}

main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
