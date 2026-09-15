#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

STATE_FILE="$REPO_DIR/.ollama_sync_state"

echo "==> Syncing Ollama models from: $REPO_DIR"

# ---------------------------------------------------------------------------
# 1. Update repository
# ---------------------------------------------------------------------------

if [[ -d ".git" ]]; then
    git pull --ff-only origin main
fi

# ---------------------------------------------------------------------------
# 2. Get Modelfiles tracked by Git & calculate checksums
# ---------------------------------------------------------------------------

declare -A REPO_MODELS=()
declare -A REPO_HASHES=()

while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    filename="$(basename "$file")"

    case "$filename" in
        *.Modelfile) model="${filename%.Modelfile}" ;;
        *.modelfile) model="${filename%.modelfile}" ;;
        *) continue ;;
    esac

    full_path="$REPO_DIR/$file"
    REPO_MODELS["$model"]="$full_path"
    REPO_HASHES["$model"]="$(sha256sum "$full_path" | awk '{print $1}')"
done < <(git ls-files -- '*.Modelfile' '*.modelfile')

echo
echo "==> Repository defines ${#REPO_MODELS[@]} model(s):"
if [[ ${#REPO_MODELS[@]} -gt 0 ]]; then
    printf '%s\n' "${!REPO_MODELS[@]}" | sort | sed 's/^/    /'
else
    echo "    NONE"
fi

# ---------------------------------------------------------------------------
# 3. Load previous state (to track what WE managed)
# ---------------------------------------------------------------------------

declare -A PREV_MODELS=()
if [[ -f "$STATE_FILE" ]]; then
    while IFS='=' read -r model hash; do
        [[ -n "$model" ]] && PREV_MODELS["$model"]="$hash"
    done < "$STATE_FILE"
fi

# ---------------------------------------------------------------------------
# 4. Build or update only changed/new models
# ---------------------------------------------------------------------------

echo
echo "==> Building/Updating changed repository models..."

for model in "${!REPO_MODELS[@]}"; do
    file="${REPO_MODELS[$model]}"
    current_hash="${REPO_HASHES[$model]}"
    prev_hash="${PREV_MODELS[$model]:-}"

    exists=false
    if ollama list | awk 'NR > 1 {print $1}' | grep -Fxq "$model"; then
        exists=true
    fi

    if [[ "$exists" == "true" && "$current_hash" == "$prev_hash" ]]; then
        echo "    SKIP $model (unchanged)"
        continue
    fi

    echo "==> BUILD/UPDATE $model"
    ollama create "$model" -f "$file"
done

# ---------------------------------------------------------------------------
# 5. Prune ONLY models that were previously managed by this repo but removed
# ---------------------------------------------------------------------------

echo
echo "==> Cleaning stale repository models..."

for prev_model in "${!PREV_MODELS[@]}"; do
    if [[ -v "REPO_MODELS[$prev_model]" ]]; then
        continue
    fi

    echo "    NUKE $prev_model (removed from repo)"
    ollama rm "$prev_model" || true
done

# ---------------------------------------------------------------------------
# 6. Save current state
# ---------------------------------------------------------------------------

> "$STATE_FILE"
for model in "${!REPO_MODELS[@]}"; do
    echo "$model=${REPO_HASHES[$model]}" >> "$STATE_FILE"
done

echo
echo "==> FINAL OLLAMA STATE"
ollama list

echo
echo "==> Ollama sync complete."