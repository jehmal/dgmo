// Package testutil provides test utilities and helpers for DGMSTT Go projects
package testutil

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

// TempDir creates a temporary directory for testing
func TempDir(t *testing.T, prefix string) string {
	t.Helper()
	
	dir, err := os.MkdirTemp("", prefix)
	if err != nil {
		t.Fatalf("Failed to create temp dir: %v", err)
	}
	
	t.Cleanup(func() {
		os.RemoveAll(dir)
	})
	
	return dir
}

// TempFile creates a temporary file with content
func TempFile(t *testing.T, dir, pattern string, content []byte) string {
	t.Helper()
	
	file, err := os.CreateTemp(dir, pattern)
	if err != nil {
		t.Fatalf("Failed to create temp file: %v", err)
	}
	defer file.Close()
	
	if len(content) > 0 {
		if _, err := file.Write(content); err != nil {
			t.Fatalf("Failed to write to temp file: %v", err)
		}
	}
	
	return file.Name()
}

// AssertEqual asserts that two values are equal
func AssertEqual(t *testing.T, got, want interface{}, msgAndArgs ...interface{}) {
	t.Helper()
	
	if !reflect.DeepEqual(got, want) {
		msg := fmt.Sprintf("Not equal:\ngot:  %+v\nwant: %+v", got, want)
		if len(msgAndArgs) > 0 {
			msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...) + "\n" + msg
		}
		t.Errorf(msg)
	}
}

// AssertNotEqual asserts that two values are not equal
func AssertNotEqual(t *testing.T, got, notWant interface{}, msgAndArgs ...interface{}) {
	t.Helper()
	
	if reflect.DeepEqual(got, notWant) {
		msg := fmt.Sprintf("Should not be equal: %+v", got)
		if len(msgAndArgs) > 0 {
			msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...) + "\n" + msg
		}
		t.Errorf(msg)
	}
}

// AssertNil asserts that a value is nil
func AssertNil(t *testing.T, value interface{}, msgAndArgs ...interface{}) {
	t.Helper()
	
	if !isNil(value) {
		msg := fmt.Sprintf("Expected nil but got: %+v", value)
		if len(msgAndArgs) > 0 {
			msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...) + "\n" + msg
		}
		t.Errorf(msg)
	}
}

// AssertNotNil asserts that a value is not nil
func AssertNotNil(t *testing.T, value interface{}, msgAndArgs ...interface{}) {
	t.Helper()
	
	if isNil(value) {
		msg := "Expected non-nil value"
		if len(msgAndArgs) > 0 {
			msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...) + "\n" + msg
		}
		t.Errorf(msg)
	}
}

// AssertError asserts that an error occurred
func AssertError(t *testing.T, err error, msgAndArgs ...interface{}) {
	t.Helper()
	
	if err == nil {
		msg := "Expected error but got nil"
		if len(msgAndArgs) > 0 {
			msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...) + "\n" + msg
		}
		t.Errorf(msg)
	}
}

// AssertNoError asserts that no error occurred
func AssertNoError(t *testing.T, err error, msgAndArgs ...interface{}) {
	t.Helper()
	
	if err != nil {
		msg := fmt.Sprintf("Unexpected error: %v", err)
		if len(msgAndArgs) > 0 {
			msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...) + "\n" + msg
		}
		t.Errorf(msg)
	}
}

// AssertContains asserts that a string contains a substring
func AssertContains(t *testing.T, s, substr string, msgAndArgs ...interface{}) {
	t.Helper()
	
	if !strings.Contains(s, substr) {
		msg := fmt.Sprintf("String does not contain substring:\nString: %s\nSubstring: %s", s, substr)
		if len(msgAndArgs) > 0 {
			msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...) + "\n" + msg
		}
		t.Errorf(msg)
	}
}

// AssertTrue asserts that a value is true
func AssertTrue(t *testing.T, value bool, msgAndArgs ...interface{}) {
	t.Helper()
	
	if !value {
		msg := "Expected true but got false"
		if len(msgAndArgs) > 0 {
			msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...)
		}
		t.Errorf(msg)
	}
}

// AssertFalse asserts that a value is false
func AssertFalse(t *testing.T, value bool, msgAndArgs ...interface{}) {
	t.Helper()
	
	if value {
		msg := "Expected false but got true"
		if len(msgAndArgs) > 0 {
			msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...)
		}
		t.Errorf(msg)
	}
}

// AssertEventually asserts that a condition is eventually true
func AssertEventually(t *testing.T, condition func() bool, timeout time.Duration, interval time.Duration, msgAndArgs ...interface{}) {
	t.Helper()
	
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(interval)
	}
	
	msg := fmt.Sprintf("Condition not met within %v", timeout)
	if len(msgAndArgs) > 0 {
		msg = fmt.Sprintf(msgAndArgs[0].(string), msgAndArgs[1:]...) + "\n" + msg
	}
	t.Errorf(msg)
}

