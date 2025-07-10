package main

import (
	"fmt"
	"strings"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ============================================================================
// Styles
// ============================================================================

var (
	// Colors
	primaryColor   = lipgloss.Color("#7D56F4")
	secondaryColor = lipgloss.Color("#F4B556")
	mutedColor     = lipgloss.Color("#666666")
	errorColor     = lipgloss.Color("#FF6B6B")
	successColor   = lipgloss.Color("#4ECDC4")

	// Styles
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(primaryColor).
			MarginLeft(2)

	statusStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("#FAFAFA")).
			Background(primaryColor).
			Padding(0, 1)

	messageStyle = lipgloss.NewStyle().
			PaddingLeft(2).
			PaddingRight(2).
			MarginBottom(1)

	userMessageStyle = messageStyle.Copy().
				Foreground(secondaryColor).
				Align(lipgloss.Right)

	assistantMessageStyle = messageStyle.Copy().
				Foreground(lipgloss.Color("#FFFFFF"))

	inputStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(primaryColor).
			Padding(1).
			MarginTop(1)

	helpStyle = lipgloss.NewStyle().
			Foreground(mutedColor).
			MarginTop(1).
			Align(lipgloss.Center)
)

// ============================================================================
// Types
// ============================================================================

type Message struct {
	ID        int
	Content   string
	Role      string // "user" or "assistant"
	Timestamp time.Time
}

type Model struct {
	messages     []Message
	input        string
	cursor       int
	width        int
	height       int
	scrollOffset int
	isThinking   bool
	thinkingDots int
	lastMsgID    int
}

// ============================================================================
// Messages
// ============================================================================

type TickMsg time.Time
type ThinkingDoneMsg struct {
	response string
}

// ============================================================================
// Commands
// ============================================================================

func tickCmd() tea.Cmd {
	return tea.Tick(time.Millisecond*300, func(t time.Time) tea.Msg {
		return TickMsg(t)
	})
}

func simulateResponse(input string) tea.Cmd {
	return func() tea.Msg {
		// Simulate thinking delay
		time.Sleep(time.Second * 2)

		// Generate mock response based on input
		response := generateMockResponse(input)

		return ThinkingDoneMsg{response: response}
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
				Content:   "Hello! I'm your AI assistant. How can I help you today?",
				Role:      "assistant",
				Timestamp: time.Now(),
			},
		},
		input:     "",
		cursor:    0,
		lastMsgID: 1,
	}
}

func (m Model) Init() tea.Cmd {
	return tea.Batch(
		tea.EnterAltScreen,
		tickCmd(),
	)
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "esc":
			return m, tea.Quit

		case "enter":
			if m.input != "" && !m.isThinking {
				// Add user message
				m.lastMsgID++
				userMsg := Message{
					ID:        m.lastMsgID,
					Content:   m.input,
					Role:      "user",
					Timestamp: time.Now(),
				}
				m.messages = append(m.messages, userMsg)
				m.input = ""
				m.cursor = 0
				m.isThinking = true
				m.thinkingDots = 0

				// Simulate AI response
				return m, simulateResponse(userMsg.Content)
			}

		case "backspace":
			if m.cursor > 0 {
				m.input = m.input[:m.cursor-1] + m.input[m.cursor:]
				m.cursor--
			}

		case "left":
			if m.cursor > 0 {
				m.cursor--
			}

		case "right":
			if m.cursor < len(m.input) {
				m.cursor++
			}

		case "up":
			if m.scrollOffset > 0 {
				m.scrollOffset--
			}

		case "down":
			maxScroll := len(m.messages) - (m.height / 3)
			if m.scrollOffset < maxScroll && maxScroll > 0 {
				m.scrollOffset++
			}

		default:
			if !m.isThinking {
				m.input = m.input[:m.cursor] + msg.String() + m.input[m.cursor:]
				m.cursor++
			}
		}

	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case TickMsg:
		if m.isThinking {
			m.thinkingDots = (m.thinkingDots + 1) % 4
		}
		return m, tickCmd()

	case ThinkingDoneMsg:
		m.isThinking = false
		m.lastMsgID++
		assistantMsg := Message{
			ID:        m.lastMsgID,
			Content:   msg.response,
			Role:      "assistant",
			Timestamp: time.Now(),
		}
		m.messages = append(m.messages, assistantMsg)
	}

	return m, nil
}

