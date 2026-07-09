#!/usr/bin/env bash

# ==============================================================================
# AI Agent Sandbox - Secure & Flexible Launcher Script (With Phase 1 Validation)
# ==============================================================================

set -e

# ------------------------------------------------------------------------------
# Phase 1: Dependency and Input Validation Functions
# ------------------------------------------------------------------------------

# Check for required host dependencies
check_dependencies() {
    local missing=()
    
    # Check for podman (required for container operations)
    if ! command -v podman &> /dev/null; then
        missing+=("podman")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo "❌ Error: Missing required dependencies: ${missing[*]}"
        echo "Please install missing dependencies and try again:"
        echo "  - Install podman: https://podman.io/getting-started/installation"
        exit 1
    fi
    
    echo "✅ All dependencies verified"
}

# Validate and normalize input paths
validate_and_normalize_inputs() {
    # Validate and normalize project directory
    PROJECT_DIR="$(pwd)"
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "❌ Error: Project directory '$PROJECT_DIR' does not exist or is not accessible."
        exit 1
    fi
    
    # Validate flavor directory exists
    if [ ! -d "flavors/$FLAVOR" ]; then
        echo "❌ Error: Flavor directory 'flavors/$FLAVOR' does not exist."
        echo "Available flavors:"
        find flavors -maxdepth 1 -type d -exec basename {} \;
        exit 1
    fi
}

# Validate CONTAINER_CMD for runtime safety
validate_container_command() {
    if [ -n "$CONTAINER_CMD" ] && echo "$CONTAINER_CMD" | grep -qE "^(rm -rf|del|/etc/passwd|chmod.*777|mkfs|dd if=|/bin/sh\s+-c|su\s+root|sudo\s+apt-get.*\s+-y\s+--purge)"; then
        echo "⚠️  Warning: Potentially dangerous command detected:"
        echo "  Command: $CONTAINER_CMD"
        echo "  This could cause significant system damage."
        echo -n "  Continue? (y/N): "
        read -r -n 1 RESPONSE
        echo
        if [[ ! $RESPONSE =~ ^[Yy]$ ]]; then
            echo "❌ Command cancelled by user."
            exit 1
        fi
        echo "✅ User confirmed dangerous command execution"
    fi
}

# ------------------------------------------------------------------------------
# Configuration & Argument Parsing
# ------------------------------------------------------------------------------

BASE_IMAGE="ai-agent-sandbox:base"
DEFAULT_FLAVOR="hermes"

# Centralized global base directory for all sandbox data on the host
DATA_DIR="$HOME/.config/ai-agent-sandbox"

# Default command will be dynamically set below depending on the chosen flavor
CONTAINER_CMD=""

# Parse arguments
FLAVOR="$DEFAULT_FLAVOR"
NETWORK_FLAG="--network none"
ENV_FLAGS=""
FORCE_BUILD=false

# Parse arguments
FLAVOR_SET=false  # <--- Diese Zeile neu hinzufügen

while [[ $# -gt 0 ]]; do
    case $1 in
        --online)
            NETWORK_FLAG="--network host"
            shift
            ;;
        --build)
            FORCE_BUILD=true
            shift
            ;;
        --local)
            DATA_DIR="$(pwd)/.ai_agent_sandbox_data"
            shift
            ;;
        *)
            # Only interpret as flavor if we haven't locked in a flavor yet
            if [ "$FLAVOR_SET" = false ] && [ -d "flavors/$1" ]; then
                FLAVOR="$1"
                CONTAINER_CMD=""
                FLAVOR_SET=true  # <--- Jetzt ist der Flavor gelockt!
            else
                CONTAINER_CMD="$*"
                break
            fi
            shift
            ;;
    esac
done

# --- SET DYNAMIC DEFAULT COMMAND ---
if [ -z "$CONTAINER_CMD" ]; then
    case $FLAVOR in
        hermes)
            CONTAINER_CMD="hermes chat --tui"
            ;;
        aider)
            CONTAINER_CMD="aider"
            ;;
        claude-code)
            CONTAINER_CMD="claude"
            ;;
        base)
            CONTAINER_CMD="bash"
            ;;
        *)
            CONTAINER_CMD="bash"
            ;;
    esac
