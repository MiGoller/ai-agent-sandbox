#!/usr/bin/env bash
set -e

echo "🔧 Setting up AI Agent Sandbox Global Symlinks..."
echo "--------------------------------------------------"

# Ensure the script directory is correct
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER_SRC="$REPO_DIR/bin/ai-sandbox.sh"
TARGET_DIR="/usr/local/bin"

# 1. Ensure the source wrapper is executable inside the repo
chmod +x "$WRAPPER_SRC"

# 2. Create the symlinks using sudo
echo "📦 Creating global symlinks in $TARGET_DIR (requires sudo)..."
sudo ln -sf "$WRAPPER_SRC" "$TARGET_DIR/ai-sandbox"
sudo ln -sf "$WRAPPER_SRC" "$TARGET_DIR/hermes"
sudo ln -sf "$WRAPPER_SRC" "$TARGET_DIR/aider"
sudo ln -sf "$WRAPPER_SRC" "$TARGET_DIR/claude"

echo "--------------------------------------------------"
echo "✅ Setup completed successfully!"
echo "You can now run 'hermes', 'aider', or 'claude' from any directory."
