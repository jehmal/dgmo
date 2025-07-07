"""
Unified File Operations Tools for DGMO-DGM Integration
Provides read, write, and edit functionality across both systems
"""

import os
import re
from pathlib import Path
from typing import Dict, Any, Optional
from datetime import datetime

from ..types.python.tool import Tool, ToolContext, ToolCategory, Language
from ..types.python.base import Result, ErrorInfo

MAX_READ_SIZE = 250 * 1024
DEFAULT_READ_LIMIT = 2000
MAX_LINE_LENGTH = 2000


# ============= READ TOOL =============

async def read_file(params: Dict[str, Any], context: ToolContext) -> Result:
    """Read file with line numbers"""
    try:
        file_path = params['filePath']
        
        # Convert Windows paths to WSL format if needed
        windows_match = re.match(r'^([A-Za-z]):\\(.*)$', file_path)
        if windows_match:
            drive = windows_match.group(1).lower()
            path_part = windows_match.group(2).replace('\\', '/')
            file_path = f'/mnt/{drive}/{path_part}'
        
        if not os.path.isabs(file_path):
            file_path = os.path.abspath(file_path)
        
        # Check file exists
        if not os.path.exists(file_path):
            return Result(
                success=False,
                error=ErrorInfo(
                    code='FILE_NOT_FOUND',
                    message=f'File not found: {file_path}',
                    recoverable=False
                )
            )
        
        # Check file size
        file_size = os.path.getsize(file_path)
        if file_size > MAX_READ_SIZE:
            return Result(
                success=False,
                error=ErrorInfo(
                    code='FILE_TOO_LARGE',
                    message=f'File is too large ({file_size} bytes). Maximum size is {MAX_READ_SIZE} bytes',
                    recoverable=False
                )
            )
        
        # Read file
        with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
        
        lines = content.split('\n')
        limit = params.get('limit', DEFAULT_READ_LIMIT)
        offset = params.get('offset', 0)
        
        selected_lines = lines[offset:offset + limit]
        formatted_lines = []
        
        for i, line in enumerate(selected_lines):
            line_num = str(i + offset + 1).zfill(5)
            truncated_line = line[:MAX_LINE_LENGTH] + '...' if len(line) > MAX_LINE_LENGTH else line
            formatted_lines.append(f'{line_num}| {truncated_line}')
        
        output = {
            'content': '\n'.join(formatted_lines),
            'lines': len(selected_lines),
            'totalLines': len(lines),
            'path': file_path
        }
        
        return Result(
            success=True,
            data=output,
            metadata={
                'id': context.message_id,
                'version': '1.0.0',
                'timestamp': datetime.now().isoformat(),
                'source': 'unified-read'
            }
        )
        
    except Exception as e:
        return Result(
            success=False,
            error=ErrorInfo(
                code='READ_ERROR',
                message=str(e),
                recoverable=False,
                details={'error': str(e)}
            )
        )


# ============= WRITE TOOL =============

async def write_file(params: Dict[str, Any], context: ToolContext) -> Result:
    """Write content to a file"""
    try:
        file_path = params['filePath']
        content = params['content']
        
        if not os.path.isabs(file_path):
            file_path = os.path.abspath(file_path)
        
        # Check if file exists
        exists = os.path.exists(file_path)
        
        # Ensure directory exists
        directory = os.path.dirname(file_path)
        os.makedirs(directory, exist_ok=True)
        
        # Write file
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        file_size = os.path.getsize(file_path)
        
        output = {
            'path': file_path,
            'exists': exists,
            'size': file_size
        }
        
        return Result(
            success=True,
            data=output,
            metadata={
                'id': context.message_id,
                'version': '1.0.0',
                'timestamp': datetime.now().isoformat(),
                'source': 'unified-write'
            }
        )
        
    except Exception as e:
        return Result(
            success=False,
            error=ErrorInfo(
                code='WRITE_ERROR',
                message=str(e),
                recoverable=False,
                details={'error': str(e)}
            )
        )


# ============= EDIT TOOL =============

