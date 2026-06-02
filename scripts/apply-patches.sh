#!/bin/bash
set -euo pipefail

# Apply repository-maintained patches to the extracted upstream Alma app.
# Usage: ./scripts/apply-patches.sh <app-base-path>

BASE_PATH="${1:?app base path required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/patches"

echo "Applying repository patches..."
for patch_script in "$PATCH_DIR"/*.sh; do
    [[ -e "$patch_script" ]] || continue
    echo "Running patch: $(basename "$patch_script")"
    "$patch_script" "$BASE_PATH"
done
echo "  ✓ Repository patches applied"
echo ""
