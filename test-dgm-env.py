#!/usr/bin/env python3
import sys
import os
import json

# Print Python environment info
info = {
    "python_executable": sys.executable,
    "python_version": sys.version,
    "python_path": sys.path,
    "env_pythonpath": os.environ.get("PYTHONPATH", "Not set"),
    "cwd": os.getcwd(),
    "can_import_anthropic": False,
    "anthropic_location": None
}

try:
    import anthropic
    info["can_import_anthropic"] = True
    info["anthropic_location"] = anthropic.__file__
except ImportError as e:
    info["import_error"] = str(e)

print(json.dumps(info, indent=2))