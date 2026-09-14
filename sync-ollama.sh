#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

echo "==> Syncing Ollama models from: $REPO_DIR"

# ---------------------------------------------------------------------------
# 1. Update repository
# ---------------------------------------------------------------------------

if [[ -d ".git" ]]; then
    git pull --ff-only origin main
fi

# ---------------------------------------------------------------------------
# 2. Discover EXACTLY the Modelfiles tracked by Git
# ---------------------------------------------------------------------------

declare -A REPO_MODELS=()

while IFS= read -r file; do
    [[ -n "$file" ]] || continue

    filename="$(basename "$file")"

    case "$filename" in
        *.Modelfile)
            model="${filename%.Modelfile}"
            ;;
        *.modelfile)
            model="${filename%.modelfile}"
            ;;
        *)
            continue
            ;;
    esac

    REPO_MODELS["$model"]="$REPO_DIR/$file"
done < <(
    git ls-files -- '*.Modelfile' '*.modelfile'
)

echo
echo "==> Repository defines ${#REPO_MODELS[@]} model(s):"

printf '%s\n' "${!REPO_MODELS[@]}" | sort | sed 's/^/    /'

# ---------------------------------------------------------------------------
# 3. BUILD EVERYTHING FIRST
# ---------------------------------------------------------------------------

echo
echo "==> Building repository models..."

for model in "${!REPO_MODELS[@]}"; do
    file="${REPO_MODELS[$model]}"

    echo
    echo "==> BUILD $model"
    ollama create "$model" -f "$file"
done

# If we got here, every model built successfully.
echo
echo "==> All repository models built successfully."

# ---------------------------------------------------------------------------
# 4. NUKE EVERYTHING NOT IN THE REPOSITORY
# ---------------------------------------------------------------------------

echo
echo "==> Cleaning stale Ollama models..."

mapfile -t INSTALLED < <(
    ollama list |
        awk 'NR > 1 && NF { print $1 }'
)

for installed in "${INSTALLED[@]}"; do
    base="${installed%%:*}"

    if [[ -v "REPO_MODELS[$base]" ]]; then
        echo "    KEEP $installed"
    else
        echo "    NUKE $installed"
        ollama rm "$installed"
    fi
done

# ---------------------------------------------------------------------------
# 5. Verify
# ---------------------------------------------------------------------------

echo
echo "==> Final Ollama state:"
ollama list

echo
echo "==> Ollama sync complete."