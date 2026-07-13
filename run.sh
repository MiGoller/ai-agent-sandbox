#!/usr/bin/env bash

# ==============================================================================
# AI Agent Sandbox - Secure & Flexible Launcher Script (With Phase 1 Validation)
# ==============================================================================

set -e

# Get the absolute directory where run.sh itself is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Robustly rescue the user's original working directory (works both for a
# direct run.sh invocation and via the wrapper, which already sets ORIGINAL_PWD).
# Saved once so that later cd calls cannot overwrite the value.
if [ -z "${ORIGINAL_PWD:-}" ]; then
    export ORIGINAL_PWD="$(pwd)"
fi

# Validate and normalize input paths
validate_and_normalize_inputs() {
    # Nutze das gerettete Verzeichnis des Users, falls vorhanden, sonst das aktuelle
    PROJECT_DIR="${ORIGINAL_PWD:-$(pwd)}"
    
    if [ ! -d "$PROJECT_DIR" ]; then
        echo "❌ Error: Project directory '$PROJECT_DIR' does not exist or is not accessible."
        exit 1
    fi
    
    # Validate flavor directory exists relative to the script location
    if [ ! -d "$SCRIPT_DIR/flavors/$FLAVOR" ]; then
        echo "❌ Error: Flavor directory '$SCRIPT_DIR/flavors/$FLAVOR' does not exist."
        echo "Available flavors:"
        find "$SCRIPT_DIR/flavors" -maxdepth 1 -type d -exec basename {} \;
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
FLAVOR_SET=false

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
            if [ "$FLAVOR_SET" = false ] && [ -d "$SCRIPT_DIR/flavors/$1" ]; then
                FLAVOR="$1"
                CONTAINER_CMD=""
                FLAVOR_SET=true
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

# ------------------------------------------------------------------------------
# Container Image Resolution (GHCR Default vs. Local Build)
# ------------------------------------------------------------------------------

REGISTRY="ghcr.io"
IMAGE_OWNER="migoller"

# Map flavor name to its specific GHCR repository name
case $FLAVOR in
    base)        IMAGE_REPO="ai-agent-sandbox-base" ;;
    hermes)      IMAGE_REPO="ai-agent-sandbox-hermes" ;;
    aider)       IMAGE_REPO="ai-agent-sandbox-aider" ;;
    claude-code) IMAGE_REPO="ai-agent-sandbox-claude-code" ;;
    *)           IMAGE_REPO="ai-agent-sandbox-$FLAVOR" ;;
esac

CONTAINER_NAME="ai-agent-jail-$(date +%s)"

echo "🛡️  AI Agent Sandbox Launcher"
echo "----------------------------------------"

if [ "$FORCE_BUILD" = true ]; then
    echo "🛠️  Force-building flavor '$FLAVOR' locally..."
    
    # Ensure local base image exists for the build process
    if ! podman image exists "$BASE_IMAGE" >/dev/null 2>&1; then
        echo "📦 Base image missing. Building $BASE_IMAGE locally..."
        podman build -t "$BASE_IMAGE" -f "$SCRIPT_DIR/flavors/base/Containerfile" "$SCRIPT_DIR/flavors/base"
    fi
    
    # Build the flavor locally
    IMAGE_NAME="ai-agent-sandbox:$FLAVOR"
    podman build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/flavors/$FLAVOR/Containerfile" "$SCRIPT_DIR/flavors/$FLAVOR"
else
    # Default: Use pre-built production images from GHCR
    IMAGE_NAME="${REGISTRY}/${IMAGE_OWNER}/${IMAGE_REPO}:latest"
    
    if ! podman image exists "$IMAGE_NAME" >/dev/null 2>&1; then
        echo "🚚 Pre-built image not found locally. Pulling from GHCR..."
        podman pull "$IMAGE_NAME" || exit 1
    else
        echo "🔄 Checking GHCR for updates to ${FLAVOR}..."
        podman pull -q "$IMAGE_NAME" || echo "⚠️  Could not check for updates, running cached local version."
    fi
fi

# Automatically detect and pass relevant API Keys & Base URLs from Host
while IFS='=' read -r name value; do
    if [[ $name =~ ^(OPENAI_|ANTHROPIC_|LITELLM_) ]]; then
        ENV_FLAGS="$ENV_FLAGS -e $name"
    fi
