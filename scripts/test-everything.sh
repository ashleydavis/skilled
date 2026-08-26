#!/bin/bash

# Compile, unit-test, then drive the real CLI.
#
# zig build puts skl at zig-out/bin/skl, which scripts/smoke-tests.sh uses unless --binary is
# passed. mise exec is used when mise is on PATH so the pinned Zig in mise.toml is the one that
# runs, not whatever happens to be first on PATH.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

zig_run() {
    if command -v mise >/dev/null 2>&1; then
        mise exec -- zig "$@"
    else
        zig "$@"
    fi
}

echo -e "${BLUE}=== zig build ===${NC}"
zig_run build

echo -e "${BLUE}=== zig build test ===${NC}"
zig_run build test

echo -e "${BLUE}=== smoke tests ===${NC}"
./scripts/smoke-tests.sh

echo ""
echo -e "${GREEN}PASS: compile, unit tests, and smoke tests${NC}"
