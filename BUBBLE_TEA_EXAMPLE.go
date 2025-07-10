package main

// Example Bubble Tea application demonstrating key concepts used in DGMSTT
// This is a simplified version showing the patterns without all dependencies

import (
	"fmt"
	"strings"
	"time"
)

// ============================================================================
// Core Bubble Tea Types (simplified for demonstration)
// ============================================================================

// Msg can be any type - it represents an event
type Msg interface{}

// Model represents the application state
type Model interface {
	Init() Cmd
	Update(Msg) (Model, Cmd)
	View() string
}

// Cmd is a function that performs I/O and returns a message
type Cmd func() Msg

// ============================================================================
// Message Types (similar to DGMSTT's message patterns)
// ============================================================================

// Key press message
type KeyMsg struct {
	Type  string
	Runes []rune
}

// Window size change
type WindowSizeMsg struct {
	Width  int
	Height int
}

// Task-related messages (like DGMSTT's task system)
type TaskStartedMsg struct {
	TaskID      string
	Description string
}

type TaskProgressMsg struct {
	TaskID   string
	Progress int
	Message  string
}

type TaskCompletedMsg struct {
	TaskID   string
	Duration time.Duration
	Success  bool
}

// Toast messages for notifications
type ShowToastMsg struct {
	Message  string
	Type     string // "info", "success", "error"
	Duration time.Duration
}

// Custom application messages
type SendMessageMsg struct {
	Text string
}

type ToggleMCPPanelMsg struct{}

type QuitMsg struct{}

// ============================================================================
// Main Application Model (simplified version of DGMSTT's appModel)
// ============================================================================

type AppModel struct {
	// Dimensions
	width  int
	height int

	// Components
	messages     []Message
	editor       EditorComponent
	status       StatusComponent
	mcpPanel     MCPPanelComponent
	toastManager ToastManager

	// State
	showMCPPanel bool
	isBusy       bool
	currentTask  *TaskInfo

	// Key sequence tracking (like DGMSTT)
	isLeaderSequence bool
	isCtrlBSequence  bool
}

// Message in the chat
type Message struct {
	ID        string
	Content   string
	Role      string // "user", "assistant"
	Timestamp time.Time
}

// Task information
type TaskInfo struct {
	ID          string
	Description string
	Progress    int
	StartTime   time.Time
}

// ============================================================================
// Component Interfaces (following DGMSTT's pattern)
// ============================================================================

type EditorComponent struct {
	value       string
	cursorPos   int
	placeholder string
}

func (e *EditorComponent) Update(msg Msg) {
	switch msg := msg.(type) {
	case KeyMsg:
		if msg.Type == "character" {
			e.value += string(msg.Runes)
			e.cursorPos = len(e.value)
		} else if msg.Type == "backspace" && len(e.value) > 0 {
			e.value = e.value[:len(e.value)-1]
			e.cursorPos = len(e.value)
		}
	}
}

func (e *EditorComponent) View() string {
	if e.value == "" {
		return fmt.Sprintf("> %s", e.placeholder)
	}
	return fmt.Sprintf("> %s█", e.value)
}

func (e *EditorComponent) Clear() {
	e.value = ""
	e.cursorPos = 0
}

type StatusComponent struct {
	width            int
	connectionStatus string
	taskInfo         *TaskInfo
}

func (s *StatusComponent) View() string {
	status := "Ready"
	if s.taskInfo != nil {
		status = fmt.Sprintf("Task: %s (%d%%)", s.taskInfo.Description, s.taskInfo.Progress)
	}

	connection := fmt.Sprintf("Connection: %s", s.connectionStatus)

	// Simple status bar
	return fmt.Sprintf("[ %s | %s ]", status, connection)
}

type MCPPanelComponent struct {
	visible bool
	calls   []MCPCall
}

type MCPCall struct {
	ID        string
	Tool      string
	Status    string
	Timestamp time.Time
}

func (m *MCPPanelComponent) View() string {
	if !m.visible {
		return ""
	}

	lines := []string{"=== MCP Panel ==="}
	for _, call := range m.calls {
		lines = append(lines, fmt.Sprintf("  %s: %s [%s]", call.Tool, call.Status, call.ID[:8]))
	}
	return strings.Join(lines, "\n")
}

type ToastManager struct {
	toasts []Toast
}

type Toast struct {
	Message   string
	Type      string
	ExpiresAt time.Time
}