done < <(env)

# --- ISOLATION NAMESPACING ---
# Determine the exact host project path (robust via ORIGINAL_PWD, which run.sh
# rescues itself if the wrapper did not set it).
HOST_PROJECT_PATH="${ORIGINAL_PWD:-$(pwd)}"

# Robust, collision-free project ID: sha256 hash of the absolute path,
# truncated to 12 chars. Stable across directory renames and avoids collisions
# for identically-named subdirs under different parent paths.
PROJECT_KEY=$(printf '%s' "$HOST_PROJECT_PATH" | sha256sum | cut -c1-12)

# --- SURGICAL MOUNTING ---
# We mount the global Hermes config folder (skills, config, SOUL, state.db,
# auth) SHARED across ALL projects, but shadow ONLY the Memories folder
# project-specifically. This keeps skills/profiles intact while project-specific
# knowledge (RAG/Memory) is cleanly separated and no content-bleed occurs
# between repos.
#
# IMPORTANT: The global store deliberately stays at the previous path
# ($DATA_DIR/$FLAVOR), so no data migration is needed and the existing global
# config is preserved. Project-isolated memories live in a new projects/ subdir.
#
# Podman shadows the longer mount path (/root/.hermes/memories) over the
# shorter one (/root/.hermes) -- both can be mounted in parallel.
GLOBAL_DATA_DIR="$DATA_DIR/$FLAVOR"              # shared global store (path unchanged)
PROJECTS_BASE="$DATA_DIR/$FLAVOR/projects"       # project-isolated memory stores
PROJ_DATA_DIR="$PROJECTS_BASE/$PROJECT_KEY"      # store for exactly this project

mkdir -p "$GLOBAL_DATA_DIR"

# --- MIGRATION (one-time) ---
# Old run.sh stored the COMPLETE .hermes tree per project under
# $DATA_DIR/$FLAVOR/<dirname>/. The new global store lives at the root
# $DATA_DIR/$FLAVOR/. These old per-project stores therefore sit AS SUBDIRS
# inside the global root -> the root is never empty, which is why we do NOT
# check for "empty" here, but instead look specifically for legacy subdirs
# (of the form <dirname>/memories or <dirname>/skills).
#
# We promote the first legacy store found (which has no already-migrated
# root-level skills) once to the global root, so skills/config/persona are
# preserved. Its MEMORY.md is in any case shadowed by the project-isolated
# mount and does not bleed into the container.
if [ ! -d "$GLOBAL_DATA_DIR/skills" ] && [ ! -d "$GLOBAL_DATA_DIR/memories" ]; then
    OLD_STORE=$(find "$DATA_DIR/$FLAVOR" -maxdepth 1 -mindepth 1 -type d ! -name projects -print -quit 2>/dev/null)
    if [ -n "$OLD_STORE" ]; then
        cp -a "$OLD_STORE/." "$GLOBAL_DATA_DIR"/
        echo "📦 Migrated existing store '$OLD_STORE' -> global config (one-time)."
    fi
fi

# Only mount the global volume if the root is populated after migration/seed.
# If it stays empty (a truly fresh install with no legacy stores), we skip the
# global mount and fall back to the image-built-in skills/config, so the first
# start does not end up without skills.
# CAUTION: decide this only AFTER creating projects/ (see below), otherwise the
# projects/ subdir would artificially populate the root.
MOUNT_GLOBAL=false
# Create the project-isolated store only NOW (after the emptiness check above,
# otherwise the projects/ subdir would artificially populate the root and set
# MOUNT_GLOBAL to true incorrectly).
mkdir -p "$PROJ_DATA_DIR/memories"
# --- PERSONA BIND-MOUNT (instead of cp-seeding) ---
# Hermes also stores the global user persona (USER.md) under memories/. Because
# we shadow memories/ project-specifically, the persona would be invisible in
# the container otherwise. Instead of copying it physically into every project
# store (drift risk), we bind-mount the global USER.md directly to the target
# path inside the container.
#
# This is the podman-native, SELinux-safe alternative to a symlink: the file
# belongs to the global :Z volume (no crossing category), the container sees
# the IDENTICAL file, and changes to the global persona take effect
# immediately in ALL projects (no drift). Read-only, so projects cannot
# overwrite the global source.
#
# IMPORTANT: We deliberately do NOT bind-mount MEMORY.md (project-specific
# knowledge)! MEMORY.md holds exactly the knowledge that previously bled
# between repos. It stays project-isolated in the shadowing memories/ mount ->
# clean separation, knowledge accumulates isolated per project.
PERSONA_BIND=""
if [ -f "$GLOBAL_DATA_DIR/memories/USER.md" ]; then
    PERSONA_BIND="-v $GLOBAL_DATA_DIR/memories/USER.md:/root/.hermes/memories/USER.md:Z,ro"
