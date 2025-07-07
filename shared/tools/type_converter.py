"""
Type conversion utilities for cross-language tool integration
"""

import json
from typing import Any, Dict, List, Union, Optional
from datetime import datetime
from decimal import Decimal
import base64


class TypeConverter:
    """Type conversion utilities"""
    
    @staticmethod
    def typescript_to_python(value: Any) -> Any:
        """Convert TypeScript types to Python types"""
        if value is None:
            return None
        
        # Handle special type indicators
        if isinstance(value, dict) and '__type__' in value:
            type_name = value['__type__']
            
            if type_name == 'datetime':
                return datetime.fromisoformat(value.get('isoformat', ''))
            
            elif type_name == 'set':
                return set(value.get('items', []))
            
            elif type_name == 'bytes':
                data = value.get('data', [])
                if isinstance(data, list):
                    return bytes(data)
                elif isinstance(data, str):
                    return base64.b64decode(data)
                return bytes()
            
            elif type_name == 'Decimal':
                return Decimal(value.get('value', '0'))
        
        # Recursively handle dicts
        if isinstance(value, dict):
            return {
                key: TypeConverter.typescript_to_python(val)
                for key, val in value.items()
            }
        
        # Recursively handle lists
        if isinstance(value, list):
            return [TypeConverter.typescript_to_python(item) for item in value]
        
        return value
    
    @staticmethod
    def python_to_typescript(value: Any) -> Any:
        """Convert Python types to TypeScript types"""
        if value is None:
            return None
        
        # Handle datetime
        if isinstance(value, datetime):
            return {
                '__type__': 'datetime',
                'isoformat': value.isoformat()
            }
        
        # Handle set
        if isinstance(value, set):
            return {
                '__type__': 'set',
                'items': list(value)
            }
        
        # Handle bytes
        if isinstance(value, bytes):
            return {
                '__type__': 'bytes',
                'data': base64.b64encode(value).decode('utf-8')
            }
        
        # Handle Decimal
        if isinstance(value, Decimal):
            return {
                '__type__': 'Decimal',
                'value': str(value)
            }
        
        # Handle tuple (mark it so TS knows it was a tuple)
        if isinstance(value, tuple):
            result = list(value)
            if isinstance(result, list):
                # Add marker that this was a tuple
                setattr(result, '__type__', 'tuple')
            return result
        
        # Recursively handle dicts
        if isinstance(value, dict):
            return {
                key: TypeConverter.python_to_typescript(val)
                for key, val in value.items()
            }
        
        # Recursively handle lists
        if isinstance(value, list):
            return [TypeConverter.python_to_typescript(item) for item in value]
        
        # Handle other types that JSON can't serialize
        try:
            json.dumps(value)
            return value
        except TypeError:
            return str(value)
    
    @staticmethod
    def json_schema_to_python_type(schema: Dict[str, Any]) -> type:
        """Convert JSON Schema to Python type hint"""
        if not schema or not isinstance(schema, dict):
            return Any
        
        schema_type = schema.get('type')
        
        if schema_type == 'string':
            return str
        elif schema_type == 'number':
            return float
        elif schema_type == 'integer':
            return int
        elif schema_type == 'boolean':
            return bool
        elif schema_type == 'array':
            item_type = TypeConverter.json_schema_to_python_type(schema.get('items', {}))
            return List[item_type]
        elif schema_type == 'object':
            return Dict[str, Any]
        elif schema_type == 'null':
            return type(None)
        else:
            return Any
    
    @staticmethod
    def validate_against_schema(value: Any, schema: Dict[str, Any]) -> tuple[bool, Optional[str]]:
        """Validate a value against a JSON schema"""
        schema_type = schema.get('type')
        
        if schema_type == 'string':
            if not isinstance(value, str):
                return False, f"Expected string, got {type(value).__name__}"
            
            if 'minLength' in schema and len(value) < schema['minLength']:
                return False, f"String length {len(value)} is less than minimum {schema['minLength']}"
            
            if 'maxLength' in schema and len(value) > schema['maxLength']:
                return False, f"String length {len(value)} is greater than maximum {schema['maxLength']}"
            
            if 'pattern' in schema:
                import re
                if not re.match(schema['pattern'], value):
                    return False, f"String does not match pattern {schema['pattern']}"
            
            if 'enum' in schema and value not in schema['enum']:
                return False, f"Value {value} is not in enum {schema['enum']}"
            
            return True, None
        
        elif schema_type == 'number' or schema_type == 'integer':
            if not isinstance(value, (int, float)):
                return False, f"Expected number, got {type(value).__name__}"
            
            if schema_type == 'integer' and not isinstance(value, int):
                return False, f"Expected integer, got float"
            
            if 'minimum' in schema and value < schema['minimum']:
                return False, f"Value {value} is less than minimum {schema['minimum']}"
            
            if 'maximum' in schema and value > schema['maximum']:
                return False, f"Value {value} is greater than maximum {schema['maximum']}"
            
            return True, None
        
        elif schema_type == 'boolean':
            if not isinstance(value, bool):
                return False, f"Expected boolean, got {type(value).__name__}"
            return True, None
        
        elif schema_type == 'array':
            if not isinstance(value, list):
                return False, f"Expected array, got {type(value).__name__}"
            
            if 'minItems' in schema and len(value) < schema['minItems']:
                return False, f"Array length {len(value)} is less than minimum {schema['minItems']}"
            
            if 'maxItems' in schema and len(value) > schema['maxItems']:
                return False, f"Array length {len(value)} is greater than maximum {schema['maxItems']}"
            
            if 'items' in schema:
                for i, item in enumerate(value):
                    valid, error = TypeConverter.validate_against_schema(item, schema['items'])
                    if not valid:
                        return False, f"Array item {i}: {error}"
            
            return True, None
        
        elif schema_type == 'object':
            if not isinstance(value, dict):
                return False, f"Expected object, got {type(value).__name__}"
            
            if 'properties' in schema:
                for prop, prop_schema in schema['properties'].items():
                    if prop in value:
                        valid, error = TypeConverter.validate_against_schema(value[prop], prop_schema)
                        if not valid:
                            return False, f"Property '{prop}': {error}"
            
            if 'required' in schema:
                for required_prop in schema['required']:
                    if required_prop not in value:
                        return False, f"Missing required property '{required_prop}'"
            
            if schema.get('additionalProperties') is False:
                allowed_props = set(schema.get('properties', {}).keys())
                actual_props = set(value.keys())
                extra_props = actual_props - allowed_props
                if extra_props:
                    return False, f"Additional properties not allowed: {extra_props}"
            
            return True, None
        
        elif schema_type == 'null':
            if value is not None:
                return False, f"Expected null, got {type(value).__name__}"
            return True, None
        
        # Handle anyOf, oneOf, allOf
        if 'anyOf' in schema:
            for sub_schema in schema['anyOf']:
                valid, _ = TypeConverter.validate_against_schema(value, sub_schema)
                if valid:
                    return True, None
            return False, "Value does not match any of the schemas"
        
        if 'oneOf' in schema:
            matches = 0
            for sub_schema in schema['oneOf']:
                valid, _ = TypeConverter.validate_against_schema(value, sub_schema)
                if valid:
                    matches += 1
            if matches == 1:
                return True, None
            elif matches == 0:
                return False, "Value does not match any of the schemas"
            else:
                return False, "Value matches multiple schemas"
        
        if 'allOf' in schema:
            for sub_schema in schema['allOf']:
                valid, error = TypeConverter.validate_against_schema(value, sub_schema)
                if not valid:
                    return False, error
            return True, None
        
        # If no type specified, accept anything
        return True, None
    
    @staticmethod
    def deep_merge(target: Dict[str, Any], source: Dict[str, Any]) -> Dict[str, Any]:
        """Deep merge two dictionaries"""
        output = target.copy()
        
        for key, value in source.items():
            if key in output and isinstance(output[key], dict) and isinstance(value, dict):
                output[key] = TypeConverter.deep_merge(output[key], value)
            else:
                output[key] = value
        
        return output
    
    @staticmethod
    def serialize_for_json(value: Any) -> Any:
        """Serialize Python objects for JSON encoding"""
        if isinstance(value, datetime):
            return value.isoformat()
        elif isinstance(value, Decimal):
            return float(value)
        elif isinstance(value, set):
            return list(value)
        elif isinstance(value, bytes):
            return base64.b64encode(value).decode('utf-8')
        elif isinstance(value, dict):
            return {
                key: TypeConverter.serialize_for_json(val)
                for key, val in value.items()
            }
        elif isinstance(value, list):
            return [TypeConverter.serialize_for_json(item) for item in value]
        else:
            return value
    
    @staticmethod
    def dgm_to_dgmo_tool_params(dgm_params: Dict[str, Any]) -> Any:
        """Convert DGM tool parameters (JSON Schema) to DGMO format"""
        # DGM uses JSON schemas, DGMO expects different format
        # This is a simplified conversion - in production, use proper converter
        return dgm_params
    
    @staticmethod
    def dgmo_to_dgm_tool_params(dgmo_params: Any) -> Dict[str, Any]:
        """Convert DGMO tool parameters to DGM format (JSON Schema)"""
        # DGMO might use Zod or other schema formats
        # Convert to JSON Schema for DGM
        if isinstance(dgmo_params, dict) and 'type' in dgmo_params:
            return dgmo_params  # Already JSON Schema
        
        # Default conversion
        return {
            'type': 'object',
            'properties': {},
            'additionalProperties': True
        }
    
    @staticmethod
    def dgm_to_dgmo_result(result: Any) -> Dict[str, Any]:
        """Convert DGM tool result to DGMO format"""
        if isinstance(result, str):
            return {
                'output': result,
                'metadata': {}
            }
        
        return {
            'output': result.get('output', str(result)),
            'metadata': result.get('metadata', {})
        }
    
    @staticmethod
    def dgmo_to_dgm_result(result: Dict[str, Any]) -> Any:
        """Convert DGMO tool result to DGM format"""
        return {
            'output': result.get('output', ''),
            'metadata': result.get('metadata', {}),
            'success': True
        }