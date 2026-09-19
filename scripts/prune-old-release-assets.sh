#!/bin/bash
set -euo pipefail

# Keep package assets on the newest N GitHub Releases; older releases keep notes only.
# Usage: ./scripts/prune-old-release-assets.sh [keep-count] [owner/repo]
# Defaults: keep-count=50, repo=$GITHUB_REPOSITORY

KEEP_RELEASES="${1:-50}"
REPO="${2:-${GITHUB_REPOSITORY:-}}"

if [[ -z "$REPO" ]]; then
  echo "Error: repository required (pass owner/repo or set GITHUB_REPOSITORY)" >&2
  exit 1
fi

if ! [[ "$KEEP_RELEASES" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: keep-count must be a positive integer (got: $KEEP_RELEASES)" >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh is required" >&2
  exit 1
fi

append_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    cat >> "$GITHUB_STEP_SUMMARY"
  fi
}

mapfile -t tags < <(
  gh api --paginate "repos/${REPO}/releases" \
    --jq '.[] | select(.draft == false) | .tag_name'
)

total="${#tags[@]}"
echo "Found $total published releases in $REPO (keep assets for the newest $KEEP_RELEASES)"

if (( total <= KEEP_RELEASES )); then
  echo "No older releases to prune"
  append_summary <<EOF
Pruned 0 older releases (total $total, keep $KEEP_RELEASES)
EOF
  exit 0
fi

pruned=0
skipped=0
for tag in "${tags[@]:KEEP_RELEASES}"; do
  mapfile -t assets < <(gh release view "$tag" --repo "$REPO" --json assets --jq '.assets[].name')
  if (( ${#assets[@]} == 0 )); then
    echo "No assets on $tag, already notes-only"
    skipped=$((skipped + 1))
    continue
  fi

  echo "Removing ${#assets[@]} assets from $tag (keeping release notes)"
  for asset in "${assets[@]}"; do
    gh release delete-asset "$tag" "$asset" --repo "$REPO" --yes
  done
  pruned=$((pruned + 1))
done

echo "Removed assets from $pruned older releases; $skipped already notes-only"
append_summary <<EOF
## Release retention

Kept package assets for the newest **$KEEP_RELEASES** of **$total** published releases.
Removed assets from **$pruned** older releases (notes and tags kept).
EOF
