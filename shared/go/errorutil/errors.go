// Package errorutil provides common error handling utilities for DGMSTT Go projects
package errorutil

import (
	"context"
	"errors"
	"fmt"
	"runtime"
	"strings"
	"time"
)

// BaseError is the base error type with structured data support
type BaseError struct {
	Code      string                 `json:"code"`
	Message   string                 `json:"message"`
	Data      map[string]interface{} `json:"data,omitempty"`
	Cause     error                  `json:"-"`
	Timestamp time.Time              `json:"timestamp"`
	Stack     []string               `json:"stack,omitempty"`
}

// Error implements the error interface
func (e *BaseError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %s (caused by: %v)", e.Code, e.Message, e.Cause)
	}
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

// Unwrap returns the cause of the error
func (e *BaseError) Unwrap() error {
	return e.Cause
}

// WithData adds data to the error
func (e *BaseError) WithData(key string, value interface{}) *BaseError {
	if e.Data == nil {
		e.Data = make(map[string]interface{})
	}
	e.Data[key] = value
	return e
}

// NewError creates a new BaseError
func NewError(code, message string, cause error) *BaseError {
	err := &BaseError{
		Code:      code,
		Message:   message,
		Cause:     cause,
		Timestamp: time.Now(),
		Data:      make(map[string]interface{}),
	}
	
	// Capture stack trace
	err.Stack = CaptureStack(2) // Skip NewError and caller
	
	return err
}

// CaptureStack captures the current stack trace
func CaptureStack(skip int) []string {
	var stack []string
	for i := skip; ; i++ {
		pc, file, line, ok := runtime.Caller(i)
		if !ok {
			break
		}
		
		fn := runtime.FuncForPC(pc)
		if fn == nil {
			continue
		}
		
		stack = append(stack, fmt.Sprintf("%s:%d %s", file, line, fn.Name()))
		
		// Limit stack depth
		if len(stack) >= 10 {
			break
		}
	}
	return stack
}

// Common error types
var (
	// ErrValidation indicates a validation error
	ErrValidation = errors.New("validation error")
	
	// ErrNetwork indicates a network error
	ErrNetwork = errors.New("network error")
	
	// ErrTimeout indicates a timeout error
	ErrTimeout = errors.New("timeout error")
	
	// ErrNotFound indicates a resource was not found
	ErrNotFound = errors.New("not found")
	
	// ErrUnauthorized indicates an authorization error
	ErrUnauthorized = errors.New("unauthorized")
	
	// ErrInternal indicates an internal error
	ErrInternal = errors.New("internal error")
)

// ValidationError creates a validation error
func ValidationError(message string, field string, value interface{}) *BaseError {
	return NewError("VALIDATION_ERROR", message, ErrValidation).
		WithData("field", field).
		WithData("value", value)
}

// NetworkError creates a network error
func NetworkError(message string, url string, statusCode int) *BaseError {
	return NewError("NETWORK_ERROR", message, ErrNetwork).
		WithData("url", url).
		WithData("status_code", statusCode)
}

// TimeoutError creates a timeout error
func TimeoutError(operation string, duration time.Duration) *BaseError {
	message := fmt.Sprintf("operation '%s' timed out after %v", operation, duration)
	return NewError("TIMEOUT_ERROR", message, ErrTimeout).
		WithData("operation", operation).
		WithData("timeout_ms", duration.Milliseconds())
}

// Wrap wraps an error with additional context
func Wrap(err error, message string) error {
	if err == nil {
		return nil
	}
	return fmt.Errorf("%s: %w", message, err)
}

// WrapWithCode wraps an error with a code and message
func WrapWithCode(err error, code, message string) *BaseError {
	if err == nil {
		return nil
	}
	
	// If it's already a BaseError, preserve the original
	if baseErr, ok := err.(*BaseError); ok {
		return NewError(code, message, baseErr)
	}
	
	return NewError(code, message, err)
}

// Is checks if an error matches a target error
func Is(err, target error) bool {
	return errors.Is(err, target)
}

// As finds the first error in err's chain that matches target
func As(err error, target interface{}) bool {
	return errors.As(err, target)
}

// ErrorChain returns all errors in the error chain
func ErrorChain(err error) []error {
	if err == nil {
		return nil
	}
	
	var chain []error
	for err != nil {
		chain = append(chain, err)
		err = errors.Unwrap(err)
	}
	return chain
}

