"""
Configuration loading utilities for DGMSTT Python projects
"""

import os
import json
import yaml
import configparser
from pathlib import Path
from typing import (
    Any, Dict, List, Optional, Union, Type, TypeVar, Callable,
    Protocol, runtime_checkable
)
from dataclasses import dataclass, field
from datetime import datetime
import logging
from dotenv import load_dotenv

from .type_converter import safe_convert, coerce_types
from .error_handler import BaseError

T = TypeVar('T')

logger = logging.getLogger(__name__)


class ConfigError(BaseError):
    """Raised when configuration loading fails"""
    pass


@runtime_checkable
class ConfigSource(Protocol):
    """Protocol for configuration sources"""
    
    def load(self) -> Dict[str, Any]:
        """Load configuration from source"""
        ...
        
    def exists(self) -> bool:
        """Check if configuration source exists"""
        ...


@dataclass
class ConfigSchema:
    """Schema definition for configuration validation"""
    
    fields: Dict[str, Type] = field(default_factory=dict)
    required: List[str] = field(default_factory=list)
    defaults: Dict[str, Any] = field(default_factory=dict)
    validators: Dict[str, Callable[[Any], bool]] = field(default_factory=dict)
    
    def validate(self, config: Dict[str, Any]) -> Dict[str, Any]:
        """Validate and coerce configuration"""
        # Check required fields
        missing = [f for f in self.required if f not in config]
        if missing:
            raise ConfigError(
                f"Missing required configuration fields: {', '.join(missing)}",
                data={'missing_fields': missing}
            )
        
        # Apply defaults
        result = self.defaults.copy()
        result.update(config)
        
        # Coerce types
        if self.fields:
            result = coerce_types(result, self.fields)
        
        # Run validators
        for field, validator in self.validators.items():
            if field in result:
                value = result[field]
                if not validator(value):
                    raise ConfigError(
                        f"Validation failed for field '{field}'",
                        data={'field': field, 'value': value}
                    )
        
        return result


class FileConfigSource:
    """Configuration source from file"""
    
    def __init__(self, path: Union[str, Path]):
        self.path = Path(path)
        
    def exists(self) -> bool:
        return self.path.exists()
        
    def load(self) -> Dict[str, Any]:
        if not self.exists():
            raise ConfigError(f"Configuration file not found: {self.path}")
            
        try:
            if self.path.suffix == '.json':
                return self._load_json()
            elif self.path.suffix in ('.yml', '.yaml'):
                return self._load_yaml()
            elif self.path.suffix in ('.ini', '.cfg'):
                return self._load_ini()
            elif self.path.suffix == '.env':
                return self._load_env()
            else:
                # Try to detect format
                return self._load_auto()
        except Exception as e:
            raise ConfigError(
                f"Failed to load configuration from {self.path}: {e}",
                cause=e
            )
    
    def _load_json(self) -> Dict[str, Any]:
        with open(self.path, 'r') as f:
            return json.load(f)
    
    def _load_yaml(self) -> Dict[str, Any]:
        with open(self.path, 'r') as f:
            return yaml.safe_load(f) or {}
    
    def _load_ini(self) -> Dict[str, Any]:
        parser = configparser.ConfigParser()
        parser.read(self.path)
        
        # Convert to nested dict
        result = {}
        for section in parser.sections():
            result[section] = dict(parser.items(section))
        
        # Include DEFAULT section if present
        if parser.defaults():
            result['DEFAULT'] = dict(parser.defaults())
            
        return result
    
    def _load_env(self) -> Dict[str, Any]:
        # Load .env file into environment
        load_dotenv(self.path)
        # Return all environment variables
        return dict(os.environ)
    
    def _load_auto(self) -> Dict[str, Any]:
        """Try to auto-detect format"""
        content = self.path.read_text()
        
        # Try JSON first
        try:
            return json.loads(content)
        except json.JSONDecodeError:
            pass
        
        # Try YAML
        try:
            return yaml.safe_load(content) or {}
        except yaml.YAMLError:
            pass
        
        # Try INI
        try:
            parser = configparser.ConfigParser()
            parser.read_string(content)
            if parser.sections():
                result = {}
                for section in parser.sections():
                    result[section] = dict(parser.items(section))
                return result
        except configparser.Error:
            pass
        
        raise ConfigError("Unable to detect configuration format")


