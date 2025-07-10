# Bubble Tea Framework Expert Guide for DGMSTT

## Table of Contents

1. [Bubble Tea Framework Overview](#bubble-tea-framework-overview)
2. [Core Concepts](#core-concepts)
3. [DGMSTT Architecture](#dgmstt-architecture)
4. [Component Patterns](#component-patterns)
5. [Message Flow](#message-flow)
6. [Best Practices](#best-practices)
7. [Advanced Patterns](#advanced-patterns)

## Bubble Tea Framework Overview

Bubble Tea is a Go framework for building terminal user interfaces (TUIs) based on The Elm
Architecture. It provides a functional, stateful way to build both simple and complex terminal
applications.

### Key Features

- **Functional Design**: Based on The Elm Architecture paradigm
- **Event-Driven**: All interactions are handled through messages
- **Composable**: Components can be nested and combined
- **Performance Optimized**: Includes framerate-based rendering and efficient updates
- **Feature-Rich**: Mouse support, alternate screen mode, focus reporting, and more

## Core Concepts

### 1. The Model-Update-View Pattern

Bubble Tea applications consist of three core components:

```go
type Model interface {
    Init() Cmd                      // Initialize and return initial commands
    Update(Msg) (Model, Cmd)        // Handle messages and update state
    View() string                   // Render the UI as a string
}
```

### 2. Messages (Msg)

Messages are events that trigger updates. They can be any type:

```go
type Msg interface{}

// Examples from DGMSTT:
type TaskStartedMsg struct {
    Task TaskInfo
}

type InterruptDebounceTimeoutMsg struct{}
```

### 3. Commands (Cmd)

Commands are functions that perform I/O and return messages:

```go
type Cmd func() Msg

// Example: Async operation
func fetchData() tea.Cmd {
    return func() tea.Msg {
        data, err := api.GetData()
        if err != nil {
            return ErrorMsg{err}
        }
        return DataFetchedMsg{data}
    }
}
```

## DGMSTT Architecture

### Application Structure

```
opencode/packages/tui/
├── cmd/dgmo/main.go          # Entry point
├── internal/
│   ├── tui/tui.go           # Main TUI model
│   ├── app/                  # Application logic
│   ├── components/           # Reusable UI components
│   │   ├── chat/            # Chat interface components
│   │   ├── dialog/          # Modal dialogs
│   │   ├── status/          # Status bar
│   │   ├── toast/           # Toast notifications
│   │   └── mcp/             # MCP panel
│   └── websocket/           # WebSocket integration
```

### Main Application Model

```go
type appModel struct {
    width, height int
    app           *app.App
    modal         layout.Modal
    status        status.StatusComponent
    editor        chat.EditorComponent
    messages      chat.MessagesComponent
    mcpPanel      mcp.MCPPanelComponent

    // Dialog states
    completions          dialog.CompletionDialog
    showCompletionDialog bool
    showMCPPanel         bool

    // Key sequence tracking
    isLeaderSequence  bool
    isCtrlBSequence   bool
    isAltScreen       bool

    // Managers
    toastManager     *toast.ToastManager
    clipboardManager *clipboard.ClipboardManager
}
```

## Component Patterns

### 1. Component Interface Pattern

DGMSTT defines interfaces for all major components:

```go
type EditorComponent interface {
    tea.Model
    SetSize(width, height int) tea.Cmd
    View(width int, align lipgloss.Position) string
    Content(width int, align lipgloss.Position) string
    Lines() int
    Value() string
    Focused() bool
    Focus() (tea.Model, tea.Cmd)
    Blur()
    Submit() (tea.Model, tea.Cmd)
    Clear() (tea.Model, tea.Cmd)
}
```

### 2. Component Composition

Components are composed hierarchically:

```go
func (a appModel) View() string {
    mainLayout := a.chat(layout.Current.Container.Width, lipgloss.Center)

    // Layer modals on top
    if a.modal != nil {
        mainLayout = a.modal.Render(mainLayout)
    }

    // Add toast overlay
    mainLayout = a.toastManager.RenderOverlay(mainLayout)

    // Add status bar at bottom
    return mainLayout + "\n" + a.status.View()
}
```

### 3. Layout System

DGMSTT uses a flexible layout system:

```go
layoutItems := []layout.FlexItem{
    {
        View: messagesView,
        Grow: true,  // Takes remaining space
    },
    {
        View:      mcpPanelView,
        FixedSize: 6,  // Fixed height
    },
    {
        View:      editorView,
        FixedSize: 5,  // Fixed height
    },
}

mainLayout := layout.Render(
    layout.FlexOptions{
        Direction: layout.Column,
        Width:     a.width,
        Height:    a.height,
    },
    layoutItems...,
)
```

## Message Flow

### 1. External Events

WebSocket events are converted to messages:

```go
// In main.go
taskClient := app.NewTaskClient(app.TaskEventHandlers{
    OnTaskStarted: func(task app.TaskInfo) {
        program.Send(app.TaskStartedMsg{Task: task})
    },
    OnTaskProgress: func(sessionID, taskID string, progress int, message string) {
        program.Send(app.TaskProgressMsg{
            SessionID: sessionID,
            TaskID:    taskID,
            Progress:  progress,
            Message:   message,
        })
    },
})
```

### 2. Key Input Handling

DGMSTT implements sophisticated key handling with priorities:

```go
func (a appModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    switch msg := msg.(type) {
    case tea.KeyPressMsg:
        // 1. Handle active modal first
        if a.modal != nil {
            if keyString == "esc" || keyString == "ctrl+c" {
                cmd := a.modal.Close()
                a.modal = nil
                return a, cmd
            }
            // Pass to modal
            updatedModal, cmd := a.modal.Update(msg)
            a.modal = updatedModal.(layout.Modal)
            return a, cmd
        }

        // 2. Handle special keys (Shift+Tab for alt screen)
        if keyString == "shift+tab" {
            a.isAltScreen = !a.isAltScreen
            // ... toggle alternate screen
        }

        // 3. Check for leader sequences
        if a.isLeaderSequence {
            matches := a.app.Commands.Matches(msg, a.isLeaderSequence)
            // ... execute commands
        }

        // 4. Handle completions
        if keyString == "/" && !a.showCompletionDialog {
            a.showCompletionDialog = true
            // ... show completions
        }

        // 5. Maximize editor responsiveness for printable chars
        if msg.Text != "" {
            updated, cmd := a.editor.Update(msg)
            // ... update editor
        }
    }
}
```

### 3. Command Batching

Multiple commands can be executed together:

```go
// Sequential execution
return a, tea.Sequence(cmds...)

// Parallel execution
return a, tea.Batch(cmds...)
```

## Best Practices

### 1. Component Independence

Each component manages its own state:

```go
type messagesComponent struct {
    app      *app.App
    viewport viewport.Model
    width    int
    height   int
    // ... component-specific state
}

func (m *messagesComponent) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    // Handle only messages relevant to this component
    switch msg := msg.(type) {
    case tea.WindowSizeMsg:
        // Update size
    case app.MessageAddedMsg:
        // Add message
    }
    return m, nil
}
```

### 2. Message Design

Messages should be:

- **Immutable**: Don't modify message data after creation
- **Descriptive**: Clear names indicating what happened
- **Minimal**: Only include necessary data

```go
// Good
type TaskCompletedMsg struct {
    SessionID string
    TaskID    string
    Duration  time.Duration
    Success   bool
}

// Bad - too much coupling
type UpdateEverythingMsg struct {
    App       *app.App  // Don't pass entire app
    Component string    // Too generic
    Data      interface{}
}
```

### 3. Error Handling

Errors are messages too:

```go
func (a appModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
    switch msg := msg.(type) {
    case error:
        return a, toast.NewErrorToast(msg.Error())
    }
}
```

### 4. Performance Optimization

DGMSTT implements several optimizations:

```go
// Debounce scroll events
if time.Since(a.lastScroll) < time.Millisecond*100 && BUGGED_SCROLL_KEYS[keyString] {
    return a, nil
}

// Prioritize editor input
if msg.Text != "" {
    updated, cmd := a.editor.Update(msg)
    return a, tea.Batch(cmds...)  // Return immediately
}
```

## Advanced Patterns

### 1. Multi-Key Sequences

DGMSTT supports complex key sequences:

```go
// Ctrl+B navigation sequence
if a.isCtrlBSequence {
    a.isCtrlBSequence = false
    switch keyString {
    case ".":
        // Navigate to next sibling
        return a, a.navigateToSibling(context.Background(), "next")
    case ",":
        // Navigate to previous sibling
        return a, a.navigateToSibling(context.Background(), "prev")
    }
}
```

### 2. Interrupt Debouncing

Prevents accidental interrupts:

```go
case InterruptKeyIdle:
    // First press - start debounce
    a.interruptKeyState = InterruptKeyFirstPress
    return a, tea.Tick(interruptDebounceTimeout, func(t time.Time) tea.Msg {
        return InterruptDebounceTimeoutMsg{}
    })
case InterruptKeyFirstPress:
    // Second press within timeout - actually interrupt
    a.interruptKeyState = InterruptKeyIdle
    return a, util.CmdHandler(commands.ExecuteCommandMsg(interruptCommand))
```

### 3. Dynamic Sizing

Components can adapt to terminal size:

```go
case tea.WindowSizeMsg:
    a.width = msg.Width
    a.height = msg.Height

    // Update all components
    cmds = append(cmds, a.editor.SetSize(msg.Width, editorHeight))
    cmds = append(cmds, a.messages.SetSize(msg.Width, messagesHeight))
```

### 4. Theme System Integration

DGMSTT integrates with a theme system:

```go
case tea.BackgroundColorMsg:
    styles.Terminal = &styles.TerminalInfo{
        Background:       msg.Color,
        BackgroundIsDark: msg.IsDark(),
    }

    return a, func() tea.Msg {
        theme.UpdateSystemTheme(
            styles.Terminal.Background,
            styles.Terminal.BackgroundIsDark,
        )
        return dialog.ThemeSelectedMsg{
            ThemeName: theme.CurrentThemeName(),
        }
    }
```

### 5. WebSocket Integration

Real-time updates through WebSocket:

```go
// WebSocket handler converts events to messages
func (h *MCPEventProcessor) HandleMCPEvent(eventType string, data MCPEventData) tea.Cmd {
    switch eventType {
    case "mcp_call_started":
        return h.handleMCPCallStarted(data)
    case "mcp_call_progress":
        return h.handleMCPCallProgress(data)
    case "mcp_call_completed":
        return h.handleMCPCallCompleted(data)
    }
}
```

## Key Takeaways

1. **Everything is a Message**: User input, API responses, timers - all events become messages
2. **Components are Self-Contained**: Each component manages its own state and updates
3. **Composition Over Inheritance**: Build complex UIs by composing simple components
4. **Functional Updates**: State changes happen through pure functions
5. **Async Through Commands**: I/O operations return commands that produce messages

## DGMSTT-Specific Patterns

1. **Task System**: Integrates with backend task execution through WebSocket
2. **MCP Integration**: Model Context Protocol panel for AI interactions
3. **Session Management**: Complex navigation between main and sub-sessions
4. **Dynamic Content**: Messages and editor adapt to content size
5. **Toast System**: Non-blocking notifications overlay the main UI
6. **Command Palette**: Slash commands with completion dialog
7. **Theme Support**: Dynamic theme switching with terminal color detection

This architecture makes DGMSTT highly responsive, maintainable, and extensible while providing a
rich terminal user interface experience.
