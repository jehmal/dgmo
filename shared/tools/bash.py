"""
Unified Bash Tool Implementation for DGMO-DGM Integration
Provides identical functionality across TypeScript and Python environments
"""

import asyncio
import os
import signal
import subprocess
from typing import Dict, Any, Optional
from datetime import datetime

from ..types.python.tool import Tool, ToolContext, ToolCategory, Language
from ..types.python.base import Result, ErrorInfo

MAX_OUTPUT_LENGTH = 30000
BANNED_COMMANDS = [
    'alias',
    'curl',
    'curlie',
    'wget',
    'axel',
    'aria2c',
    'nc',
    'telnet',
    'lynx',
    'w3m',
    'links',
    'httpie',
    'xh',
    'http-prompt',
    'chrome',
    'firefox',
    'safari',
]
DEFAULT_TIMEOUT = 60  # seconds
MAX_TIMEOUT = 600  # seconds


class BashOutput:
    """Output from bash command execution"""
    def __init__(self, stdout: str, stderr: str, exit_code: Optional[int], 
                 description: str, command: str):
        self.stdout = stdout
        self.stderr = stderr
        self.exit_code = exit_code
        self.description = description
        self.command = command


async def execute_bash_command(params: Dict[str, Any], context: ToolContext) -> Result:
    """Execute bash command with proper error handling and output capture"""
    try:
        command = params['command']
        timeout = min(params.get('timeout', DEFAULT_TIMEOUT * 1000) / 1000, MAX_TIMEOUT)
        description = params['description']
        
        # Validate banned commands
        for banned in BANNED_COMMANDS:
            if command.startswith(banned):
                return Result(
                    success=False,
                    error=ErrorInfo(
                        code='BANNED_COMMAND',
                        message=f"Command '{command}' is not allowed",
                        recoverable=False
                    )
                )
        
        # Get working directory from context or use current
        cwd = context.metadata.get('cwd', os.getcwd())
        
        # Create process
        process = await asyncio.create_subprocess_shell(
            command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            cwd=cwd,
            env=os.environ.copy()
        )
        
        # Execute with timeout
        try:
            stdout_data, stderr_data = await asyncio.wait_for(
                process.communicate(),
                timeout=timeout
            )
            
            stdout = stdout_data.decode('utf-8', errors='replace')
            stderr = stderr_data.decode('utf-8', errors='replace')
            
            # Truncate if too long
            if len(stdout) > MAX_OUTPUT_LENGTH:
                stdout = stdout[:MAX_OUTPUT_LENGTH] + '\n... (output truncated)'
            if len(stderr) > MAX_OUTPUT_LENGTH:
                stderr = stderr[:MAX_OUTPUT_LENGTH] + '\n... (output truncated)'
            
            output = BashOutput(
                stdout=stdout,
                stderr=stderr,
                exit_code=process.returncode,
                description=description,
                command=command
            )
            
            return Result(
                success=True,
                data=output,
                metadata={
                    'id': context.message_id,
                    'version': '1.0.0',
                    'timestamp': datetime.now().isoformat(),
                    'source': 'unified-bash'
                }
            )
            
        except asyncio.TimeoutError:
            # Kill the process
            try:
                process.terminate()
                await asyncio.sleep(0.1)
                if process.returncode is None:
                    process.kill()
            except:
                pass
            
            return Result(
                success=False,
                error=ErrorInfo(
                    code='TIMEOUT',
                    message=f'Command timed out after {timeout}s',
                    recoverable=True,
                    details={'command': command}
                )
            )
            
    except Exception as e:
        return Result(
            success=False,
            error=ErrorInfo(
                code='UNEXPECTED_ERROR',
                message=str(e),
                recoverable=False,
                details={'error': str(e)}
            )
        )


def format_bash_output(output: BashOutput) -> str:
    """Format bash output for display"""
    parts = [
        '<stdout>',
        output.stdout or '',
        '</stdout>',
        '<stderr>',
        output.stderr or '',
        '</stderr>'
    ]
    
    if output.exit_code != 0:
        parts.append(f'<exit_code>{output.exit_code}</exit_code>')
    
    return '\n'.join(parts)


# Create unified bash tool definition
bash_tool = Tool(
    id='bash',
    name='bash',
    description='Execute bash commands with timeout and output capture',
    version='1.0.0',
    category=ToolCategory.UTILITY,
    language=Language.PYTHON,
    input_schema={
        'type': 'object',
        'properties': {
            'command': {
                'type': 'string',
                'description': 'The command to execute'
            },
            'timeout': {
                'type': 'number',
                'minimum': 0,
                'maximum': MAX_TIMEOUT * 1000,
                'description': 'Optional timeout in milliseconds'
            },
            'description': {
                'type': 'string',
                'description': 'Clear, concise description of what this command does in 5-10 words'
            }
        },
        'required': ['command', 'description']
    },
    output_schema={
        'type': 'object',
        'properties': {
            'stdout': {'type': 'string'},
            'stderr': {'type': 'string'},
            'exitCode': {'type': ['number', 'null']},
            'description': {'type': 'string'},
            'command': {'type': 'string'}
        },
        'required': ['stdout', 'stderr', 'exitCode', 'description', 'command']
    },
    metadata={
        'id': 'unified-bash',
        'version': '1.0.0',
        'timestamp': datetime.now().isoformat(),
        'source': 'shared'
    }
)


async def bash_tool_handler(input_data: Dict[str, Any], context: ToolContext) -> Result:
    """Bash tool handler for unified registry"""
    result = await execute_bash_command(input_data, context)
    
    if result.success and result.data:
        return Result(
            success=True,
            data={
                'output': format_bash_output(result.data),
                'metadata': {
                    'stdout': result.data.stdout,
                    'stderr': result.data.stderr,
                    'exitCode': result.data.exit_code,
                    'description': result.data.description,
                    'command': result.data.command,
                    'title': result.data.command
                }
            },
            metadata=result.metadata
        )
    
    return result


# Export for DGM compatibility
async def tool_function_async(params: Dict[str, Any], context: Optional[ToolContext] = None) -> Dict[str, Any]:
    """DGM-compatible tool function"""
    if not context:
        # Create minimal context for DGM compatibility
        context = ToolContext(
            session_id='dgm-session',
            message_id='dgm-message',
            timeout=params.get('timeout', DEFAULT_TIMEOUT * 1000) / 1000,
            metadata={'cwd': os.getcwd()}
        )
    
    result = await bash_tool_handler(params, context)
    
    if result.success:
        return result.data
    else:
        raise Exception(result.error.message if result.error else 'Bash execution failed')


def tool_info() -> Dict[str, Any]:
    """Return tool information for DGM registration"""
    return {
        'name': 'bash',
        'description': bash_tool.description,
        'input_schema': bash_tool.input_schema,
        'output_schema': bash_tool.output_schema,
        'category': bash_tool.category.value,
        'tags': ['command', 'shell', 'execution']
    }