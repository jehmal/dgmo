"""
Unified Tool Registry for cross-language tool management
Supports both DGMO and DGM tools with seamless integration
"""

import asyncio
from typing import Dict, List, Optional, Any, Callable, Union
from pathlib import Path
import importlib.util
import sys
import json
from datetime import datetime

from ..types.python.tool import (
    Tool,
    ToolCategory,
    ToolFilter,
    ToolHandler,
    Language,
    ToolContext,
    ToolError
)
from ..types.python.base import Result, ErrorInfo, Metadata
from .python_adapter import PythonTypeScriptAdapter, TypeScriptToolInfo, TypeScriptToolRegistration
from .type_converter import TypeConverter


# DGM Tool Interface (from Python)
class DGMTool:
    """DGM tool definition"""
    def __init__(self, name: str, description: str, input_schema: Dict[str, Any], 
                 output_schema: Optional[Dict[str, Any]] = None, 
                 category: Optional[str] = None, tags: Optional[List[str]] = None):
        self.name = name
        self.description = description
        self.input_schema = input_schema
        self.output_schema = output_schema
        self.category = category
        self.tags = tags


# DGMO Tool Interface (from TypeScript)
class DGMOTool:
    """DGMO tool definition"""
    def __init__(self, id: str, description: str, parameters: Any, execute: Callable):
        self.id = id
        self.description = description
        self.parameters = parameters
        self.execute = execute


class ToolRegistration:
    """Tool registration information"""
    def __init__(self, tool: Tool, handler: ToolHandler, source: str = 'local', 
                 module: Optional[str] = None, original_tool: Optional[Union[DGMOTool, DGMTool]] = None):
        self.tool = tool
        self.handler = handler
        self.source = source
        self.module = module
        self.original_tool = original_tool


