# DGMSTT Shared Utilities

This directory contains shared utility modules to reduce code duplication across the DGMSTT codebase. These utilities provide common patterns for error handling, type conversion, configuration loading, and testing.

## Structure

```
shared/
├── typescript/     # TypeScript utilities
├── python/        # Python utilities
└── go/           # Go utilities
```

## TypeScript Utilities

### error-handler.ts
Common error handling patterns including:
- Structured error classes with validation
- Retry with exponential backoff
- JSON-RPC error handling
- Safe async execution

### path-validator.ts
Path validation and manipulation utilities:
- Path existence and type checking
- Security-aware path operations
- Batch path validation
- Common path manipulation helpers

### type-guards.ts
Type checking and validation utilities:
- Type guards for common types
- JSON-RPC message validation
- Custom type guard creators
- Type refinement helpers

## Python Utilities

### type_converter.py
Unified type conversion implementations:
- Safe type conversion with defaults
- JSON serialization helpers
- Common parsing functions
- Type coercion with schemas

### error_handler.py
Error handling decorators and utilities:
- Retry decorators with backoff
- Error context managers
- Error collection utilities
- Structured error classes

### config_loader.py
Unified configuration loading:
- Multiple source support (files, env, dict)
- Schema validation
- Configuration merging
- Reload support with callbacks

## Go Utilities

### errorutil/errors.go
Common error handling patterns:
- Structured errors with stack traces
- Error wrapping utilities
- Retry with exponential backoff
- Error list accumulation

### syncutil/context.go
Context and synchronization utilities:
- Context value helpers with type safety
- Cancel group management
- Safe goroutine execution
- Debounce and throttle functions

### testutil/helpers.go
Test utilities and helpers:
- Assertion helpers
- Mock HTTP server
- Golden file testing
- Temporary file/directory management

## Usage Examples

### TypeScript
```typescript
import { retryWithBackoff, ValidationError } from '@dgmstt/shared/typescript/error-handler';
import { validatePath } from '@dgmstt/shared/typescript/path-validator';
import { isJsonRpcRequest } from '@dgmstt/shared/typescript/type-guards';

// Retry an operation
const result = await retryWithBackoff(
  async () => await fetchData(),
  { maxAttempts: 3, initialDelayMs: 1000 }
);

// Validate a path
const validation = await validatePath('/some/path', {
  mustExist: true,
  mustBeFile: true
});

// Type guard usage
if (isJsonRpcRequest(message)) {
  // message is typed as JsonRpcRequest
}
```

### Python
```python
from dgmstt.shared import safe_convert, retry, ConfigLoader

# Type conversion
value = safe_convert("123", int, default=0)

# Retry decorator
@retry(max_attempts=3, delay=1.0)
def fetch_data():
    return requests.get("http://api.example.com")

# Configuration loading
loader = ConfigLoader()
loader.add_file("config.json")
loader.add_env("APP_")
config = loader.load()
```

### Go
```go
import (
    "github.com/dgmstt/shared/errorutil"
    "github.com/dgmstt/shared/syncutil"
    "github.com/dgmstt/shared/testutil"
)

// Error handling
err := errorutil.Retry(ctx, errorutil.DefaultRetryConfig(), func() error {
    return someOperation()
})

// Context utilities
ctx = syncutil.WithValue(ctx, syncutil.RequestIDKey, "123")
requestID, _ := syncutil.GetValue[string](ctx, syncutil.RequestIDKey)

// Test helpers
testutil.AssertNoError(t, err)
testutil.AssertEqual(t, got, want)
```

## Best Practices

1. **Import Only What You Need**: These utilities are designed to be imported individually to keep bundle sizes small.

2. **Extend, Don't Modify**: If you need additional functionality, create new utilities or extend existing ones rather than modifying the shared code.

3. **Document Usage**: When using these utilities in your code, add comments explaining why you chose a particular pattern.

4. **Test Your Usage**: These utilities are tested, but always test how you use them in your specific context.

5. **Version Carefully**: When updating shared utilities, ensure backward compatibility or clearly document breaking changes.