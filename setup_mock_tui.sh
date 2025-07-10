#!/bin/bash

# Setup script for Mock TUI Chat Application

echo "🧋 Setting up Mock TUI Chat Application..."

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo "❌ Go is not installed. Please install Go 1.19 or higher."
    echo "Visit: https://golang.org/dl/"
    exit 1
fi

# Check Go version
GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
echo "✅ Found Go version: $GO_VERSION"

# Initialize Go module if not exists
if [ ! -f "go.mod" ]; then
    echo "📦 Initializing Go module..."
    go mod init dgmstt-mock
else
    echo "✅ Go module already initialized"
fi

# Install dependencies
echo "📥 Installing dependencies..."
go get github.com/charmbracelet/bubbletea@latest
go get github.com/charmbracelet/lipgloss@latest

# Tidy up
echo "🧹 Tidying up dependencies..."
go mod tidy

echo ""
echo "✨ Setup complete! You can now run the mock TUI with:"
echo "   go run mock_tui_chat.go"
echo ""
echo "📖 See MOCK_TUI_README.md for usage instructions"