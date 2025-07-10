package main

import (
	"fmt"
	"math/rand"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ============================================================================
// Retro-Futuristic Color Scheme
// ============================================================================

var (
	// CRT Monitor Colors
	crtGreen   = lipgloss.Color("#00FF41") // Matrix green
	crtAmber   = lipgloss.Color("#FFB000") // Amber monitor
	crtBlue    = lipgloss.Color("#00D9FF") // Cyan blue
	crtPink    = lipgloss.Color("#FF006E") // Hot pink
	crtPurple  = lipgloss.Color("#8B00FF") // Purple
	darkBg     = lipgloss.Color("#0A0A0A") // Almost black
	darkGray   = lipgloss.Color("#1A1A1A") // Dark gray
	mediumGray = lipgloss.Color("#333333") // Medium gray

	// Retro Styles
	borderStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.DoubleBorder()).
			BorderForeground(crtGreen)

	titleBarStyle = lipgloss.NewStyle().
			Background(crtGreen).
			Foreground(darkBg).
			Bold(true).
			Padding(0, 2)

	statusBarStyle = lipgloss.NewStyle().
			Background(mediumGray).
			Foreground(crtGreen).
			Padding(0, 1)

	messageBoxStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(crtBlue).
			Padding(1).
			MarginBottom(1)

	userMsgStyle = messageBoxStyle.Copy().
			BorderForeground(crtPink).
			Foreground(crtPink)

	aiMsgStyle = messageBoxStyle.Copy().
			BorderForeground(crtBlue).
			Foreground(crtBlue)

	editorStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.ThickBorder()).
			BorderForeground(crtAmber).
			Padding(1)

	mcpPanelStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(crtPurple).
			Padding(1)

	toastStyle = lipgloss.NewStyle().
			Background(crtGreen).
			Foreground(darkBg).
			Padding(0, 2).
			MarginTop(1)

	glitchChars = []string{"▓", "▒", "░", "█", "▄", "▀", "■", "□", "▪", "▫"}
)

// ============================================================================
// Data Structures
// ============================================================================

type Message struct {
	ID        int
	Content   string
	Role      string
	Timestamp time.Time
	Tool      string // For MCP operations
}

type MCPOperation struct {
	ID       string
	Tool     string
	Status   string
	Progress int
}

type Toast struct {
	Message   string
	Type      string
	ExpiresAt time.Time
}

type Model struct {
	// Layout
	width, height int

	// Content
	messages []Message
	input    string
	cursor   int

	// UI State
	activePane   string // "messages", "editor", "mcp"
	scrollOffset int
	showMCP      bool
	showCommand  bool
	commandInput string

	// Effects
	glitchEffect bool
	scanlineY    int
	toasts       []Toast

	// MCP Operations
	mcpOps       []MCPOperation
	isProcessing bool

	// Session Info
	sessionID     string
	contextTokens int
	cost          float64
}

// ============================================================================
// Messages
// ============================================================================

type TickMsg time.Time
type ProcessingDoneMsg struct {
	response string
	tool     string
}
type GlitchMsg struct{}
type ScanlineMsg struct{}

// ============================================================================
// Commands
// ============================================================================

func tickCmd() tea.Cmd {
	return tea.Tick(time.Millisecond*100, func(t time.Time) tea.Msg {
		return TickMsg(t)
	})
}

func glitchCmd() tea.Cmd {
	return tea.Tick(time.Millisecond*50, func(t time.Time) tea.Msg {
		return GlitchMsg{}
	})
}

func scanlineCmd() tea.Cmd {
	return tea.Tick(time.Millisecond*30, func(t time.Time) tea.Msg {
		return ScanlineMsg{}
	})
}

func processCommand(input string) tea.Cmd {
	return func() tea.Msg {
		time.Sleep(time.Millisecond * 1500)

		// Simulate different tools
		tools := []string{"file_reader", "code_analyzer", "web_search", "calculator"}
		tool := tools[rand.Intn(len(tools))]

		response := generateResponse(input, tool)
		return ProcessingDoneMsg{response: response, tool: tool}
	}
}

// ============================================================================
// Model Implementation
// ============================================================================

