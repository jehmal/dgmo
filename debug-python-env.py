#!/usr/bin/env python3
import sys
import os
import subprocess

print("=== Python Environment Debug ===")
print(f"Python executable: {sys.executable}")
print(f"Python version: {sys.version}")
print(f"\nEnvironment variables:")
print(f"PYTHONPATH: {os.environ.get('PYTHONPATH', 'Not set')}")
print(f"VIRTUAL_ENV: {os.environ.get('VIRTUAL_ENV', 'Not set')}")
print(f"ANTHROPIC_AUTH_TOKEN: {'Set' if os.environ.get('ANTHROPIC_AUTH_TOKEN') else 'Not set'}")

print(f"\nsys.path:")
for i, p in enumerate(sys.path):
    print(f"  {i}: {p}")

print("\nTrying to import anthropic...")
try:
    import anthropic
    print(f"SUCCESS: anthropic imported from {anthropic.__file__}")
except ImportError as e:
    print(f"FAILED: {e}")
    
print("\nRunning pip list | grep anthropic:")
result = subprocess.run([sys.executable, "-m", "pip", "list"], capture_output=True, text=True)
for line in result.stdout.split('\n'):
    if 'anthropic' in line.lower():
        print(f"  {line}")