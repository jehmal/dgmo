import { EventEmitter } from 'eventemitter3';
import { Command, CommandResult } from '../types/command.types';

/**
 * Async task states
 */
export enum AsyncTaskState {
  PENDING = 'pending',
  RUNNING = 'running',
  COMPLETED = 'completed',
  FAILED = 'failed',
  CANCELLED = 'cancelled',
}

/**
 * Async task information
 */
export interface AsyncTask {
  id: string;
  commandId: string;
  state: AsyncTaskState;
  progress?: number;
  message?: string;
  result?: CommandResult;
  error?: Error;
  startedAt: Date;
  completedAt?: Date;
  metadata?: Record<string, any>;
}

/**
 * Async response events
 */
export interface AsyncResponseEvents {
  'task.created': { task: AsyncTask };
  'task.started': { task: AsyncTask };
  'task.progress': { task: AsyncTask; progress: number; message?: string };
  'task.completed': { task: AsyncTask; result: CommandResult };
  'task.failed': { task: AsyncTask; error: Error };
  'task.cancelled': { task: AsyncTask };
}

/**
 * Progress update callback
 */
export type ProgressCallback = (progress: number, message?: string) => void;

/**
 * Async execution context
 */
export interface AsyncContext {
  updateProgress: ProgressCallback;
  checkCancellation: () => boolean;
  metadata: Record<string, any>;
}

/**
 * Async response manager for handling long-running commands
 */
export class AsyncResponseManager extends EventEmitter<AsyncResponseEvents> {
  private tasks: Map<string, AsyncTask> = new Map();
  private commandToTask: Map<string, string> = new Map();
  private cancellationTokens: Map<string, boolean> = new Map();

  /**
   * Create a new async task
   */
  createTask(command: Command, metadata?: Record<string, any>): AsyncTask {
    const task: AsyncTask = {
      id: `task_${command.id}`,
      commandId: command.id,
      state: AsyncTaskState.PENDING,
      startedAt: new Date(),
      metadata,
    };

    this.tasks.set(task.id, task);
    this.commandToTask.set(command.id, task.id);
    this.cancellationTokens.set(task.id, false);

    this.emit('task.created', { task });
    return task;
  }

  /**
   * Start a task
   */
  startTask(taskId: string): void {
    const task = this.tasks.get(taskId);
    if (!task) {
      throw new Error(`Task not found: ${taskId}`);
    }

    if (task.state !== AsyncTaskState.PENDING) {
      throw new Error(`Task ${taskId} is not in pending state`);
    }

    task.state = AsyncTaskState.RUNNING;
    this.emit('task.started', { task });
  }

  /**
   * Update task progress
   */
  updateProgress(taskId: string, progress: number, message?: string): void {
    const task = this.tasks.get(taskId);
    if (!task) {
      throw new Error(`Task not found: ${taskId}`);
    }

    if (task.state !== AsyncTaskState.RUNNING) {
      throw new Error(`Task ${taskId} is not running`);
    }

    task.progress = Math.max(0, Math.min(100, progress));
    task.message = message;

    this.emit('task.progress', { task, progress: task.progress, message });
  }

  /**
   * Complete a task
   */
  completeTask(taskId: string, result: CommandResult): void {
    const task = this.tasks.get(taskId);
    if (!task) {
      throw new Error(`Task not found: ${taskId}`);
    }

    if (task.state !== AsyncTaskState.RUNNING) {
      throw new Error(`Task ${taskId} is not running`);
    }

    task.state = AsyncTaskState.COMPLETED;
    task.result = result;
    task.completedAt = new Date();
    task.progress = 100;

    this.emit('task.completed', { task, result });
    this.cleanup(taskId);
  }

  /**
   * Fail a task
   */
  failTask(taskId: string, error: Error): void {
    const task = this.tasks.get(taskId);
    if (!task) {
      throw new Error(`Task not found: ${taskId}`);
    }

    if (task.state === AsyncTaskState.COMPLETED || task.state === AsyncTaskState.CANCELLED) {
      return; // Already in terminal state
    }

    task.state = AsyncTaskState.FAILED;
    task.error = error;
    task.completedAt = new Date();

    this.emit('task.failed', { task, error });
    this.cleanup(taskId);
  }