class EnvironmentConfigSource:
    """Configuration source from environment variables"""
    
    def __init__(self, prefix: str = "", delimiter: str = "_"):
        self.prefix = prefix
        self.delimiter = delimiter
        
    def exists(self) -> bool:
        return True  # Environment always exists
        
    def load(self) -> Dict[str, Any]:
        result = {}
        
        for key, value in os.environ.items():
            if self.prefix and not key.startswith(self.prefix):
                continue
                
            # Remove prefix
            if self.prefix:
                key = key[len(self.prefix):]
                
            # Convert to nested structure
            parts = key.lower().split(self.delimiter)
            current = result
            
            for part in parts[:-1]:
                if part not in current:
                    current[part] = {}
                current = current[part]
                
            # Set the value
            current[parts[-1]] = value
            
        return result


class DictConfigSource:
    """Configuration source from dictionary"""
    
    def __init__(self, data: Dict[str, Any]):
        self.data = data
        
    def exists(self) -> bool:
        return True
        
    def load(self) -> Dict[str, Any]:
        return self.data.copy()


class ConfigLoader:
    """
    Main configuration loader with support for multiple sources
    
    Example:
        loader = ConfigLoader()
        loader.add_source(FileConfigSource('config.json'))
        loader.add_source(EnvironmentConfigSource('APP_'))
        
        schema = ConfigSchema(
            fields={'port': int, 'debug': bool},
            required=['port'],
            defaults={'debug': False}
        )
        
        config = loader.load(schema)
    """
    
    def __init__(self):
        self.sources: List[ConfigSource] = []
        self._cache: Optional[Dict[str, Any]] = None
        
    def add_source(self, source: ConfigSource, required: bool = False) -> 'ConfigLoader':
        """Add a configuration source"""
        if required and not source.exists():
            raise ConfigError(f"Required configuration source does not exist")
        self.sources.append(source)
        return self
        
    def add_file(self, path: Union[str, Path], required: bool = False) -> 'ConfigLoader':
        """Add a file configuration source"""
        return self.add_source(FileConfigSource(path), required)
        
    def add_env(self, prefix: str = "", delimiter: str = "_") -> 'ConfigLoader':
        """Add environment variables as configuration source"""
        return self.add_source(EnvironmentConfigSource(prefix, delimiter))
        
    def add_dict(self, data: Dict[str, Any]) -> 'ConfigLoader':
        """Add a dictionary as configuration source"""
        return self.add_source(DictConfigSource(data))
        
    def clear_cache(self):
        """Clear the configuration cache"""
        self._cache = None
        
    def load(
        self,
        schema: Optional[ConfigSchema] = None,
        use_cache: bool = True
    ) -> Dict[str, Any]:
        """Load configuration from all sources"""
        if use_cache and self._cache is not None:
            result = self._cache.copy()
        else:
            result = {}
            
            # Load from each source in order
            for source in self.sources:
                if source.exists():
                    try:
                        data = source.load()
                        result = merge_configs(result, data)
                    except Exception as e:
                        logger.warning(f"Failed to load from source: {e}")
                        
            # Cache the result
            if use_cache:
                self._cache = result.copy()
        
        # Apply schema if provided
        if schema:
            result = schema.validate(result)
            
        return result
    
    def get(
        self,
        key: str,
        default: Any = None,
        cast: Optional[Type[T]] = None
    ) -> Union[Any, T]:
        """Get a configuration value by key (dot notation supported)"""
        config = self.load()
        
        # Navigate nested structure
        parts = key.split('.')
        current = config
        
        for part in parts:
            if isinstance(current, dict) and part in current:
                current = current[part]
            else:
                return default
                
        # Cast if requested
        if cast:
            return safe_convert(current, cast, default=default)
            
        return current


