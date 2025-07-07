"""
Unified Error Handling System - Python Implementation
Consolidates error handling across TypeScript and Python components
"""

import traceback
from typing import Any, Dict, Optional, List, Union
from datetime import datetime
from abc import ABC, abstractmethod

from ...types.python.tool import (
    ToolError,
    ToolExecutionResult,
    ToolExecutionStatus,
    ToolContext,
    ToolPerformance
)


class ErrorContext:
    """Context information for error handling"""
    
    def __init__(self, tool_id: str, language: str, parameters: Any, 
                 context: ToolContext, start_time: Optional[datetime] = None):
        self.tool_id = tool_id
        self.language = language
        self.parameters = parameters
        self.context = context
        self.start_time = start_time or datetime.now()


class ErrorHandler(ABC):
    """Base error handler interface"""
    
    @property
    @abstractmethod
    def priority(self) -> int:
        """Handler priority (lower number = higher priority)"""
        pass
    
    @abstractmethod
    def can_handle(self, error: Exception) -> bool:
        """Check if this handler can handle the error"""
        pass
    
    @abstractmethod
    def handle(self, error: Exception, context: ErrorContext) -> ToolError:
        """Handle the error and return a ToolError"""
        pass


class BaseErrorHandler(ErrorHandler):
    """Base error handler with common functionality"""
    
    def create_tool_error(self, code: str, message: str, details: Any, 
                         retryable: bool = False) -> ToolError:
        """Create a ToolError instance"""
        return ToolError(
            code=code,
            message=message,
            details=details,
            retryable=retryable,
            cause=str(details.get('original_error', '')) if isinstance(details, dict) else None
        )


class TimeoutErrorHandler(BaseErrorHandler):
    """Handler for timeout errors"""
    
    @property
    def priority(self) -> int:
        return 1
    
    def can_handle(self, error: Exception) -> bool:
        error_str = str(error).lower()
        return (
            'timeout' in error_str or
            isinstance(error, TimeoutError) or
            (hasattr(error, 'code') and error.code == 'ETIMEDOUT') or
            (hasattr(error, 'code') and error.code == 'TIMEOUT_ERROR')
        )
    
    def handle(self, error: Exception, context: ErrorContext) -> ToolError:
        duration = (datetime.now() - context.start_time).total_seconds() * 1000
        return self.create_tool_error(
            'TOOL_TIMEOUT',
            f'Tool execution timed out after {context.context.timeout}ms',
            {
                'tool_id': context.tool_id,
                'timeout': context.context.timeout,
                'duration': duration,
                'language': context.language
            },
            True
        )


class ValidationErrorHandler(BaseErrorHandler):
    """Handler for validation errors"""
    
    @property
    def priority(self) -> int:
        return 2
    
    def can_handle(self, error: Exception) -> bool:
        error_str = str(error).lower()
        return (
            type(error).__name__ == 'ValidationError' or
            'validation' in error_str or
            'invalid parameters' in error_str or
            (hasattr(error, 'code') and error.code == 'VALIDATION_ERROR')
        )
    
    def handle(self, error: Exception, context: ErrorContext) -> ToolError:
        return self.create_tool_error(
            'VALIDATION_ERROR',
            'Parameter validation failed',
            {
                'tool_id': context.tool_id,
                'parameters': context.parameters,
                'validation_errors': str(error),
                'language': context.language
            },
            False
        )


class PermissionErrorHandler(BaseErrorHandler):
    """Handler for permission errors"""
    
    @property
    def priority(self) -> int:
        return 3
    
    def can_handle(self, error: Exception) -> bool:
        error_str = str(error).lower()
        return (
            isinstance(error, PermissionError) or
            'permission denied' in error_str or
            'access denied' in error_str or
            (hasattr(error, 'code') and error.code in ['EACCES', 'EPERM'])
        )
    
    def handle(self, error: Exception, context: ErrorContext) -> ToolError:
        return self.create_tool_error(
            'PERMISSION_DENIED',
            'Permission denied for tool execution',
            {
                'tool_id': context.tool_id,
                'operation': context.parameters,
                'error': str(error),
                'language': context.language
            },
            False
        )


class ResourceErrorHandler(BaseErrorHandler):
    """Handler for resource not found errors"""
    
    @property
    def priority(self) -> int:
        return 4
    
    def can_handle(self, error: Exception) -> bool:
        error_str = str(error).lower()
        return (
            isinstance(error, FileNotFoundError) or
            'not found' in error_str or
            'does not exist' in error_str or
            (hasattr(error, 'code') and error.code in ['ENOENT', 'ENOTFOUND'])
        )
    
    def handle(self, error: Exception, context: ErrorContext) -> ToolError:
        return self.create_tool_error(
            'RESOURCE_NOT_FOUND',
            'Required resource not found',
            {
                'tool_id': context.tool_id,
                'resource': getattr(error, 'filename', getattr(error, 'path', 'unknown')),
                'error': str(error),
                'language': context.language
            },
            False
        )


