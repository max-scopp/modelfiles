#!/usr/bin/env bash
set -euo pipefail

# Navigate to the repo directory relative to this script
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# 1. Pull latest changes if inside a git tracking repository
if [ -d ".git" ]; then
  git pull origin main
fi

declare -A REPO_MODELS

# 2. Iterate dynamically over all *.Modelfile files
shopt -s nullglob
for f in *.Modelfile *.modelfile; do
  [ -e "$f" ] || continue
  
  # Extract model tag name (e.g., gemma-32k.Modelfile -> gemma-32k)
  MODEL_NAME="${f%.*}"
  REPO_MODELS["$MODEL_NAME"]=1

  echo "Building Ollama model: $MODEL_NAME from $f..."
  ollama create "$MODEL_NAME" -f "$f"
done

# 3. Clean up deleted / stale custom models
mapfile -t INSTALLED_MODELS < <(ollama list | awk 'NR>1 {print $1}')

for model in "${INSTALLED_MODELS[@]}"; do
  BASE_NAME="${model%:latest}"
  
  # Skip stock/base downloaded models
  if [[ "$model" == *":"* && "$model" != *":latest" ]]; then
    continue
  fi
  if [[ "$model" == "gemma"* || "$model" == "llama"* || "$model" == "qwen"* || "$model" == "mistral"* ]]; then
    continue
  fi

  # Remove models missing from Git
  if [[ -z "${REPO_MODELS[$BASE_NAME]:-}" && -z "${REPO_MODELS[$model]:-}" ]]; then
    echo "Deleting stale model: $model"
    ollama rm "$model"
  fi
done

echo "Ollama sync finished cleanly."
