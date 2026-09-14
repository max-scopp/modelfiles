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
# 2. Get EXACTLY the Modelfiles tracked by Git
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

if [[ ${#REPO_MODELS[@]} -gt 0 ]]; then
    printf '%s\n' "${!REPO_MODELS[@]}" | sort | sed 's/^/    /'
else
    echo "    NONE"
fi

# ---------------------------------------------------------------------------
# 3. Build EVERYTHING first
# ---------------------------------------------------------------------------

echo
echo "==> Building repository models..."

for model in "${!REPO_MODELS[@]}"; do
    file="${REPO_MODELS[$model]}"

    echo
    echo "==> BUILD $model"
    ollama create "$model" -f "$file"
done

echo
echo "==> All repository models built successfully."

# ---------------------------------------------------------------------------
# 4. Nuke EVERYTHING not in Git
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
        continue
    fi

    echo "    NUKE $installed"

    # Don't let one stale/non-existent entry abort the entire sync.
    if ollama rm "$installed"; then
        echo "         deleted"
    else
        # Re-check: Ollama may have removed it between list and rm.
        if ollama list | awk 'NR > 1 { print $1 }' | grep -Fxq "$installed"; then
            echo "         WARNING: still present, retrying..."
            ollama rm "$installed" || true
        else
            echo "         already gone"
        fi
    fi
done

# ---------------------------------------------------------------------------
# 5. Final verification + second cleanup pass
# ---------------------------------------------------------------------------

echo
echo "==> Verifying final state..."

# A second pass catches anything that appeared/stayed during the first pass.
mapfile -t REMAINING < <(
    ollama list |
        awk 'NR > 1 && NF { print $1 }'
)

for installed in "${REMAINING[@]}"; do
    base="${installed%%:*}"

    if [[ ! -v "REPO_MODELS[$base]" ]]; then
        echo "    FINAL NUKE $installed"
        ollama rm "$installed" || true
    fi
done

echo
echo "==> FINAL OLLAMA STATE"
ollama list

echo
echo "==> Ollama sync complete."