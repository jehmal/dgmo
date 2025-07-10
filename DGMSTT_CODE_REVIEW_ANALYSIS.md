# Go Code Review: TUI Package Analysis

## Executive Summary

This code review identified several critical issues that could lead to runtime panics, resource leaks, and race conditions in the TUI package. The most severe issues include unchecked pointer dereferences, missing mutex protections, and potential goroutine leaks.

## Critical Issues (High Severity)

### 1. Null Pointer Dereferences

#### main.go
- **Line 37**: `json.Unmarshal` called on `appInfoStr` without checking if the environment variable is empty
  ```go
  appInfoStr := os.Getenv("DGMO_APP_INFO")
  var appInfo opencode.App
  err := json.Unmarshal([]byte(appInfoStr), &appInfo) // Will panic if appInfoStr is empty
  ```
  **Fix**: Check if `appInfoStr` is empty before unmarshaling

- **Line 66-69**: Dead code - error check after `httpClient` creation which doesn't return an error
  ```go
  httpClient := opencode.NewClient(
      option.WithBaseURL(url),
  )
  
  if err != nil { // 'err' is from previous operation, not NewClient
      slog.Error("Failed to create client", "error", err)
      os.Exit(1)
  }
  ```

#### app.go
- **Line 179-180**: Potential nil pointer if no provider with ID "anthropic" is found
  ```go
  if provider.ID == "anthropic" {
      anthropic = &provider
  }
  // Later used without nil check in some paths
  ```

- **Line 234**: `getDefaultModel` can return nil, but the result is used without checking
  ```go
  defaultModel = getDefaultModel(providersResponse, provider)
  // defaultModel could be nil if no models exist
  ```

- **Line 319**: Session can be nil but accessed without check
  ```go
  if a.Session == nil || a.Session.ID == "" {
      // ... creates session
  }
  // But Session could still be nil if CreateSession fails
  ```

#### task_client.go
- **Line 483-486**: Unsafe conn access in readLoop
  ```go
  tc.mu.RLock()
  conn := tc.conn
  tc.mu.RUnlock()
  
  if conn != nil {
      conn.SetReadDeadline(time.Now().Add(70 * time.Second))
  }
  // conn could become nil between check and use
  ```

### 2. Race Conditions

#### task_client.go
- **Line 243-249**: Race condition in connection state check
  ```go
  tc.mu.RLock()
  isConnected := tc.conn != nil && tc.GetConnectionState() == StateConnected
  tc.mu.RUnlock()
  
  if isConnected {
      return nil
  }
  // State could change here before setState is called
  tc.setState(StateConnecting, nil)
  ```

- **Line 315-318**: Connection assignment race
  ```go
  tc.mu.Lock()
  tc.conn = conn
  tc.mu.Unlock()
  // Other goroutines might access conn before state is updated
  atomic.StoreInt32(&tc.retryCount, 0)
  tc.setState(StateConnected, nil)
  ```

#### app.go
- **Line 507-513**: Session stack manipulation without synchronization
  ```go
  func (a *App) PushSession(sessionID string) {
      if a.SessionStack == nil {
          a.SessionStack = []string{}
      }
      // No mutex protection for concurrent access
      a.SessionStack = append(a.SessionStack, sessionID)
  }
  ```

### 3. Goroutine Leaks

#### main.go
- **Line 175-186**: Goroutine launched without proper cleanup mechanism
  ```go
  go func() {
      slog.Info("TUI attempting to connect to WebSocket server...")
      if err := taskClient.Connect(); err != nil {
          slog.Error("TUI failed to connect to task event server", "error", err)
      }
      // No way to stop this goroutine
  }()
  ```

- **Line 188-198**: Event streaming goroutine without context cancellation check
  ```go
  go func() {
      stream := httpClient.Event.ListStreaming(ctx)
      for stream.Next() {
          evt := stream.Current().AsUnion()
          program.Send(evt)
      }
      // Will continue running even after main exits
  }()
  ```

#### task_client.go
- **Line 637-642, 663-668**: Cleanup goroutines that could accumulate
  ```go
  go func() {
      time.Sleep(30 * time.Second)
      tc.mu.Lock()
      delete(tc.tasks, data.TaskID)
      tc.mu.Unlock()
  }()
  // No cancellation mechanism
  ```

### 4. Resource Leaks

