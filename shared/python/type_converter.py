"""
Type conversion utilities for DGMSTT Python projects
"""

import json
import ast
from typing import Any, Dict, List, Union, Optional, Type, TypeVar, Callable
from datetime import datetime, date
from decimal import Decimal
from pathlib import Path

T = TypeVar('T')


class ConversionError(Exception):
    """Raised when type conversion fails"""
    pass


def safe_convert(
    value: Any,
    target_type: Type[T],
    default: Optional[T] = None,
    strict: bool = False
) -> Optional[T]:
    """
    Safely convert a value to the target type.
    
    Args:
        value: The value to convert
        target_type: The type to convert to
        default: Default value if conversion fails
        strict: If True, raise exception on failure; if False, return default
        
    Returns:
        The converted value or default
        
    Raises:
        ConversionError: If strict=True and conversion fails
    """
    if value is None:
        return default
        
    if isinstance(value, target_type):
        return value
        
    try:
        # Handle common conversions
        if target_type == bool:
            return _to_bool(value)
        elif target_type == int:
            return int(value)
        elif target_type == float:
            return float(value)
        elif target_type == str:
            return str(value)
        elif target_type == list:
            return _to_list(value)
        elif target_type == dict:
            return _to_dict(value)
        elif target_type == datetime:
            return _to_datetime(value)
        elif target_type == date:
            return _to_date(value)
        elif target_type == Path:
            return Path(value)
        elif target_type == Decimal:
            return Decimal(value)
        else:
            # Try direct conversion
            return target_type(value)
            
    except (ValueError, TypeError, AttributeError) as e:
        if strict:
            raise ConversionError(
                f"Cannot convert {type(value).__name__} '{value}' to {target_type.__name__}: {e}"
            ) from e
        return default


def _to_bool(value: Any) -> bool:
    """Convert various representations to boolean"""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        value_lower = value.lower()
        if value_lower in ('true', 'yes', '1', 'on'):
            return True
        elif value_lower in ('false', 'no', '0', 'off', ''):
            return False
        else:
            raise ValueError(f"Cannot convert '{value}' to bool")
    return bool(value)


def _to_list(value: Any) -> List[Any]:
    """Convert various representations to list"""
    if isinstance(value, list):
        return value
    if isinstance(value, (tuple, set)):
        return list(value)
    if isinstance(value, str):
        # Try to parse as JSON array
        try:
            parsed = json.loads(value)
            if isinstance(parsed, list):
                return parsed
        except json.JSONDecodeError:
            pass
        # Try to parse as Python literal
        try:
            parsed = ast.literal_eval(value)
            if isinstance(parsed, (list, tuple)):
                return list(parsed)
        except (ValueError, SyntaxError):
            pass
        # Split comma-separated values
        if ',' in value:
            return [item.strip() for item in value.split(',')]
        # Single item
        return [value]
    # Try to iterate
    try:
        return list(value)
    except TypeError:
        return [value]


def _to_dict(value: Any) -> Dict[str, Any]:
    """Convert various representations to dict"""
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        # Try to parse as JSON object
        try:
            parsed = json.loads(value)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass
        # Try to parse as Python literal
        try:
            parsed = ast.literal_eval(value)
            if isinstance(parsed, dict):
                return parsed
        except (ValueError, SyntaxError):
            pass
        # Try key=value format
        if '=' in value:
            result = {}
            for pair in value.split(','):
                if '=' in pair:
                    key, val = pair.split('=', 1)
                    result[key.strip()] = val.strip()
            return result
    raise ValueError(f"Cannot convert {type(value).__name__} to dict")


def _to_datetime(value: Any) -> datetime:
    """Convert various representations to datetime"""
    if isinstance(value, datetime):
        return value
    if isinstance(value, date):
        return datetime.combine(value, datetime.min.time())
    if isinstance(value, (int, float)):
        # Assume timestamp
        return datetime.fromtimestamp(value)
    if isinstance(value, str):
        # Try common formats
        formats = [
            '%Y-%m-%d %H:%M:%S',
            '%Y-%m-%dT%H:%M:%S',
            '%Y-%m-%dT%H:%M:%SZ',
            '%Y-%m-%d',
            '%d/%m/%Y',
            '%m/%d/%Y',
        ]
        for fmt in formats:
            try:
                return datetime.strptime(value, fmt)
            except ValueError:
                continue
        # Try ISO format
        try:
            return datetime.fromisoformat(value.replace('Z', '+00:00'))
        except ValueError:
            pass
    raise ValueError(f"Cannot convert {type(value).__name__} to datetime")


def _to_date(value: Any) -> date:
    """Convert various representations to date"""
    if isinstance(value, date):
        return value
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, str):
        # Try converting to datetime first, then extract date
        dt = _to_datetime(value)
        return dt.date()
    raise ValueError(f"Cannot convert {type(value).__name__} to date")