func (m Model) View() string {
	if m.width == 0 || m.height == 0 {
		return "Loading..."
	}

	// Title
	title := titleStyle.Render("🤖 Mock Chat TUI")

	// Messages area
	messagesHeight := m.height - 10 // Reserve space for input and status
	messages := m.renderMessages(messagesHeight)

	// Input area
	inputPrompt := "> "
	inputContent := m.input
	if m.cursor < len(m.input) {
		inputContent = m.input[:m.cursor] + "█" + m.input[m.cursor:]
	} else {
		inputContent = m.input + "█"
	}

	inputBox := inputStyle.Width(m.width - 4).Render(inputPrompt + inputContent)

	// Status bar
	status := m.renderStatus()

	// Help text
	help := helpStyle.Width(m.width).Render("ESC to quit • Enter to send • ↑↓ to scroll")

	// Combine all elements
	return lipgloss.JoinVertical(
		lipgloss.Left,
		title,
		messages,
		inputBox,
		status,
		help,
	)
}

// ============================================================================
// Helper Functions
// ============================================================================

func (m Model) renderMessages(height int) string {
	var lines []string

	// Add messages
	for _, msg := range m.messages {
		var style lipgloss.Style
		prefix := ""

		if msg.Role == "user" {
			style = userMessageStyle
			prefix = "You: "
		} else {
			style = assistantMessageStyle
			prefix = "AI: "
		}

		content := prefix + msg.Content
		wrapped := wordWrap(content, m.width-6)

		for _, line := range wrapped {
			lines = append(lines, style.Render(line))
		}
		lines = append(lines, "") // Empty line between messages
	}

	// Add thinking indicator
	if m.isThinking {
		dots := strings.Repeat(".", m.thinkingDots)
		thinking := assistantMessageStyle.Render("AI is thinking" + dots)
		lines = append(lines, thinking)
	}

	// Apply scrolling
	visibleLines := lines
	if len(lines) > height {
		start := m.scrollOffset
		if start > len(lines)-height {
			start = len(lines) - height
		}
		if start < 0 {
			start = 0
		}
		end := start + height
		if end > len(lines) {
			end = len(lines)
		}
		visibleLines = lines[start:end]
	}

	// Pad to fill height
	for len(visibleLines) < height {
		visibleLines = append(visibleLines, "")
	}

	return strings.Join(visibleLines, "\n")
}

func (m Model) renderStatus() string {
	msgCount := fmt.Sprintf("Messages: %d", len(m.messages))

	var activity string
	if m.isThinking {
		activity = "AI is thinking..."
	} else {
		activity = "Ready"
	}

	left := statusStyle.Render(msgCount)
	right := statusStyle.Render(activity)

	gap := m.width - lipgloss.Width(left) - lipgloss.Width(right)
	if gap < 0 {
		gap = 0
	}

	return left + strings.Repeat(" ", gap) + right
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

func generateMockResponse(input string) string {
	// Simple mock responses based on keywords
	lowered := strings.ToLower(input)

	switch {
	case strings.Contains(lowered, "hello") || strings.Contains(lowered, "hi"):
		return "Hello there! It's great to chat with you. What would you like to talk about?"

	case strings.Contains(lowered, "how are you"):
		return "I'm doing well, thank you for asking! I'm here and ready to help with whatever you need."

	case strings.Contains(lowered, "weather"):
		return "I'm just a mock AI, so I can't check the real weather. But let's pretend it's a beautiful sunny day with a gentle breeze!"

	case strings.Contains(lowered, "help"):
		return "I'm a mock chat interface demonstrating Bubble Tea capabilities. I can respond to your messages with pre-programmed responses. Try asking about the weather, saying hello, or asking me to tell a joke!"

	case strings.Contains(lowered, "joke"):
		return "Why don't scientists trust atoms? Because they make up everything! 😄"

	case strings.Contains(lowered, "code") || strings.Contains(lowered, "programming"):
		return "Ah, a fellow coder! This TUI is built with Bubble Tea, a delightful Go framework for building terminal apps. The entire chat interface you're seeing is rendered in your terminal!"

	case strings.Contains(lowered, "quit") || strings.Contains(lowered, "exit"):
		return "You can press ESC or Ctrl+C to quit the application. Thanks for chatting!"

	default:
		responses := []string{
			"That's interesting! Tell me more about that.",
			"I see what you mean. Have you considered looking at it from another angle?",
			"Fascinating! This reminds me of something... but I'm just a mock AI so I'll make something up: Did you know that honey never spoils?",
			"Great question! While I can't give you a real answer (being a mock and all), I can say that you're asking the right questions!",
			"Hmm, let me think about that... *pretends to access vast knowledge base* ... I'd say the answer is 42!",
		}
		// Simple pseudo-random selection based on input length
		index := len(input) % len(responses)
		return responses[index]
	}
}

// ============================================================================
// Main
// ============================================================================

func main() {
	p := tea.NewProgram(initialModel())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v", err)
	}
}
