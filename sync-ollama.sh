#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

echo "==> Repository: $REPO_DIR"

# Pull latest repo
if [ -d ".git" ]; then
    git pull --ff-only origin main
fi

declare -A REPO_MODELS=()

# Find Modelfiles in the repo root
while IFS= read -r -d '' file; do
    filename="$(basename "$file")"
    model="${filename%.*}"
    REPO_MODELS["$model"]=1
done < <(
    find "$REPO_DIR" -maxdepth 1 -type f \
        \( -name '*.Modelfile' -o -name '*.modelfile' \) \
        -print0
)

echo
echo "==> Models defined by repository:"
if [ "${#REPO_MODELS[@]}" -eq 0 ]; then
    echo "    NONE"
else
    for model in "${!REPO_MODELS[@]}"; do
        echo "    $model"
    done
fi

# Build/update repo models
for model in "${!REPO_MODELS[@]}"; do
    file="$REPO_DIR/$model.Modelfile"

    # Handle lowercase extension
    if [ ! -f "$file" ]; then
        file="$REPO_DIR/$model.modelfile"
    fi

    echo
    echo "==> Building $model"
    ollama create "$model" -f "$file"
done

# Get installed models
mapfile -t INSTALLED_MODELS < <(
    ollama list | tail -n +2 | awk '{print $1}'
)

echo
echo "==> Installed models:"
printf '    %s\n' "${INSTALLED_MODELS[@]}"

# Delete anything not in repository
for installed in "${INSTALLED_MODELS[@]}"; do

    # ollama list:
    #   gemma-48k:latest
    #   gemma4:12b
    #
    # Repo:
    #   gemma-48k
    #
    base="${installed%%:*}"

    if [[ "${REPO_MODELS[$base]+exists}" ]]; then
        echo "==> KEEP   $installed"
    else
        echo "==> DELETE $installed"
        ollama rm "$installed"
    fi
done

echo
echo "==> Final state:"
ollama list