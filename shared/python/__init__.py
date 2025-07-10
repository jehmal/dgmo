"""
DGMSTT Python shared utilities package
"""

from .type_converter import (
    ConversionError,
    safe_convert,
    TypeConverter,
    coerce_types,
    parse_bool,
    parse_int,
    parse_float,
    parse_list,
    parse_dict,
    to_json_serializable,
    from_json_string,
    to_json_string,
)

from .error_handler import (
    BaseError,
    ValidationError,
    NetworkError,
    TimeoutError,
    retry,
    catch_and_log,
    with_timeout,
    handle_errors,
    ErrorContext,
    safe_execute,
    create_error_handler,
    ErrorCollector,
)

from .config_loader import (
    ConfigError,
    ConfigSchema,
    ConfigLoader,
    ConfigManager,
    FileConfigSource,
    EnvironmentConfigSource,
    DictConfigSource,
    merge_configs,
    load_config_file,
    create_config_schema,
    load_from_env,
    load_with_defaults,
)

__all__ = [
    # Type converter
    'ConversionError',
    'safe_convert',
    'TypeConverter',
    'coerce_types',
    'parse_bool',
    'parse_int',
    'parse_float',
    'parse_list',
    'parse_dict',
    'to_json_serializable',
    'from_json_string',
    'to_json_string',
    
    # Error handler
    'BaseError',
    'ValidationError',
    'NetworkError',
    'TimeoutError',
    'retry',
    'catch_and_log',
    'with_timeout',
    'handle_errors',
    'ErrorContext',
    'safe_execute',
    'create_error_handler',
    'ErrorCollector',
    
    # Config loader
    'ConfigError',
    'ConfigSchema',
    'ConfigLoader',
    'ConfigManager',
    'FileConfigSource',
    'EnvironmentConfigSource',
    'DictConfigSource',
    'merge_configs',
    'load_config_file',
    'create_config_schema',
    'load_from_env',
    'load_with_defaults',
]