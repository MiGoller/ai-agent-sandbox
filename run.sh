#!/usr/bin/env bash

# ==============================================================================
# AI Agent Sandbox - Secure & Flexible Launcher Script
# ==============================================================================

set -e

BASE_IMAGE="ai-agent-sandbox:base"
DEFAULT_FLAVOR="python-hermes"

# Parse arguments
FLAVOR="$DEFAULT_FLAVOR"
NETWORK_FLAG="--network none"
ENV_FLAGS=""
FORCE_BUILD=false

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
        *)
            FLAVOR="$1"
            shift
            ;;
    esac
done

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
if [ ! -d "flavors/$FLAVOR" ]; then
    echo "❌ Error: Flavor '$FLAVOR' does not exist."
    exit 1
fi

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

# 4. NEU: Erstelle den persistenten Datenordner auf dem Host, falls er fehlt
DATA_DIR="$(pwd)/.hermes_sandbox_data"
mkdir -p "$DATA_DIR"

echo "🚀 Launching AI Agent Sandbox..."
echo "📂 Mounting project directory: $(pwd)"
echo "🧠 Mounting agent memory:      $DATA_DIR"
if [ "$NETWORK_FLAG" = "--network host" ]; then
    echo "🌐 Network: ENABLED (Host Mode - Local proxies accessible via localhost)"
else
    echo "🔒 Network: DISABLED (Strict Isolation Mode)"
fi
echo "----------------------------------------"

# Jetzt mit zweitem Mount für das Gedächtnis des Agenten
podman run --rm -it \
  --name "$CONTAINER_NAME" \
  $NETWORK_FLAG \
  $ENV_FLAGS \
  -v "$(pwd)":/workspace:Z \
  -v "$DATA_DIR":/root/.hermes:Z \
  -w /workspace \
  "$IMAGE_NAME" /bin/bash
