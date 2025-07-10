package tui

// This file contains optimized code fixes for DGMSTT TUI implementation
// These are drop-in replacements for existing code with performance and safety improvements

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea/v2"
	"github.com/sst/dgmo/internal/app"
	"github.com/sst/dgmo/internal/commands"
	"github.com/sst/dgmo/internal/components/chat"
	"github.com/sst/dgmo/internal/components/dialog"
	"github.com/sst/dgmo/internal/components/toast"
	"github.com/sst/dgmo/internal/layout"
	"github.com/sst/dgmo/internal/util"
)

// ============================================================================
// Constants - Replace magic numbers
// ============================================================================

const (
	// Time constants
	ScrollDebounceTime       = 100 * time.Millisecond
	InterruptDebounceTimeout = 1 * time.Second

	// UI dimensions
	DefaultEditorHeight = 5
	MCPPanelHeight      = 6
	MaxEditorWidth      = 80

	// Command capacity
	DefaultCommandCapacity = 8
)

// Pre-defined toast messages to avoid string allocations
var toastMessages = struct {
	MCPEnabled        string
	MCPDisabled       string
	AltScreenEnabled  string
	AltScreenDisabled string
	NavigateNext      string
	NavigatePrev      string
	NoEditorSet       string
	EditorOpenFailed  string
}{
	MCPEnabled:        "MCP panel enabled",
	MCPDisabled:       "MCP panel disabled",
	AltScreenEnabled:  "Fullscreen mode enabled",
	AltScreenDisabled: "Fullscreen mode disabled",
	NavigateNext:      "Press . for next or , for previous sibling",
	NavigatePrev:      "Navigate to previous sibling",
	NoEditorSet:       "No EDITOR set, can't open editor",
	EditorOpenFailed:  "Something went wrong, couldn't open editor",
}

// ============================================================================
// Helper Functions
// ============================================================================

// hasValidSession checks if the app has a valid session
func (a *appModel) hasValidSession() bool {
	return a.app != nil && a.app.Session != nil && a.app.Session.ID != ""
}

// isSessionMatch checks if the message session ID matches current session
func (a *appModel) isSessionMatch(sessionID string) bool {
	if !a.hasValidSession() || sessionID == "" {
		return false
	}
	return sessionID == a.app.Session.ID
}

// updateComponentSafe safely updates a component with type checking
func updateComponentSafe[T tea.Model](component T, msg tea.Msg) (T, tea.Cmd, error) {
	var zero T
	updated, cmd := component.Update(msg)

	typedComponent, ok := updated.(T)
	if !ok {
		return zero, nil, fmt.Errorf("type assertion failed: expected %T, got %T", zero, updated)
	}

	return typedComponent, cmd, nil
}

// ============================================================================
// Command Pipeline for efficient batching
// ============================================================================

type CommandPipeline struct {
	cmds []tea.Cmd
	mu   sync.Mutex
}

func NewCommandPipeline(capacity int) *CommandPipeline {
	return &CommandPipeline{
		cmds: make([]tea.Cmd, 0, capacity),
	}
}

func (cp *CommandPipeline) Add(cmd tea.Cmd) {
	if cmd == nil {
		return
	}

	cp.mu.Lock()
	defer cp.mu.Unlock()
	cp.cmds = append(cp.cmds, cmd)
}

func (cp *CommandPipeline) AddMultiple(cmds ...tea.Cmd) {
	cp.mu.Lock()
	defer cp.mu.Unlock()

	for _, cmd := range cmds {
		if cmd != nil {
			cp.cmds = append(cp.cmds, cmd)
		}
	}
}

func (cp *CommandPipeline) Batch() tea.Cmd {
	cp.mu.Lock()
	defer cp.mu.Unlock()

	if len(cp.cmds) == 0 {
		return nil
	}

	// Create a copy to avoid race conditions
	cmdsCopy := make([]tea.Cmd, len(cp.cmds))
	copy(cmdsCopy, cp.cmds)

	return tea.Batch(cmdsCopy...)
}

