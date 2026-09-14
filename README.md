# Ollama Modelfile Auto-Sync

Automated management setup for custom Ollama model files. Any push to `main` containing `.Modelfile` definitions triggers a remote sync on `192.168.2.127`, creating/updating models and deleting stale ones automatically.

---

## 1. Repository Layout

Place your `.Modelfile` definitions directly in the root of the Git repository alongside `sync-ollama.sh`:

```text
.
├── gemma-32k.Modelfile
├── gemma-64k.Modelfile
├── sync-ollama.sh
└── README.md

```

---

## 2. In-Repo Sync Script (`sync-ollama.sh`)

This script dynamically builds any model matching `*.Modelfile` (or `*.modelfile`) and prunes local custom models no longer present in Git.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Locate repository root relative to script execution
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# 1. Pull latest changes if tracking remote branch
if [ -d ".git" ]; then
  git pull origin main
fi

declare -A REPO_MODELS

# 2. Build/Update all model files dynamically
shopt -s nullglob
for f in *.Modelfile *.modelfile; do
  [ -e "$f" ] || continue

  # Extract tag name: "gemma-32k.Modelfile" -> "gemma-32k"
  MODEL_NAME="${f%.*}"
  REPO_MODELS["$MODEL_NAME"]=1

  echo "Building Ollama model: $MODEL_NAME from$f..."
  ollama create "$MODEL_NAME" -f "$f"
done

# 3. Cleanup deleted / stale custom models
mapfile -t INSTALLED_MODELS < <(ollama list | awk 'NR>1 {print $1}')

for model in "${INSTALLED_MODELS[@]}"; do
  BASE_NAME="${model%:latest}"

  # Skip stock base models downloaded from Ollama registry
  if [[ "$model" == *":"* && "$model" != *":latest" ]]; then
    continue
  fi
  if [[ "$model" == "gemma"* \vert{}\vert{} "$model" == "llama"* || "$model" == "qwen"* \vert{}\vert{} "$model" == "mistral"* ]]; then
    continue
  fi

  # Remove custom models missing from Git
  if [[ -z "${REPO_MODELS[$BASE_NAME]:-}" && -z "${REPO_MODELS[$model]:-}" ]]; then
    echo "Deleting stale model: $model"
    ollama rm "$model"
  fi
done

echo "Ollama sync finished cleanly."

```

Make the script executable before committing:

```bash
chmod +x sync-ollama.sh

```

---

## 3. Server Setup (`192.168.2.127`)

Run these commands on the server to install `webhook` and configure auto-execution.

### Step 1: Clone Repository & Install Webhook

```bash
# Clone repository to working directory
git clone <YOUR_GIT_REPO_URL> /opt/ollama-modelfiles
chmod +x /opt/ollama-modelfiles/sync-ollama.sh

# Install webhook listener binary
apt-get update && apt-get install -y webhook

```

### Step 2: Create `/etc/webhook.json`

```json
[
  {
    "id": "ollama-sync",
    "execute-command": "/opt/ollama-modelfiles/sync-ollama.sh",
    "command-working-directory": "/opt/ollama-modelfiles",
    "response-message": "Ollama sync executed from repository script"
  }
]
```

### Step 3: Create Systemd Service (`/etc/systemd/system/ollama-webhook.service`)

```ini
[Unit]
Description=Ollama Git Webhook Listener
After=network.target ollama.service

[Service]
Type=simple
User=root
ExecStart=/usr/bin/webhook -hooks /etc/webhook.json -port 9000 -verbose
Restart=always

[Install]
WantedBy=multi-user.target

```

### Step 4: Enable Service

```bash
systemctl daemon-reload
systemctl enable --now ollama-webhook

```

---

## 4. Triggering the Sync

Send an HTTP POST or GET request to port `9000` to execute the sync pipeline manually or via GitHub Webhook:

```bash
curl http://192.168.2.127:9000/hooks/ollama-sync
```
