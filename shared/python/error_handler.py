"""
Error handling utilities and decorators for DGMSTT Python projects
"""

import functools
import logging
import traceback
import time
from typing import (
    Any, Callable, Optional, Type, TypeVar, Union, Tuple, Dict, List,
    Protocol, runtime_checkable
)
from datetime import datetime
import json

T = TypeVar('T')
F = TypeVar('F', bound=Callable[..., Any])

# Set up module logger
logger = logging.getLogger(__name__)


class BaseError(Exception):
    """Base error class with structured data support"""
    
    def __init__(
        self,
        message: str,
        code: Optional[str] = None,
        data: Optional[Dict[str, Any]] = None,
        cause: Optional[Exception] = None
    ):
        super().__init__(message)
        self.message = message
        self.code = code or self.__class__.__name__
        self.data = data or {}
        self.cause = cause
        self.timestamp = datetime.now()
        
    def to_dict(self) -> Dict[str, Any]:
        """Convert error to dictionary representation"""
        result = {
            'type': self.__class__.__name__,
            'message': self.message,
            'code': self.code,
            'timestamp': self.timestamp.isoformat(),
            'data': self.data
        }
        if self.cause:
            result['cause'] = str(self.cause)
        return result
        
    def to_json(self) -> str:
        """Convert error to JSON string"""
        return json.dumps(self.to_dict())


class ValidationError(BaseError):
    """Raised when validation fails"""
    def __init__(self, message: str, field: Optional[str] = None, value: Any = None):
        data = {}
        if field:
            data['field'] = field
        if value is not None:
            data['value'] = str(value)
        super().__init__(message, code='VALIDATION_ERROR', data=data)


class NetworkError(BaseError):
    """Raised when network operations fail"""
    def __init__(
        self,
        message: str,
        url: Optional[str] = None,
        status_code: Optional[int] = None
    ):
        data = {}
        if url:
            data['url'] = url
        if status_code:
            data['status_code'] = status_code
        super().__init__(message, code='NETWORK_ERROR', data=data)


class TimeoutError(BaseError):
    """Raised when operations timeout"""
    def __init__(self, message: str, operation: str, timeout_seconds: float):
        super().__init__(
            message,
            code='TIMEOUT_ERROR',
            data={'operation': operation, 'timeout_seconds': timeout_seconds}
        )


@runtime_checkable
class Retriable(Protocol):
    """Protocol for retriable exceptions"""
    @property
    def retriable(self) -> bool:
        """Whether the error is retriable"""
        ...


def retry(
    max_attempts: int = 3,
    delay: float = 1.0,
    backoff: float = 2.0,
    exceptions: Tuple[Type[Exception], ...] = (Exception,),
    on_retry: Optional[Callable[[Exception, int], None]] = None,
    should_retry: Optional[Callable[[Exception], bool]] = None
) -> Callable[[F], F]:
    """
    Decorator for retrying functions with exponential backoff
    
    Args:
        max_attempts: Maximum number of attempts
        delay: Initial delay between retries in seconds
        backoff: Backoff multiplier
        exceptions: Tuple of exceptions to catch
        on_retry: Callback called on each retry with (exception, attempt)
        should_retry: Function to determine if an exception should trigger retry
        
    Example:
        @retry(max_attempts=3, delay=1.0)
        def fetch_data():
            return requests.get('http://api.example.com/data')
    """
    def decorator(func: F) -> F:
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            last_exception = None
            current_delay = delay
            
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    last_exception = e
                    
                    # Check if we should retry
                    if should_retry and not should_retry(e):
                        raise
                        
                    # Check if exception implements Retriable protocol
                    if isinstance(e, Retriable) and not e.retriable:
                        raise
                        
                    if attempt == max_attempts:
                        raise
                        
                    # Call retry callback
                    if on_retry:
                        on_retry(e, attempt)
                    else:
                        logger.warning(
                            f"Retry {attempt}/{max_attempts} for {func.__name__} "
                            f"after {e.__class__.__name__}: {str(e)}"
                        )
                    
                    # Wait before retry
                    time.sleep(current_delay)
                    current_delay *= backoff
                    
            # This should never be reached, but just in case
            if last_exception:
                raise last_exception
                
        return wrapper
    return decorator


def catch_and_log(
    exceptions: Tuple[Type[Exception], ...] = (Exception,),
    default: Any = None,
    log_level: int = logging.ERROR,
    log_traceback: bool = True,
    reraise: bool = False
) -> Callable[[F], F]:
    """
    Decorator to catch exceptions and log them
    
    Args:
        exceptions: Tuple of exceptions to catch
        default: Default value to return on exception
        log_level: Logging level for errors
        log_traceback: Whether to log the full traceback
        reraise: Whether to re-raise the exception after logging
        
    Example:
        @catch_and_log(exceptions=(ValueError,), default=0)
        def parse_int(value):
            return int(value)
    """
    def decorator(func: F) -> F:
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except exceptions as e:
                message = f"Error in {func.__name__}: {e.__class__.__name__}: {str(e)}"
                
                if log_traceback:
                    message += f"\n{traceback.format_exc()}"
                    
                logger.log(log_level, message)
                
                if reraise:
                    raise
                    
                return default
                
        return wrapper
    return decorator


