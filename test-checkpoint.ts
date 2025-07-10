import { CheckpointManager } from './opencode/packages/opencode/src/checkpoint/checkpoint-manager';

async function testCheckpoint() {
  console.log('Testing checkpoint functionality...');

  try {
    // Test creating a checkpoint
    const checkpoint = await CheckpointManager.createCheckpoint(
      'ses_test123',
      'msg_test456',
      'Test checkpoint',
    );

    console.log('✅ Checkpoint created:', checkpoint);

    // Test listing checkpoints
    const checkpoints = await CheckpointManager.listCheckpoints('ses_test123');
    console.log('✅ Checkpoints listed:', checkpoints.length, 'checkpoints found');

    // Test getting a specific checkpoint
    const retrieved = await CheckpointManager.getCheckpoint(checkpoint.id);
    console.log('✅ Checkpoint retrieved:', retrieved.id);

    console.log('\n🎉 All checkpoint tests passed!');
  } catch (error) {
    console.error('❌ Test failed:', error);
  }
}

testCheckpoint();