func (t *ToastManager) AddToast(msg string, toastType string) {
	t.toasts = append(t.toasts, Toast{
		Message:   msg,
		Type:      toastType,
		ExpiresAt: time.Now().Add(3 * time.Second),
	})
}

func (t *ToastManager) View() string {
	now := time.Now()
	var activeToasts []string

	// Remove expired toasts
	var newToasts []Toast
	for _, toast := range t.toasts {
		if toast.ExpiresAt.After(now) {
			newToasts = append(newToasts, toast)
			prefix := "ℹ️"
			if toast.Type == "error" {
				prefix = "❌"
			} else if toast.Type == "success" {
				prefix = "✅"
			}
			activeToasts = append(activeToasts, fmt.Sprintf("%s %s", prefix, toast.Message))
		}
	}
	t.toasts = newToasts

	if len(activeToasts) == 0 {
		return ""
	}

	return strings.Join(activeToasts, "\n")
}

// ============================================================================
// Main Model Implementation
// ============================================================================

func NewAppModel() AppModel {
	return AppModel{
		width:  80,
		height: 24,
		editor: EditorComponent{
			placeholder: "Type a message...",
		},
		status: StatusComponent{
			connectionStatus: "Connected",
		},
		mcpPanel: MCPPanelComponent{
			visible: false,
			calls:   []MCPCall{},
		},
		toastManager: ToastManager{},
		messages:     []Message{},
	}
}

func (m AppModel) Init() Cmd {
	// Return initial commands to run
	return Batch(
		// Simulate connecting to server
		func() Msg {
			time.Sleep(100 * time.Millisecond)
			return ShowToastMsg{
				Message: "Connected to server",
				Type:    "success",
			}
		},
	)
}

func (m AppModel) Update(msg Msg) (Model, Cmd) {
	var cmds []Cmd

	switch msg := msg.(type) {
	case KeyMsg:
		// Handle key sequences like DGMSTT

		// 1. Check for quit
		if msg.Type == "ctrl+c" {
			return m, Quit
		}

		// 2. Handle leader sequences
		if m.isLeaderSequence {
			m.isLeaderSequence = false
			// Handle leader + key combinations
			return m, nil
		}

		// 3. Handle Ctrl+B sequences (navigation)
		if m.isCtrlBSequence {
			m.isCtrlBSequence = false
			switch msg.Type {
			case ".":
				cmds = append(cmds, func() Msg {
					return ShowToastMsg{Message: "Navigate to next sibling", Type: "info"}
				})
			case ",":
				cmds = append(cmds, func() Msg {
					return ShowToastMsg{Message: "Navigate to previous sibling", Type: "info"}
				})
			}
			return m, Batch(cmds...)
		}

		// 4. Special key handling
		switch msg.Type {
		case "ctrl+m":
			// Toggle MCP panel
			m.showMCPPanel = !m.showMCPPanel
			m.mcpPanel.visible = m.showMCPPanel
			toastMsg := "MCP panel enabled"
			if !m.showMCPPanel {
				toastMsg = "MCP panel disabled"
			}
			cmds = append(cmds, func() Msg {
				return ShowToastMsg{Message: toastMsg, Type: "info"}
			})

		case "ctrl+b":
			// Start navigation sequence
			m.isCtrlBSequence = true
			cmds = append(cmds, func() Msg {
				return ShowToastMsg{Message: "Press . for next or , for previous", Type: "info"}
			})

		case "enter":
			// Send message
			if m.editor.value != "" && !m.isBusy {
				cmds = append(cmds, func() Msg {
					return SendMessageMsg{Text: m.editor.value}
				})
			}

		default:
			// Update editor
			m.editor.Update(msg)
		}

	case WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		m.status.width = msg.Width

	case SendMessageMsg:
		// Add user message
		m.messages = append(m.messages, Message{
			ID:        fmt.Sprintf("msg-%d", len(m.messages)),
			Content:   msg.Text,
			Role:      "user",
			Timestamp: time.Now(),
		})
		m.editor.Clear()

		// Simulate starting a task
		taskID := fmt.Sprintf("task-%d", time.Now().Unix())
		cmds = append(cmds, func() Msg {
			return TaskStartedMsg{
				TaskID:      taskID,
				Description: "Processing message",
			}
		})

	case TaskStartedMsg:
		m.isBusy = true
		m.currentTask = &TaskInfo{
			ID:          msg.TaskID,
			Description: msg.Description,
			Progress:    0,
			StartTime:   time.Now(),
		}
		m.status.taskInfo = m.currentTask

		// Simulate task progress
		cmds = append(cmds, simulateTaskProgress(msg.TaskID))

	case TaskProgressMsg:
		if m.currentTask != nil && m.currentTask.ID == msg.TaskID {
			m.currentTask.Progress = msg.Progress

			// Add MCP call to panel
			if m.mcpPanel.visible {
				m.mcpPanel.calls = append(m.mcpPanel.calls, MCPCall{
					ID:        msg.TaskID,
					Tool:      "process",
					Status:    fmt.Sprintf("%d%%", msg.Progress),
					Timestamp: time.Now(),
				})
			}
		}

	case TaskCompletedMsg:
		m.isBusy = false
		m.currentTask = nil
		m.status.taskInfo = nil

		// Add assistant response
		m.messages = append(m.messages, Message{
			ID:        fmt.Sprintf("msg-%d", len(m.messages)),
			Content:   "Task completed successfully!",
			Role:      "assistant",
			Timestamp: time.Now(),
		})

		// Show completion toast
		cmds = append(cmds, func() Msg {
			return ShowToastMsg{
				Message: "Task completed",
				Type:    "success",
			}
		})

	case ShowToastMsg:
		m.toastManager.AddToast(msg.Message, msg.Type)

	case QuitMsg:
		// Cleanup and exit
		return m, Quit
	}

	return m, Batch(cmds...)
}