func initialModel() Model {
	return Model{
		messages: []Message{
			{
				ID:        1,
				Content:   "SYSTEM INITIALIZED. RETRO-DGMO v2.0 ONLINE.",
				Role:      "system",
				Timestamp: time.Now(),
			},
			{
				ID:        2,
				Content:   "Welcome to the retro-futuristic terminal. How may I assist you today?",
				Role:      "assistant",
				Timestamp: time.Now(),
			},
		},
		activePane:    "editor",
		sessionID:     fmt.Sprintf("RETRO-%d", time.Now().Unix()),
		contextTokens: 1337,
		cost:          0.42,
		showMCP:       true,
		mcpOps: []MCPOperation{
			{ID: "OP-001", Tool: "system_check", Status: "completed", Progress: 100},
		},
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(
		tea.EnterAltScreen,
		tickCmd(),
		scanlineCmd(),
	)
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "ctrl+q":
			return m, tea.Quit

		case "tab":
			// Cycle through panes
			switch m.activePane {
			case "messages":
				m.activePane = "editor"
			case "editor":
				if m.showMCP {
					m.activePane = "mcp"
				} else {
					m.activePane = "messages"
				}
			case "mcp":
				m.activePane = "messages"
			}

		case "ctrl+m":
			m.showMCP = !m.showMCP
			if !m.showMCP && m.activePane == "mcp" {
				m.activePane = "editor"
			}
			toast := "MCP PANEL: ACTIVATED"
			if !m.showMCP {
				toast = "MCP PANEL: DEACTIVATED"
			}
			m.addToast(toast, "info")

		case "ctrl+k":
			m.showCommand = !m.showCommand
			if m.showCommand {
				m.commandInput = ""
			}

		case "ctrl+g":
			// Toggle glitch effect
			m.glitchEffect = !m.glitchEffect
			if m.glitchEffect {
				return m, glitchCmd()
			}

		case "enter":
			if m.showCommand {
				// Execute command
				m.executeCommand()
				m.showCommand = false
			} else if m.activePane == "editor" && m.input != "" && !m.isProcessing {
				// Send message
				m.messages = append(m.messages, Message{
					ID:        len(m.messages) + 1,
					Content:   m.input,
					Role:      "user",
					Timestamp: time.Now(),
				})

				// Add MCP operation
				m.mcpOps = append(m.mcpOps, MCPOperation{
					ID:       fmt.Sprintf("OP-%03d", len(m.mcpOps)+1),
					Tool:     "processing",
					Status:   "running",
					Progress: 0,
				})

				m.isProcessing = true
				cmd := processCommand(m.input)
				m.input = ""
				m.cursor = 0
				m.contextTokens += rand.Intn(100) + 50
				m.cost += float64(rand.Intn(10)) / 100

				return m, cmd
			}

		case "backspace":
			if m.showCommand && len(m.commandInput) > 0 {
				m.commandInput = m.commandInput[:len(m.commandInput)-1]
			} else if m.activePane == "editor" && m.cursor > 0 {
				m.input = m.input[:m.cursor-1] + m.input[m.cursor:]
				m.cursor--
			}

		case "left":
			if m.activePane == "editor" && m.cursor > 0 {
				m.cursor--
			}

		case "right":
			if m.activePane == "editor" && m.cursor < len(m.input) {
				m.cursor++
			}

		case "up":
			if m.activePane == "messages" && m.scrollOffset > 0 {
				m.scrollOffset--
			}

		case "down":
			if m.activePane == "messages" {
				m.scrollOffset++
			}

		default:
			if m.showCommand {
				m.commandInput += msg.String()
			} else if m.activePane == "editor" && !m.isProcessing {
				m.input = m.input[:m.cursor] + msg.String() + m.input[m.cursor:]
				m.cursor++
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case TickMsg:
		// Update MCP operations
		for i := range m.mcpOps {
			if m.mcpOps[i].Status == "running" {
				m.mcpOps[i].Progress += 10
				if m.mcpOps[i].Progress >= 100 {
					m.mcpOps[i].Progress = 100
					m.mcpOps[i].Status = "completed"
				}
			}
		}

		// Clean expired toasts
		var activeToasts []Toast
		now := time.Now()
		for _, toast := range m.toasts {
			if toast.ExpiresAt.After(now) {
				activeToasts = append(activeToasts, toast)
			}
		}
		m.toasts = activeToasts

		return m, tickCmd()

	case ProcessingDoneMsg:
		m.isProcessing = false

		// Update MCP operation
		if len(m.mcpOps) > 0 {
			m.mcpOps[len(m.mcpOps)-1].Status = "completed"
			m.mcpOps[len(m.mcpOps)-1].Tool = msg.tool
		}

		// Add response
		m.messages = append(m.messages, Message{
			ID:        len(m.messages) + 1,
			Content:   msg.response,
			Role:      "assistant",
			Timestamp: time.Now(),
			Tool:      msg.tool,
		})

		m.addToast("PROCESSING COMPLETE", "success")

	case GlitchMsg:
		if m.glitchEffect {
			return m, glitchCmd()
		}

	case ScanlineMsg:
		m.scanlineY = (m.scanlineY + 1) % m.height
		return m, scanlineCmd()
	}

	return m, nil
}

func (m Model) View() string {
	if m.width == 0 || m.height == 0 {
		return "INITIALIZING..."
	}

	// Build layout
	var content string

	// Title bar
	title := titleBarStyle.Width(m.width).Render("◼ RETRO-DGMO TERMINAL v2.0 ◼")

	// Main content area
	mainHeight := m.height - 4 // Title, status, margins

	if m.showMCP {
		// Three-column layout
		messagesWidth := m.width * 4 / 10
		editorWidth := m.width * 4 / 10
		mcpWidth := m.width * 2 / 10

		messages := m.renderMessages(messagesWidth, mainHeight)
		editor := m.renderEditor(editorWidth, mainHeight)
		mcp := m.renderMCP(mcpWidth, mainHeight)

		content = lipgloss.JoinHorizontal(lipgloss.Top, messages, editor, mcp)
	} else {
		// Two-column layout
		messagesWidth := m.width / 2
		editorWidth := m.width / 2

		messages := m.renderMessages(messagesWidth, mainHeight)
		editor := m.renderEditor(editorWidth, mainHeight)

		content = lipgloss.JoinHorizontal(lipgloss.Top, messages, editor)
	}

	// Status bar
	status := m.renderStatus()

	// Command palette overlay
	if m.showCommand {
		content = m.renderCommandPalette(content)
	}

	// Toast overlay
	if len(m.toasts) > 0 {
		content = m.renderToasts(content)
	}

	// Apply CRT effects
	final := lipgloss.JoinVertical(lipgloss.Left, title, content, status)

	if m.glitchEffect {
		final = m.applyGlitch(final)
	}

	return m.applyScanline(final)
}

// ============================================================================
// Render Functions
// ============================================================================

func (m Model) renderMessages(width, height int) string {
	style := borderStyle.Width(width - 2).Height(height - 2)
	if m.activePane == "messages" {
		style = style.BorderForeground(crtAmber)
	}

	title := " MESSAGES "
	content := []string{}

	for _, msg := range m.messages {
		var msgStyle lipgloss.Style
		prefix := ""

		switch msg.Role {
		case "user":
			msgStyle = userMsgStyle.Width(width - 6)
			prefix = "USER> "
		case "assistant":
			msgStyle = aiMsgStyle.Width(width - 6)
			prefix = "AI> "
			if msg.Tool != "" {
				prefix = fmt.Sprintf("AI[%s]> ", msg.Tool)
			}
		case "system":
			msgStyle = lipgloss.NewStyle().Foreground(crtGreen).Bold(true)
			prefix = "SYS> "
		}

		lines := wordWrap(prefix+msg.Content, width-8)
		for _, line := range lines {
			content = append(content, msgStyle.Render(line))
		}
		content = append(content, "") // Space between messages
	}

	// Apply scrolling
	visibleContent := content
	if len(content) > height-4 {
		start := m.scrollOffset
		if start > len(content)-height+4 {
			start = len(content) - height + 4
		}
		if start < 0 {
			start = 0
		}
		end := start + height - 4
		if end > len(content) {
			end = len(content)
		}
		visibleContent = content[start:end]
	}

	inner := strings.Join(visibleContent, "\n")
	return style.Render(lipgloss.JoinVertical(lipgloss.Left, title, inner))
}

func (m Model) renderEditor(width, height int) string {
	style := editorStyle.Width(width - 2).Height(height - 2)
	if m.activePane == "editor" {
		style = style.BorderForeground(crtPink)
	}

	title := " COMMAND INPUT "

	// Input with cursor
	input := m.input
	if m.cursor < len(m.input) {
		input = m.input[:m.cursor] + "▊" + m.input[m.cursor:]
	} else {
		input = m.input + "▊"
	}

	prompt := "> "
	if m.isProcessing {
		prompt = "◊ PROCESSING... "
	}

	inputLine := lipgloss.NewStyle().Foreground(crtAmber).Render(prompt + input)

	// Help text
	help := []string{
		"",
		"COMMANDS:",
		"TAB      - Switch panes",
		"CTRL+M   - Toggle MCP panel",
		"CTRL+K   - Command palette",
		"CTRL+G   - Glitch effect",
		"CTRL+C   - Exit",
		"",
		"STATUS: " + strings.ToUpper(fmt.Sprintf("Ready")),
	}

	if m.isProcessing {
		help[len(help)-1] = "STATUS: PROCESSING..."
	}

	helpText := lipgloss.NewStyle().Foreground(crtGreen).Render(strings.Join(help, "\n"))

	content := lipgloss.JoinVertical(lipgloss.Left, inputLine, "", helpText)

	return style.Render(lipgloss.JoinVertical(lipgloss.Left, title, content))
}

func (m Model) renderMCP(width, height int) string {
	style := mcpPanelStyle.Width(width - 2).Height(height - 2)
	if m.activePane == "mcp" {
		style = style.BorderForeground(crtAmber)
	}

	title := " MCP OPS "
	content := []string{}

	for _, op := range m.mcpOps {
		status := "◼"
		if op.Status == "running" {
			status = "◊"
		} else if op.Status == "completed" {
			status = "◆"
		}

		progress := ""
		if op.Status == "running" {
			filled := op.Progress / 10
			progress = "\n[" + strings.Repeat("█", filled) + strings.Repeat("░", 10-filled) + "]"
		}

		opText := fmt.Sprintf("%s %s\n%s%s", status, op.ID, op.Tool, progress)

		color := crtPurple
		if op.Status == "completed" {
			color = crtGreen
		} else if op.Status == "running" {
			color = crtAmber
		}

		content = append(content, lipgloss.NewStyle().Foreground(color).Render(opText))
		content = append(content, "")
	}

	inner := strings.Join(content, "\n")
	return style.Render(lipgloss.JoinVertical(lipgloss.Left, title, inner))
}

func (m Model) renderStatus() string {
	left := fmt.Sprintf(" SESSION: %s | TOKENS: %d | COST: $%.2f ",
		m.sessionID, m.contextTokens, m.cost)

	right := fmt.Sprintf(" %s | MEM: 64KB | CPU: 99%% ", time.Now().Format("15:04:05"))

	gap := m.width - lipgloss.Width(left) - lipgloss.Width(right)
	if gap < 0 {
		gap = 0
	}

	status := left + strings.Repeat("─", gap) + right

	return statusBarStyle.Width(m.width).Render(status)
}

func (m Model) renderCommandPalette(content string) string {
	width := 60
	height := 3

	x := (m.width - width) / 2
	y := (m.height - height) / 2

	palette := lipgloss.NewStyle().
		BorderStyle(lipgloss.DoubleBorder()).
		BorderForeground(crtPink).
		Background(darkBg).
		Foreground(crtPink).
		Width(width).
		Height(height).
		Padding(1).
		Render("COMMAND> " + m.commandInput + "▊")

	lines := strings.Split(content, "\n")
	for i := y; i < y+height+2 && i < len(lines); i++ {
		if i >= 0 {
			lines[i] = overlayString(lines[i], palette, x, i-y)
		}
	}

	return strings.Join(lines, "\n")
}

func (m Model) renderToasts(content string) string {
	y := 2
	for _, toast := range m.toasts {
		toastView := toastStyle.Render("◆ " + toast.Message + " ◆")
		x := (m.width - lipgloss.Width(toastView)) / 2

		lines := strings.Split(content, "\n")
		if y < len(lines) {
			lines[y] = overlayString(lines[y], toastView, x, 0)
		}
		content = strings.Join(lines, "\n")
		y += 2
	}

	return content
}

// ============================================================================
// Helper Functions
// ============================================================================

func (m *Model) addToast(message, toastType string) {
	m.toasts = append(m.toasts, Toast{
		Message:   message,
		Type:      toastType,
		ExpiresAt: time.Now().Add(3 * time.Second),
	})
}

func (m *Model) executeCommand() {
	cmd := strings.ToLower(m.commandInput)

	switch {
	case strings.HasPrefix(cmd, "theme"):
		m.addToast("THEME CHANGED", "info")
	case strings.HasPrefix(cmd, "clear"):
		m.messages = m.messages[:2] // Keep system messages
		m.addToast("MESSAGES CLEARED", "info")
	case strings.HasPrefix(cmd, "stats"):
		m.addToast(fmt.Sprintf("TOKENS: %d | COST: $%.2f", m.contextTokens, m.cost), "info")
	default:
		m.addToast("UNKNOWN COMMAND", "error")
	}
}

func (m Model) applyGlitch(content string) string {
	lines := strings.Split(content, "\n")

	// Random glitch lines
	for i := 0; i < 3; i++ {
		y := rand.Intn(len(lines))
		if y < len(lines) {
			runes := []rune(lines[y])
			for j := 0; j < 5; j++ {
				x := rand.Intn(len(runes))
				if x < len(runes) {
					runes[x] = []rune(glitchChars[rand.Intn(len(glitchChars))])[0]
				}
			}
			lines[y] = string(runes)
		}
	}

	return strings.Join(lines, "\n")
}

func (m Model) applyScanline(content string) string {
	lines := strings.Split(content, "\n")

	if m.scanlineY < len(lines) && m.scanlineY >= 0 {
		// Dim the scanline
		line := lines[m.scanlineY]
		dimmed := lipgloss.NewStyle().Foreground(mediumGray).Render(line)
		lines[m.scanlineY] = dimmed
	}

	return strings.Join(lines, "\n")
}

func wordWrap(text string, width int) []string {
	var lines []string
	words := strings.Fields(text)

	var currentLine string
	for _, word := range words {
		if currentLine == "" {
			currentLine = word
		} else if len(currentLine)+1+len(word) <= width {
			currentLine += " " + word
		} else {
			lines = append(lines, currentLine)
			currentLine = word
		}
	}

	if currentLine != "" {
		lines = append(lines, currentLine)
	}

	return lines
}

func overlayString(base, overlay string, x, y int) string {
	if y != 0 {
		return base
	}

	baseRunes := []rune(base)
	overlayRunes := []rune(overlay)

	for i, r := range overlayRunes {
		pos := x + i
		if pos >= 0 && pos < len(baseRunes) {
			baseRunes[pos] = r
		}
	}

	return string(baseRunes)
}

func generateResponse(input, tool string) string {
	responses := map[string][]string{
		"file_reader": {
			"Analyzing file structure... Found 42 components across 7 modules.",
			"File scan complete. Detected TypeScript, Go, and configuration files.",
			"Reading directory tree... 1,337 files processed.",
		},
		"code_analyzer": {
			"Code analysis initiated. Detecting patterns and potential optimizations.",
			"Found 3 performance bottlenecks and 7 style violations.",
			"Analysis complete. Code quality score: 8.5/10.",
		},
		"web_search": {
			"Searching the retro-net... Found 256 relevant results.",
			"Web crawl complete. Top result confidence: 94.2%.",
			"Search terminated. Data packets retrieved successfully.",
		},
		"calculator": {
			"Computing... Result: 42. The answer to everything.",
			"Calculation complete. Quantum probability: 0.9999.",
			"Mathematical operation successful. Check MCP logs for details.",
		},
	}

	toolResponses := responses[tool]
	if toolResponses == nil {
		toolResponses = responses["file_reader"]
	}

	return toolResponses[rand.Intn(len(toolResponses))]
}

// ============================================================================
// Main
// ============================================================================

func main() {
	rand.Seed(time.Now().UnixNano())

	p := tea.NewProgram(initialModel())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error: %v", err)
	}
}