class ExecutionErrorHandler(BaseErrorHandler):
    """Handler for language-specific execution errors"""
    
    @property
    def priority(self) -> int:
        return 5
    
    def can_handle(self, error: Exception) -> bool:
        return (
            (hasattr(error, 'code') and error.code in ['PYTHON_EXECUTION_ERROR', 'TYPESCRIPT_EXECUTION_ERROR']) or
            (hasattr(error, 'source') and error.source in ['python', 'typescript'])
        )
    
    def handle(self, error: Exception, context: ErrorContext) -> ToolError:
        is_retryable = self._is_retryable(error)
        code = 'PYTHON_EXECUTION_ERROR' if context.language == 'python' else 'TYPESCRIPT_EXECUTION_ERROR'
        
        return self.create_tool_error(
            code,
            str(error) or f'{context.language} tool execution failed',
            {
                'tool_id': context.tool_id,
                'language': context.language,
                'traceback': self._extract_traceback(error),
                'original_error': str(error)
            },
            is_retryable
        )
    
    def _extract_traceback(self, error: Exception) -> List[str]:
        """Extract traceback information"""
        if hasattr(error, 'traceback'):
            tb = error.traceback
            return tb if isinstance(tb, list) else tb.split('\n')
        
        # Generate traceback for Python exceptions
        if hasattr(error, '__traceback__') and error.__traceback__:
            return traceback.format_exception(type(error), error, error.__traceback__)
        
        return []
    
    def _is_retryable(self, error: Exception) -> bool:
        """Determine if error is retryable"""
        error_str = str(error).lower()
        
        # Don't retry syntax or import errors
        if isinstance(error, (SyntaxError, ImportError, ModuleNotFoundError, TypeError, NameError)):
            return False
        
        if any(err in error_str for err in ['syntaxerror', 'importerror', 'modulenotfounderror']):
            return False
        
        # Retry network or temporary errors
        if any(err in error_str for err in ['connection', 'timeout', 'temporary', 'econnrefused', 'etimedout']):
            return True
        
        return False


class DefaultErrorHandler(BaseErrorHandler):
    """Default fallback error handler"""
    
    @property
    def priority(self) -> int:
        return 999  # Lowest priority
    
    def can_handle(self, error: Exception) -> bool:
        return True
    
    def handle(self, error: Exception, context: ErrorContext) -> ToolError:
        tb = []
        if hasattr(error, '__traceback__') and error.__traceback__:
            tb = traceback.format_exception(type(error), error, error.__traceback__)
        
        return self.create_tool_error(
            'UNKNOWN_ERROR',
            str(error) or 'An unknown error occurred',
            {
                'tool_id': context.tool_id,
                'language': context.language,
                'error': str(error),
                'traceback': tb,
                'type': type(error).__name__
            },
            False
        )


class RetryStrategy:
    """Retry strategy for failed operations"""
    
    def __init__(self, max_attempts: int = 3, backoff_multiplier: float = 2,
                 initial_delay: int = 1000, max_delay: int = 30000):
        self.max_attempts = max_attempts
        self.backoff_multiplier = backoff_multiplier
        self.initial_delay = initial_delay
        self.max_delay = max_delay
    
    def should_retry(self, attempt: int, last_error: ToolError) -> bool:
        """Check if we should retry"""
        return attempt < self.max_attempts and last_error.retryable
    
    def get_delay(self, attempt: int) -> int:
        """Get delay before next retry in milliseconds"""
        delay = self.initial_delay * (self.backoff_multiplier ** attempt)
        return min(int(delay), self.max_delay)


class UnifiedErrorHandler:
    """Unified error handling middleware for tool execution"""
    
    def __init__(self):
        self.handlers: List[ErrorHandler] = []
        self._register_default_handlers()
    
    def _register_default_handlers(self) -> None:
        """Register default error handlers"""
        self.add_handler(TimeoutErrorHandler())
        self.add_handler(ValidationErrorHandler())
        self.add_handler(PermissionErrorHandler())
        self.add_handler(ResourceErrorHandler())
        self.add_handler(ExecutionErrorHandler())
        self.add_handler(DefaultErrorHandler())
    
    def add_handler(self, handler: ErrorHandler) -> None:
        """Add a custom error handler"""
        self.handlers.append(handler)
        self.handlers.sort(key=lambda h: h.priority)
    
    def handle_error(self, error: Exception, context: ErrorContext) -> ToolExecutionResult:
        """Handle an error and convert to ToolExecutionResult"""
        handler = next(h for h in self.handlers if h.can_handle(error))
        tool_error = handler.handle(error, context)
        
        self._log_error(tool_error, context)
        
        end_time = datetime.now()
        duration = int((end_time - context.start_time).total_seconds() * 1000)
        
        return ToolExecutionResult(
            tool_id=context.tool_id,
            execution_id=f"error_{int(datetime.now().timestamp())}_{context.tool_id[:9]}",
            status=ToolExecutionStatus.ERROR,
            error=tool_error,
            performance=ToolPerformance(
                start_time=context.start_time.isoformat(),
                end_time=end_time.isoformat(),
                duration=duration
            )
        )
    
    def is_retryable(self, error: ToolError) -> bool:
        """Check if an error is retryable"""
        return error.retryable
    
    def create_retry_strategy(self, error: ToolError) -> Optional[RetryStrategy]:
        """Create a retry strategy for an error"""
        if not self.is_retryable(error):
            return None
        return RetryStrategy()
    
    def _log_error(self, error: ToolError, context: ErrorContext) -> None:
        """Log error for debugging"""
        print(f"[Unified Error Handler] {error.code}: {error.message}")
        print(f"  Tool ID: {context.tool_id}")
        print(f"  Language: {context.language}")
        print(f"  Retryable: {error.retryable}")
        if error.details:
            print(f"  Details: {error.details}")


# Create singleton instance
unified_error_handler = UnifiedErrorHandler()


def create_error_context(tool_id: str, language: str, parameters: Any,
                        context: ToolContext, start_time: Optional[datetime] = None) -> ErrorContext:
    """Factory function for creating error contexts"""
    return ErrorContext(tool_id, language, parameters, context, start_time)