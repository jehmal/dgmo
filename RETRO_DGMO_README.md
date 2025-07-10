# 🖥️ RETRO-DGMO Terminal v2.0

A retro-futuristic reimagining of DGMO with an 80s computer aesthetic, CRT effects, and cyberpunk
vibes.

## 🎨 Features

### Visual Design

- **CRT Monitor Colors**: Matrix green, amber, cyan, hot pink, and purple
- **Double & Thick Borders**: Classic terminal styling
- **Glitch Effects**: Toggle-able visual glitches (Ctrl+G)
- **Scanline Animation**: Authentic CRT monitor effect
- **Retro Typography**: Block characters and ASCII art

### Layout

- **Three-Pane View**: Messages | Editor | MCP Operations
- **Collapsible MCP Panel**: Toggle with Ctrl+M
- **Active Pane Highlighting**: Visual feedback for focused area
- **Status Bar**: Session info, tokens, cost, and system stats

### Interactive Elements

- **Command Palette**: Ctrl+K for quick commands
- **Toast Notifications**: Retro-styled popup messages
- **Progress Bars**: ASCII-style progress indicators
- **Tool Integration**: Simulated file_reader, code_analyzer, web_search, calculator

## 🚀 Installation

1. Set up Go environment:

```bash
cd /mnt/c/Users/jehma/Desktop/DGMSTT
go mod init retro-dgmo
```

2. Install dependencies:

```bash
go get github.com/charmbracelet/bubbletea@latest
go get github.com/charmbracelet/lipgloss@latest
```

3. Run the application:

```bash
go run retro_dgmo_tui.go
```

## ⌨️ Keyboard Controls

### Navigation

- **TAB** - Cycle through panes (Messages → Editor → MCP)
- **↑/↓** - Scroll messages when in message pane
- **←/→** - Move cursor in editor

### Commands

- **ENTER** - Send message / Execute command
- **CTRL+M** - Toggle MCP panel visibility
- **CTRL+K** - Open command palette
- **CTRL+G** - Toggle glitch effect (fun!)
- **CTRL+C/Q** - Exit application

### Command Palette Commands

- `theme` - Change theme (simulated)
- `clear` - Clear message history
- `stats` - Show session statistics

## 🎮 UI/UX Features

### Message Types

- **USER>** - Your messages (pink border)
- **AI>** - Assistant responses (blue border)
- **AI[tool]>** - Tool-specific responses
- **SYS>** - System messages (green, bold)

### MCP Operations Panel

- **◼** - Queued operation
- **◊** - Running operation (with progress bar)
- **◆** - Completed operation

### Status Indicators

- Session ID (RETRO-timestamp format)
- Token count (starts at 1337 🎮)
- Cost tracking
- Simulated CPU and memory usage
- Real-time clock

## 🛠️ Customization

### Color Schemes

Edit the color variables at the top of the file:

```go
crtGreen  = lipgloss.Color("#00FF41")  // Matrix green
crtAmber  = lipgloss.Color("#FFB000")  // Amber monitor
crtBlue   = lipgloss.Color("#00D9FF")  // Cyan blue
crtPink   = lipgloss.Color("#FF006E")  // Hot pink
crtPurple = lipgloss.Color("#8B00FF")  // Purple
```

### Add New Tools

Extend the `generateResponse` function:

```go
responses := map[string][]string{
    "your_tool": {
        "Response 1",
        "Response 2",
    },
}
```

### Modify Layout

Adjust the column widths in the `View()` method:

```go
messagesWidth := m.width * 4 / 10  // 40%
editorWidth := m.width * 4 / 10    // 40%
mcpWidth := m.width * 2 / 10       // 20%
```

## 🎯 Design Philosophy

This reimagining takes DGMO's powerful features and wraps them in a nostalgic, cyberpunk-inspired
interface that feels like you're hacking on a vintage terminal from an 80s sci-fi movie. The retro
aesthetic isn't just visual - it extends to the interaction patterns, with command palettes, ASCII
progress bars, and glitch effects that make the experience fun and memorable.

## 🐛 Troubleshooting

### Import Errors

Run `go mod tidy` to resolve dependency issues

### Display Issues

- Ensure your terminal supports Unicode characters
- Use a monospace font for best results
- Terminal should be at least 80x24 characters

### Performance

- Disable glitch effect if it causes lag
- The scanline effect is lightweight and shouldn't impact performance

## 🚧 Future Enhancements

- [ ] Sound effects (beeps and boops!)
- [ ] More CRT effects (phosphor burn-in, color bleeding)
- [ ] Customizable color themes (CGA, EGA, VGA modes)
- [ ] ASCII art splash screen
- [ ] Matrix rain background effect
- [ ] Retro loading animations

Enjoy your retro-futuristic terminal experience! 🖥️✨