// isNil checks if a value is nil, handling interface nil checks
func isNil(value interface{}) bool {
	if value == nil {
		return true
	}
	
	v := reflect.ValueOf(value)
	switch v.Kind() {
	case reflect.Chan, reflect.Func, reflect.Interface, reflect.Map, reflect.Ptr, reflect.Slice:
		return v.IsNil()
	}
	
	return false
}

// MockHTTPServer creates a mock HTTP server for testing
type MockHTTPServer struct {
	*httptest.Server
	Requests []RecordedRequest
}

// RecordedRequest represents a recorded HTTP request
type RecordedRequest struct {
	Method  string
	Path    string
	Headers http.Header
	Body    []byte
}

// NewMockHTTPServer creates a new mock HTTP server
func NewMockHTTPServer(t *testing.T, handler http.HandlerFunc) *MockHTTPServer {
	t.Helper()
	
	mock := &MockHTTPServer{
		Requests: make([]RecordedRequest, 0),
	}
	
	// Wrap the handler to record requests
	wrappedHandler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		r.Body = io.NopCloser(bytes.NewReader(body))
		
		mock.Requests = append(mock.Requests, RecordedRequest{
			Method:  r.Method,
			Path:    r.URL.Path,
			Headers: r.Header.Clone(),
			Body:    body,
		})
		
		handler(w, r)
	})
	
	mock.Server = httptest.NewServer(wrappedHandler)
	
	t.Cleanup(func() {
		mock.Server.Close()
	})
	
	return mock
}

// GetRequest returns a specific recorded request
func (m *MockHTTPServer) GetRequest(index int) *RecordedRequest {
	if index < 0 || index >= len(m.Requests) {
		return nil
	}
	return &m.Requests[index]
}

// LastRequest returns the last recorded request
func (m *MockHTTPServer) LastRequest() *RecordedRequest {
	if len(m.Requests) == 0 {
		return nil
	}
	return &m.Requests[len(m.Requests)-1]
}

// JSONResponse creates an HTTP handler that responds with JSON
func JSONResponse(statusCode int, body interface{}) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(statusCode)
		json.NewEncoder(w).Encode(body)
	}
}

// SkipIfShort skips a test if testing.Short() is true
func SkipIfShort(t *testing.T) {
	if testing.Short() {
		t.Skip("Skipping test in short mode")
	}
}

// SkipIfCI skips a test if running in CI environment
func SkipIfCI(t *testing.T) {
	if os.Getenv("CI") != "" {
		t.Skip("Skipping test in CI environment")
	}
}

// RequireEnv skips a test if an environment variable is not set
func RequireEnv(t *testing.T, envVar string) string {
	t.Helper()
	
	value := os.Getenv(envVar)
	if value == "" {
		t.Skipf("Skipping test: %s environment variable not set", envVar)
	}
	
	return value
}

// Context creates a test context that is cancelled when the test ends
func Context(t *testing.T) context.Context {
	t.Helper()
	
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	
	return ctx
}

// Parallel runs subtests in parallel
func Parallel(t *testing.T, tests map[string]func(t *testing.T)) {
	for name, test := range tests {
		name, test := name, test // capture range variables
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			test(t)
		})
	}
}

// GoldenFile compares output with a golden file
func GoldenFile(t *testing.T, got []byte, goldenPath string, update bool) {
	t.Helper()
	
	if update {
		dir := filepath.Dir(goldenPath)
		if err := os.MkdirAll(dir, 0755); err != nil {
			t.Fatalf("Failed to create golden file directory: %v", err)
		}
		
		if err := os.WriteFile(goldenPath, got, 0644); err != nil {
			t.Fatalf("Failed to update golden file: %v", err)
		}
		return
	}
	
	want, err := os.ReadFile(goldenPath)
	if err != nil {
		t.Fatalf("Failed to read golden file: %v", err)
	}
	
	if !bytes.Equal(got, want) {
		t.Errorf("Output does not match golden file %s", goldenPath)
		t.Errorf("Got:\n%s", got)
		t.Errorf("Want:\n%s", want)
	}
}

// Benchmark provides a simple benchmarking helper
func Benchmark(b *testing.B, fn func()) {
	b.Helper()
	b.ResetTimer()
	
	for i := 0; i < b.N; i++ {
		fn()
	}
}

// MustJSON marshals a value to JSON or fails the test
func MustJSON(t *testing.T, v interface{}) string {
	t.Helper()
	
	data, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("Failed to marshal to JSON: %v", err)
	}
	
	return string(data)
}

// MustUnmarshalJSON unmarshals JSON or fails the test
func MustUnmarshalJSON(t *testing.T, data string, v interface{}) {
	t.Helper()
	
	if err := json.Unmarshal([]byte(data), v); err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}
}