fi

# ------------------------------------------------------------------------------
# Execute Pre-Flight Validation (Phase 1)
# ------------------------------------------------------------------------------

echo "🔍 Executing Phase 1: Dependency and Input Validation"
echo "--------------------------------------------------"
check_dependencies
validate_and_normalize_inputs
validate_container_command
echo "✅ Phase 1 validation completed successfully"
echo "=================================================="

IMAGE_NAME="ai-agent-sandbox:$FLAVOR"
CONTAINER_NAME="ai-agent-jail-$(date +%s)"

echo "🛡️  AI Agent Sandbox Launcher"
echo "----------------------------------------"

# 1. Ensure Base Image exists (or force rebuild)
if [ "$FORCE_BUILD" = true ] || ! podman image exists "$BASE_IMAGE" >/dev/null 2>&1; then
    echo "📦 Building/Verifying base image $BASE_IMAGE..."
    podman build -t "$BASE_IMAGE" -f flavors/base/Containerfile flavors/base
fi

# 2. Ensure Flavor exists and build it
if [ "$FORCE_BUILD" = true ] || ! podman image exists "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "📦 Building/Verifying flavor image $IMAGE_NAME..."
    podman build -t "$IMAGE_NAME" -f flavors/$FLAVOR/Containerfile flavors/$FLAVOR
fi

# 3. Automatically detect and pass relevant API Keys & Base URLs from Host
while IFS='=' read -r name value; do
    if [[ $name =~ ^(OPENAI_|ANTHROPIC_|LITELLM_) ]]; then
        ENV_FLAGS="$ENV_FLAGS -e $name"
    fi
done < <(env)

# 4. Ensure the flavor-specific persistent data directory exists on the host
mkdir -p "$DATA_DIR/$FLAVOR"

echo "🚀 Launching AI Agent Sandbox..."
echo "📂 Mounting project directory: $(pwd)"
echo "🧠 Mounting agent memory:      $DATA_DIR/$FLAVOR"
echo "💻 Executing command:          $CONTAINER_CMD"
if [ "$NETWORK_FLAG" = "--network host" ]; then
    echo "🌐 Network: ENABLED (Host Mode - Local proxies accessible via localhost)"
else
    echo "🔒 Network: DISABLED (Strict Isolation Mode)"
fi
echo "----------------------------------------"

# --- DYNAMIC MAPPING TO NATIVE STANDARD DIRECTORIES ---
if [ "$FLAVOR" = "hermes" ]; then
    VOLUME_FLAG="-v $DATA_DIR/$FLAVOR:/root/.hermes:Z"
elif [ "$FLAVOR" = "aider" ]; then
    VOLUME_FLAG="-v $DATA_DIR/$FLAVOR:/root/.aider:Z"
    
    # Force Aider to store its history in its native standard directory inside the container
    ENV_FLAGS="$ENV_FLAGS -e AIDER_CHAT_HISTORY_FILE=/root/.aider/.aider.chat.history.md"
    ENV_FLAGS="$ENV_FLAGS -e AIDER_INPUT_HISTORY_FILE=/root/.aider/.aider.input.history"
    ENV_FLAGS="$ENV_FLAGS -e AIDER_CACHE_DIR=/root/.aider/.aider.tags.cache.v4"
else
    VOLUME_FLAG="-v $DATA_DIR/$FLAVOR:/root/.$FLAVOR:Z"
fi

# Run container with dynamic CONTAINER_CMD at the end
podman run --rm -it \
  --name "$CONTAINER_NAME" \
  $NETWORK_FLAG \
  $ENV_FLAGS \
  -v "$(pwd)":/workspace:Z \
  $VOLUME_FLAG \
  -w /workspace \
  "$IMAGE_NAME" $CONTAINER_CMD
