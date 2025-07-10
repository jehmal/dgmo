// Package syncutil provides synchronization and context utilities for DGMSTT Go projects
package syncutil

import (
	"context"
	"sync"
	"sync/atomic"
	"time"
)

// ContextKey is a type for context keys to avoid collisions
type ContextKey string

// Common context keys
const (
	RequestIDKey   ContextKey = "request_id"
	UserIDKey      ContextKey = "user_id"
	SessionIDKey   ContextKey = "session_id"
	TraceIDKey     ContextKey = "trace_id"
	CorrelationKey ContextKey = "correlation_id"
)

// WithValue adds a value to context with a typed key
func WithValue(ctx context.Context, key ContextKey, value interface{}) context.Context {
	return context.WithValue(ctx, key, value)
}

// GetValue retrieves a value from context with a typed key
func GetValue[T any](ctx context.Context, key ContextKey) (T, bool) {
	value, ok := ctx.Value(key).(T)
	return value, ok
}

// GetValueOrDefault retrieves a value from context or returns a default
func GetValueOrDefault[T any](ctx context.Context, key ContextKey, defaultValue T) T {
	if value, ok := GetValue[T](ctx, key); ok {
		return value
	}
	return defaultValue
}

// Merge merges multiple contexts, with later contexts taking precedence
func Merge(contexts ...context.Context) context.Context {
	if len(contexts) == 0 {
		return context.Background()
	}
	
	result := contexts[0]
	for i := 1; i < len(contexts); i++ {
		if contexts[i] != nil {
			// This is a simplified merge - in practice you might need more sophisticated merging
			result = contexts[i]
		}
	}
	return result
}

// CancelGroup manages multiple cancellable operations
type CancelGroup struct {
	mu       sync.Mutex
	parent   context.Context
	cancels  []context.CancelFunc
	contexts []context.Context
}

// NewCancelGroup creates a new cancel group
func NewCancelGroup(parent context.Context) *CancelGroup {
	if parent == nil {
		parent = context.Background()
	}
	return &CancelGroup{
		parent: parent,
	}
}

// Create creates a new cancellable context in the group
func (g *CancelGroup) Create() context.Context {
	g.mu.Lock()
	defer g.mu.Unlock()
	
	ctx, cancel := context.WithCancel(g.parent)
	g.cancels = append(g.cancels, cancel)
	g.contexts = append(g.contexts, ctx)
	
	return ctx
}

// CreateWithTimeout creates a new context with timeout in the group
func (g *CancelGroup) CreateWithTimeout(timeout time.Duration) context.Context {
	g.mu.Lock()
	defer g.mu.Unlock()
	
	ctx, cancel := context.WithTimeout(g.parent, timeout)
	g.cancels = append(g.cancels, cancel)
	g.contexts = append(g.contexts, ctx)
	
	return ctx
}

// CancelAll cancels all contexts in the group
func (g *CancelGroup) CancelAll() {
	g.mu.Lock()
	defer g.mu.Unlock()
	
	for _, cancel := range g.cancels {
		cancel()
	}
	
	// Clear the slices
	g.cancels = nil
	g.contexts = nil
}

// Wait waits for all contexts to be done
func (g *CancelGroup) Wait() {
	g.mu.Lock()
	contexts := make([]context.Context, len(g.contexts))
	copy(contexts, g.contexts)
	g.mu.Unlock()
	
	for _, ctx := range contexts {
		<-ctx.Done()
	}
}

// SafeRoutine manages a goroutine with context and panic recovery
type SafeRoutine struct {
	ctx    context.Context
	cancel context.CancelFunc
	done   chan struct{}
	err    atomic.Value
}

// NewSafeRoutine creates a new safe routine
func NewSafeRoutine(ctx context.Context) *SafeRoutine {
	if ctx == nil {
		ctx = context.Background()
	}
	
	ctx, cancel := context.WithCancel(ctx)
	return &SafeRoutine{
		ctx:    ctx,
		cancel: cancel,
		done:   make(chan struct{}),
	}
}

