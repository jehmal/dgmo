/**
 * Comprehensive tests for AsyncResponseManager
 * Addresses critical test coverage gap identified in analysis
 */

import {
  AsyncResponseManager,
  AsyncTaskState,
  AsyncTask,
} from '../../src/managers/async-response-manager';
import { Command, CommandResult } from '../../src/types/command.types';

describe('AsyncResponseManager', () => {
  let manager: AsyncResponseManager;
  let mockCommand: Command;

  beforeEach(() => {
    manager = new AsyncResponseManager();
    mockCommand = {
      id: 'test-command-1',
      type: 'test',
      parameters: { test: true },
      timestamp: new Date(),
    };
  });

  afterEach(() => {
    manager.removeAllListeners();
  });

  describe('Task Creation', () => {
    it('should create a new task with correct initial state', () => {
      const task = manager.createTask(mockCommand);

      expect(task.id).toBe(`task_${mockCommand.id}`);
      expect(task.commandId).toBe(mockCommand.id);
      expect(task.state).toBe(AsyncTaskState.PENDING);
      expect(task.startedAt).toBeInstanceOf(Date);
      expect(task.progress).toBeUndefined();
      expect(task.result).toBeUndefined();
      expect(task.error).toBeUndefined();
    });

    it('should emit task.created event', (done) => {
      manager.once('task.created', ({ task }) => {
        expect(task.commandId).toBe(mockCommand.id);
        done();
      });

      manager.createTask(mockCommand);
    });

    it('should create task with metadata', () => {
      const metadata = { priority: 'high', source: 'test' };
      const task = manager.createTask(mockCommand, metadata);

      expect(task.metadata).toEqual(metadata);
    });
  });

  describe('Task State Management', () => {
    let task: AsyncTask;

    beforeEach(() => {
      task = manager.createTask(mockCommand);
    });

    it('should start a pending task', () => {
      manager.startTask(task.id);

      const updatedTask = manager.getTask(task.id);
      expect(updatedTask?.state).toBe(AsyncTaskState.RUNNING);
    });

    it('should emit task.started event', (done) => {
      manager.once('task.started', ({ task: startedTask }) => {
        expect(startedTask.state).toBe(AsyncTaskState.RUNNING);
        done();
      });

      manager.startTask(task.id);
    });

    it('should throw error when starting non-pending task', () => {
      manager.startTask(task.id); // Start once

      expect(() => manager.startTask(task.id)).toThrow(
        'Task test-command-1 is not in pending state',
      );
    });

    it('should throw error when starting non-existent task', () => {
      expect(() => manager.startTask('non-existent')).toThrow('Task not found: non-existent');
    });
  });

  describe('Progress Updates', () => {
    let task: AsyncTask;

    beforeEach(() => {
      task = manager.createTask(mockCommand);
      manager.startTask(task.id);
    });

    it('should update task progress', () => {
      manager.updateProgress(task.id, 50, 'Half complete');

      const updatedTask = manager.getTask(task.id);
      expect(updatedTask?.progress).toBe(50);
      expect(updatedTask?.message).toBe('Half complete');
    });

    it('should clamp progress between 0 and 100', () => {
      manager.updateProgress(task.id, -10);
      expect(manager.getTask(task.id)?.progress).toBe(0);

      manager.updateProgress(task.id, 150);
      expect(manager.getTask(task.id)?.progress).toBe(100);
    });

    it('should emit task.progress event', (done) => {
      manager.once('task.progress', ({ task: progressTask, progress, message }) => {
        expect(progressTask.id).toBe(task.id);
        expect(progress).toBe(75);
        expect(message).toBe('Almost done');
        done();
      });

      manager.updateProgress(task.id, 75, 'Almost done');
    });

    it('should throw error when updating progress of non-running task', () => {
      const pendingTask = manager.createTask({
        ...mockCommand,
        id: 'pending-task',
      });

      expect(() => manager.updateProgress(pendingTask.id, 50)).toThrow(
        'Task pending-task is not running',
      );
    });
  });

  describe('Task Completion', () => {
    let task: AsyncTask;
    let mockResult: CommandResult;

    beforeEach(() => {
      task = manager.createTask(mockCommand);
      manager.startTask(task.id);
      mockResult = {
        success: true,
        data: { result: 'test completed' },
        timestamp: new Date(),
      };
    });

    it('should complete a running task', () => {
      manager.completeTask(task.id, mockResult);

      const completedTask = manager.getTask(task.id);
      expect(completedTask?.state).toBe(AsyncTaskState.COMPLETED);
      expect(completedTask?.result).toEqual(mockResult);
      expect(completedTask?.progress).toBe(100);
      expect(completedTask?.completedAt).toBeInstanceOf(Date);
    });

    it('should emit task.completed event', (done) => {
      manager.once('task.completed', ({ task: completedTask, result }) => {
        expect(completedTask.id).toBe(task.id);
        expect(result).toEqual(mockResult);
        done();
      });

      manager.completeTask(task.id, mockResult);
    });

    it('should throw error when completing non-running task', () => {
      const pendingTask = manager.createTask({
        ...mockCommand,
        id: 'pending-task',
      });

      expect(() => manager.completeTask(pendingTask.id, mockResult)).toThrow(
        'Task pending-task is not running',
      );
    });
  });

  describe('Task Failure', () => {
    let task: AsyncTask;
    let mockError: Error;

    beforeEach(() => {
      task = manager.createTask(mockCommand);
      manager.startTask(task.id);
      mockError = new Error('Test error');
    });

    it('should fail a running task', () => {
      manager.failTask(task.id, mockError);

      const failedTask = manager.getTask(task.id);
      expect(failedTask?.state).toBe(AsyncTaskState.FAILED);
      expect(failedTask?.error).toBe(mockError);
      expect(failedTask?.completedAt).toBeInstanceOf(Date);
    });

    it('should emit task.failed event', (done) => {
      manager.once('task.failed', ({ task: failedTask, error }) => {
        expect(failedTask.id).toBe(task.id);
        expect(error).toBe(mockError);
        done();
      });

      manager.failTask(task.id, mockError);
    });

    it('should not fail already completed task', () => {
      const mockResult: CommandResult = {
        success: true,
        data: {},
        timestamp: new Date(),
      };

      manager.completeTask(task.id, mockResult);
      manager.failTask(task.id, mockError);

      const task2 = manager.getTask(task.id);
      expect(task2?.state).toBe(AsyncTaskState.COMPLETED);
    });
  });

  describe('Task Cancellation', () => {
    let task: AsyncTask;

    beforeEach(() => {
      task = manager.createTask(mockCommand);
    });

    it('should cancel a pending task', () => {
      const cancelled = manager.cancelTask(task.id);

      expect(cancelled).toBe(true);
      expect(manager.getTask(task.id)?.state).toBe(AsyncTaskState.CANCELLED);
      expect(manager.isCancelled(task.id)).toBe(true);
    });

    it('should cancel a running task', () => {
      manager.startTask(task.id);
      const cancelled = manager.cancelTask(task.id);

      expect(cancelled).toBe(true);
      expect(manager.getTask(task.id)?.state).toBe(AsyncTaskState.CANCELLED);
    });

    it('should not cancel completed task', () => {
      manager.startTask(task.id);
      manager.completeTask(task.id, {
        success: true,
        data: {},
        timestamp: new Date(),
      });

      const cancelled = manager.cancelTask(task.id);
      expect(cancelled).toBe(false);
    });

    it('should emit task.cancelled event', (done) => {
      manager.once('task.cancelled', ({ task: cancelledTask }) => {
        expect(cancelledTask.id).toBe(task.id);
        done();
      });

      manager.cancelTask(task.id);
    });
  });

  describe('Task Waiting and Promises', () => {
    let task: AsyncTask;

    beforeEach(() => {
      task = manager.createTask(mockCommand);
    });

    it('should resolve immediately for completed task', async () => {
      const mockResult: CommandResult = {
        success: true,
        data: { test: 'result' },
        timestamp: new Date(),
      };

      manager.startTask(task.id);
      manager.completeTask(task.id, mockResult);

      const result = await manager.waitForTask(task.id);
      expect(result).toEqual(mockResult);
    });

    it('should reject immediately for failed task', async () => {
      const mockError = new Error('Task failed');

      manager.startTask(task.id);
      manager.failTask(task.id, mockError);

      await expect(manager.waitForTask(task.id)).rejects.toThrow('Task failed');
    });

    it('should reject immediately for cancelled task', async () => {
      manager.cancelTask(task.id);

      await expect(manager.waitForTask(task.id)).rejects.toThrow('Task cancelled');
    });

    it('should wait for task completion', async () => {
      const mockResult: CommandResult = {
        success: true,
        data: { async: 'result' },
        timestamp: new Date(),
      };

      manager.startTask(task.id);

      // Complete task after a delay
      setTimeout(() => {
        manager.completeTask(task.id, mockResult);
      }, 50);

      const result = await manager.waitForTask(task.id);
      expect(result).toEqual(mockResult);
    });

    it('should timeout waiting for task', async () => {
      manager.startTask(task.id);

      await expect(manager.waitForTask(task.id, 100)).rejects.toThrow('Task timeout');
    });

    it('should reject for non-existent task', async () => {
      await expect(manager.waitForTask('non-existent')).rejects.toThrow(
        'Task not found: non-existent',
      );
    });
  });

  describe('Async Context', () => {
    let task: AsyncTask;

    beforeEach(() => {
      task = manager.createTask(mockCommand, { priority: 'high' });
    });

    it('should create async context with correct methods', () => {
      const context = manager.createAsyncContext(task.id);

      expect(typeof context.updateProgress).toBe('function');
      expect(typeof context.checkCancellation).toBe('function');
      expect(context.metadata).toEqual({ priority: 'high' });
    });

    it('should update progress through context', () => {
      manager.startTask(task.id);
      const context = manager.createAsyncContext(task.id);

      context.updateProgress(60, 'Context update');

      const updatedTask = manager.getTask(task.id);
      expect(updatedTask?.progress).toBe(60);
      expect(updatedTask?.message).toBe('Context update');
    });

    it('should check cancellation through context', () => {
      const context = manager.createAsyncContext(task.id);

      expect(context.checkCancellation()).toBe(false);

      manager.cancelTask(task.id);
      expect(context.checkCancellation()).toBe(true);
    });

    it('should throw error for non-existent task', () => {
      expect(() => manager.createAsyncContext('non-existent')).toThrow(
        'Task not found: non-existent',
      );
    });
  });

  describe('Task Queries and Statistics', () => {
    beforeEach(() => {
      // Create multiple tasks in different states
      const task1 = manager.createTask(mockCommand);
      const task2 = manager.createTask({ ...mockCommand, id: 'cmd-2' });
      const task3 = manager.createTask({ ...mockCommand, id: 'cmd-3' });

      manager.startTask(task1.id);
      manager.startTask(task2.id);
      manager.completeTask(task2.id, { success: true, data: {}, timestamp: new Date() });
      manager.failTask(task3.id, new Error('Test error'));
    });

    it('should get task by command ID', () => {
      const task = manager.getTaskByCommand(mockCommand.id);
      expect(task?.commandId).toBe(mockCommand.id);
    });

    it('should get all tasks', () => {
      const tasks = manager.getAllTasks();
      expect(tasks).toHaveLength(3);
    });

    it('should get tasks by state', () => {
      const runningTasks = manager.getTasksByState(AsyncTaskState.RUNNING);
      const completedTasks = manager.getTasksByState(AsyncTaskState.COMPLETED);
      const failedTasks = manager.getTasksByState(AsyncTaskState.FAILED);

      expect(runningTasks).toHaveLength(1);
      expect(completedTasks).toHaveLength(1);
      expect(failedTasks).toHaveLength(1);
    });

    it('should provide accurate statistics', () => {
      const stats = manager.getStatistics();

      expect(stats.total).toBe(3);
      expect(stats.pending).toBe(0);
      expect(stats.running).toBe(1);
      expect(stats.completed).toBe(1);
      expect(stats.failed).toBe(1);
      expect(stats.cancelled).toBe(0);
    });
  });

  describe('Cleanup Operations', () => {
    it('should clean up completed tasks', () => {
      const task1 = manager.createTask(mockCommand);
      const task2 = manager.createTask({ ...mockCommand, id: 'cmd-2' });

      manager.startTask(task1.id);
      manager.completeTask(task1.id, { success: true, data: {}, timestamp: new Date() });
      manager.startTask(task2.id);

      const cleaned = manager.cleanupCompleted();

      expect(cleaned).toBe(1);
      expect(manager.getAllTasks()).toHaveLength(1);
      expect(manager.getTask(task2.id)).toBeDefined();
      expect(manager.getTask(task1.id)).toBeUndefined();
    });

    it('should automatically cleanup after timeout', (done) => {
      const task = manager.createTask(mockCommand);
      manager.startTask(task.id);
      manager.completeTask(task.id, { success: true, data: {}, timestamp: new Date() });

      // Override cleanup timeout for testing
      (manager as any).cleanup(task.id);

      setTimeout(() => {
        expect(manager.getTask(task.id)).toBeUndefined();
        done();
      }, 10);
    }, 1000);
  });

  describe('Error Handling and Edge Cases', () => {
    it('should handle multiple event listeners correctly', (done) => {
      const task = manager.createTask(mockCommand);
      let eventCount = 0;

      const handler = () => {
        eventCount++;
        if (eventCount === 2) done();
      };

      manager.on('task.started', handler);
      manager.on('task.progress', handler);

      manager.startTask(task.id);
      manager.updateProgress(task.id, 50);
    });

    it('should handle rapid state changes', () => {
      const task = manager.createTask(mockCommand);

      manager.startTask(task.id);
      manager.updateProgress(task.id, 25);
      manager.updateProgress(task.id, 50);
      manager.updateProgress(task.id, 75);
      manager.completeTask(task.id, { success: true, data: {}, timestamp: new Date() });

      const finalTask = manager.getTask(task.id);
      expect(finalTask?.state).toBe(AsyncTaskState.COMPLETED);
      expect(finalTask?.progress).toBe(100);
    });

    it('should handle concurrent operations safely', async () => {
      const task = manager.createTask(mockCommand);
      manager.startTask(task.id);

      const promises = [
        manager.waitForTask(task.id),
        manager.waitForTask(task.id),
        manager.waitForTask(task.id),
      ];

      setTimeout(() => {
        manager.completeTask(task.id, { success: true, data: {}, timestamp: new Date() });
      }, 50);

      const results = await Promise.all(promises);
      results.forEach((result) => {
        expect(result.success).toBe(true);
      });
    });
  });
});
