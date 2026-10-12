#!/bin/bash

# Compile, unit-test, then drive the real CLI, running only the targets whose watched paths changed.
#
# what-changed (targets in what-changed.yaml) decides what runs. Each target records its baseline
# only after it passes, so a failure never marks a broken tree as tested.
#
# zig build puts skl at zig-out/bin/skl, which scripts/smoke-tests.sh uses unless --binary is
# passed. mise exec is used when mise is on PATH so the pinned tools in mise.toml are the ones that
# run, not whatever happens to be first on PATH.
#
# Options:
#   --force     Run every target regardless of what changed.
#   --plan      Print which targets would run, and run nothing.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

FORCE=false
PLAN_ONLY=false

for ARGUMENT in "$@"; do
    case "$ARGUMENT" in
        --force)
            FORCE=true
            ;;
        --plan)
            PLAN_ONLY=true
            ;;
        *)
            echo "Unknown option \"$ARGUMENT\". Known options: --force, --plan."
            exit 1
            ;;
    esac
done

mise_run() {
    if command -v mise >/dev/null 2>&1; then
        mise exec -- "$@"
    else
        "$@"
    fi
}

zig_run() {
    mise_run zig "$@"
}

what_changed() {
    mise_run what-changed "$@"
}

# Runs one named target, then records its baseline. set -e stops the script before the capture
# when the target fails.
run_target() {
    local name="$1"
    echo -e "${BLUE}=== $name ===${NC}"
    case "$name" in
        compile)
            zig_run build
            ;;
        test)
            zig_run build test
            ;;
        smoke)
            ./scripts/smoke-tests.sh
            ;;
        *)
            echo "Target \"$name\" is in what-changed.yaml but this script does not know how to run it."
            exit 1
            ;;
    esac
    what_changed baseline capture "$name"
}

TARGETS=()
if [ "$FORCE" = true ]; then
    while IFS= read -r LINE; do
        if [ -n "$LINE" ]; then
            TARGETS+=("$LINE")
        fi
    done <<< "$(what_changed targets list)"
else
    while IFS= read -r LINE; do
        if [ -n "$LINE" ]; then
            TARGETS+=("$LINE")
        fi
    done <<< "$(what_changed targets)"
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo -e "${GREEN}Nothing to run: nothing has changed since the last baseline. Use --force to run everything.${NC}"
    exit 0
fi

echo "Targets to run: ${TARGETS[*]}"

if [ "$PLAN_ONLY" = true ]; then
    echo "--plan given, running nothing."
    exit 0
fi

for TARGET_NAME in "${TARGETS[@]}"; do
    run_target "$TARGET_NAME"
done

echo ""
echo -e "${GREEN}PASS: ${TARGETS[*]}${NC}"
