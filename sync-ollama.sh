#!/usr/bin/env bash
set -euo pipefail

# Navigate to the repo directory relative to this script
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

STATE_FILE="$REPO_DIR/.ollama-managed-models"

echo "==> Syncing repository..."

# 1. Pull latest changes
if [ -d ".git" ]; then
    git pull --ff-only origin main
fi

declare -A REPO_MODELS=()
declare -A OLD_MODELS=()

# 2. Load previously managed models
if [ -f "$STATE_FILE" ]; then
    while IFS= read -r model; do
        [ -n "$model" ] && OLD_MODELS["$model"]=1
    done < "$STATE_FILE"
fi

# 3. Discover current Modelfiles
shopt -s nullglob
MODEL_FILES=( *.Modelfile *.modelfile )

if [ ${#MODEL_FILES[@]} -eq 0 ]; then
    echo "WARNING: No Modelfiles found."
fi

for f in "${MODEL_FILES[@]}"; do
    [ -f "$f" ] || continue

    # gemma-64k.Modelfile -> gemma-64k
    MODEL_NAME="${f%.*}"

    REPO_MODELS["$MODEL_NAME"]=1

    echo
    echo "==> Building: $MODEL_NAME"
    echo "    Source: $f"

    ollama create "$MODEL_NAME" -f "$f"
done

# 4. Remove models that were previously managed but no longer have a Modelfile
for model in "${!OLD_MODELS[@]}"; do
    if [[ -z "${REPO_MODELS[$model]:-}" ]]; then
        echo
        echo "==> Removing deleted model: $model"

        if ollama show "$model" >/dev/null 2>&1; then
            ollama rm "$model"
        else
            echo "    Already absent."
        fi
    fi
done

# 5. Save current managed model list
{
    for model in "${!REPO_MODELS[@]}"; do
        echo "$model"
    done
} | sort > "$STATE_FILE"

echo
echo "==> Ollama sync finished."
echo
echo "Managed models:"
cat "$STATE_FILE"
echo
echo "Installed models:"
ollama list