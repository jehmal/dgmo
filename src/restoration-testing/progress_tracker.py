"""
Progress Tracking System for Backup Restoration Testing

This module provides a comprehensive progress tracking system with support for:
- Multiple progress indicators (percentage, ETA, throughput)
- Real-time updates with configurable intervals
- Thread-safe progress reporting
- Nested progress tracking for complex operations
- Multiple display modes (console, callback, silent)
"""

import threading
import time
from dataclasses import dataclass, field
from typing import Optional, Callable, Dict, Any, List, Union
from enum import Enum
from contextlib import contextmanager
import sys


class ProgressMode(Enum):
    """Progress display modes."""
    CONSOLE = "console"
    CALLBACK = "callback"
    SILENT = "silent"


class ProgressUnit(Enum):
    """Units for progress measurement."""
    ITEMS = "items"
    BYTES = "bytes"
    PERCENT = "percent"


@dataclass
class ProgressReport:
    """Data class for progress status updates."""
    operation_id: str
    current: int
    total: int
    percentage: float
    elapsed_time: float
    eta: Optional[float] = None
    throughput: Optional[float] = None
    throughput_unit: str = "items/sec"
    custom_message: str = ""
    sub_operations: Dict[str, 'ProgressReport'] = field(default_factory=dict)
    
    @property
    def is_complete(self) -> bool:
        """Check if operation is complete."""
        return self.current >= self.total
    
    @property
    def remaining_items(self) -> int:
        """Get remaining items to process."""
        return max(0, self.total - self.current)


