#!/usr/bin/env bash
# Enables the checked-in pre-commit hook in this clone, once per clone.
#
# Git only runs hooks from the clone's own hooks directory, which is not version controlled. This
# symlinks .githooks/pre-commit into it, so edits to the checked-in hook apply straight away. No git
# configuration is changed. Worktrees share the same hooks directory.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_DIR"

HOOKS_DIR="$(cd "$(git rev-parse --git-common-dir)" && pwd)/hooks"
mkdir -p "$HOOKS_DIR"

if [ -e "$HOOKS_DIR/pre-commit" ] && [ ! -L "$HOOKS_DIR/pre-commit" ]; then
    echo "ERROR: $HOOKS_DIR/pre-commit already exists and is not a symlink. Move it aside first." >&2
    exit 1
fi

ln -sfn "$REPO_DIR/.githooks/pre-commit" "$HOOKS_DIR/pre-commit"

echo "Hook installed: $HOOKS_DIR/pre-commit -> .githooks/pre-commit"
echo "  pre-commit: ./scripts/test-everything.sh (only the targets whose watched paths changed)"
echo "Bypass a single commit with --no-verify."