class TypeConverter:
    """
    A configurable type converter with custom conversion rules
    """
    
    def __init__(self):
        self._converters: Dict[Type, Callable[[Any], Any]] = {}
        self._register_default_converters()
        
    def _register_default_converters(self):
        """Register default type converters"""
        self._converters[bool] = _to_bool
        self._converters[list] = _to_list
        self._converters[dict] = _to_dict
        self._converters[datetime] = _to_datetime
        self._converters[date] = _to_date
        
    def register_converter(
        self,
        target_type: Type[T],
        converter: Callable[[Any], T]
    ) -> None:
        """Register a custom converter for a type"""
        self._converters[target_type] = converter
        
    def convert(
        self,
        value: Any,
        target_type: Type[T],
        default: Optional[T] = None,
        strict: bool = False
    ) -> Optional[T]:
        """Convert a value using registered converters"""
        if value is None:
            return default
            
        if isinstance(value, target_type):
            return value
            
        try:
            # Use custom converter if available
            if target_type in self._converters:
                return self._converters[target_type](value)
            # Fall back to safe_convert
            return safe_convert(value, target_type, default, strict)
        except Exception as e:
            if strict:
                raise ConversionError(
                    f"Conversion failed: {e}"
                ) from e
            return default


def coerce_types(
    data: Dict[str, Any],
    schema: Dict[str, Type],
    strict: bool = False
) -> Dict[str, Any]:
    """
    Coerce dictionary values to match a type schema
    
    Args:
        data: Dictionary with values to convert
        schema: Dictionary mapping keys to expected types
        strict: If True, raise exception on failure
        
    Returns:
        Dictionary with converted values
    """
    result = {}
    for key, value in data.items():
        if key in schema:
            target_type = schema[key]
            converted = safe_convert(value, target_type, strict=strict)
            if converted is not None or value is None:
                result[key] = converted
            elif not strict:
                result[key] = value
        else:
            result[key] = value
            
    # Add missing keys with None
    for key in schema:
        if key not in result:
            result[key] = None
            
    return result


def parse_bool(value: Any, default: bool = False) -> bool:
    """Parse a boolean value with default fallback"""
    try:
        return _to_bool(value)
    except (ValueError, TypeError):
        return default


def parse_int(value: Any, default: int = 0) -> int:
    """Parse an integer value with default fallback"""
    return safe_convert(value, int, default=default)


def parse_float(value: Any, default: float = 0.0) -> float:
    """Parse a float value with default fallback"""
    return safe_convert(value, float, default=default)


def parse_list(value: Any, default: Optional[List] = None) -> List[Any]:
    """Parse a list value with default fallback"""
    if default is None:
        default = []
    return safe_convert(value, list, default=default)


def parse_dict(value: Any, default: Optional[Dict] = None) -> Dict[str, Any]:
    """Parse a dict value with default fallback"""
    if default is None:
        default = {}
    return safe_convert(value, dict, default=default)


def to_json_serializable(obj: Any) -> Any:
    """
    Convert an object to a JSON-serializable format
    
    Handles common types that aren't JSON serializable by default
    """
    if isinstance(obj, (str, int, float, bool, type(None))):
        return obj
    elif isinstance(obj, (datetime, date)):
        return obj.isoformat()
    elif isinstance(obj, Decimal):
        return float(obj)
    elif isinstance(obj, Path):
        return str(obj)
    elif isinstance(obj, bytes):
        return obj.decode('utf-8', errors='replace')
    elif isinstance(obj, dict):
        return {k: to_json_serializable(v) for k, v in obj.items()}
    elif isinstance(obj, (list, tuple)):
        return [to_json_serializable(item) for item in obj]
    elif isinstance(obj, set):
        return list(obj)
    elif hasattr(obj, '__dict__'):
        return to_json_serializable(obj.__dict__)
    else:
        return str(obj)


def from_json_string(
    json_str: str,
    default: Any = None,
    strict: bool = False
) -> Any:
    """
    Parse a JSON string with error handling
    
    Args:
        json_str: JSON string to parse
        default: Default value if parsing fails
        strict: If True, raise exception on failure
        
    Returns:
        Parsed value or default
    """
    try:
        return json.loads(json_str)
    except json.JSONDecodeError as e:
        if strict:
            raise ConversionError(f"Invalid JSON: {e}") from e
        return default


def to_json_string(
    obj: Any,
    pretty: bool = False,
    default: Optional[str] = None,
    strict: bool = False
) -> Optional[str]:
    """
    Convert an object to JSON string with error handling
    
    Args:
        obj: Object to serialize
        pretty: If True, format with indentation
        default: Default value if serialization fails
        strict: If True, raise exception on failure
        
    Returns:
        JSON string or default
    """
    try:
        if pretty:
            return json.dumps(obj, default=to_json_serializable, indent=2)
        else:
            return json.dumps(obj, default=to_json_serializable)
    except (TypeError, ValueError) as e:
        if strict:
            raise ConversionError(f"Cannot serialize to JSON: {e}") from e
        return default