def merge_configs(
    base: Dict[str, Any],
    override: Dict[str, Any]
) -> Dict[str, Any]:
    """
    Deep merge two configuration dictionaries
    
    Args:
        base: Base configuration
        override: Configuration to merge on top
        
    Returns:
        Merged configuration
    """
    result = base.copy()
    
    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            # Recursively merge nested dicts
            result[key] = merge_configs(result[key], value)
        else:
            # Override the value
            result[key] = value
            
    return result


def load_config_file(
    path: Union[str, Path],
    schema: Optional[ConfigSchema] = None
) -> Dict[str, Any]:
    """
    Convenience function to load a single configuration file
    
    Args:
        path: Path to configuration file
        schema: Optional schema for validation
        
    Returns:
        Loaded configuration
    """
    loader = ConfigLoader()
    loader.add_file(path, required=True)
    return loader.load(schema)


def create_config_schema(**kwargs) -> ConfigSchema:
    """
    Convenience function to create a ConfigSchema
    
    Example:
        schema = create_config_schema(
            fields={'port': int, 'host': str},
            required=['port'],
            defaults={'host': 'localhost'}
        )
    """
    return ConfigSchema(**kwargs)


class ConfigManager:
    """
    Advanced configuration manager with reload support
    """
    
    def __init__(self, loader: ConfigLoader, schema: Optional[ConfigSchema] = None):
        self.loader = loader
        self.schema = schema
        self._config: Optional[Dict[str, Any]] = None
        self._last_reload: Optional[datetime] = None
        self._callbacks: List[Callable[[Dict[str, Any]], None]] = []
        
    def load(self) -> Dict[str, Any]:
        """Load configuration"""
        self._config = self.loader.load(self.schema)
        self._last_reload = datetime.now()
        return self._config
        
    def reload(self) -> Dict[str, Any]:
        """Reload configuration"""
        self.loader.clear_cache()
        old_config = self._config
        new_config = self.load()
        
        # Call callbacks if config changed
        if old_config != new_config:
            for callback in self._callbacks:
                try:
                    callback(new_config)
                except Exception as e:
                    logger.error(f"Error in config reload callback: {e}")
                    
        return new_config
        
    def get(self, key: str, default: Any = None) -> Any:
        """Get configuration value"""
        if self._config is None:
            self.load()
        return self.loader.get(key, default)
        
    def on_reload(self, callback: Callable[[Dict[str, Any]], None]):
        """Register a callback for configuration reloads"""
        self._callbacks.append(callback)
        
    @property
    def config(self) -> Dict[str, Any]:
        """Get current configuration"""
        if self._config is None:
            self.load()
        return self._config
        
    @property
    def last_reload(self) -> Optional[datetime]:
        """Get last reload timestamp"""
        return self._last_reload


# Convenience functions for common patterns

def load_from_env(prefix: str = "", schema: Optional[ConfigSchema] = None) -> Dict[str, Any]:
    """Load configuration from environment variables"""
    loader = ConfigLoader()
    loader.add_env(prefix)
    return loader.load(schema)


def load_with_defaults(
    config_paths: List[Union[str, Path]],
    env_prefix: str = "",
    schema: Optional[ConfigSchema] = None
) -> Dict[str, Any]:
    """
    Load configuration with common defaults pattern:
    1. Default config file
    2. Environment-specific config file
    3. Environment variables
    """
    loader = ConfigLoader()
    
    for path in config_paths:
        loader.add_file(path, required=False)
        
    if env_prefix:
        loader.add_env(env_prefix)
        
    return loader.load(schema)