class ProgressTracker:
    """
    Thread-safe progress tracker with support for nested operations and multiple display modes.
    
    Features:
    - Real-time progress updates
    - ETA and throughput calculations
    - Nested progress tracking
    - Multiple output formats
    - Thread-safe operations
    """
    
    def __init__(
        self,
        operation_id: str,
        total_items: int,
        mode: ProgressMode = ProgressMode.CONSOLE,
        update_interval: float = 0.1,
        callback: Optional[Callable[[ProgressReport], None]] = None,
        unit: ProgressUnit = ProgressUnit.ITEMS,
        custom_format: Optional[str] = None
    ):
        """
        Initialize progress tracker.
        
        Args:
            operation_id: Unique identifier for this operation
            total_items: Total number of items to process
            mode: Display mode (console, callback, silent)
            update_interval: Minimum time between updates (seconds)
            callback: Optional callback function for progress updates
            unit: Unit of measurement for progress
            custom_format: Custom format string for console output
        """
        self.operation_id = operation_id
        self.total_items = total_items
        self.mode = mode
        self.update_interval = update_interval
        self.callback = callback
        self.unit = unit
        self.custom_format = custom_format
        
        # Thread safety
        self._lock = threading.RLock()
        
        # Progress state
        self._current_item = 0
        self._start_time: Optional[float] = None
        self._last_update_time = 0.0
        self._custom_message = ""
        self._is_finished = False
        
        # Nested operations
        self._sub_trackers: Dict[str, 'ProgressTracker'] = {}
        self._parent_tracker: Optional['ProgressTracker'] = None
        
        # Performance metrics
        self._throughput_samples: List[tuple] = []  # (timestamp, items_processed)
        self._max_samples = 10
        
        # Console state
        self._last_console_length = 0
        
    def start(self) -> None:
        """Start progress tracking."""
        with self._lock:
            if self._start_time is not None:
                return  # Already started
                
            self._start_time = time.time()
            self._last_update_time = self._start_time
            self._throughput_samples = [(self._start_time, 0)]
            
            if self.mode == ProgressMode.CONSOLE:
                self._print_initial_message()
            
            self._notify_update()
    
    def update(self, items_processed: int = 1, custom_message: str = "") -> None:
        """
        Update progress.
        
        Args:
            items_processed: Number of items processed since last update
            custom_message: Custom message to display
        """
        with self._lock:
            if self._start_time is None:
                self.start()
            
            self._current_item = min(self._current_item + items_processed, self.total_items)
            if custom_message:
                self._custom_message = custom_message
            
            current_time = time.time()
            
            # Update throughput samples
            self._throughput_samples.append((current_time, self._current_item))
            if len(self._throughput_samples) > self._max_samples:
                self._throughput_samples.pop(0)
            
            # Check if enough time has passed for update
            if current_time - self._last_update_time >= self.update_interval:
                self._last_update_time = current_time
                self._notify_update()
    
    def set_current(self, current_item: int, custom_message: str = "") -> None:
        """
        Set absolute current progress.
        
        Args:
            current_item: Current item number (absolute position)
            custom_message: Custom message to display
        """
        with self._lock:
            if self._start_time is None:
                self.start()
            
            self._current_item = min(max(0, current_item), self.total_items)
            if custom_message:
                self._custom_message = custom_message
            
            current_time = time.time()
            
            # Update throughput samples
            self._throughput_samples.append((current_time, self._current_item))
            if len(self._throughput_samples) > self._max_samples:
                self._throughput_samples.pop(0)
            
            # Check if enough time has passed for update
            if current_time - self._last_update_time >= self.update_interval:
                self._last_update_time = current_time
                self._notify_update()
    
    def finish(self, custom_message: str = "Complete") -> None:
        """
        Mark operation as finished.
        
        Args:
            custom_message: Final message to display
        """
        with self._lock:
            if self._is_finished:
                return
            
            self._current_item = self.total_items
            self._custom_message = custom_message
            self._is_finished = True
            
            if self.mode == ProgressMode.CONSOLE:
                self._print_final_message()
            
            self._notify_update()
    
    def add_sub_operation(
        self,
        sub_id: str,
        total_items: int,
        **kwargs
    ) -> 'ProgressTracker':
        """
        Add a nested sub-operation.
        
        Args:
            sub_id: Unique identifier for sub-operation
            total_items: Total items for sub-operation
            **kwargs: Additional arguments for ProgressTracker
        
        Returns:
            ProgressTracker instance for sub-operation
        """
        with self._lock:
            # Default to silent mode for sub-operations unless specified
            if 'mode' not in kwargs:
                kwargs['mode'] = ProgressMode.SILENT
            
            sub_tracker = ProgressTracker(
                operation_id=f"{self.operation_id}.{sub_id}",
                total_items=total_items,
                **kwargs
            )
            sub_tracker._parent_tracker = self
            self._sub_trackers[sub_id] = sub_tracker
            
            return sub_tracker
    
    def get_report(self) -> ProgressReport:
        """
        Get current progress report.
        
        Returns:
            ProgressReport with current status
        """
        with self._lock:
            elapsed_time = 0.0
            if self._start_time is not None:
                elapsed_time = time.time() - self._start_time
            
            percentage = (self._current_item / self.total_items * 100) if self.total_items > 0 else 0.0
            
            # Calculate ETA
            eta = self._calculate_eta()
            
            # Calculate throughput
            throughput, throughput_unit = self._calculate_throughput()
            
            # Get sub-operation reports
            sub_reports = {}
            for sub_id, sub_tracker in self._sub_trackers.items():
                sub_reports[sub_id] = sub_tracker.get_report()
            
            return ProgressReport(
                operation_id=self.operation_id,
                current=self._current_item,
                total=self.total_items,
                percentage=percentage,
                elapsed_time=elapsed_time,
                eta=eta,
                throughput=throughput,
                throughput_unit=throughput_unit,
                custom_message=self._custom_message,
                sub_operations=sub_reports
            )
    
    @contextmanager
    def operation_context(self):
        """Context manager for automatic start/finish."""
        try:
            self.start()
            yield self
        finally:
            if not self._is_finished:
                self.finish()
    
    def _calculate_eta(self) -> Optional[float]:
        """Calculate estimated time to completion."""
        if len(self._throughput_samples) < 2 or self._current_item == 0:
            return None
        
        # Use recent samples for ETA calculation
        recent_samples = self._throughput_samples[-3:]
        if len(recent_samples) < 2:
            return None
        
        time_diff = recent_samples[-1][0] - recent_samples[0][0]
        items_diff = recent_samples[-1][1] - recent_samples[0][1]
        
        if time_diff <= 0 or items_diff <= 0:
            return None
        
        items_per_second = items_diff / time_diff
        remaining_items = self.total_items - self._current_item
        
        return remaining_items / items_per_second if items_per_second > 0 else None
    
    def _calculate_throughput(self) -> tuple[Optional[float], str]:
        """Calculate current throughput."""
        if len(self._throughput_samples) < 2:
            return None, self._get_throughput_unit()
        
        # Use recent samples for throughput calculation
        recent_samples = self._throughput_samples[-3:]
        if len(recent_samples) < 2:
            return None, self._get_throughput_unit()
        
        time_diff = recent_samples[-1][0] - recent_samples[0][0]
        items_diff = recent_samples[-1][1] - recent_samples[0][1]
        
        if time_diff <= 0:
            return None, self._get_throughput_unit()
        
        throughput = items_diff / time_diff
        return throughput, self._get_throughput_unit()
    
    def _get_throughput_unit(self) -> str:
        """Get appropriate throughput unit string."""
        if self.unit == ProgressUnit.BYTES:
            return "bytes/sec"
        elif self.unit == ProgressUnit.ITEMS:
            return "items/sec"
        else:
            return "units/sec"
    
    def _notify_update(self) -> None:
        """Notify about progress update."""
        report = self.get_report()
        
        # Notify parent if this is a sub-operation
        if self._parent_tracker:
            self._parent_tracker._notify_update()
        
        # Handle different modes
        if self.mode == ProgressMode.CONSOLE:
            self._print_progress(report)
        elif self.mode == ProgressMode.CALLBACK and self.callback:
            self.callback(report)
    
    def _print_initial_message(self) -> None:
        """Print initial progress message."""
        print(f"\nStarting: {self.operation_id}")
        print(f"Total items: {self.total_items:,}")
    
    def _print_progress(self, report: ProgressReport) -> None:
        """Print progress to console."""
        if self.custom_format:
            message = self.custom_format.format(report=report)
        else:
            # Default format
            bar_length = 40
            filled_length = int(bar_length * report.percentage / 100)
            bar = '█' * filled_length + '░' * (bar_length - filled_length)
            
            # Format throughput
            throughput_str = ""
            if report.throughput is not None:
                if self.unit == ProgressUnit.BYTES:
                    throughput_str = f" | {self._format_bytes(report.throughput)}/s"
                else:
                    throughput_str = f" | {report.throughput:.1f} {report.throughput_unit}"
            
            # Format ETA
            eta_str = ""
            if report.eta is not None:
                eta_str = f" | ETA: {self._format_time(report.eta)}"
            
            # Format custom message
            custom_str = f" | {report.custom_message}" if report.custom_message else ""
            
            message = (
                f"\r{self.operation_id}: [{bar}] "
                f"{report.percentage:5.1f}% "
                f"({report.current:,}/{report.total:,})"
                f"{throughput_str}{eta_str}{custom_str}"
            )
        
        # Clear previous line if needed
        if len(message) < self._last_console_length:
            message += " " * (self._last_console_length - len(message))
        
        self._last_console_length = len(message)
        print(message, end='', flush=True)
    
    def _print_final_message(self) -> None:
        """Print final completion message."""
        report = self.get_report()
        print()  # New line after progress bar
        print(f"✓ {self.operation_id} completed in {self._format_time(report.elapsed_time)}")
        
        if report.throughput is not None:
            if self.unit == ProgressUnit.BYTES:
                print(f"  Average throughput: {self._format_bytes(report.throughput)}/s")
            else:
                print(f"  Average throughput: {report.throughput:.1f} {report.throughput_unit}")
    
    @staticmethod
    def _format_time(seconds: float) -> str:
        """Format time duration."""
        if seconds < 60:
            return f"{seconds:.1f}s"
        elif seconds < 3600:
            minutes = int(seconds // 60)
            secs = seconds % 60
            return f"{minutes}m {secs:.0f}s"
        else:
            hours = int(seconds // 3600)
            minutes = int((seconds % 3600) // 60)
            return f"{hours}h {minutes}m"
    
    @staticmethod
    def _format_bytes(bytes_count: float) -> str:
        """Format byte count with appropriate units."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if bytes_count < 1024.0:
                return f"{bytes_count:.1f}{unit}"
            bytes_count /= 1024.0
        return f"{bytes_count:.1f}PB"


class MultiProgressTracker:
    """
    Manager for multiple concurrent progress trackers.
    
    Useful for tracking multiple parallel operations with consolidated reporting.
    """
    
    def __init__(self, update_interval: float = 0.5):
        """
        Initialize multi-progress tracker.
        
        Args:
            update_interval: Update interval for consolidated reports
        """
        self.update_interval = update_interval
        self._trackers: Dict[str, ProgressTracker] = {}
        self._lock = threading.RLock()
        self._callbacks: List[Callable[[Dict[str, ProgressReport]], None]] = []
        
        # Background update thread
        self._update_thread: Optional[threading.Thread] = None
        self._stop_event = threading.Event()
    
    def add_tracker(self, tracker: ProgressTracker) -> None:
        """Add a progress tracker to monitor."""
        with self._lock:
            self._trackers[tracker.operation_id] = tracker
    
    def remove_tracker(self, operation_id: str) -> None:
        """Remove a progress tracker."""
        with self._lock:
            self._trackers.pop(operation_id, None)
    
    def add_callback(self, callback: Callable[[Dict[str, ProgressReport]], None]) -> None:
        """Add callback for consolidated progress updates."""
        with self._lock:
            self._callbacks.append(callback)
    
    def start_monitoring(self) -> None:
        """Start background monitoring thread."""
        if self._update_thread and self._update_thread.is_alive():
            return
        
        self._stop_event.clear()
        self._update_thread = threading.Thread(target=self._monitor_loop, daemon=True)
        self._update_thread.start()
    
    def stop_monitoring(self) -> None:
        """Stop background monitoring."""
        self._stop_event.set()
        if self._update_thread:
            self._update_thread.join(timeout=1.0)
    
    def get_consolidated_report(self) -> Dict[str, ProgressReport]:
        """Get reports from all tracked operations."""
        with self._lock:
            return {
                op_id: tracker.get_report()
                for op_id, tracker in self._trackers.items()
            }
    
    def _monitor_loop(self) -> None:
        """Background monitoring loop."""
        while not self._stop_event.wait(self.update_interval):
            try:
                reports = self.get_consolidated_report()
                
                # Notify all callbacks
                with self._lock:
                    for callback in self._callbacks:
                        try:
                            callback(reports)
                        except Exception as e:
                            print(f"Error in progress callback: {e}", file=sys.stderr)
                            
            except Exception as e:
                print(f"Error in progress monitoring: {e}", file=sys.stderr)


# Convenience functions for common use cases

def track_operation(
    operation_id: str,
    total_items: int,
    mode: ProgressMode = ProgressMode.CONSOLE,
    **kwargs
) -> ProgressTracker:
    """
    Create and start a progress tracker.
    
    Args:
        operation_id: Operation identifier
        total_items: Total items to process
        mode: Display mode
        **kwargs: Additional ProgressTracker arguments
    
    Returns:
        Started ProgressTracker instance
    """
    tracker = ProgressTracker(operation_id, total_items, mode, **kwargs)
    tracker.start()
    return tracker


@contextmanager
def progress_context(
    operation_id: str,
    total_items: int,
    mode: ProgressMode = ProgressMode.CONSOLE,
    **kwargs
):
    """
    Context manager for automatic progress tracking.
    
    Args:
        operation_id: Operation identifier
        total_items: Total items to process
        mode: Display mode
        **kwargs: Additional ProgressTracker arguments
    
    Yields:
        ProgressTracker instance
    """
    tracker = ProgressTracker(operation_id, total_items, mode, **kwargs)
    with tracker.operation_context():
        yield tracker


# Example usage and testing
if __name__ == "__main__":
    import random
    
    def demo_basic_progress():
        """Demonstrate basic progress tracking."""
        print("=== Basic Progress Demo ===")
        
        with progress_context("File Processing", 100) as tracker:
            for i in range(100):
                time.sleep(0.02)  # Simulate work
                tracker.update(1, f"Processing file {i+1}")
        
        print("\n")
    
    def demo_nested_progress():
        """Demonstrate nested progress tracking."""
        print("=== Nested Progress Demo ===")
        
        with progress_context("Backup Restoration", 3, ProgressMode.CONSOLE) as main_tracker:
            # Sub-operation 1
            sub1 = main_tracker.add_sub_operation("Database Restore", 50, mode=ProgressMode.SILENT)
            sub1.start()
            for i in range(50):
                time.sleep(0.01)
                sub1.update(1, f"Restoring table {i+1}")
            sub1.finish()
            main_tracker.update(1, "Database restoration complete")
            
            # Sub-operation 2
            sub2 = main_tracker.add_sub_operation("File Restore", 30, mode=ProgressMode.SILENT)
            sub2.start()
            for i in range(30):
                time.sleep(0.015)
                sub2.update(1, f"Restoring file {i+1}")
            sub2.finish()
            main_tracker.update(1, "File restoration complete")
            
            # Sub-operation 3
            sub3 = main_tracker.add_sub_operation("Verification", 20, mode=ProgressMode.SILENT)
            sub3.start()
            for i in range(20):
                time.sleep(0.02)
                sub3.update(1, f"Verifying item {i+1}")
            sub3.finish()
            main_tracker.update(1, "Verification complete")
        
        print("\n")
    
    def demo_callback_mode():
        """Demonstrate callback-based progress tracking."""
        print("=== Callback Mode Demo ===")
        
        def progress_callback(report: ProgressReport):
            print(f"Callback: {report.operation_id} - {report.percentage:.1f}% complete")
        
        tracker = ProgressTracker(
            "Callback Operation",
            50,
            mode=ProgressMode.CALLBACK,
            callback=progress_callback,
            update_interval=0.1
        )
        
        tracker.start()
        for i in range(50):
            time.sleep(0.05)
            tracker.update(1)
        tracker.finish()
        
        print("\n")
    
    # Run demos
    demo_basic_progress()
    demo_nested_progress()
    demo_callback_mode()