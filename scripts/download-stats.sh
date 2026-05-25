#!/usr/bin/env bash
# Show download counts per release and platform for m-tky/koreader-tategumi.

set -euo pipefail

REPO="m-tky/koreader-tategumi"

gh api "repos/$REPO/releases" --jq '
  .[] |
  "=== \(.tag_name) (\(.published_at[:10])) — total: \([.assets[].download_count] | add) ===",
  (
    .assets[]
    | select(.download_count > 0)
    | select(.name | test("-latest-stable\\.zsync$") | not)
    | select(.name | test("-latest-stable$") | not)
    | "  \(.name): \(.download_count)"
  )
' | grep -v '^$'

echo ""
echo "Grand total: $(gh api "repos/$REPO/releases" --jq '[.[].assets[].download_count] | add') downloads"