// SafeClose closes a resource safely, logging any errors
func SafeClose(closer interface{ Close() error }, description string) {
	if closer == nil {
		return
	}
	
	if err := closer.Close(); err != nil {
		// In a real application, you'd log this error
		// For now, we'll just ignore it
		_ = err
	}
}

// Retry retries an operation with exponential backoff
type RetryConfig struct {
	MaxAttempts int
	InitialDelay time.Duration
	MaxDelay     time.Duration
	Multiplier   float64
	ShouldRetry  func(error) bool
}

// DefaultRetryConfig returns a default retry configuration
func DefaultRetryConfig() RetryConfig {
	return RetryConfig{
		MaxAttempts:  3,
		InitialDelay: time.Second,
		MaxDelay:     30 * time.Second,
		Multiplier:   2.0,
		ShouldRetry: func(err error) bool {
			// Retry on network and timeout errors by default
			return Is(err, ErrNetwork) || Is(err, ErrTimeout)
		},
	}
}

// Retry executes an operation with retry logic
func Retry(ctx context.Context, config RetryConfig, operation func() error) error {
	var lastErr error
	delay := config.InitialDelay
	
	for attempt := 0; attempt < config.MaxAttempts; attempt++ {
		// Check context
		if err := ctx.Err(); err != nil {
			return Wrap(err, "context cancelled during retry")
		}
		
		// Try the operation
		if err := operation(); err != nil {
			lastErr = err
			
			// Check if we should retry
			if !config.ShouldRetry(err) {
				return err
			}
			
			// Check if this was the last attempt
			if attempt == config.MaxAttempts-1 {
				break
			}
			
			// Wait before retry
			select {
			case <-time.After(delay):
				// Increase delay for next attempt
				delay = time.Duration(float64(delay) * config.Multiplier)
				if delay > config.MaxDelay {
					delay = config.MaxDelay
				}
			case <-ctx.Done():
				return Wrap(ctx.Err(), "context cancelled during retry delay")
			}
		} else {
			// Success
			return nil
		}
	}
	
	return WrapWithCode(lastErr, "RETRY_EXHAUSTED", 
		fmt.Sprintf("operation failed after %d attempts", config.MaxAttempts))
}

// Must panics if err is not nil
func Must(err error) {
	if err != nil {
		panic(err)
	}
}

// MustValue returns the value or panics if err is not nil
func MustValue[T any](value T, err error) T {
	if err != nil {
		panic(err)
	}
	return value
}

// Ignore explicitly ignores an error (use sparingly)
func Ignore(_ error) {
	// Intentionally empty
}

// FirstError returns the first non-nil error from a list
func FirstError(errs ...error) error {
	for _, err := range errs {
		if err != nil {
			return err
		}
	}
	return nil
}

// ErrorList accumulates multiple errors
type ErrorList struct {
	errors []error
}

// Add adds an error to the list
func (e *ErrorList) Add(err error) {
	if err != nil {
		e.errors = append(e.errors, err)
	}
}

// AddIf conditionally adds an error
func (e *ErrorList) AddIf(condition bool, err error) {
	if condition && err != nil {
		e.errors = append(e.errors, err)
	}
}

// Error returns the combined error message
func (e *ErrorList) Error() string {
	if len(e.errors) == 0 {
		return ""
	}
	
	if len(e.errors) == 1 {
		return e.errors[0].Error()
	}
	
	var messages []string
	for i, err := range e.errors {
		messages = append(messages, fmt.Sprintf("%d. %v", i+1, err))
	}
	return fmt.Sprintf("multiple errors occurred:\n%s", strings.Join(messages, "\n"))
}

// Err returns an error if the list is not empty
func (e *ErrorList) Err() error {
	if len(e.errors) == 0 {
		return nil
	}
	return e
}

// HasErrors returns true if there are any errors
func (e *ErrorList) HasErrors() bool {
	return len(e.errors) > 0
}

// Errors returns the list of errors
func (e *ErrorList) Errors() []error {
	return append([]error(nil), e.errors...)
}

// PanicHandler recovers from panics and converts them to errors
func PanicHandler(errPtr *error) {
	if r := recover(); r != nil {
		if err, ok := r.(error); ok {
			*errPtr = WrapWithCode(err, "PANIC", "panic recovered")
		} else {
			*errPtr = NewError("PANIC", fmt.Sprintf("panic recovered: %v", r), nil)
		}
	}
}

// SafeGo runs a function in a goroutine with panic recovery
func SafeGo(fn func()) {
	go func() {
		defer func() {
			if r := recover(); r != nil {
				// In a real application, you'd log this
				_ = r
			}
		}()
		fn()
	}()
}