// ============================================================================
// Optimized Update Method
// ============================================================================

// OptimizedUpdate is a performance-optimized version of the Update method
func (a appModel) OptimizedUpdate(msg tea.Msg) (tea.Model, tea.Cmd) {
	// Pre-allocate command pipeline
	pipeline := NewCommandPipeline(DefaultCommandCapacity)

	switch msg := msg.(type) {
	case tea.KeyPressMsg:
		return a.handleKeyPress(msg, pipeline)

	case tea.WindowSizeMsg:
		return a.handleWindowSize(msg, pipeline)

	case tea.MouseWheelMsg:
		return a.handleMouseWheel(msg, pipeline)

		// Add other message types...
	}

	return a, pipeline.Batch()
}

// handleKeyPress processes key press events with optimizations
func (a appModel) handleKeyPress(msg tea.KeyPressMsg, pipeline *CommandPipeline) (tea.Model, tea.Cmd) {
	keyString := msg.String()

	// Debounce scroll keys
	if time.Since(a.lastScroll) < ScrollDebounceTime && BUGGED_SCROLL_KEYS[keyString] {
		return a, nil
	}

	// Handle modal if active
	if a.modal != nil {
		return a.handleModalKeyPress(keyString, msg)
	}

	// Use key handler map for special keys
	if handler, exists := keyHandlers[keyString]; exists {
		return handler(&a)
	}

	// Handle leader sequences
	if a.isLeaderSequence {
		return a.handleLeaderSequence(msg)
	}

	// Handle printable characters with priority
	if msg.Text != "" {
		return a.handlePrintableChar(msg, pipeline)
	}

	// Default to editor update
	return a.updateEditor(msg, pipeline)
}

// Key handler map for better performance
var keyHandlers = map[string]func(*appModel) (tea.Model, tea.Cmd){
	"shift+tab": handleAltScreenToggle,
	"ctrl+m":    handleMCPToggle,
	"ctrl+b":    handleNavigationStart,
	"/":         handleCompletionTrigger,
}

func handleAltScreenToggle(a *appModel) (tea.Model, tea.Cmd) {
	a.isAltScreen = !a.isAltScreen

	var cmd tea.Cmd
	var toastMsg string

	if a.isAltScreen {
		cmd = tea.EnterAltScreen
		toastMsg = toastMessages.AltScreenEnabled
	} else {
		cmd = tea.ExitAltScreen
		toastMsg = toastMessages.AltScreenDisabled
	}

	return *a, tea.Batch(cmd, toast.NewInfoToast(toastMsg))
}

func handleMCPToggle(a *appModel) (tea.Model, tea.Cmd) {
	a.showMCPPanel = !a.showMCPPanel
	a.mcpPanel.SetVisible(a.showMCPPanel)

	toastMsg := toastMessages.MCPDisabled
	if a.showMCPPanel {
		toastMsg = toastMessages.MCPEnabled
	}

	return *a, toast.NewInfoToast(toastMsg)
}

// ============================================================================
// Optimized String Operations
// ============================================================================

// extractLastWord efficiently extracts the last word from input
func extractLastWord(input string) string {
	if input == "" || strings.HasSuffix(input, " ") {
		return ""
	}

	// Find last space without splitting entire string
	lastSpaceIdx := strings.LastIndex(input, " ")
	if lastSpaceIdx == -1 {
		return input
	}

	return input[lastSpaceIdx+1:]
}

// optimizedCompletionValue builds completion value efficiently
func (a *appModel) optimizedCompletionValue() string {
	currentInput := a.editor.Value()
	lastWord := extractLastWord(currentInput)

	if lastWord == "" {
		return "/"
	}

	return lastWord + "/"
}

// ============================================================================
// Secure Editor Opening
// ============================================================================