class UnifiedToolRegistry:
    """Unified registry for tools across languages"""
    
    _instance = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if not hasattr(self, '_initialized') or not self._initialized:
            self.tools: Dict[str, Dict[Language, ToolRegistration]] = {}
            self._initialized = False
    
    async def initialize(self) -> None:
        """Initialize the registry"""
        if self._initialized:
            return
        
        # Initialize adapters
        await PythonTypeScriptAdapter.initialize()
        
        # Load built-in tools
        await self._load_built_in_tools()
        
        self._initialized = True
    
    async def register(self, tool: Tool, handler: ToolHandler, module: Optional[str] = None, 
                      original_tool: Optional[Union[DGMOTool, DGMTool]] = None) -> None:
        """Register a tool with unified interface"""
        language_map = self.tools.get(tool.id, {})
        
        source = 'local'
        if original_tool:
            source = 'dgmo' if isinstance(original_tool, DGMOTool) else 'dgm'
        elif module:
            source = 'remote'
        
        language_map[tool.language] = ToolRegistration(
            tool=tool,
            handler=handler,
            source=source,
            module=module,
            original_tool=original_tool
        )
        
        self.tools[tool.id] = language_map
        
        # If it's a TypeScript tool, make it available to Python
        if tool.language == Language.TYPESCRIPT and module:
            await PythonTypeScriptAdapter.register_typescript_tool(
                TypeScriptToolRegistration(
                    module=module,
                    tool_id=tool.id,
                    info=TypeScriptToolInfo(
                        id=tool.id,
                        description=tool.description,
                        parameters=tool.input_schema
                    )
                )
            )
    
    async def register_dgm_tool(self, tool_def: DGMTool, module: str) -> None:
        """Register a DGM tool (from Python)"""
        tool = Tool(
            id=tool_def.name,
            name=tool_def.name,
            description=tool_def.description,
            version='1.0.0',
            category=ToolCategory(tool_def.category) if tool_def.category else self._infer_category(tool_def.name),
            language=Language.PYTHON,
            input_schema=tool_def.input_schema,
            output_schema=tool_def.output_schema,
            metadata={
                'id': f'dgm-{tool_def.name}',
                'version': '1.0.0',
                'timestamp': datetime.now().isoformat(),
                'source': 'dgm',
                'tags': tool_def.tags
            }
        )
        
        async def handler(input_data: Any, context: ToolContext) -> Result:
            try:
                # Load and execute the Python tool
                spec = importlib.util.spec_from_file_location("tool_module", module)
                if not spec or not spec.loader:
                    raise Exception(f"Failed to load module {module}")
                
                tool_module = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(tool_module)
                
                # Execute the tool
                if hasattr(tool_module, 'tool_function_async'):
                    result = await tool_module.tool_function_async(input_data, context)
                elif hasattr(tool_module, 'tool_function'):
                    result = await asyncio.get_event_loop().run_in_executor(
                        None, tool_module.tool_function, input_data
                    )
                else:
                    raise Exception(f"No tool function found in {module}")
                
                return Result(
                    success=True,
                    data=result,
                    metadata={
                        'id': context.message_id,
                        'version': '1.0.0',
                        'timestamp': datetime.now().isoformat(),
                        'source': 'dgm'
                    }
                )
            except Exception as e:
                return Result(
                    success=False,
                    error=ErrorInfo(
                        code='DGM_TOOL_ERROR',
                        message=str(e),
                        recoverable=True,
                        details={'tool': tool_def.name, 'error': str(e)}
                    )
                )
        
        await self.register(tool, handler, module, tool_def)
    
    async def register_dgmo_tool(self, tool_def: DGMOTool) -> None:
        """Register a DGMO tool (from TypeScript)"""
        tool = Tool(
            id=tool_def.id,
            name=tool_def.id,
            description=tool_def.description,
            version='1.0.0',
            category=self._infer_category(tool_def.id),
            language=Language.TYPESCRIPT,
            input_schema=self._convert_dgmo_parameters_to_json_schema(tool_def.parameters),
            metadata={
                'id': f'dgmo-{tool_def.id}',
                'version': '1.0.0',
                'timestamp': datetime.now().isoformat(),
                'source': 'dgmo'
            }
        )
        
        async def handler(input_data: Any, context: ToolContext) -> Result:
            try:
                # Convert Python input to TypeScript format
                ts_input = TypeConverter.python_to_typescript(input_data)
                
                # Execute via TypeScript adapter
                result = await PythonTypeScriptAdapter.execute_typescript_tool(
                    tool_def.id,
                    ts_input,
                    {
                        'sessionId': context.session_id,
                        'messageId': context.message_id,
                        'timeout': context.timeout
                    }
                )
                
                # Convert result back to Python
                py_result = TypeConverter.typescript_to_python(result)
                
                return Result(
                    success=True,
                    data=py_result,
                    metadata={
                        'id': context.message_id,
                        'version': '1.0.0',
                        'timestamp': datetime.now().isoformat(),
                        'source': 'dgmo'
                    }
                )
            except Exception as e:
                return Result(
                    success=False,
                    error=ErrorInfo(
                        code='DGMO_TOOL_ERROR',
                        message=str(e),
                        recoverable=True,
                        details={'tool': tool_def.id, 'error': str(e)}
                    )
                )
        
        await self.register(tool, handler, None, tool_def)
    
    async def unregister(self, tool_id: str, language: Optional[Language] = None) -> None:
        """Unregister a tool"""
        if language:
            language_map = self.tools.get(tool_id)
            if language_map and language in language_map:
                del language_map[language]
                if not language_map:
                    del self.tools[tool_id]
        else:
            if tool_id in self.tools:
                del self.tools[tool_id]
    
    async def get(self, tool_id: str, language: Optional[Language] = None) -> Optional[Tool]:
        """Get a tool by ID and optionally language"""
        language_map = self.tools.get(tool_id)
        if not language_map:
            return None
        
        if language:
            registration = language_map.get(language)
            return registration.tool if registration else None
        
        # Return the first available tool
        first_registration = next(iter(language_map.values()), None)
        return first_registration.tool if first_registration else None
    
    def get_handler(self, tool_id: str, language: Language) -> Optional[ToolHandler]:
        """Get tool handler"""
        language_map = self.tools.get(tool_id)
        if not language_map:
            return None
        
        registration = language_map.get(language)
        return registration.handler if registration else None
    
    async def list(self, filter: Optional[ToolFilter] = None) -> List[Tool]:
        """List tools with optional filter"""
        tools = []
        
        for language_map in self.tools.values():
            for registration in language_map.values():
                tool = registration.tool
                
                # Apply filters
                if filter:
                    if filter.category and tool.category != filter.category:
                        continue
                    if filter.language and tool.language != filter.language:
                        continue
                    if filter.tags and filter.tags:
                        tool_tags = tool.metadata.get('tags', []) if tool.metadata else []
                        if not any(tag in tool_tags for tag in filter.tags):
                            continue
                
                tools.append(tool)
        
        return tools
    
    async def search(self, query: str) -> List[Tool]:
        """Search tools by query"""
        lower_query = query.lower()
        tools = []
        
        for language_map in self.tools.values():
            for registration in language_map.values():
                tool = registration.tool
                
                # Search in name, description, and category
                if (lower_query in tool.name.lower() or
                    lower_query in tool.description.lower() or
                    lower_query in tool.category.value.lower()):
                    tools.append(tool)
        
        return tools
    
    async def execute(self, tool_id: str, input_data: Any, context: ToolContext, 
                     preferred_language: Optional[Language] = None) -> Result:
        """Execute a tool with automatic language selection"""
        language_map = self.tools.get(tool_id)
        if not language_map:
            return Result(
                success=False,
                error=ErrorInfo(
                    code='TOOL_NOT_FOUND',
                    message=f'Tool {tool_id} not found',
                    recoverable=False
                )
            )
        
        # Try preferred language first
        if preferred_language:
            registration = language_map.get(preferred_language)
            if registration:
                return await registration.handler(input_data, context)
        
        # Fall back to first available
        first_registration = next(iter(language_map.values()), None)
        if first_registration:
            return await first_registration.handler(input_data, context)
        
        return Result(
            success=False,
            error=ErrorInfo(
                code='NO_HANDLER_FOUND',
                message=f'No handler found for tool {tool_id}',
                recoverable=False
            )
        )
    
    async def validate_input(self, tool_id: str, input_data: Any, 
                           language: Optional[Language] = None) -> Result:
        """Validate tool input against schema"""
        tool = await self.get(tool_id, language)
        if not tool:
            return Result(
                success=False,
                error=ErrorInfo(
                    code='TOOL_NOT_FOUND',
                    message=f'Tool {tool_id} not found',
                    recoverable=False
                )
            )
        
        try:
            # Validate against JSON schema
            valid, error = TypeConverter.validate_against_schema(input_data, tool.input_schema)
            if not valid:
                return Result(
                    success=False,
                    error=ErrorInfo(
                        code='VALIDATION_ERROR',
                        message=error or 'Input validation failed',
                        recoverable=False,
                        details={'input': input_data, 'schema': tool.input_schema}
                    )
                )
            
            return Result(success=True, data=input_data)
        except Exception as e:
            return Result(
                success=False,
                error=ErrorInfo(
                    code='VALIDATION_ERROR',
                    message=str(e),
                    recoverable=False,
                    details={'error': str(e)}
                )
            )
    
    async def discover(self) -> Dict[str, Any]:
        """Get tool discovery information"""
        stats = {
            'total_tools': 0,
            'by_language': {},
            'by_category': {},
            'by_source': {}
        }
        
        for language_map in self.tools.values():
            for language, registration in language_map.items():
                stats['total_tools'] += 1
                
                # Count by language
                lang_str = language.value
                stats['by_language'][lang_str] = stats['by_language'].get(lang_str, 0) + 1
                
                # Count by category
                category_str = registration.tool.category.value
                stats['by_category'][category_str] = stats['by_category'].get(category_str, 0) + 1
                
                # Count by source
                source = registration.source
                stats['by_source'][source] = stats['by_source'].get(source, 0) + 1
        
        return stats
    
    async def _load_built_in_tools(self) -> None:
        """Load built-in tools"""
        # Load Python tools from DGM
        await self._load_dgm_tools()
        
        # Load TypeScript tools from OpenCode
        await self._load_opencode_tools()
    
    async def _load_dgm_tools(self) -> None:
        """Load DGM tools"""
        try:
            tool_modules = [
                {'path': Path(__file__).parent.parent.parent / 'dgm' / 'tools' / 'bash.py', 'name': 'bash'},
                {'path': Path(__file__).parent.parent.parent / 'dgm' / 'tools' / 'edit.py', 'name': 'edit'}
            ]
            
            for module_info in tool_modules:
                module_path = module_info['path']
                if module_path.exists():
                    try:
                        await self._load_python_tool(str(module_path), module_info['name'])
                    except Exception as e:
                        print(f"Failed to load DGM tool from {module_path}: {e}")
        except Exception as e:
            print(f"Failed to load DGM tools: {e}")
    
    async def _load_python_tool(self, module_path: str, tool_name: str) -> None:
        """Load a Python tool module"""
        spec = importlib.util.spec_from_file_location("tool_module", module_path)
        if not spec or not spec.loader:
            return
        
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        
        # Check for tool_info function
        if hasattr(module, 'tool_info'):
            info = module.tool_info()
            
            # Create DGM tool definition
            dgm_tool = DGMTool(
                name=tool_name,
                description=info.get('description', ''),
                input_schema=info.get('input_schema', {}),
                output_schema=info.get('output_schema'),
                category=info.get('category'),
                tags=info.get('tags')
            )
            
            await self.register_dgm_tool(dgm_tool, module_path)
    
    async def _load_opencode_tools(self) -> None:
        """Load TypeScript tools from OpenCode"""
        try:
            tool_modules = [
                '/mnt/c/Users/jehma/Desktop/AI/DGMSTT/opencode/packages/opencode/src/tool/bash.ts',
                '/mnt/c/Users/jehma/Desktop/AI/DGMSTT/opencode/packages/opencode/src/tool/edit.ts',
                '/mnt/c/Users/jehma/Desktop/AI/DGMSTT/opencode/packages/opencode/src/tool/read.ts',
                '/mnt/c/Users/jehma/Desktop/AI/DGMSTT/opencode/packages/opencode/src/tool/write.ts'
            ]
            
            for module_path in tool_modules:
                try:
                    # Load TypeScript tool info via adapter
                    tool_info = await PythonTypeScriptAdapter.load_typescript_module(module_path)
                    if tool_info:
                        # Create DGMO tool definition
                        dgmo_tool = DGMOTool(
                            id=tool_info.get('id', Path(module_path).stem),
                            description=tool_info.get('description', ''),
                            parameters=tool_info.get('parameters', {}),
                            execute=None  # Will be handled by adapter
                        )
                        
                        await self.register_dgmo_tool(dgmo_tool)
                except Exception as e:
                    print(f"Failed to load OpenCode tool from {module_path}: {e}")
        except Exception as e:
            print(f"Failed to load OpenCode tools: {e}")
    
    def _infer_category(self, tool_id: str) -> ToolCategory:
        """Infer tool category from ID"""
        category_map = {
            'bash': ToolCategory.UTILITY,
            'edit': ToolCategory.FILE_SYSTEM,
            'read': ToolCategory.FILE_SYSTEM,
            'write': ToolCategory.FILE_SYSTEM,
            'ls': ToolCategory.FILE_SYSTEM,
            'grep': ToolCategory.TEXT_PROCESSING,
            'glob': ToolCategory.FILE_SYSTEM,
            'patch': ToolCategory.FILE_SYSTEM,
            'multiedit': ToolCategory.FILE_SYSTEM
        }
        
        return category_map.get(tool_id, ToolCategory.UTILITY)
    
    def _convert_dgmo_parameters_to_json_schema(self, parameters: Any) -> Dict[str, Any]:
        """Convert DGMO parameters to JSON Schema"""
        # If it's already a JSON schema, return it
        if isinstance(parameters, dict) and 'type' in parameters:
            return parameters
        
        # Default fallback
        return {
            'type': 'object',
            'properties': {},
            'additionalProperties': True
        }
    
    def get_available_languages(self, tool_id: str) -> List[Language]:
        """Get available languages for a tool"""
        language_map = self.tools.get(tool_id)
        if not language_map:
            return []
        
        return list(language_map.keys())
    
    def supports_language(self, tool_id: str, language: Language) -> bool:
        """Check if a tool supports a specific language"""
        language_map = self.tools.get(tool_id)
        if not language_map:
            return False
        
        return language in language_map


# Create singleton instance
tool_registry = UnifiedToolRegistry()


# Convenience functions
async def register_tool(tool: Tool, handler: ToolHandler, module: Optional[str] = None) -> None:
    """Register a tool in the unified registry"""
    await tool_registry.register(tool, handler, module)


async def get_tool(tool_id: str, language: Optional[Language] = None) -> Optional[Tool]:
    """Get a tool from the registry"""
    return await tool_registry.get(tool_id, language)


async def list_tools(filter: Optional[ToolFilter] = None) -> List[Tool]:
    """List all available tools"""
    return await tool_registry.list(filter)


async def search_tools(query: str) -> List[Tool]:
    """Search for tools"""
    return await tool_registry.search(query)


async def execute_tool(tool_id: str, input_data: Any, context: ToolContext, 
                      preferred_language: Optional[Language] = None) -> Result:
    """Execute a tool"""
    return await tool_registry.execute(tool_id, input_data, context, preferred_language)