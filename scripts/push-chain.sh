#!/usr/bin/env bash
# push-chain.sh — push commits through the crengine → koreader-base → koreader chain.
#
# Usage:
#   ./scripts/push-chain.sh [crengine|base|koreader] [--dry-run]
#
#   crengine  (default) push crengine, then base, then koreader
#   base                push base, then koreader  (skip crengine)
#   koreader            push koreader only
#   --dry-run           show what would be pushed without doing anything

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CRENGINE_DIR="$ROOT/base/thirdparty/kpvcrlib/crengine"
BASE_DIR="$ROOT/base"

GRN='\033[0;32m'; YLW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GRN}▶${NC} $*"; }
warn()  { echo -e "${YLW}⚠${NC} $*"; }
die()   { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

DRY=false
START="crengine"

for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY=true ;;
        crengine|base|koreader) START="$arg" ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

$DRY && warn "Dry run — no changes will be made."

# ── helpers ──────────────────────────────────────────────────────────────────

# Print commits ahead of remote/master.
show_ahead() {
    local dir="$1" remote="$2"
    git -C "$dir" fetch "$remote" master -q 2>/dev/null || true
    local ahead
    ahead=$(git -C "$dir" log --oneline "$remote/master..HEAD" 2>/dev/null || true)
    if [[ -z "$ahead" ]]; then
        echo "  (nothing to push)"
    else
        echo "$ahead" | sed 's/^/  /'
    fi
}

# Push all commits ahead of remote/master onto that remote's master.
# If needed, cherry-pick (handles detached HEAD / diverged branches).
# After cherry-picking, if $sub_path is set, ensure the submodule at that path
# points to $sub_sha (adds a fixup commit if the cherry-pick brought a stale SHA).
# Prints the pushed SHA on stdout.
push_onto_remote_master() {
    local dir="$1" remote="$2" sub_path="${3:-}" sub_sha="${4:-}"

    git -C "$dir" fetch "$remote" master -q 2>/dev/null || true
    local remote_tip
    remote_tip=$(git -C "$dir" rev-parse "$remote/master")

    local ahead
    ahead=$(git -C "$dir" log --reverse --format="%H" "$remote_tip..HEAD" 2>/dev/null || true)

    # Nothing ahead and no submodule to fix → already done.
    if [[ -z "$ahead" && -z "$sub_path" ]]; then
        info "  already up to date"
        echo "$remote_tip"
        return
    fi

    # Build on top of remote master in a temp branch.
    git -C "$dir" checkout -q -b _push_tmp "$remote_tip"

    # Cherry-pick each commit.
    for sha in $ahead; do
        if ! git -C "$dir" cherry-pick -q "$sha"; then
            git -C "$dir" cherry-pick --abort 2>/dev/null || true
            git -C "$dir" checkout -q -
            git -C "$dir" branch -D _push_tmp 2>/dev/null || true
            die "Cherry-pick of $sha failed. Resolve manually."
        fi
    done

    # Fix submodule pointer if needed.
    if [[ -n "$sub_path" && -n "$sub_sha" ]]; then
        local cur_sha
        cur_sha=$(git -C "$dir" ls-tree HEAD "$sub_path" 2>/dev/null | awk '{print $3}')
        if [[ "$cur_sha" != "$sub_sha" ]]; then
            git -C "$dir/$sub_path" checkout -q "$sub_sha" 2>/dev/null \
                || die "Cannot checkout $sub_sha in $sub_path"
            git -C "$dir" add "$sub_path"
            local sub_name
            sub_name=$(basename "$sub_path")
            git -C "$dir" commit -q -m "$sub_name: bump to ${sub_sha:0:8}"
            warn "  submodule $sub_path was stale → bumped to ${sub_sha:0:8}"
        fi
    fi

    git -C "$dir" push -q "$remote" "_push_tmp:master"
    local pushed_sha
    pushed_sha=$(git -C "$dir" rev-parse HEAD)

    git -C "$dir" checkout -q -
    git -C "$dir" branch -D _push_tmp 2>/dev/null || true

    echo "$pushed_sha"
}

# ── dry-run mode ─────────────────────────────────────────────────────────────

if $DRY; then
    if [[ "$START" == "crengine" ]]; then
        info "crengine (mytky → master):"
        show_ahead "$CRENGINE_DIR" mytky
    fi
    if [[ "$START" != "koreader" ]]; then
        info "koreader-base (mytky → master):"
        show_ahead "$BASE_DIR" mytky
    fi
    info "koreader-tategumi (origin → master):"
    show_ahead "$ROOT" origin
    exit 0
fi

# ── push ─────────────────────────────────────────────────────────────────────

crengine_sha=""
base_sha=""

if [[ "$START" == "crengine" ]]; then
    info "Pushing crengine…"
    crengine_sha=$(push_onto_remote_master "$CRENGINE_DIR" mytky)
    info "  → $crengine_sha"
fi

if [[ "$START" != "koreader" ]]; then
    info "Pushing koreader-base…"
    base_sha=$(push_onto_remote_master "$BASE_DIR" mytky \
        "thirdparty/kpvcrlib/crengine" "$crengine_sha")
    info "  → $base_sha"
fi

info "Pushing koreader-tategumi…"
push_onto_remote_master "$ROOT" origin "base" "$base_sha" > /dev/null
local_sha=$(git -C "$ROOT" rev-parse origin/master)
info "  → $local_sha"

info "Done."
