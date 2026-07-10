#!/usr/bin/env bash
set -e

# RETTE DAS URSPRÜNGLICHE VERZEICHNIS DES USERS!
export ORIGINAL_PWD="$(pwd)"

# Resolve the absolute path of this script, even if called via a symlink
REAL_SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")" && pwd)"
SANDBOX_DIR="$(dirname "$SCRIPT_DIR")"

# Get the name of how this script (or symlink) was called
TRIGGER_NAME=$(basename "$0")

cd "$SANDBOX_DIR"

case "$TRIGGER_NAME" in
    hermes)
        if [ $# -eq 0 ]; then
            exec ./run.sh hermes --online
        else
            exec ./run.sh hermes --online hermes "$@"
        fi
        ;;
    aider)
        exec ./run.sh aider --online "$@"
        ;;
    claude)
        if [ $# -eq 0 ]; then
            exec ./run.sh claude-code --online
        else
            exec ./run.sh claude-code --online claude "$@"
        fi
        ;;
    ai-sandbox.sh|ai-sandbox|*)
        if [ $# -eq 0 ]; then
            echo "🛡️  AI Agent Sandbox Global Wrapper"
            echo "----------------------------------------"
            echo "Usage: ai-sandbox [flavor] [args]"
            exit 1
        fi
        exec ./run.sh "$@"
        ;;
esac