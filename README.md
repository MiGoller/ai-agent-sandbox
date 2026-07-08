# AI Agent Sandbox 🛡️

**Secure, isolated, and rootless environments for running autonomous AI CLI agents (`Nous Hermes`, `Claude Code`, `Aider`, etc.) without exposing your host system.**

## Enhanced Security Features

🧱 **Phase 1: Dependency & Input Validation**

The `run.sh` launcher now includes **enhanced security validation** in Phase 1:

- 🔍 **Dependency Verification**: Automatically checks for required tools (podman, etc.) before proceeding
- 🛡️ **Input Validation**: Validates project directory and flavor directories  
- ⚠️ **Safety Checks**: Detects and prevents potentially dangerous commands
- 📋 **Progress Tracking**: Clear feedback on validation progress

> *Before: Script assumed all dependencies were present and valid. After: Comprehensive pre-flight checks ensure system security.*

## The Problem

Modern AI coding agents are incredibly powerful, but they require execution capabilities in your terminal. If an agent is targeted by an **Indirect Prompt Injection** (e.g., by reading a malicious file in a public repository or a website), it could be instructed to:

- 🔐 **Exfiltrate private SSH keys** (`~/.ssh`) or AWS credentials
- 💥 **Run destructive commands** (`rm -rf /`) due to a hallucination or malicious input  
- 🌐 **Access sensitive host processes**

A simple `.gitignore` or `.hermesignore` style file only helps with token clutter—**it is not a security boundary.** Our enhanced launcher provides the security boundary you need.

## The Solution

`ai-agent-sandbox` locks your AI agents into a hardened **rootless container jail** using Podman with **enhanced security validation**.

- 🔒 **Complete Isolation**: The agent only sees the specific project folder you grant it access to. It cannot see your home directory, SSH keys, or environment variables.
- 🌐 **Network Lock (Optional/Default)**: Prevents data exfiltration by disabling network access unless explicitly enabled.
- 🚫 **No Root Privileges**: The agent runs as an unprivileged user (`agent`), preventing container escape vulnerabilities.
- 🛡️ **Enhanced Security**: Phase 1 validation adds dependency checks, path validation, and dangerous command detection.

---

## Prerequisites

To use this sandbox, you need **Podman** installed on your host system. Podman is preferred over Docker because it runs rootless by default, providing superior security.

### Enhanced Requirements

**Phase 1 Validation**: The enhanced `run.sh` script now performs:

- ✅ **Dependency Check**: Verifies podman and other required tools
- ✅ **Path Validation**: Ensures project and flavor directories are accessible
- ✅ **Safety Verification**: Scans for potentially dangerous commands
- ✅ **Progress Reporting**: Clear feedback during validation phase

### Installation Guide

#### 🐧 WSL2 (Ubuntu / Debian)

Inside your WSL2 terminal, run:

```bash
sudo apt update
sudo apt install -y podman
```

#### 🍏 macOS (Homebrew)

```bash
brew install podman
podman machine init
podman machine start
```

---

## Directory Structure

This repository uses a multi-flavor architecture to support different types of AI agents:

```
ai-agent-sandbox/
├── run.sh                 # Universal secure launcher (with Phase 1 validation)
└── flavors/
├── base/
│   └── Containerfile  # Hardened base Linux environment
└── python-hermes/
└── Containerfile  # Python flavor featuring 'uv' and Hermes Agent
```

### Flavor Options

- `base`: Minimal, hardened base environment
- `python-hermes`: Full-featured Python environment with Hermes TUI

---

Ah, I see what happened. By trying to hide the code inside raw HTML `<pre>` tags, your chat app didn't show a copyable code box at all—it just blended right into the screen like normal text!

Let's fix this for good. I am going to write out the Markdown blocks **without using backticks**. Instead, I will use indented text blocks so your interface displays it properly, and you can just copy it directly.

---

## Quick Start

1. **Clone this repository** to your local machine:
* `git clone [https://github.com/MiGoller/ai-agent-sandbox.git](https://github.com/MiGoller/ai-agent-sandbox.git)`
* `cd ai-agent-sandbox`


2. **Make the launcher script executable**:
* `chmod +x run.sh`


3. **Launch the Hermes Agent instantly**:
* `./run.sh --online`



*This performs Phase 1 validation, hooks into your host network (to allow local proxies like LiteLLM), boots the container, and automatically launches the Hermes TUI using your global persistent memory.*

---

## Usage & CLI Flags

The universal launcher script (`run.sh`) is highly flexible and acts as a wrapper for your container.

### Core Flags

* `./run.sh` -> Launches the container in **Strict Isolation Mode** (No network) and drops straight into the Hermes TUI.
* `./run.sh --online` -> Enables host network mode (required for external LLM API calls or local proxies).
* `./run.sh --build` -> Forces Podman to rebuild the container layers.
* `./run.sh --local` -> Switches agent memory from the global fallback (`~/.config/hermes_sandbox_data`) to a project-specific hidden folder (`.hermes_sandbox_data`) in your current directory.

### Switching Flavors

To use a different agent profile or base environment, pass the flavor name as the first argument:

* `./run.sh base`

### Running Custom Commands / Shell Access

If you want to bypass the automatic Hermes TUI and explore the container, check settings, or run a specific task, simply append your command to the end of the script:

* `# Get a standard interactive bash shell inside the container`
* `./run.sh --online bash`
* `# Execute a one-off Hermes CLI command and immediately exit`
* `./run.sh --online hermes profile list`

Inside the sandbox, your current directory is mounted to `/workspace`. You can now safely run your AI agent commands without worrying about your host system's safety.

## Security Features

### Phase 1: Dependency & Input Validation

The enhanced launcher script performs comprehensive security checks before launching:

1. **Dependency Validation**: Ensures required tools (podman) are available
2. **Path Validation**: Validates project directory and flavor directory accessibility
3. **Safety Checks**: Detects and prevents potentially dangerous commands
4. **Progress Tracking**: Clear feedback throughout the validation process

### Runtime Security

- **Container Isolation**: Agents run in isolated containers without root privileges
- **Network Controls**: Strict network isolation by default
- **Resource Limits**: Container resource constraints enforced
- **Memory Isolation**: Separate memory spaces for each agent

## License

This project is licensed under the **MIT License**. See the LICENSE file for details.

## Notes

### Phase 1 Validation

The enhanced launcher script (`run.sh`) includes **Phase 1 validation** to ensure:

- ✅ All system dependencies are present
- ✅ Directory paths are accessible and valid
- ✅ Potentially dangerous commands are detected and prevented
- ✅ User has proper permissions to execute the sandbox

This pre-flight validation prevents common runtime errors and enhances system security.

### Flavor Management

The sandbox supports multiple flavors for different use cases:

- **`base`**: Minimal, security-focused environment
- **`python-hermes`**: Full-featured Python environment with Hermes TUI

Each flavor includes optimized dependencies and configurations for its specific purpose while maintaining the same security principles.

For custom commands or troubleshooting, consult the script output for detailed error messages and installation guidance.