// Run executes the function in a safe goroutine
func (r *SafeRoutine) Run(fn func(context.Context) error) {
	go func() {
		defer close(r.done)
		defer func() {
			if p := recover(); p != nil {
				if err, ok := p.(error); ok {
					r.err.Store(err)
				} else {
					r.err.Store(p)
				}
			}
		}()
		
		if err := fn(r.ctx); err != nil {
			r.err.Store(err)
		}
	}()
}

// Stop stops the routine by cancelling its context
func (r *SafeRoutine) Stop() {
	r.cancel()
}

// Wait waits for the routine to complete
func (r *SafeRoutine) Wait() error {
	<-r.done
	if err := r.err.Load(); err != nil {
		if e, ok := err.(error); ok {
			return e
		}
		// If it's not an error, it was a panic with a non-error value
		return nil
	}
	return nil
}

// StopAndWait stops the routine and waits for completion
func (r *SafeRoutine) StopAndWait() error {
	r.Stop()
	return r.Wait()
}

// Done returns a channel that's closed when the routine completes
func (r *SafeRoutine) Done() <-chan struct{} {
	return r.done
}

// OrDone returns a channel that receives values from c or closes when ctx is done
func OrDone[T any](ctx context.Context, c <-chan T) <-chan T {
	valStream := make(chan T)
	
	go func() {
		defer close(valStream)
		for {
			select {
			case <-ctx.Done():
				return
			case v, ok := <-c:
				if !ok {
					return
				}
				select {
				case valStream <- v:
				case <-ctx.Done():
					return
				}
			}
		}
	}()
	
	return valStream
}

// DoWithTimeout executes a function with a timeout
func DoWithTimeout(timeout time.Duration, fn func() error) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	
	done := make(chan error, 1)
	go func() {
		done <- fn()
	}()
	
	select {
	case <-ctx.Done():
		return ctx.Err()
	case err := <-done:
		return err
	}
}

// RunPeriodic runs a function periodically until the context is cancelled
func RunPeriodic(ctx context.Context, interval time.Duration, fn func() error) error {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	
	// Run immediately
	if err := fn(); err != nil {
		return err
	}
	
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			if err := fn(); err != nil {
				return err
			}
		}
	}
}

// Debounce creates a debounced function that delays invoking fn until after wait duration
// has elapsed since the last time the debounced function was invoked
func Debounce(wait time.Duration, fn func()) func() {
	var mu sync.Mutex
	var timer *time.Timer
	
	return func() {
		mu.Lock()
		defer mu.Unlock()
		
		if timer != nil {
			timer.Stop()
		}
		
		timer = time.AfterFunc(wait, fn)
	}
}

// Throttle creates a throttled function that only invokes fn at most once per duration
func Throttle(duration time.Duration, fn func()) func() {
	var mu sync.Mutex
	var lastCall time.Time
	
	return func() {
		mu.Lock()
		defer mu.Unlock()
		
		now := time.Now()
		if now.Sub(lastCall) >= duration {
			lastCall = now
			fn()
		}
	}
}

// WaitGroup with context support
type ContextWaitGroup struct {
	wg  sync.WaitGroup
	ctx context.Context
}

// NewContextWaitGroup creates a new context-aware wait group
func NewContextWaitGroup(ctx context.Context) *ContextWaitGroup {
	return &ContextWaitGroup{ctx: ctx}
}

// Add adds delta to the wait group counter
func (cwg *ContextWaitGroup) Add(delta int) {
	cwg.wg.Add(delta)
}

// Done decrements the wait group counter
func (cwg *ContextWaitGroup) Done() {
	cwg.wg.Done()
}

// Wait waits for the counter to reach zero or context to be cancelled
func (cwg *ContextWaitGroup) Wait() error {
	done := make(chan struct{})
	go func() {
		cwg.wg.Wait()
		close(done)
	}()
	
	select {
	case <-cwg.ctx.Done():
		return cwg.ctx.Err()
	case <-done:
		return nil
	}
}

// Once ensures a function is only called once, even in concurrent scenarios
type Once struct {
	once sync.Once
	err  error
}

// Do calls the function exactly once and returns its error on all calls
func (o *Once) Do(fn func() error) error {
	o.once.Do(func() {
		o.err = fn()
	})
	return o.err
}