fi

# Decide only NOW (after projects/ and persona setup) whether the global mount
# happens: the root must contain real global data (skills/ or memories/), not
# just the projects/ subdir we created ourselves.
if [ -d "$GLOBAL_DATA_DIR/skills" ] || [ -d "$GLOBAL_DATA_DIR/memories" ]; then
    MOUNT_GLOBAL=true
fi

echo "🚀 Launching AI Agent Sandbox..."
echo "📂 Mounting project directory: $HOST_PROJECT_PATH"
echo "🧠 Mounting global config:     $GLOBAL_DATA_DIR -> /root/.hermes (shared)"
echo "🔒 Mounting project memory:    $PROJ_DATA_DIR/memories -> /root/.hermes/memories (isolated, key=$PROJECT_KEY)"
echo "💻 Executing command:          $CONTAINER_CMD"
if [ "$NETWORK_FLAG" = "--network host" ]; then
    echo "🌐 Network: ENABLED (Host Mode - Local proxies/MCP servers accessible)"
else
    echo "🔒 Network: DISABLED (Strict Isolation Mode)"
fi
echo "----------------------------------------"

# --- DYNAMIC MAPPING TO NATIVE STANDARD DIRECTORIES ---
# Hermes: shared global store + project-isolated Memories folder (surgical).
if [ "$FLAVOR" = "hermes" ]; then
    VOLUME_FLAG=""
    if [ "$MOUNT_GLOBAL" = true ]; then
        VOLUME_FLAG="-v $GLOBAL_DATA_DIR:/root/.hermes:Z"
    fi
    VOLUME_FLAG="$VOLUME_FLAG -v $PROJ_DATA_DIR/memories:/root/.hermes/memories:Z"
    VOLUME_FLAG="$VOLUME_FLAG $PERSONA_BIND"
elif [ "$FLAVOR" = "aider" ]; then
    # Aider: shared global tool store, but project-isolated history/cache data
    VOLUME_FLAG=""
    if [ "$MOUNT_GLOBAL" = true ]; then
        VOLUME_FLAG="-v $GLOBAL_DATA_DIR:/root/.aider:Z"
    fi
    VOLUME_FLAG="$VOLUME_FLAG -v $PROJ_DATA_DIR:/root/.aider/project:Z"

    ENV_FLAGS="$ENV_FLAGS -e AIDER_CHAT_HISTORY_FILE=/root/.aider/project/.aider.chat.history.md"
    ENV_FLAGS="$ENV_FLAGS -e AIDER_INPUT_HISTORY_FILE=/root/.aider/project/.aider.input.history"
    ENV_FLAGS="$ENV_FLAGS -e AIDER_CACHE_DIR=/root/.aider/project/.aider.tags.cache.v4"
else
    # Generic flavor: shared global store + project-isolated data subdir
    VOLUME_FLAG=""
    if [ "$MOUNT_GLOBAL" = true ]; then
        VOLUME_FLAG="-v $GLOBAL_DATA_DIR:/root/.$FLAVOR:Z"
    fi
    VOLUME_FLAG="$VOLUME_FLAG -v $PROJ_DATA_DIR:/root/.$FLAVOR/project:Z"
fi

# Run container with project-isolated memory (chirurgical scoping) and matched
# absolute host paths so the working directory inside the container matches the
# host project path exactly.
podman run --rm -it \
  --name "$CONTAINER_NAME" \
  $NETWORK_FLAG \
  $ENV_FLAGS \
  -v "$HOST_PROJECT_PATH":"$HOST_PROJECT_PATH":Z \
  $VOLUME_FLAG \
  -w "$HOST_PROJECT_PATH" \
  "$IMAGE_NAME" $CONTAINER_CMD
