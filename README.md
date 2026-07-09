# AI Agent Sandbox 🛡️

**Secure, isolated, and rootless environments for running autonomous AI CLI agents (`Hermes`, `Aider`, `Claude Code`) without exposing your host system.**

## The Problem

Modern AI coding agents are incredibly powerful, but they require execution capabilities in your terminal. If an agent is targeted by an **Indirect Prompt Injection** (e.g., by reading a malicious file in a public repository or a website), it could be instructed to:

- 🔐 **Exfiltrate private SSH keys** (`~/.ssh`) or credentials.
- 💥 **Run destructive commands** (`rm -rf /`) due to a hallucination or malicious input.
- 🌐 **Access sensitive host processes**.

A simple `.gitignore` style file only helps with token clutter—**it is not a security boundary.**

## The Solution

`ai-agent-sandbox` locks your AI agents into a hardened **rootless container jail** using Podman with multi-layered security verification.

- 🔒 **Complete Isolation:** The agent only sees the specific project folder you grant it access to. It cannot see your home directory or unapproved processes.
- 🌐 **Network Lock (Optional/Default):** Prevents data exfiltration by disabling network access unless explicitly enabled via `--online`.
- 🛡️ **Phase 1 Pre-Flight Validation:** The launcher automatically checks host dependencies, validates input paths, and intercepts potentially dangerous commands before execution.
- 🧹 **Clean Workspace Policy:** Tool-specific data, chat histories, and configurations are mapped to a centralized host directory, keeping your project folders completely clutter-free.

---

## Directory Structure & Memory Mapping

The host system provides a centralized configuration directory that maps dynamically to the native standard directories expected by each tool inside the container:

```text
Host System                               Container (Guest)
└── ~/.config/ai-agent-sandbox/
    ├── hermes/       ───────────────►    /root/.hermes/
    ├── aider/        ───────────────►    /root/.aider/
    └── claude-code/  ───────────────►    /root/.claude-code/

```

### Repository Layout

```text
.
├── run.sh                 # Universal secure launcher (with Phase 1 validation)
└── flavors/
    ├── base/              # Common core layer (Ubuntu 24.04 + core utilities)
    ├── hermes/            # Hermes Agent flavor layer
    ├── aider/             # Aider flavor layer
    └── claude-code/       # Claude Code flavor layer

```

---

## Supported Flavors

| Flavor | Target AI Agent | Default Container Command | Network Requirement |
| --- | --- | --- | --- |
| `hermes` | Open-source multi-agent router | `hermes chat --tui` | Offline capable |
| `aider` | CLI Pair-Programmer | `aider` | Offline capable (with local LLMs) |
| `claude-code` | Anthropic's official CLI Agent | `claude` | Requires `--online` |
| `base` | Sandbox core environment | `bash` | Offline capable |

---

## Prerequisites & Installation

To use this sandbox, you need **Podman** installed on your host system. Podman is required because it runs rootless by default, providing superior security over standard Docker setups.

### 🐧 Linux / WSL2 (Ubuntu / Debian)

```bash
sudo apt update && sudo apt install -y podman

```

### 🍏 macOS (Homebrew)

```bash
brew install podman
podman machine init
podman machine start

```

---

## Quick Start

1. **Clone the repository and run the global installer**:
    ```bash
    git clone [https://github.com/MiGoller/ai-agent-sandbox.git](https://github.com/MiGoller/ai-agent-sandbox.git)
    cd ai-agent-sandbox
    ./setup.sh
    ```
2. **Launch any agent instantly from ANY directory on your host**:
    ```bash
    hermes
    aider
    claude
    ```

---

## Usage & CLI Flags

The universal launcher script (`run.sh`) acts as a secure wrapper for your container execution.

### Core Flags

* `./run.sh` ➔ Launches the default flavor (`hermes`) in **Strict Isolation Mode** (No network).
* `./run.sh --online` ➔ Enables host network mode (required for external API calls or local LLM proxies like LiteLLM).
* `./run.sh --build` ➔ Forces Podman to rebuild the container layers for the selected flavor.
* `./run.sh --local` ➔ Switches agent memory from the global fallback (`~/.config/ai-agent-sandbox`) to a project-specific hidden folder (`.ai_agent_sandbox_data`) in your current directory.

### Custom Commands & Shell Access

To bypass the default startup command or drop into an interactive debug shell, simply append your command to the end of the script:

```bash
# Get a standard interactive bash shell inside the Aider sandbox
./run.sh aider bash

# Execute a one-off command and immediately exit
./run.sh --online hermes profile list

```

## License

This project is licensed under the **MIT License**.
