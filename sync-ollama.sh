#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

# 1. Pull latest repository state
if [ -d ".git" ]; then
    git pull --ff-only origin main
fi

declare -A REPO_MODELS=()

# 2. Find every Modelfile in the repository
shopt -s nullglob
MODEL_FILES=( *.Modelfile *.modelfile )

for f in "${MODEL_FILES[@]}"; do
    [ -f "$f" ] || continue

    # gemma-64k.Modelfile -> gemma-64k
    MODEL_NAME="${f%.*}"

    REPO_MODELS["$MODEL_NAME"]=1

    echo "==> Building $MODEL_NAME from $f"
    ollama create "$MODEL_NAME" -f "$f"
done

# 3. Get every installed Ollama model
mapfile -t INSTALLED_MODELS < <(
    ollama list | awk 'NR > 1 { print $1 }'
)

# 4. Delete EVERYTHING that isn't represented by a Modelfile
for installed in "${INSTALLED_MODELS[@]}"; do

    # ollama list gives e.g.:
    # gemma-64k:latest
    #
    # Repository gives:
    # gemma-64k
    #
    # Strip tag for exact repository comparison.
    BASE_NAME="${installed%%:*}"

    if [[ -n "${REPO_MODELS[$BASE_NAME]:-}" ]]; then
        echo "==> Keeping $installed"
    else
        echo "==> Removing $installed"
        ollama rm "$installed"
    fi
done

echo
echo "==> Ollama sync complete."
echo
echo "Repository models:"
for model in "${!REPO_MODELS[@]}"; do
    echo "  $model"
done

echo
echo "Installed models:"
ollama list