def with_timeout(timeout_seconds: float) -> Callable[[F], F]:
    """
    Decorator to add timeout to functions (requires signal support)
    
    Note: This only works on Unix-like systems and in the main thread
    
    Args:
        timeout_seconds: Timeout in seconds
        
    Example:
        @with_timeout(5.0)
        def slow_operation():
            time.sleep(10)
    """
    def decorator(func: F) -> F:
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            import signal
            
            def timeout_handler(signum, frame):
                raise TimeoutError(
                    f"Operation timed out after {timeout_seconds} seconds",
                    operation=func.__name__,
                    timeout_seconds=timeout_seconds
                )
            
            # Set up timeout
            old_handler = signal.signal(signal.SIGALRM, timeout_handler)
            signal.alarm(int(timeout_seconds))
            
            try:
                result = func(*args, **kwargs)
            finally:
                # Clean up
                signal.alarm(0)
                signal.signal(signal.SIGALRM, old_handler)
                
            return result
            
        return wrapper
    return decorator


def handle_errors(
    error_map: Dict[Type[Exception], Union[Any, Callable[[Exception], Any]]]
) -> Callable[[F], F]:
    """
    Decorator to handle specific exceptions with custom handlers
    
    Args:
        error_map: Dictionary mapping exception types to handlers or values
        
    Example:
        @handle_errors({
            ValueError: 0,
            KeyError: lambda e: f"Missing key: {e}",
            IOError: lambda e: None
        })
        def process_data(data):
            return data['value']
    """
    def decorator(func: F) -> F:
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                for exc_type, handler in error_map.items():
                    if isinstance(e, exc_type):
                        if callable(handler):
                            return handler(e)
                        else:
                            return handler
                # Re-raise if no handler found
                raise
                
        return wrapper
    return decorator


class ErrorContext:
    """
    Context manager for adding context to errors
    
    Example:
        with ErrorContext("Processing user data", user_id=123):
            process_user(123)
    """
    
    def __init__(self, operation: str, **context):
        self.operation = operation
        self.context = context
        
    def __enter__(self):
        return self
        
    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_val is not None:
            # Add context to the exception
            if isinstance(exc_val, BaseError):
                exc_val.data.update(self.context)
                exc_val.data['operation'] = self.operation
            else:
                # Wrap in BaseError with context
                wrapped = BaseError(
                    f"{self.operation} failed: {str(exc_val)}",
                    code=exc_type.__name__,
                    data=self.context,
                    cause=exc_val
                )
                raise wrapped from exc_val
        return False


def safe_execute(
    func: Callable[..., T],
    *args,
    default: Optional[T] = None,
    exceptions: Tuple[Type[Exception], ...] = (Exception,),
    **kwargs
) -> Tuple[Optional[T], Optional[Exception]]:
    """
    Safely execute a function and return result with error
    
    Args:
        func: Function to execute
        *args: Positional arguments for func
        default: Default value on error
        exceptions: Exceptions to catch
        **kwargs: Keyword arguments for func
        
    Returns:
        Tuple of (result, error)
        
    Example:
        result, error = safe_execute(int, "123")
        if error:
            print(f"Conversion failed: {error}")
    """
    try:
        result = func(*args, **kwargs)
        return result, None
    except exceptions as e:
        return default, e


def create_error_handler(
    default_response: Any = None,
    log_errors: bool = True,
    include_traceback: bool = False
) -> Callable[[Callable], Callable]:
    """
    Create a custom error handler decorator
    
    Args:
        default_response: Default response on error
        log_errors: Whether to log errors
        include_traceback: Whether to include traceback in response
        
    Returns:
        Error handler decorator
    """
    def error_handler(func: Callable) -> Callable:
        @functools.wraps(func)
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                if log_errors:
                    logger.error(
                        f"Error in {func.__name__}: {e}",
                        exc_info=include_traceback
                    )
                    
                if include_traceback:
                    error_info = {
                        'error': str(e),
                        'type': e.__class__.__name__,
                        'traceback': traceback.format_exc()
                    }
                else:
                    error_info = {
                        'error': str(e),
                        'type': e.__class__.__name__
                    }
                    
                if callable(default_response):
                    return default_response(error_info)
                else:
                    return default_response
                    
        return wrapper
    return error_handler


class ErrorCollector:
    """
    Collect multiple errors and handle them together
    
    Example:
        collector = ErrorCollector()
        
        with collector.collect():
            validate_name(data['name'])
            
        with collector.collect():
            validate_email(data['email'])
            
        if collector.has_errors():
            raise ValidationError(collector.format_errors())
    """
    
    def __init__(self):
        self.errors: List[Tuple[str, Exception]] = []
        
    def collect(self, context: str = ""):
        """Context manager to collect errors"""
        return ErrorCollectContext(self, context)
        
    def add_error(self, error: Exception, context: str = ""):
        """Add an error to the collection"""
        self.errors.append((context, error))
        
    def has_errors(self) -> bool:
        """Check if any errors were collected"""
        return len(self.errors) > 0
        
    def format_errors(self) -> str:
        """Format all errors as a string"""
        if not self.errors:
            return ""
            
        lines = ["Multiple errors occurred:"]
        for i, (context, error) in enumerate(self.errors, 1):
            if context:
                lines.append(f"{i}. [{context}] {error}")
            else:
                lines.append(f"{i}. {error}")
                
        return "\n".join(lines)
        
    def get_errors(self) -> List[Tuple[str, Exception]]:
        """Get all collected errors"""
        return self.errors.copy()
        
    def clear(self):
        """Clear all collected errors"""
        self.errors.clear()


class ErrorCollectContext:
    """Context manager for ErrorCollector"""
    
    def __init__(self, collector: ErrorCollector, context: str):
        self.collector = collector
        self.context = context
        
    def __enter__(self):
        return self
        
    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_val is not None:
            self.collector.add_error(exc_val, self.context)
            return True  # Suppress the exception
        return False