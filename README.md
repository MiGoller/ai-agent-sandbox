# AI Agent Sandbox 🛡️

**Secure, isolated, and rootless environments for running autonomous AI CLI agents (`Hermes`, `Aider`, `Claude Code`) without exposing your host system.**

## The Problem

Modern AI coding agents are incredibly powerful, but they require execution capabilities in your terminal. If an agent is targeted by an **Indirect Prompt Injection** (e.g., by reading a malicious file in a public repository or a website), it could be instructed to:

- 🔐 **Exfiltrate private SSH keys** (`~/.ssh`) or credentials.
- 💥 **Run destructive commands** (`rm -rf /`) due to a hallucination or malicious input.
- 🌐 **Access sensitive host processes.**

A simple `.gitignore` style file only helps with token clutter—**it is not a security boundary.**

## The Solution

`ai-agent-sandbox` locks your AI agents into a hardened **rootless container jail** using Podman with multi-layered security verification.

- 🔒 **Complete Isolation:** The agent only sees the specific project folder you grant it access to. It cannot see your home directory or unapproved processes.
- 🌐 **Network Lock (Optional/Default):** Prevents data exfiltration by disabling network access unless explicitly enabled via `--online`.
- 🛡️ **Phase 1 Pre-Flight Validation:** The launcher automatically checks host dependencies, validates input paths, and intercepts potentially dangerous commands before execution.
- 🧹 **Clean Workspace Policy:** Tool-specific data, chat histories, and configurations are mapped to a centralized host directory, keeping your project folders completely clutter-free.
- 🚀 **Cloud-First Deployment:** Images are automatically built via CI/CD and published to the **GitHub Container Registry (GHCR)**. The launcher fetches them seamlessly on demand.

---

## Directory Structure & Memory Mapping

The host system provides a centralized configuration directory that maps dynamically to the native standard directories expected by each tool inside the container:

```text
Host System                                          Container (Guest)
└── ~/.config/ai-agent-sandbox/
    ├── hermes/              ──────────────────────►   /root/.hermes/            (shared global store: skills, config, SOUL, state.db, auth)
    │   └── projects/
    │       └── <sha256-of-abs-path[:12]>/
    │           └── memories/  ───────────────────►   /root/.hermes/memories/   (project-isolated: RAG/Memory, no cross-repo bleed)
    │               └── USER.md (bind-mounted :ro from global)                  (persona, single source of truth)
    ├── aider/               ──────────────────────►   /root/.aider/
    │   └── projects/
    │       └── <sha256-of-abs-path[:12]>/             (project-isolated history/cache)
    └── claude-code/         ──────────────────────►   /root/.claude-code/
```

### Project Isolation (Content-Bleed Prevention)

The launcher scopes agent memory **per project directory**, not per tool. A short, collision-free project key (`sha256` of the project's absolute host path, truncated to 12 chars) isolates each repo's `memories/` store:

- **Shared global store** — skills, config, persona source and tool state are mounted once for all projects (`/root/.hermes` inside the container).
- **Project-isolated memory** — only `~/.hermes/memories` is mounted from `projects/<key>/memories`, shadowing the global folder via Podman sub-mount. Project-specific knowledge (RAG/Memory) therefore never leaks between repositories.
- **Persona bind-mount** — the global `USER.md` is bind-mounted read-only (`USER.md:Z,ro`) into each project's `memories/`. This is a single source of truth: editing the global persona takes effect in every project immediately, with zero drift, and projects cannot overwrite it.
- **`MEMORY.md` is deliberately NOT shared** — it holds per-project knowledge and stays isolated in each project store.

> **Migration note:** Legacy installs stored the *entire* `.hermes` tree per project under `~/.config/ai-agent-sandbox/hermes/<dirname>/`. On first launch with the new layout, the launcher promotes the first such legacy store once to the shared global root (skills/config/persona preserved); its `MEMORY.md` is shadowed and does not bleed into the container.

### Repository Layout

```text
.
├── run.sh                 # Universal secure launcher (with GHCR integration & Phase 1 validation)
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

## 🚚 Container Management & Updates

The launcher script (`run.sh`) connects directly to the GitHub Container Registry. You do not need to build images locally!

### Automatic Image Management
When executing an agent, the sandbox automatically handles the lifecycle:
* **First Launch:** If the image isn't available on your host, it will be pulled from GHCR automatically.
* **Auto-Updates:** On subsequent launches, the script performs a quick, low-overhead check against GHCR to ensure you are always running the latest, most secure image version.

### Registry Authentication
If your repository or packages are set to private, ensure your local Podman client is authenticated:
```bash
echo "YOUR_GITHUB_TOKEN" | podman login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

## Usage & CLI Flags

The universal launcher script (`run.sh`) acts as a secure wrapper for your container execution.

### Core Flags

* `./run.sh` ➔ Launches the default flavor (`hermes`) in **Strict Isolation Mode** (No network) using the production GHCR image.
* `./run.sh --online` ➔ Enables host network mode (required for external API calls or local LLM proxies like LiteLLM).
* `./run.sh --build` ➔ Enforces local compilation. It bypasses the GHCR registry and builds the container layers locally from your `flavors/` directories (ideal for tweaking or development).
* `./run.sh --local` ➔ Switches agent memory from the global fallback (`~/.config/ai-agent-sandbox`) to a project-specific hidden folder (`.ai_agent_sandbox_data`) in your current directory.

### Dry-Run / Debugging

To inspect the exact `podman run` command (all volume mounts, env pass-through, network mode) **without starting a container**, generate a `sed`-modified copy of the launcher and run it:

```bash
# Preview the resolved podman command (no container is started)
sed 's/^podman run /echo podman run /' run.sh > run-dry.sh && chmod +x run-dry.sh
./run-dry.sh hermes --online
```

Use this to verify the per-project memory mounts (`projects/<key>/memories`) and the read-only persona bind-mount (`USER.md:Z,ro`) before launching for real. `run-dry.sh` is git-ignored.

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