func (m AppModel) View() string {
	var lines []string

	// Header
	lines = append(lines, strings.Repeat("=", m.width))
	lines = append(lines, "DGMO - Bubble Tea Example")
	lines = append(lines, strings.Repeat("=", m.width))

	// Messages
	lines = append(lines, "")
	for _, msg := range m.messages {
		prefix := "You: "
		if msg.Role == "assistant" {
			prefix = "Assistant: "
		}
		lines = append(lines, fmt.Sprintf("%s%s", prefix, msg.Content))
	}

	// Fill space
	usedLines := len(lines) + 5 // account for editor, status, etc
	if m.mcpPanel.visible {
		usedLines += 5
	}
	for i := usedLines; i < m.height-5; i++ {
		lines = append(lines, "")
	}

	// MCP Panel (if visible)
	if m.mcpPanel.visible {
		lines = append(lines, m.mcpPanel.View())
	}

	// Editor
	lines = append(lines, "")
	lines = append(lines, m.editor.View())
	lines = append(lines, "")

	// Status bar
	lines = append(lines, m.status.View())

	// Toast overlay
	if toastView := m.toastManager.View(); toastView != "" {
		// Overlay toasts at the top
		toastLines := strings.Split(toastView, "\n")
		for i, toast := range toastLines {
			if i < len(lines)-5 {
				lines[i+3] = toast + strings.Repeat(" ", m.width-len(toast))
			}
		}
	}

	return strings.Join(lines, "\n")
}

// ============================================================================
// Helper Functions
// ============================================================================

// Batch runs multiple commands in parallel
func Batch(cmds ...Cmd) Cmd {
	return func() Msg {
		// In real Bubble Tea, this would run commands concurrently
		// For this example, we'll just run the first one
		if len(cmds) > 0 {
			return cmds[0]()
		}
		return nil
	}
}

// Quit command
var Quit = func() Msg {
	return QuitMsg{}
}

// Simulate task progress
func simulateTaskProgress(taskID string) Cmd {
	return func() Msg {
		// In a real app, this would be async
		go func() {
			for i := 0; i <= 100; i += 20 {
				time.Sleep(500 * time.Millisecond)
				// In real Bubble Tea, you'd use Program.Send() here
				// For this example, we'll just show the concept
			}
		}()

		// Return a progress message
		return TaskProgressMsg{
			TaskID:   taskID,
			Progress: 20,
			Message:  "Processing...",
		}
	}
}

// ============================================================================
// Main Function (demonstration only - won't run without full Bubble Tea)
// ============================================================================

func main() {
	// This is how you would initialize a Bubble Tea program:
	//
	// p := tea.NewProgram(
	//     NewAppModel(),
	//     tea.WithAltScreen(),       // Use alternate screen buffer
	//     tea.WithMouseCellMotion(), // Enable mouse support
	// )
	//
	// if _, err := p.Run(); err != nil {
	//     fmt.Printf("Error: %v", err)
	//     os.Exit(1)
	// }

	fmt.Println("This is a demonstration of Bubble Tea patterns used in DGMSTT")
	fmt.Println("See BUBBLE_TEA_EXPERT_GUIDE.md for the full explanation")
}
