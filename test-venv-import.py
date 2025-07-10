#!/usr/bin/env python3
import sys
print("Python executable:", sys.executable)
print("Python version:", sys.version)
print("sys.path:")
for p in sys.path:
    print(f"  {p}")

print("\nTrying to import anthropic...")
try:
    import anthropic
    print("SUCCESS: anthropic imported from:", anthropic.__file__)
except ImportError as e:
    print("FAILED:", str(e))
    
print("\nChecking site-packages:")
import site
for p in site.getsitepackages():
    print(f"  {p}")