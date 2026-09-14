#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

echo "==> Syncing Ollama models from: $REPO_DIR"

# Pull latest repository state
if [[ -d ".git" ]]; then
    git pull --ff-only origin main
fi

# ---------------------------------------------------------------------------
# Discover repository models
# ---------------------------------------------------------------------------

declare -A REPO_MODELS=()

while IFS= read -r -d '' file; do
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

    REPO_MODELS["$model"]="$file"
done < <(
    find "$REPO_DIR" -maxdepth 1 -type f \
        \( -name '*.Modelfile' -o -name '*.modelfile' \) \
        -print0
)

echo
echo "==> Repository defines ${#REPO_MODELS[@]} model(s):"

if [[ ${#REPO_MODELS[@]} -gt 0 ]]; then
    while IFS= read -r model; do
        echo "    $model"
    done < <(printf '%s\n' "${!REPO_MODELS[@]}" | sort)
else
    echo "    NONE"
fi

# ---------------------------------------------------------------------------
# Build repository models
# ---------------------------------------------------------------------------

for model in "${!REPO_MODELS[@]}"; do
    file="${REPO_MODELS[$model]}"

    echo
    echo "==> BUILD $model"
    ollama create "$model" -f "$file"
done

# ---------------------------------------------------------------------------
# Remove EVERYTHING not defined by the repository
# ---------------------------------------------------------------------------

echo
echo "==> Synchronizing installed models..."

while IFS= read -r installed; do
    [[ -n "$installed" ]] || continue

    # Ollama reports:
    #   model:latest
    #   model:tag
    #
    # Repository model names are untagged.
    base="${installed%%:*}"

    if [[ -v "REPO_MODELS[$base]" ]]; then
        echo "    KEEP   $installed"
    else
        echo "    NUKE   $installed"
        ollama rm "$installed"
    fi
done < <(
    ollama list |
        awk 'NR > 1 && NF { print $1 }'
)

# ---------------------------------------------------------------------------
# Verify final state
# ---------------------------------------------------------------------------

echo
echo "==> Final Ollama models:"
ollama list

echo
echo "==> Ollama sync complete."