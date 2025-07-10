# Mock TUI Chat Application

This is a standalone mock Terminal User Interface (TUI) chat application built with Bubble Tea. It
demonstrates the UI capabilities without requiring any backend connections.

## Features

- 🤖 Interactive chat interface
- 💬 Mock AI responses
- 🎨 Colorful terminal UI with styled components
- ⌨️ Keyboard navigation
- 📜 Message scrolling
- ⏱️ Simulated thinking indicator
- 🎯 No external dependencies (just Bubble Tea)

## Prerequisites

- Go 1.19 or higher
- Terminal that supports colors

## Installation

1. First, initialize a Go module in the DGMSTT directory:

```bash
cd /mnt/c/Users/jehma/Desktop/DGMSTT
go mod init dgmstt-mock
```

2. Install the required dependencies:

```bash
go get github.com/charmbracelet/bubbletea
go get github.com/charmbracelet/lipgloss
```

## Running the Application

Simply run:

```bash
go run mock_tui_chat.go
```

## Controls

- **Type your message** - Just start typing
- **Enter** - Send message
- **↑/↓** - Scroll through messages
- **←/→** - Move cursor in input
- **Backspace** - Delete character
- **ESC or Ctrl+C** - Quit application

## Mock Responses

The AI will respond to certain keywords:

- Say "hello" or "hi" for a greeting
- Ask "how are you" for a status update
- Mention "weather" for a weather response
- Say "help" to learn about the interface
- Ask for a "joke" to hear one
- Mention "code" or "programming" for tech talk
- Say "quit" or "exit" for exit instructions

For any other input, you'll get a contextual mock response!

## Architecture

The application follows the Bubble Tea Model-Update-View pattern:

- **Model**: Stores messages, input state, and UI dimensions
- **Update**: Handles keyboard input and state changes
- **View**: Renders the terminal UI with styling

## Customization

You can easily modify:

- Colors in the styles section
- Mock responses in `generateMockResponse()`
- UI layout in the `View()` method
- Add more keyboard shortcuts in `Update()`

## Screenshot Example

```
🤖 Mock Chat TUI

AI: Hello! I'm your AI assistant. How can I help you today?

You: Hi there!

AI: Hello there! It's great to chat with you. What would you like to talk about?

You: Tell me a joke

AI is thinking...

> |

Messages: 4                                                     AI is thinking...
ESC to quit • Enter to send • ↑↓ to scroll
```

## Troubleshooting

If you get import errors:

1. Make sure you're in the correct directory
2. Run `go mod tidy` to clean up dependencies
3. Check that your Go version is 1.19+

## Next Steps

This mock TUI demonstrates the basic structure. You could:

- Add more sophisticated mock responses
- Implement message persistence
- Add emoji support
- Create different UI themes
- Add mouse support
- Implement message editing

Enjoy exploring Bubble Tea! 🧋
