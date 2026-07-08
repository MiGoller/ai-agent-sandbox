Hier ist der Inhalt völlig ohne Markdown-Formatierung (ohne umschließenden Codeblock), sodass er im Chat nicht mehr aufbrechen kann. Du kannst den Text von der ersten bis zur letzten Zeile einfach markieren und kopieren:

# AI Agent Sandbox 🛡️

Secure, isolated, and rootless environments for running autonomous AI CLI agents (`Nous Hermes`, `Claude Code`, `Aider`, etc.) without exposing your host system.

## The Problem

Modern AI coding agents are incredibly powerful, but they require execution capabilities in your terminal. If an agent is targeted by an **Indirect Prompt Injection** (e.g., by reading a malicious file in a public repository or a website), it could be instructed to:

* Exfiltrate your private SSH keys (`~/.ssh`) or AWS credentials.
* Run destructive commands (`rm -rf /`) due to a hallucination or malicious input.
* Access sensitive host processes.

A simple `.gitignore` or `.hermesignore` style file only helps with token clutter—**it is not a security boundary.**

## The Solution

`ai-agent-sandbox` locks your AI agents into a hardened **rootless container jail** using Podman.

* **Complete Isolation:** The agent only sees the specific project folder you grant it access to. It cannot see your home directory, SSH keys, or environment variables.
* **Network Lock (Optional/Default):** Prevents data exfiltration by disabling network access unless explicitly enabled.
* **No Root Privileges:** The agent runs as an unprivileged user (`agent`), preventing container escape vulnerabilities.

---

## Prerequisites

To use this sandbox, you need **Podman** installed on your host system. Podman is preferred over Docker because it runs rootless by default, providing superior security.

### Installation Guide

#### 🐧 WSL2 (Ubuntu / Debian)

Inside your WSL2 terminal, run:

sudo apt update
sudo apt install -y podman

#### 🍏 macOS (Homebrew)

brew install podman
podman machine init
podman machine start

---

## Directory Structure

This repository uses a multi-flavor architecture to support different types of AI agents:

ai-agent-sandbox/
├── run.sh                 # Universal secure launcher
└── flavors/
├── base/
│   └── Containerfile  # Hardened base Linux environment
└── python-hermes/
└── Containerfile  # Python flavor featuring 'uv' and Hermes Agent

---

## Quick Start

1. **Clone this repository** to your local machine:
git clone [https://github.com/MiGoller/ai-agent-sandbox.git](https://www.google.com/search?q=https://github.com/MiGoller/ai-agent-sandbox.git)
cd ai-agent-sandbox
2. **Make the launcher script executable**:
chmod +x run.sh
3. **Launch the sandbox** (it will automatically build the images on its first run):
./run.sh python-hermes
*Note: If no flavor is specified, it defaults to `python-hermes`.*

Inside the sandbox, your current directory is mounted to `/workspace`. You can now safely run your AI agent commands without worrying about your host system's safety.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