async def edit_file(params: Dict[str, Any], context: ToolContext) -> Result:
    """Edit a file by replacing text"""
    try:
        file_path = params['filePath']
        old_string = params['oldString']
        new_string = params['newString']
        replace_all = params.get('replaceAll', False)
        
        if old_string == new_string:
            return Result(
                success=False,
                error=ErrorInfo(
                    code='INVALID_EDIT',
                    message='oldString and newString must be different',
                    recoverable=False
                )
            )
        
        if not os.path.isabs(file_path):
            file_path = os.path.abspath(file_path)
        
        # Read file
        if not os.path.exists(file_path):
            return Result(
                success=False,
                error=ErrorInfo(
                    code='FILE_NOT_FOUND',
                    message=f'File not found: {file_path}',
                    recoverable=False
                )
            )
        
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Perform replacement
        replacements = 0
        if replace_all:
            new_content = content
            while old_string in new_content:
                new_content = new_content.replace(old_string, new_string, 1)
                replacements += 1
        else:
            if old_string in content:
                new_content = content.replace(old_string, new_string, 1)
                replacements = 1
            else:
                new_content = content
        
        if replacements == 0:
            return Result(
                success=False,
                error=ErrorInfo(
                    code='STRING_NOT_FOUND',
                    message=f'String not found in file: {old_string}',
                    recoverable=False
                )
            )
        
        # Write file
        with open(file_path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        
        # Create simple diff
        diff = create_simple_diff(content, new_content, file_path)
        
        output = {
            'path': file_path,
            'replacements': replacements,
            'diff': diff
        }
        
        return Result(
            success=True,
            data=output,
            metadata={
                'id': context.message_id,
                'version': '1.0.0',
                'timestamp': datetime.now().isoformat(),
                'source': 'unified-edit'
            }
        )
        
    except Exception as e:
        return Result(
            success=False,
            error=ErrorInfo(
                code='EDIT_ERROR',
                message=str(e),
                recoverable=False,
                details={'error': str(e)}
            )
        )


def create_simple_diff(old_content: str, new_content: str, file_path: str) -> str:
    """Create a simple diff between old and new content"""
    old_lines = old_content.split('\n')
    new_lines = new_content.split('\n')
    
    diff = f'--- {file_path}\n+++ {file_path}\n'
    
    # Simple line-by-line comparison
    max_lines = max(len(old_lines), len(new_lines))
    for i in range(max_lines):
        if i >= len(old_lines):
            diff += f'+{new_lines[i]}\n'
        elif i >= len(new_lines):
            diff += f'-{old_lines[i]}\n'
        elif old_lines[i] != new_lines[i]:
            diff += f'-{old_lines[i]}\n'
            diff += f'+{new_lines[i]}\n'
    
    return diff


# Tool definitions
read_tool = Tool(
    id='read',
    name='read',
    description='Read contents of a file with line numbers',
    version='1.0.0',
    category=ToolCategory.FILE_SYSTEM,
    language=Language.PYTHON,
    input_schema={
        'type': 'object',
        'properties': {
            'filePath': {'type': 'string', 'description': 'The path to the file to read'},
            'offset': {'type': 'number', 'description': 'The line number to start reading from (0-based)'},
            'limit': {'type': 'number', 'description': 'The number of lines to read (defaults to 2000)'}
        },
        'required': ['filePath']
    },
    output_schema={
        'type': 'object',
        'properties': {
            'content': {'type': 'string'},
            'lines': {'type': 'number'},
            'totalLines': {'type': 'number'},
            'path': {'type': 'string'}
        },
        'required': ['content', 'lines', 'totalLines', 'path']
    },
    metadata={
        'id': 'unified-read',
        'version': '1.0.0',
        'timestamp': datetime.now().isoformat(),
        'source': 'shared'
    }
)

write_tool = Tool(
    id='write',
    name='write',
    description='Write content to a file',
    version='1.0.0',
    category=ToolCategory.FILE_SYSTEM,
    language=Language.PYTHON,
    input_schema={
        'type': 'object',
        'properties': {
            'filePath': {'type': 'string', 'description': 'The absolute path to the file to write'},
            'content': {'type': 'string', 'description': 'The content to write to the file'}
        },
        'required': ['filePath', 'content']
    },
    output_schema={
        'type': 'object',
        'properties': {
            'path': {'type': 'string'},
            'exists': {'type': 'boolean'},
            'size': {'type': 'number'}
        },
        'required': ['path', 'exists', 'size']
    },
    metadata={
        'id': 'unified-write',
        'version': '1.0.0',
        'timestamp': datetime.now().isoformat(),
        'source': 'shared'
    }
)

edit_tool = Tool(
    id='edit',
    name='edit',
    description='Edit a file by replacing text',
    version='1.0.0',
    category=ToolCategory.FILE_SYSTEM,
    language=Language.PYTHON,
    input_schema={
        'type': 'object',
        'properties': {
            'filePath': {'type': 'string', 'description': 'The absolute path to the file to modify'},
            'oldString': {'type': 'string', 'description': 'The text to replace'},
            'newString': {'type': 'string', 'description': 'The text to replace it with'},
            'replaceAll': {'type': 'boolean', 'description': 'Replace all occurrences (default false)'}
        },
        'required': ['filePath', 'oldString', 'newString']
    },
    output_schema={
        'type': 'object',
        'properties': {
            'path': {'type': 'string'},
            'replacements': {'type': 'number'},
            'diff': {'type': 'string'}
        },
        'required': ['path', 'replacements', 'diff']
    },
    metadata={
        'id': 'unified-edit',
        'version': '1.0.0',
        'timestamp': datetime.now().isoformat(),
        'source': 'shared'
    }
)


# Tool handlers
async def read_tool_handler(input_data: Dict[str, Any], context: ToolContext) -> Result:
    """Read tool handler for unified registry"""
    result = await read_file(input_data, context)
    
    if result.success and result.data:
        output = '<file>\n'
        output += result.data['content']
        
        if result.data['totalLines'] > result.data['lines'] + input_data.get('offset', 0):
            output += f"\n\n(File has more lines. Use 'offset' parameter to read beyond line {
                result.data['lines'] + input_data.get('offset', 0)
            })"
        output += '\n</file>'
        
        return Result(
            success=True,
            data={
                'output': output,
                'metadata': {
                    'preview': '\n'.join(result.data['content'].split('\n')[:20]),
                    'title': os.path.basename(result.data['path'])
                }
            },
            metadata=result.metadata
        )
    
    return result


