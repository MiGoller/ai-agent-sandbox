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

# Rette das ursprüngliche Arbeitsverzeichnis des Users robust (funktioniert
# sowohl beim direkten Aufruf von run.sh als auch über den Wrapper, der
# ORIGINAL_PWD bereits setzt). Einmalig sichern, damit spätere cd-Aufrufe
# den Wert nicht überschreiben.
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
# Bestimme den exakten Host-Pfad (robust über ORIGINAL_PWD, das in run.sh selbst
# gerettet wurde, falls der Wrapper es nicht gesetzt hat).
HOST_PROJECT_PATH="${ORIGINAL_PWD:-$(pwd)}"

# Robuste, kollisionsfreie Projekt-ID: sha256-Hash des absoluten Pfads,
# gekürzt auf 12 Zeichen. Stabil bei Ordner-Umbenennung und vermeidet
# Kollisionen bei gleichnamigen Unterordnern in verschiedenen Elternpfaden.
PROJECT_KEY=$(printf '%s' "$HOST_PROJECT_PATH" | sha256sum | cut -c1-12)

# --- CHIRURGISCHES MOUNTING ---
# Wir mounten den globalen Hermes-Konfigurationsordner (Skills, config, SOUL,
# state.db, auth) FÜR ALLE PROJEKTE GLEICH, überschatten aber gezielt NUR den
# Memories-Ordner projektspezifisch. So bleiben Skills/Profile erhalten, während
# projektspezifisches Wissen (RAG/Memory) sauber getrennt wird und kein
# Content-Bleed zwischen Repos stattfindet.
#
# WICHTIG: Der globale Store bleibt bewusst am bisherigen Pfad ($DATA_DIR/$FLAVOR),
# damit keine Datenmigration nötig ist und bestehende Global-Konfiguration erhalten
# bleibt. Projektisolierte Memories liegen in einem neuen projects/-Unterordner.
#
# Podman überschattet den längeren Mount-Pfad (/root/.hermes/memories) über den
# kürzeren (/root/.hermes) – beide können parallel gemountet werden.
GLOBAL_DATA_DIR="$DATA_DIR/$FLAVOR"              # bestehender, geteilter Global-Store (Pfad bewusst unverändert)
PROJECTS_BASE="$DATA_DIR/$FLAVOR/projects"       # projektisolierte Memory-Stores
PROJ_DATA_DIR="$PROJECTS_BASE/$PROJECT_KEY"      # Store für genau dieses Projekt

mkdir -p "$GLOBAL_DATA_DIR"

# --- MIGRATION (einmalig) ---
# Alte run.sh speicherte den KOMPLETTEN .hermes-Tree pro Projekt unter
# $DATA_DIR/$FLAVOR/<dirname>/. Der neue Global-Store liegt auf der Wurzel
# $DATA_DIR/$FLAVOR/. Diese alten per-Projekt-Stores liegen also ALS
# UNTERORDNER in der Global-Wurzel -> die Wurzel ist nie leer, weshalb wir
# HIER nicht auf "leer" prüfen, sondern gezielt nach Legacy-Unterordnern
# (Typ: <dirname>/memories oder <dirname>/skills) suchen.
#
# Wir befördern den ersten gefundenen Legacy-Store (der noch keine bereits
# migrierten Root-Level-Skills besitzt) einmalig zur Global-Wurzel, damit
# Skills/Config/Persona erhalten bleiben. MEMORY.md darin wird ohnehin durch
# den projektisolerten Mount überschattet und bleedet nicht in den Container.
if [ ! -d "$GLOBAL_DATA_DIR/skills" ] && [ ! -d "$GLOBAL_DATA_DIR/memories" ]; then
    OLD_STORE=$(find "$DATA_DIR/$FLAVOR" -maxdepth 1 -mindepth 1 -type d ! -name projects -print -quit 2>/dev/null)
    if [ -n "$OLD_STORE" ]; then
        cp -a "$OLD_STORE/." "$GLOBAL_DATA_DIR"/
        echo "📦 Migrated existing store '$OLD_STORE' -> global config (one-time)."
    fi
fi