  /**
   * Cancel a task
   */
  cancelTask(taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task) {
      return false;
    }

    if (task.state === AsyncTaskState.COMPLETED || task.state === AsyncTaskState.FAILED) {
      return false; // Already in terminal state
    }

    task.state = AsyncTaskState.CANCELLED;
    task.completedAt = new Date();
    this.cancellationTokens.set(taskId, true);

    this.emit('task.cancelled', { task });
    this.cleanup(taskId);
    return true;
  }

  /**
   * Get task by ID
   */
  getTask(taskId: string): AsyncTask | undefined {
    return this.tasks.get(taskId);
  }

  /**
   * Get task by command ID
   */
  getTaskByCommand(commandId: string): AsyncTask | undefined {
    const taskId = this.commandToTask.get(commandId);
    return taskId ? this.tasks.get(taskId) : undefined;
  }

  /**
   * Get all tasks
   */
  getAllTasks(): AsyncTask[] {
    return Array.from(this.tasks.values());
  }

  /**
   * Get tasks by state
   */
  getTasksByState(state: AsyncTaskState): AsyncTask[] {
    return Array.from(this.tasks.values()).filter((task) => task.state === state);
  }

  /**
   * Check if a task is cancelled
   */
  isCancelled(taskId: string): boolean {
    return this.cancellationTokens.get(taskId) || false;
  }

  /**
   * Create async execution context
   */
  createAsyncContext(taskId: string): AsyncContext {
    if (!this.tasks.has(taskId)) {
      throw new Error(`Task not found: ${taskId}`);
    }

    return {
      updateProgress: (progress, message) => this.updateProgress(taskId, progress, message),
      checkCancellation: () => this.isCancelled(taskId),
      metadata: this.tasks.get(taskId)!.metadata || {},
    };
  }

  /**
   * Wait for task completion
   */
  waitForTask(taskId: string, timeoutMs?: number): Promise<CommandResult> {
    return new Promise((resolve, reject) => {
      const task = this.validateTaskExists(taskId);
      if (!task) {
        reject(new Error(`Task not found: ${taskId}`));
        return;
      }

      const immediateResult = this.checkImmediateTaskResult(task);
      if (immediateResult.shouldReturn) {
        if (immediateResult.isSuccess) {
          resolve(immediateResult.result!);
        } else {
          reject(immediateResult.error!);
        }
        return;
      }

      this.setupTaskWaiting(taskId, timeoutMs, resolve, reject);
    });
  }

  private validateTaskExists(taskId: string): AsyncTask | null {
    return this.tasks.get(taskId) || null;
  }

  private checkImmediateTaskResult(task: AsyncTask): {
    shouldReturn: boolean;
    isSuccess: boolean;
    result?: CommandResult;
    error?: Error;
  } {
    if (task.state === AsyncTaskState.COMPLETED && task.result) {
      return { shouldReturn: true, isSuccess: true, result: task.result };
    }

    if (task.state === AsyncTaskState.FAILED) {
      return {
        shouldReturn: true,
        isSuccess: false,
        error: task.error || new Error('Task failed'),
      };
    }

    if (task.state === AsyncTaskState.CANCELLED) {
      return {
        shouldReturn: true,
        isSuccess: false,
        error: new Error('Task cancelled'),
      };
    }

    return { shouldReturn: false, isSuccess: false };
  }

  private setupTaskWaiting(
    taskId: string,
    timeoutMs: number | undefined,
    resolve: (result: CommandResult) => void,
    reject: (error: Error) => void,
  ): void {
    const cleanup = this.createEventCleanup();
    const timeoutHandle = this.setupTimeout(timeoutMs, cleanup, reject);
    const handlers = this.createEventHandlers(taskId, timeoutHandle, cleanup, resolve, reject);

    this.registerEventHandlers(handlers);
  }

  private createEventCleanup() {
    const handlers: Array<() => void> = [];
    return {
      add: (handler: () => void) => handlers.push(handler),
      cleanup: () => handlers.forEach((h) => h()),
    };
  }

  private setupTimeout(
    timeoutMs: number | undefined,
    cleanup: { cleanup: () => void },
    reject: (error: Error) => void,
  ): NodeJS.Timeout | undefined {
    if (!timeoutMs) return undefined;

    return setTimeout(() => {
      cleanup.cleanup();
      reject(new Error('Task timeout'));
    }, timeoutMs);
  }

  private createEventHandlers(
    taskId: string,
    timeoutHandle: NodeJS.Timeout | undefined,
    cleanup: { cleanup: () => void },
    resolve: (result: CommandResult) => void,
    reject: (error: Error) => void,
  ) {
    const completeHandler = (event: { task: AsyncTask; result: CommandResult }) => {
      if (event.task.id === taskId) {
        if (timeoutHandle) clearTimeout(timeoutHandle);
        cleanup.cleanup();
        resolve(event.result);
      }
    };

    const failHandler = (event: { task: AsyncTask; error: Error }) => {
      if (event.task.id === taskId) {
        if (timeoutHandle) clearTimeout(timeoutHandle);
        cleanup.cleanup();
        reject(event.error);
      }
    };

    const cancelHandler = (event: { task: AsyncTask }) => {
      if (event.task.id === taskId) {
        if (timeoutHandle) clearTimeout(timeoutHandle);
        cleanup.cleanup();
        reject(new Error('Task cancelled'));
      }
    };

    return { completeHandler, failHandler, cancelHandler };
  }

  private registerEventHandlers(handlers: {
    completeHandler: (event: { task: AsyncTask; result: CommandResult }) => void;
    failHandler: (event: { task: AsyncTask; error: Error }) => void;
    cancelHandler: (event: { task: AsyncTask }) => void;
  }): void {
    this.once('task.completed', handlers.completeHandler);
    this.once('task.failed', handlers.failHandler);
    this.once('task.cancelled', handlers.cancelHandler);
  }
  /**
   * Clean up completed/failed/cancelled tasks
   */
  private cleanup(taskId: string): void {
    // Keep task in memory for a while for status queries
    setTimeout(() => {
      const task = this.tasks.get(taskId);
      if (
        task &&
        (task.state === AsyncTaskState.COMPLETED ||
          task.state === AsyncTaskState.FAILED ||
          task.state === AsyncTaskState.CANCELLED)
      ) {
        this.tasks.delete(taskId);
        this.commandToTask.delete(task.commandId);
        this.cancellationTokens.delete(taskId);
      }
    }, 300000); // 5 minutes
  }

  /**
   * Clean up all completed tasks immediately
   */
  cleanupCompleted(): number {
    let cleaned = 0;
    for (const [taskId, task] of this.tasks.entries()) {
      if (
        task.state === AsyncTaskState.COMPLETED ||
        task.state === AsyncTaskState.FAILED ||
        task.state === AsyncTaskState.CANCELLED
      ) {
        this.tasks.delete(taskId);
        this.commandToTask.delete(task.commandId);
        this.cancellationTokens.delete(taskId);
        cleaned++;
      }
    }
    return cleaned;
  }

  /**
   * Get task statistics
   */
  getStatistics(): {
    total: number;
    pending: number;
    running: number;
    completed: number;
    failed: number;
    cancelled: number;
  } {
    const stats = {
      total: this.tasks.size,
      pending: 0,
      running: 0,
      completed: 0,
      failed: 0,
      cancelled: 0,
    };

    for (const task of this.tasks.values()) {
      switch (task.state) {
        case AsyncTaskState.PENDING:
          stats.pending++;
          break;
        case AsyncTaskState.RUNNING:
          stats.running++;
          break;
        case AsyncTaskState.COMPLETED:
          stats.completed++;
          break;
        case AsyncTaskState.FAILED:
          stats.failed++;
          break;
        case AsyncTaskState.CANCELLED:
          stats.cancelled++;
          break;
      }
    }

    return stats;
  }
}