async def write_tool_handler(input_data: Dict[str, Any], context: ToolContext) -> Result:
    """Write tool handler for unified registry"""
    result = await write_file(input_data, context)
    
    if result.success and result.data:
        return Result(
            success=True,
            data={
                'output': '',
                'metadata': {
                    'filepath': result.data['path'],
                    'exists': result.data['exists'],
                    'title': os.path.basename(result.data['path'])
                }
            },
            metadata=result.metadata
        )
    
    return result


async def edit_tool_handler(input_data: Dict[str, Any], context: ToolContext) -> Result:
    """Edit tool handler for unified registry"""
    result = await edit_file(input_data, context)
    
    if result.success and result.data:
        return Result(
            success=True,
            data={
                'output': result.data['diff'],
                'metadata': {
                    'filepath': result.data['path'],
                    'replacements': result.data['replacements'],
                    'title': os.path.basename(result.data['path'])
                }
            },
            metadata=result.metadata
        )
    
    return result


# DGM compatibility functions
async def tool_function_async_read(params: Dict[str, Any], context: Optional[ToolContext] = None) -> Dict[str, Any]:
    """DGM-compatible read tool function"""
    if not context:
        context = ToolContext(
            session_id='dgm-session',
            message_id='dgm-message',
            timeout=30,
            metadata={}
        )
    
    result = await read_tool_handler(params, context)
    
    if result.success:
        return result.data
    else:
        raise Exception(result.error.message if result.error else 'Read failed')


async def tool_function_async_write(params: Dict[str, Any], context: Optional[ToolContext] = None) -> Dict[str, Any]:
    """DGM-compatible write tool function"""
    if not context:
        context = ToolContext(
            session_id='dgm-session',
            message_id='dgm-message',
            timeout=30,
            metadata={}
        )
    
    result = await write_tool_handler(params, context)
    
    if result.success:
        return result.data
    else:
        raise Exception(result.error.message if result.error else 'Write failed')


async def tool_function_async_edit(params: Dict[str, Any], context: Optional[ToolContext] = None) -> Dict[str, Any]:
    """DGM-compatible edit tool function"""
    if not context:
        context = ToolContext(
            session_id='dgm-session',
            message_id='dgm-message',
            timeout=30,
            metadata={}
        )
    
    result = await edit_tool_handler(params, context)
    
    if result.success:
        return result.data
    else:
        raise Exception(result.error.message if result.error else 'Edit failed')


def tool_info_read() -> Dict[str, Any]:
    """Return read tool information for DGM registration"""
    return {
        'name': 'read',
        'description': read_tool.description,
        'input_schema': read_tool.input_schema,
        'output_schema': read_tool.output_schema,
        'category': read_tool.category.value,
        'tags': ['file', 'read', 'content']
    }


def tool_info_write() -> Dict[str, Any]:
    """Return write tool information for DGM registration"""
    return {
        'name': 'write',
        'description': write_tool.description,
        'input_schema': write_tool.input_schema,
        'output_schema': write_tool.output_schema,
        'category': write_tool.category.value,
        'tags': ['file', 'write', 'create']
    }


def tool_info_edit() -> Dict[str, Any]:
    """Return edit tool information for DGM registration"""
    return {
        'name': 'edit',
        'description': edit_tool.description,
        'input_schema': edit_tool.input_schema,
        'output_schema': edit_tool.output_schema,
        'category': edit_tool.category.value,
        'tags': ['file', 'edit', 'replace']
    }