# Global-Volume nur mounten, wenn die Wurzel nach Migration/Seed befüllt ist.
# Bleibt sie leer (wirklich frische Installation ohne alte Stores), verzichten
# wir auf den Global-Mount und verlassen uns auf die image-eingebauten
# Skills/Config, damit der erste Start nicht ohne Skills endet.
# ACHTUNG: erst NACH Anlegen von projects/ prüfen (siehe unten), sonst würde
# das projects/-Unterverzeichnis die Wurzel künstlich füllen.
MOUNT_GLOBAL=false
# Erst JETZT den projektisolerten Store anlegen (nach der Leer-Prüfung oben,
# sonst würde das projects/-Unterverzeichnis die Wurzel künstlich füllen und
# MOUNT_GLOBAL fälschlich auf true setzen).
mkdir -p "$PROJ_DATA_DIR/memories"
# --- PERSONA BIND-MOUNT (statt cp-Seeding) ---
# Hermes legt die globale User-Persona (USER.md) ebenfalls unter memories/ ab.
# Da wir memories/ projektisolert überschatten, wäre die Persona sonst im Container
# unsichtbar. Statt sie physisch in jeden Projekt-Store zu kopieren (Drift-Risiko),
# bind-mounten wir die globale USER.md direkt an den Zielpfad im Container.
#
# Das ist die podman-native, SELinux-sichere Variante eines Symlinks: die Datei
# gehoert zum globalen :Z-Volume (keine ueberschreitende Kategorie), der Container
# sieht die IDENTISCHE Datei, und Aenderungen an der globalen Persona wirken sofort
# in ALLEN Projekten (kein Drift). read-only, damit Projekte die globale Quelle
# nicht ueberschreiben.
#
# WICHTIG: Wir bind-mounten BEWUSST NICHT MEMORY.md (das projektspezifische Wissen)!
# MEMORY.md enthaelt genau das Wissen, das bisher zwischen Repos gebleedet ist.
# Es verbleibt projektisoliert im ueberschattenden memories/-Mount -> saubere
# Trennung, das Wissen akkumuliert fortan isoliert je Projekt.
PERSONA_BIND=""
if [ -f "$GLOBAL_DATA_DIR/memories/USER.md" ]; then
    PERSONA_BIND="-v $GLOBAL_DATA_DIR/memories/USER.md:/root/.hermes/memories/USER.md:Z,ro"
fi

# Erst JETZT (nach Anlegen von projects/ und Persona-Setup) entscheiden, ob der
# Global-Mount erfolgt: die Wurzel muss echte Global-Daten enthalten (skills/
# oder memories/), nicht nur das projects/-Subdir, das wir selbst erstellt haben.
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
# Hermes: globaler Store + projektisolierter Memories-Ordner (chirurgisch).
if [ "$FLAVOR" = "hermes" ]; then
    VOLUME_FLAG=""
    if [ "$MOUNT_GLOBAL" = true ]; then
        VOLUME_FLAG="-v $GLOBAL_DATA_DIR:/root/.hermes:Z"
    fi
    VOLUME_FLAG="$VOLUME_FLAG -v $PROJ_DATA_DIR/memories:/root/.hermes/memories:Z"
    VOLUME_FLAG="$VOLUME_FLAG $PERSONA_BIND"
elif [ "$FLAVOR" = "aider" ]; then
    # Aider: globaler Tool-Store, aber projektisolierte History/Cache-Daten
    VOLUME_FLAG=""
    if [ "$MOUNT_GLOBAL" = true ]; then
        VOLUME_FLAG="-v $GLOBAL_DATA_DIR:/root/.aider:Z"
    fi
    VOLUME_FLAG="$VOLUME_FLAG -v $PROJ_DATA_DIR:/root/.aider/project:Z"

    ENV_FLAGS="$ENV_FLAGS -e AIDER_CHAT_HISTORY_FILE=/root/.aider/project/.aider.chat.history.md"
    ENV_FLAGS="$ENV_FLAGS -e AIDER_INPUT_HISTORY_FILE=/root/.aider/project/.aider.input.history"
    ENV_FLAGS="$ENV_FLAGS -e AIDER_CACHE_DIR=/root/.aider/project/.aider.tags.cache.v4"
else
    # Generischer Flavor: globaler Store + projektisolierter Daten-Unterordner
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