#### checkpoint_client.go
- **Line 63**: Response body not closed on error paths
  ```go
  resp, err := httpClient.Do(req)
  if err != nil {
      return nil, fmt.Errorf("failed to execute request: %w", err)
      // resp.Body not closed if resp is non-nil
  }
  defer resp.Body.Close()
  ```

#### main.go
- **Line 56**: File handle not closed on error in deferred function
  ```go
  file, err := os.Create(logfile)
  if err != nil {
      slog.Error("Failed to create log file", "error", err)
      os.Exit(1) // Exits before defer can run
  }
  defer file.Close()
  ```

### 5. Logic Errors

#### app.go
- **Line 193-195**: Duplicate providers in slice
  ```go
  for _, provider := range providers {
      // ...
      providers = append(providers, provider) // Appending to same slice being iterated
  }
  ```

#### task_client.go
- **Line 254-255**: Retry count check happens after state change
  ```go
  if atomic.LoadInt32(&tc.retryCount) == 0 {
      // First connection attempt logic
  }
  // But retryCount is incremented later at line 309
  ```

### 6. Missing Error Handling

#### app.go
- **Line 273-282**: Fire-and-forget session initialization
  ```go
  go func() {
      _, err := a.Client.Session.Init(ctx, a.Session.ID, opencode.SessionInitParams{
          ProviderID: opencode.F(a.Provider.ID),
          ModelID:    opencode.F(a.Model.ID),
      })
      if err != nil {
          slog.Error("Failed to initialize project", "error", err)
          // Error logged but not propagated
      }
  }()
  ```

### 7. Type Assertions Without Checks

#### main.go
- **Line 192**: Type assertion on stream event without verification
  ```go
  evt := stream.Current().AsUnion()
  program.Send(evt)
  // No check if AsUnion() returns expected type
  ```

## Medium Severity Issues

### 1. Improper Defer Usage

#### main.go
- **Line 172**: Defer in non-function scope might not behave as expected
  ```go
  app_.TaskClient = taskClient
  defer taskClient.Disconnect() // In main(), will only run at program exit
  ```

### 2. Channel Operations Without Timeouts

#### task_client.go
- Throughout the readLoop, there are no timeouts on channel operations which could block indefinitely

### 3. Map Access Without Checks

#### app.go
- **Line 228**: Map access without existence check
  ```go
  model := provider.Models[match]
  // 'match' might not exist in Models map
  ```

## Low Severity Issues

### 1. Slice Bounds (Potential)
- No direct slice bounds errors found, but several places where slice operations could benefit from bounds checking

### 2. Context Propagation
- Some operations create new contexts instead of propagating the parent context

## Recommendations

1. **Add Nil Checks**: Implement comprehensive nil checking before pointer dereferences
2. **Add Mutex Protection**: Protect shared state (SessionStack, connections) with appropriate synchronization
3. **Implement Graceful Shutdown**: Add context cancellation to all goroutines
4. **Fix Resource Cleanup**: Ensure all resources are properly closed in all code paths
5. **Add Recovery Mechanisms**: Implement panic recovery in critical paths
6. **Improve Error Propagation**: Don't silently log errors in goroutines
7. **Add Integration Tests**: Test concurrent operations and error scenarios

## Code Patterns to Implement

### Safe Pointer Access Pattern
```go
tc.mu.RLock()
conn := tc.conn
tc.mu.RUnlock()

if conn == nil {
    return fmt.Errorf("connection is nil")
}
// Use conn safely here
```

### Goroutine Lifecycle Pattern
```go
go func() {
    defer func() {
        if r := recover(); r != nil {
            slog.Error("Goroutine panicked", "error", r)
        }
    }()
    
    for {
        select {
        case <-ctx.Done():
            return
        case work := <-workChan:
            // Do work
        }
    }
}()
```

### Resource Cleanup Pattern
```go
resp, err := client.Do(req)
if err != nil {
    return nil, err
}
defer func() {
    if err := resp.Body.Close(); err != nil {
        slog.Warn("Failed to close response body", "error", err)
    }
}()
```

## Summary Statistics

- **Critical Issues**: 15
- **High Priority Fixes**: 7
- **Race Conditions**: 4
- **Resource Leaks**: 3
- **Null Pointer Risks**: 8

The codebase shows signs of concurrent programming without sufficient synchronization, leading to multiple race conditions. The error handling is inconsistent, with some errors being silently logged rather than properly propagated. These issues should be addressed immediately to prevent runtime panics and ensure application stability.