// List of allowed editors for security
var allowedEditors = map[string]bool{
	"vim":     true,
	"nvim":    true,
	"emacs":   true,
	"nano":    true,
	"code":    true,
	"subl":    true,
	"atom":    true,
	"gedit":   true,
	"kate":    true,
	"notepad": true,
}

// isValidEditor checks if the editor is in the allowed list
func isValidEditor(editor string) bool {
	// Extract base command (handle paths like /usr/bin/vim)
	parts := strings.Split(editor, "/")
	baseName := parts[len(parts)-1]

	// Remove any arguments
	baseName = strings.Split(baseName, " ")[0]

	return allowedEditors[baseName]
}

// secureOpenEditor opens an editor with security checks
func (a appModel) secureOpenEditor() (tea.Model, tea.Cmd) {
	if a.app.IsBusy() {
		return a, nil
	}

	editor := os.Getenv("EDITOR")
	if editor == "" {
		return a, toast.NewErrorToast(toastMessages.NoEditorSet)
	}

	if !isValidEditor(editor) {
		return a, toast.NewErrorToast("Invalid editor specified")
	}

	value := a.editor.Value()

	// Clear editor first
	updated, clearCmd := a.editor.Clear()
	a.editor = updated.(chat.EditorComponent)

	// Create secure temp file
	tmpfile, err := os.CreateTemp("", "dgmo_msg_*.md")
	if err != nil {
		return a, toast.NewErrorToast(toastMessages.EditorOpenFailed)
	}

	// Set secure permissions immediately
	if err := tmpfile.Chmod(0600); err != nil {
		os.Remove(tmpfile.Name())
		return a, toast.NewErrorToast("Failed to secure temp file")
	}

	// Write content
	if _, err := tmpfile.WriteString(value); err != nil {
		os.Remove(tmpfile.Name())
		return a, toast.NewErrorToast(toastMessages.EditorOpenFailed)
	}
	tmpfile.Close()

	// Prepare command with proper escaping
	cmd := exec.Command(editor, tmpfile.Name())
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	execCmd := tea.ExecProcess(cmd, func(err error) tea.Msg {
		defer os.Remove(tmpfile.Name()) // Always cleanup

		if err != nil {
			return toast.NewErrorToast("Editor failed: " + err.Error())
		}

		// Read the edited content
		content, readErr := os.ReadFile(tmpfile.Name())
		if readErr != nil {
			return toast.NewErrorToast("Failed to read edited content")
		}

		return app.EditorFinishedMsg{
			Content: string(content),
		}
	})

	return a, tea.Batch(clearCmd, execCmd)
}

// ============================================================================
// Error Types for Better Error Handling
// ============================================================================

type TUIError struct {
	Op      string    // Operation that failed
	Kind    ErrorKind // Type of error
	Err     error     // Underlying error
	Context string    // Additional context
}

type ErrorKind int

const (
	ErrorKindValidation ErrorKind = iota
	ErrorKindIO
	ErrorKindTypeAssertion
	ErrorKindNullPointer
	ErrorKindSecurity
)

func (e *TUIError) Error() string {
	if e.Context != "" {
		return fmt.Sprintf("%s: %s (%s): %v", e.Op, e.Kind, e.Context, e.Err)
	}
	return fmt.Sprintf("%s: %s: %v", e.Op, e.Kind, e.Err)
}

func (e *TUIError) Unwrap() error {
	return e.Err
}

// ============================================================================
// Message Pool for High-Frequency Messages
// ============================================================================

var toastMessagePool = sync.Pool{
	New: func() interface{} {
		return &toast.ShowToastMsg{}
	},
}

func getPooledToastMessage(message, toastType string) *toast.ShowToastMsg {
	msg := toastMessagePool.Get().(*toast.ShowToastMsg)
	msg.Message = message
	msg.Type = toastType
	msg.Duration = 3 * time.Second
	return msg
}

func releaseToastMessage(msg *toast.ShowToastMsg) {
	msg.Message = ""
	msg.Type = ""
	msg.Duration = 0
	toastMessagePool.Put(msg)
}
