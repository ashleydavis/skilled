#!/bin/bash

# skl smoke tests
#
# Drives the real CLI as a real process and asserts exit codes, output, and filesystem effects
# (namespace symlinks, store clones, YAML writes). Unit tests cannot see those.
#
# Every scenario is independent: it gets its own throwaway HOME, its own project directory, its own
# copy of the fixture remotes, and its own CLI output file, and it performs whatever setup it needs
# rather than inheriting state from the scenario before it. That is what lets the driver run them
# in parallel (--jobs) and lets one scenario be understood, or re-run, on its own.
#
# Isolation: every directory comes from mktemp. Fixture git init/add/commit/config run only with
# GIT_DIR and GIT_WORK_TREE set to those throwaway paths; the script aborts if
# git rev-parse --show-toplevel is not that path. skl is invoked with those two unset.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

USE_BINARY=0
ONLY=""
# Lanes, not batches: this many scenarios run at once and each lane takes the next one the moment
# it is free. --jobs changes how many lanes there are.
JOBS=4

while [ "$#" -gt 0 ]; do
    case "$1" in
        --binary)
            USE_BINARY=1
            shift
            ;;
        --jobs|-j)
            JOBS="$2"
            shift 2
            ;;
        --jobs=*)
            JOBS="${1#*=}"
            shift
            ;;
        --only)
            ONLY="$2"
            shift 2
            ;;
        --only=*)
            ONLY="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Usage: smoke-tests.sh [--binary] [--jobs N] [--only PATTERN]"
            exit 1
            ;;
    esac
done

if [ "$JOBS" -lt 1 ] 2>/dev/null; then
    JOBS=1
fi

RUN_CLI=("$PROJECT_DIR/zig-out/bin/skl")
if [ "${OS:-}" = "Windows_NT" ]; then
    RUN_CLI=("$PROJECT_DIR/zig-out/bin/skl.exe")
fi
CLI_DESCRIPTION="in-tree binary at ${RUN_CLI[0]}"

if [ "$USE_BINARY" = "1" ]; then
    if [ "${OS:-}" = "Windows_NT" ]; then
        BINARY_PATH="$PROJECT_DIR/bin/x64/win/skl.exe"
    elif [ "$(uname -s)" = "Darwin" ]; then
        if [ "$(uname -m)" = "arm64" ]; then
            BINARY_PATH="$PROJECT_DIR/bin/arm64/mac/skl"
        else
            BINARY_PATH="$PROJECT_DIR/bin/x64/mac/skl"
        fi
    else
        if [ "$(uname -m)" = "aarch64" ] || [ "$(uname -m)" = "arm64" ]; then
            BINARY_PATH="$PROJECT_DIR/bin/arm64/linux/skl"
        else
            BINARY_PATH="$PROJECT_DIR/bin/x64/linux/skl"
        fi
    fi
    if [ ! -x "$BINARY_PATH" ]; then
        echo "No executable at $BINARY_PATH. Build it first with 'zig build release'."
        exit 1
    fi
    RUN_CLI=("$BINARY_PATH")
    CLI_DESCRIPTION="compiled executable at $BINARY_PATH"
fi

if [ ! -x "${RUN_CLI[0]}" ]; then
    echo "No executable at ${RUN_CLI[0]}. Build it first with 'zig build'."
    exit 1
fi

LAST_EXIT=0
OUTPUT_FILE=""

####################################################################################################
#
# Reporting.
#
# pass and fail print into the running scenario's own log, which the driver prints whole once that
# scenario finishes, so parallel scenarios never interleave their lines. fail ends the scenario.
#
####################################################################################################

pass() {
    echo -e "  ${GREEN}PASS${NC} $1"
}

fail() {
    echo -e "  ${RED}FAIL${NC} $1"
    echo "    --- CLI output ---"
    if [ -n "$OUTPUT_FILE" ] && [ -f "$OUTPUT_FILE" ]; then
        sed 's/^/    /' "$OUTPUT_FILE" || true
    fi
    echo "    Throwaway HOME: ${HOME:-unset}"
    exit 1
}

posix_path() {
    local path="$1"
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -u "$path"
    else
        printf '%s' "$path"
    fi
}

assert_fixture_toplevel() {
    local work="$1"
    local actual expected
    actual="$(GIT_DIR="$work/.git" GIT_WORK_TREE="$work" git rev-parse --show-toplevel)"
    actual="$(posix_path "$actual")"
    expected="$(posix_path "$work")"
    if [ "$actual" != "$expected" ]; then
        echo -e "${RED}ABORTING: expected the repository at $expected but git reports $actual.${NC}"
        echo -e "${RED}Refusing to run any check rather than risk touching a real repository.${NC}"
        exit 1
    fi
}

# State-changing git against one throwaway work tree. GIT_DIR is work/.git so metadata stays
# inside that directory; GIT_WORK_TREE is the same path the abort check compares.
fixture_git() {
    local work="$1"
    shift
    GIT_DIR="$work/.git" GIT_WORK_TREE="$work" git "$@"
    assert_fixture_toplevel "$work"
}

run_cli_in() {
    local directory="$1"
    shift
    set +e
    (
        cd "$directory" || exit 1
        unset GIT_DIR GIT_WORK_TREE
        "${RUN_CLI[@]}" "$@"
    ) </dev/null >"$OUTPUT_FILE" 2>&1
    LAST_EXIT=$?
    set -e
}

assert_exit() {
    local expected="$1"
    if [ "$LAST_EXIT" = "$expected" ]; then
        pass "exit code $expected"
    else
        fail "expected exit code $expected, got $LAST_EXIT"
    fi
}

assert_failed() {
    if [ "$LAST_EXIT" != "0" ]; then
        pass "exited non-zero ($LAST_EXIT)"
    else
        fail "expected a non-zero exit, got 0"
    fi
}

assert_output_contains() {
    local expected="$1"
    if grep -qF -- "$expected" "$OUTPUT_FILE"; then
        pass "output mentions \"$expected\""
    else
        fail "expected the output to mention \"$expected\""
    fi
}

assert_output_lacks() {
    local unexpected="$1"
    if grep -qF -- "$unexpected" "$OUTPUT_FILE"; then
        fail "expected the output NOT to mention \"$unexpected\""
    else
        pass "output does not mention \"$unexpected\""
    fi
}

assert_no_ansi() {
    if grep -q $'\033\\[' "$OUTPUT_FILE"; then
        fail "expected no ANSI escapes in the output"
    else
        pass "output has no ANSI escapes"
    fi
}

assert_file_exists() {
    local path="$1"
    if [ -f "$path" ]; then
        pass "$path exists"
    else
        fail "expected $path to exist"
    fi
}

assert_dir_exists() {
    local path="$1"
    if [ -d "$path" ]; then
        pass "$path exists"
    else
        fail "expected directory $path to exist"
    fi
}

assert_file_contains() {
    local path="$1"
    local expected="$2"
    if [ -f "$path" ] && grep -qF -- "$expected" "$path"; then
        pass "$path contains \"$expected\""
    else
        fail "expected $path to contain \"$expected\""
    fi
}

# YAML `local:` is the path the native binary stored. Git Bash converts `/c/Users/...`
# argv to `C:/Users/...` when it launches skl.exe, so a byte match against $LOCAL_PKG fails
# on Windows. Slash and backslash are the same separator.
assert_file_contains_path() {
    local path="$1"
    local expected="$2"
    if [ ! -f "$path" ]; then
        fail "expected $path to contain path \"$expected\""
    fi
    local content posix_expected
    content="$(tr '\\' '/' <"$path")"
    posix_expected="$(printf '%s' "$expected" | tr '\\' '/')"
    if printf '%s' "$content" | grep -qF -- "$posix_expected"; then
        pass "$path contains \"$expected\""
        return
    fi
    local letter third drive_form
    letter="$(printf '%s' "$posix_expected" | cut -c2)"
    third="$(printf '%s' "$posix_expected" | cut -c3)"
    if [ "$third" = "/" ] && printf '%s' "$letter" | grep -q '^[A-Za-z]$'; then
        drive_form="$(printf '%s' "$letter" | tr '[:lower:]' '[:upper:]'):/${posix_expected#???}"
        if printf '%s' "$content" | grep -qF -- "$drive_form"; then
            pass "$path contains \"$drive_form\""
            return
        fi
    fi
    fail "expected $path to contain \"$expected\""
}

assert_file_lacks() {
    local path="$1"
    local unexpected="$2"
    if [ -f "$path" ] && grep -qF -- "$unexpected" "$path"; then
        fail "expected $path NOT to contain \"$unexpected\""
    else
        pass "$path does not contain \"$unexpected\""
    fi
}

assert_not_exists() {
    local path="$1"
    if [ -e "$path" ] || [ -L "$path" ]; then
        fail "expected $path not to exist"
    else
        pass "$path does not exist"
    fi
}

assert_symlink() {
    local path="$1"
    local needle="$2"
    if [ ! -L "$path" ]; then
        fail "expected $path to be a symlink"
    fi
    local target target_posix
    target="$(readlink "$path")"
    target_posix="$(printf '%s' "$target" | tr '\\' '/')"
    case "$target_posix" in
        *"$needle"*) pass "$path is a symlink to $target" ;;
        *) fail "expected $path to point at a path containing \"$needle\", got $target" ;;
    esac
}

assert_not_symlink_path() {
    local path="$1"
    if [ -L "$path" ] || [ -e "$path" ]; then
        fail "expected $path not to exist (no namespace link)"
    else
        pass "$path does not exist (no namespace link)"
    fi
}

write_empty_yaml() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    printf 'packages: []\n' >"$path"
}

####################################################################################################
#
# Fixture remotes and the local package, built once and never written to by a scenario.
#
# A scenario that needs to commit (31) copies these into its own HOME first, so the originals stay
# the same for every other scenario however the suite is ordered or parallelised.
#
# READ THIS BEFORE ADDING GIT COMMANDS.
#
# fixture_git is the only wrapper that may run git init / add / commit / config. It sets GIT_DIR
# and GIT_WORK_TREE to the throwaway path and aborts unless show-toplevel is that path. Never run
# those commands against this checkout. skl is invoked with GIT_DIR and GIT_WORK_TREE unset.
#
####################################################################################################

FIXTURES="$(cd "$(mktemp -d)" && pwd -P)"
FIXTURE_REMOTES="$FIXTURES/remotes"
mkdir -p "$FIXTURE_REMOTES"

export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
# If insteadOf failed to rewrite, fail immediately rather than waiting on SSH.
export GIT_SSH_COMMAND="false"
if [ "${OS:-}" = "Windows_NT" ]; then
    # Git Bash `ln -s` copies unless MSYS asks for native links; Developer Mode is enabled in CI.
    export MSYS="winsymlinks:nativestrict"
fi
unset XDG_CONFIG_HOME

# The fixture build needs an identity before any scenario HOME exists.
export GIT_CONFIG_GLOBAL="$FIXTURES/gitconfig"
cat >"$GIT_CONFIG_GLOBAL" <<EOF
[user]
	name = skl-smoke
	email = smoke@example.com
[safe]
	directory = *
[protocol "file"]
	allow = always
EOF

write_remote() {
    local dest="$1"
    mkdir -p "$dest"
    dest="$(cd "$dest" && pwd -P)"
    fixture_git "$dest" init -b main --quiet
    shift
    while [ "$#" -gt 0 ]; do
        local rel="$1"
        local contents="$2"
        shift 2
        mkdir -p "$dest/$(dirname "$rel")"
        printf '%s' "$contents" >"$dest/$rel"
    done
    fixture_git "$dest" add -A
    fixture_git "$dest" commit --quiet -m "initial"
    printf '%s' "$dest"
}

write_local_package() {
    local dest="$1"
    mkdir -p "$dest"
    dest="$(cd "$dest" && pwd -P)"
    fixture_git "$dest" init -b main --quiet
    mkdir -p "$dest/skills/hello"
    printf '%s' "---
description: Local hello
---

# Hello
" >"$dest/skills/hello/SKILL.md"
    printf 'A local working tree.\n' >"$dest/README.md"
    fixture_git "$dest" add -A
    fixture_git "$dest" commit --quiet -m "local"
    printf '%s' "$dest"
}

FIXTURE_SKILLS="$(write_remote "$FIXTURE_REMOTES/acme/skills.git" \
    "README.md" "A pack of demo skills.
" \
    "skills/demo/SKILL.md" "---
description: Says hello
---

# Hello
")"

fixture_git "$FIXTURE_SKILLS" checkout -b dev
printf 'Skills from the dev branch.\n' >"$FIXTURE_SKILLS/README.md"
printf '%s' "---
description: Hello from dev
---

# Hello
" >"$FIXTURE_SKILLS/skills/demo/SKILL.md"
fixture_git "$FIXTURE_SKILLS" add -A
fixture_git "$FIXTURE_SKILLS" commit --quiet -m "dev"
fixture_git "$FIXTURE_SKILLS" checkout main

write_remote "$FIXTURE_REMOTES/acme/cmds.git" \
    "README.md" "A pack of demo commands.
" \
    "commands/plan/create.md" "---
description: Create a plan
---

Write a plan.
" >/dev/null

write_remote "$FIXTURE_REMOTES/acme/both.git" \
    "README.md" "Skills and commands together.
" \
    "skills/hello/SKILL.md" "---
description: Says hello
---
" \
    "commands/plan/create.md" "---
description: Create a plan
---
" >/dev/null

write_remote "$FIXTURE_REMOTES/acme/empty.git" \
    "README.md" "Not a package.
" >/dev/null

write_remote "$FIXTURE_REMOTES/acme/skl-config.git" \
    "teams/platform.yaml" "packages:
  - repo: acme/skills
    namespace: demo
  - repo: acme/cmds
    namespace: cmd
" >/dev/null

FIXTURE_LOCAL="$(write_local_package "$FIXTURES/local-skills")"

if [ "${OS:-}" = "Windows_NT" ]; then
    FIXTURE_BROWSER="$FIXTURES/skl-browser.cmd"
    cat >"$FIXTURE_BROWSER" <<'EOF'
@echo off
echo %*>>"%SKL_BROWSER_LOG%"
EOF
else
    FIXTURE_BROWSER="$FIXTURES/skl-browser"
    cat >"$FIXTURE_BROWSER" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" >>"$SKL_BROWSER_LOG"
EOF
    chmod +x "$FIXTURE_BROWSER"
fi

####################################################################################################
#
# Per-scenario world.
#
# Called first in every scenario function, inside that scenario's own subshell, so the exports and
# the variables below belong to that scenario alone. Fixture remotes are copied rather than shared
# so a scenario may commit to its own remote.
#
####################################################################################################

scenario_env() {
    SC_HOME="$(cd "$(mktemp -d)" && pwd -P)"
    export HOME="$SC_HOME"
    export USERPROFILE="$SC_HOME"

    CWD="$(cd "$(mktemp -d)" && pwd -P)"

    mkdir -p "$SC_HOME/tmp" "$SC_HOME/.ssh"
    export TMPDIR="$SC_HOME/tmp"
    export TMP="$SC_HOME/tmp"
    export TEMP="$SC_HOME/tmp"

    REMOTES="$SC_HOME/remotes"
    cp -R "$FIXTURE_REMOTES" "$REMOTES"
    REMOTE_SKILLS="$REMOTES/acme/skills.git"

    LOCAL_PKG="$SC_HOME/local-skills"
    cp -R "$FIXTURE_LOCAL" "$LOCAL_PKG"

    local instead_of_base
    if command -v cygpath >/dev/null 2>&1; then
        instead_of_base="file:///$(cygpath -m "$REMOTES")/"
    else
        instead_of_base="file://${REMOTES}/"
    fi

    export GIT_CONFIG_GLOBAL="$SC_HOME/.gitconfig"
    cat >"$GIT_CONFIG_GLOBAL" <<EOF
[user]
	name = skl-smoke
	email = smoke@example.com
[safe]
	directory = *
[protocol "file"]
	allow = always
[url "$instead_of_base"]
	insteadOf = git@github.com:
	insteadOf = git@github.example.com:
EOF

    BROWSER_LOG="$SC_HOME/browser.log"
    : >"$BROWSER_LOG"
    export SKL_BROWSER_LOG="$BROWSER_LOG"
    export SKL_BROWSER="$FIXTURE_BROWSER"

    OUTPUT_FILE="$SC_HOME/cli-output.txt"
    : >"$OUTPUT_FILE"

    STORE="$SC_HOME/.skilled/store"
    GLOBAL_YAML="$SC_HOME/.config/skilled/skl.yaml"
    SCRATCH="$CWD/.skilled/scratch"
}

####################################################################################################
#
# Setup inside a scenario.
#
# A setup step is not an assertion: it prints nothing when it works, and ends the scenario when it
# does not, so the PASS lines a scenario prints are only the behaviour it is there to check.
#
####################################################################################################

setup_cli() {
    run_cli_in "$CWD" "$@"
    if [ "$LAST_EXIT" != "0" ]; then
        fail "setup step 'skl $*' failed with exit $LAST_EXIT"
    fi
}

# Branch the store clone of acme/skills is checked out on.
store_branch() {
    git -C "$STORE/github.com/acme/skills" rev-parse --abbrev-ref HEAD
}

# A skill and a command inside this scenario's project scratch directory.
write_scratch_items() {
    mkdir -p "$SCRATCH/skills/hello" "$SCRATCH/commands/plan"
    printf '%s' "---
description: Scratch hello
---

# Hello
" >"$SCRATCH/skills/hello/SKILL.md"
    printf '%s' "---
description: Create a scratch plan
---

Write a plan.
" >"$SCRATCH/commands/plan/create.md"
}

####################################################################################################
#
# 1–8: root and global flags.
#
####################################################################################################

sc01() {
    scenario_env
    for flag in --help -h help; do
        run_cli_in "$CWD" "$flag"
        assert_exit 0
        assert_output_contains "init"
        assert_output_contains "install"
        assert_output_contains "add"
        assert_output_contains "remove"
        assert_output_contains "update"
        assert_output_contains "list"
        assert_output_contains "docs"
        assert_output_contains "help"
        assert_output_contains "version"
    done
}

sc02() {
    scenario_env
    run_cli_in "$CWD" --version
    assert_exit 0
    local version
    version="$(tr -d '[:space:]' <"$OUTPUT_FILE")"
    if [ -z "$version" ]; then
        fail "expected --version to print a version"
    else
        pass "version is \"$version\""
    fi
    for flag in --version -V version; do
        run_cli_in "$CWD" "$flag"
        assert_exit 0
        assert_output_contains "$version"
    done
}

sc03() {
    scenario_env
    run_cli_in "$CWD"
    assert_exit 0
    assert_output_contains "Usage: skl"
    assert_output_contains "init"
}

sc04() {
    scenario_env
    run_cli_in "$CWD" nosuch
    assert_failed
    assert_output_contains "unknown command"
    assert_output_contains "nosuch"
}

sc05() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" --no-color list
    assert_exit 0
    assert_no_ansi
}

sc06() {
    scenario_env
    setup_cli init
    NO_COLOR=1 run_cli_in "$CWD" list
    assert_exit 0
    assert_no_ansi
}

sc07() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" -n add acme/skills
    assert_failed
    assert_output_contains "--ns"
}

sc08() {
    scenario_env
    setup_cli init
    SKL_NONINTERACTIVE=1 run_cli_in "$CWD" add acme/skills
    assert_failed
    assert_output_contains "--ns"
}

####################################################################################################
#
# 9–14, 47: init.
#
####################################################################################################

sc09() {
    scenario_env
    run_cli_in "$CWD" init
    assert_exit 0
    assert_file_exists "$CWD/skl.yaml"
    assert_file_contains "$CWD/skl.yaml" "packages: []"
}

sc10() {
    scenario_env
    setup_cli init
    printf 'packages:\n  - repo: acme/keep\n    namespace: keep\n' >"$CWD/skl.yaml"
    run_cli_in "$CWD" init
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "acme/keep"
    assert_file_contains "$CWD/skl.yaml" "namespace: keep"
}

sc11() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" init -g
    assert_exit 0
    assert_file_exists "$GLOBAL_YAML"
    assert_file_contains "$GLOBAL_YAML" "packages: []"
    assert_file_contains "$CWD/skl.yaml" "packages: []"
}

sc12() {
    scenario_env
    run_cli_in "$CWD" init --from acme/skl-config:teams/platform.yaml
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "acme/skills"
    assert_file_contains "$CWD/skl.yaml" "namespace: demo"
    assert_file_contains "$CWD/skl.yaml" "acme/cmds"
    assert_file_contains "$CWD/skl.yaml" "namespace: cmd"
    assert_not_exists "$STORE/github.com/acme/skl-config"
    assert_dir_exists "$STORE/github.com/acme/skills"
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
    assert_symlink "$CWD/.claude/commands/demo" "github.com/acme/skills"
    assert_symlink "$CWD/.cursor/commands/cmd" "github.com/acme/cmds"
    assert_symlink "$CWD/.claude/commands/cmd" "github.com/acme/cmds"
}

sc13() {
    scenario_env
    run_cli_in "$CWD" init -g --from git@github.com:acme/skl-config.git:teams/platform.yaml
    assert_exit 0
    assert_file_contains "$GLOBAL_YAML" "acme/skills"
    assert_file_contains "$GLOBAL_YAML" "namespace: demo"
    assert_file_contains "$GLOBAL_YAML" "acme/cmds"
    assert_not_exists "$STORE/github.com/acme/skl-config"
}

sc14() {
    scenario_env
    setup_cli init --from acme/skl-config:teams/platform.yaml
    run_cli_in "$CWD" add --from https://github.com/acme/skl-config/blob/main/teams/platform.yaml
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "acme/skills"
    assert_file_contains "$CWD/skl.yaml" "acme/cmds"
    assert_not_exists "$STORE/github.com/acme/skl-config"
}

sc47() {
    scenario_env
    setup_cli init --from acme/skl-config:teams/platform.yaml
    cp "$CWD/skl.yaml" "$SC_HOME/yaml.before"
    run_cli_in "$CWD" init --from acme/skl-config:teams/platform.yaml
    assert_failed
    assert_output_contains "add --from"
    if cmp -s "$CWD/skl.yaml" "$SC_HOME/yaml.before"; then
        pass "project YAML unchanged"
    else
        fail "project YAML changed after refused init --from"
    fi
}

####################################################################################################
#
# 15–22: add.
#
####################################################################################################

sc15() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add acme/skills --ns demo
    assert_exit 0
    assert_dir_exists "$STORE/github.com/acme/skills"
    assert_file_exists "$STORE/github.com/acme/skills/skills/demo/SKILL.md"
    assert_file_contains "$CWD/skl.yaml" "acme/skills"
    assert_file_contains "$CWD/skl.yaml" "namespace: demo"
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
    assert_symlink "$CWD/.claude/commands/demo" "github.com/acme/skills"
    assert_not_symlink_path "$CWD/.cursor/commands/demo"
    assert_not_symlink_path "$CWD/.claude/skills/demo"
}

sc16() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add acme/cmds --ns cmd
    assert_exit 0
    assert_symlink "$CWD/.cursor/commands/cmd" "github.com/acme/cmds"
    assert_symlink "$CWD/.claude/commands/cmd" "github.com/acme/cmds"
    assert_file_exists "$CWD/.cursor/commands/cmd/plan/create.md"
    assert_not_symlink_path "$CWD/.cursor/skills/cmd"
}

sc17() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add acme/both --ns both
    assert_exit 0
    assert_symlink "$CWD/.cursor/skills/both" "github.com/acme/both"
    assert_symlink "$CWD/.claude/skills/both" "github.com/acme/both"
    assert_symlink "$CWD/.cursor/commands/both" "github.com/acme/both"
    assert_symlink "$CWD/.claude/commands/both" "github.com/acme/both"
}

sc18() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add acme/empty --ns empty
    assert_failed
    assert_file_lacks "$CWD/skl.yaml" "namespace: empty"
    assert_file_lacks "$CWD/skl.yaml" "acme/empty"
}

sc19() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add git@github.example.com:acme/skills.git --ns ent
    assert_exit 0
    assert_dir_exists "$STORE/github.example.com/acme/skills"
    assert_file_contains "$CWD/skl.yaml" "github.example.com"
}

sc20() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    cp "$CWD/skl.yaml" "$SC_HOME/yaml.before"
    run_cli_in "$CWD" add acme/skills --ns demo
    assert_failed
    if cmp -s "$CWD/skl.yaml" "$SC_HOME/yaml.before"; then
        pass "project YAML unchanged on duplicate ns"
    else
        fail "project YAML changed on duplicate namespace"
    fi
}

sc21() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    run_cli_in "$CWD" add acme/both --ns demo
    assert_failed
    assert_output_contains "demo"
}

sc22() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    setup_cli init -g
    run_cli_in "$CWD" -g add acme/skills --ns demo
    assert_exit 0
    assert_file_contains "$GLOBAL_YAML" "acme/skills"
    assert_file_contains "$GLOBAL_YAML" "namespace: demo"
    assert_symlink "$SC_HOME/.cursor/skills/demo" "github.com/acme/skills"
    assert_symlink "$SC_HOME/.claude/commands/demo" "github.com/acme/skills"
    if [ -e "$CWD/.cursor/skills/demo" ]; then
        pass "project skills/demo still present"
    else
        fail "project skills/demo was removed by -g add"
    fi
}

####################################################################################################
#
# 23–25: install.
#
####################################################################################################

sc23() {
    scenario_env
    run_cli_in "$CWD" init --from acme/skl-config:teams/platform.yaml
    assert_exit 0
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
    assert_symlink "$CWD/.claude/commands/demo" "github.com/acme/skills"
    assert_symlink "$CWD/.cursor/commands/cmd" "github.com/acme/cmds"
    assert_symlink "$CWD/.claude/commands/cmd" "github.com/acme/cmds"
    run_cli_in "$CWD" install
    assert_exit 0
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
}

sc24() {
    scenario_env
    setup_cli init --from acme/skl-config:teams/platform.yaml
    run_cli_in "$CWD" i
    assert_exit 0
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
}

sc25() {
    scenario_env
    setup_cli init -g --from acme/skl-config:teams/platform.yaml
    run_cli_in "$CWD" -g install
    assert_exit 0
    assert_symlink "$SC_HOME/.cursor/skills/demo" "github.com/acme/skills"
    assert_symlink "$SC_HOME/.claude/commands/demo" "github.com/acme/skills"
}

####################################################################################################
#
# 26–29: remove.
#
####################################################################################################

sc26() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    run_cli_in "$CWD" remove demo
    assert_exit 0
    assert_not_exists "$CWD/.cursor/skills/demo"
    assert_not_exists "$CWD/.claude/commands/demo"
    assert_file_lacks "$CWD/skl.yaml" "namespace: demo"
    assert_dir_exists "$STORE/github.com/acme/skills"
}

sc27() {
    scenario_env
    setup_cli init
    setup_cli add acme/cmds --ns cmd
    run_cli_in "$CWD" remove cmds
    assert_exit 0
    assert_not_exists "$CWD/.cursor/commands/cmd"
    assert_file_lacks "$CWD/skl.yaml" "acme/cmds"
}

sc28() {
    scenario_env
    setup_cli init
    setup_cli add acme/both --ns both
    setup_cli init -g
    setup_cli -g add acme/skills --ns demo
    run_cli_in "$CWD" -g remove acme/skills
    assert_exit 0
    assert_not_exists "$SC_HOME/.cursor/skills/demo"
    assert_not_exists "$SC_HOME/.claude/commands/demo"
    assert_symlink "$CWD/.cursor/skills/both" "github.com/acme/both"
}

sc29() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" remove nosuch
    assert_failed
}

####################################################################################################
#
# 30–38: update, list, docs.
#
####################################################################################################

sc30() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    run_cli_in "$CWD" update
    assert_exit 0
    assert_output_contains "unchanged"
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
}

sc31() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    local old_sha new_sha
    old_sha="$(cat "$STORE/github.com/acme/skills/.git/refs/heads/main")"
    printf '\nextra line\n' >>"$REMOTE_SKILLS/README.md"
    fixture_git "$REMOTE_SKILLS" add README.md
    fixture_git "$REMOTE_SKILLS" commit --quiet -m "extra"
    run_cli_in "$CWD" update demo
    assert_exit 0
    new_sha="$(cat "$STORE/github.com/acme/skills/.git/refs/heads/main")"
    if [ "$old_sha" = "$new_sha" ]; then
        fail "store HEAD did not move after update"
    else
        pass "store HEAD moved $old_sha -> $new_sha"
    fi
    assert_output_contains "$old_sha"
    assert_output_contains "$new_sha"
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
    assert_file_contains "$STORE/github.com/acme/skills/README.md" "extra line"
}

sc32() {
    scenario_env
    setup_cli init -g --from acme/skl-config:teams/platform.yaml
    run_cli_in "$CWD" -g update
    assert_exit 0
}

sc33() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    setup_cli add acme/cmds --ns cmd
    run_cli_in "$CWD" list
    assert_exit 0
    assert_output_contains "demo"
    assert_output_contains "acme/skills"
    assert_output_contains "demo:demo"
    assert_output_contains "Says hello"
    assert_output_contains "cmd:plan/create"
    assert_output_contains "Create a plan"
    assert_output_contains "A pack of demo skills"
}

sc34() {
    scenario_env
    setup_cli init
    setup_cli add acme/both --ns both
    setup_cli init -g
    setup_cli -g add acme/skills --ns demo
    run_cli_in "$CWD" -g list
    assert_exit 0
    assert_output_contains "acme/skills"
    assert_output_contains "demo"
    assert_output_lacks "acme/both"
    assert_output_lacks "both:"
}

sc35() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    : >"$BROWSER_LOG"
    run_cli_in "$CWD" docs demo -n
    assert_exit 0
    assert_output_contains "acme/skills"
    assert_output_contains "demo"
    if [ -s "$BROWSER_LOG" ]; then
        fail "SKL_BROWSER was invoked; log is not empty"
    else
        pass "SKL_BROWSER was not invoked"
    fi
}

sc36() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    run_cli_in "$CWD" docs demo --open
    assert_failed
    assert_output_contains "unknown option"
}

sc37() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" docs -n
    assert_failed
    assert_output_contains "package"
}

sc38() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    : >"$BROWSER_LOG"
    run_cli_in "$CWD" docs demo -n
    assert_exit 0
    assert_output_contains "github.io"
    if [ -s "$BROWSER_LOG" ]; then
        fail "SKL_BROWSER was invoked; log is not empty"
    else
        pass "SKL_BROWSER was not invoked"
    fi
}

####################################################################################################
#
# 39–44: safety and IO.
#
####################################################################################################

sc39() {
    scenario_env
    local dotfiles="$SC_HOME/dotfiles"
    mkdir -p "$dotfiles" "$SC_HOME/.config/skilled"
    write_empty_yaml "$dotfiles/skl.yaml"
    rm -f "$GLOBAL_YAML"
    ln -s "$dotfiles/skl.yaml" "$GLOBAL_YAML"
    if [ ! -L "$GLOBAL_YAML" ]; then
        fail "failed to create stow symlink at $GLOBAL_YAML"
    fi
    run_cli_in "$CWD" -g add acme/cmds --ns cmd
    assert_exit 0
    if [ -L "$GLOBAL_YAML" ]; then
        pass "global yaml is still a symlink"
    else
        fail "global yaml is no longer a symlink"
    fi
    assert_file_contains "$dotfiles/skl.yaml" "acme/cmds"
    assert_file_contains "$dotfiles/skl.yaml" "namespace: cmd"
}

sc40() {
    scenario_env
    printf 'packages: [\n' >"$CWD/skl.yaml"
    run_cli_in "$CWD" list
    assert_failed
    assert_output_contains "skl.yaml"
}

sc41() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    assert_not_exists "$SC_HOME/.cursor/skills-cursor"
}

sc42() {
    scenario_env
    setup_cli init
    if [ -e "$SC_HOME/.ssh" ] || [ -L "$SC_HOME/.ssh" ]; then
        mv "$SC_HOME/.ssh" "$SC_HOME/.ssh.away"
    fi
    run_cli_in "$CWD" add acme/skills --ns demo
    assert_exit 0
    assert_dir_exists "$STORE/github.com/acme/skills"
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
}

sc43() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add /tmp/some-path --ns x
    assert_failed
}

sc44() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add https://github.com/acme/skills --ns x
    assert_failed
}

####################################################################################################
#
# 45–46: add --from.
#
####################################################################################################

sc45() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add --from acme/skl-config:teams/platform.yaml
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "acme/skills"
    assert_file_contains "$CWD/skl.yaml" "acme/cmds"
    assert_not_exists "$STORE/github.com/acme/skl-config"
    assert_not_exists "$CWD/.cursor/skills/demo"
}

sc46() {
    scenario_env
    printf 'packages:\n  - repo: acme/both\n    namespace: keep\n' >"$CWD/skl.yaml"
    run_cli_in "$CWD" add --from acme/skl-config:teams/platform.yaml
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "namespace: keep"
    assert_file_contains "$CWD/skl.yaml" "acme/both"
    assert_file_contains "$CWD/skl.yaml" "namespace: demo"
    assert_file_contains "$CWD/skl.yaml" "namespace: cmd"
}

####################################################################################################
#
# 48–59: --branch and --local.
#
####################################################################################################

sc48() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add acme/skills --ns demo --branch dev
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "acme/skills"
    assert_file_contains "$CWD/skl.yaml" "branch: dev"
    assert_file_lacks "$CWD/skl.yaml" "local:"
    if [ "$(store_branch)" = "dev" ]; then
        pass "store HEAD is dev"
    else
        fail "expected store HEAD to be dev, got $(store_branch)"
    fi
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
    run_cli_in "$CWD" list
    assert_exit 0
    assert_output_contains "Hello from dev"
}

sc49() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo --branch dev
    run_cli_in "$CWD" install
    assert_exit 0
    if [ "$(store_branch)" = "dev" ]; then
        pass "store HEAD is still dev"
    else
        fail "expected store HEAD to stay dev, got $(store_branch)"
    fi
    assert_file_contains "$CWD/skl.yaml" "branch: dev"
}

sc50() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo --branch dev
    run_cli_in "$CWD" update demo --branch main
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "branch: main"
    assert_file_lacks "$CWD/skl.yaml" "local:"
    if [ "$(store_branch)" = "main" ]; then
        pass "store HEAD is main"
    else
        fail "expected store HEAD to be main, got $(store_branch)"
    fi
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
}

sc51() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    run_cli_in "$CWD" update demo --local "$LOCAL_PKG"
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "local:"
    assert_file_contains_path "$CWD/skl.yaml" "$LOCAL_PKG"
    assert_file_lacks "$CWD/skl.yaml" "branch:"
    assert_symlink "$CWD/.cursor/skills/demo" "local-skills"
    run_cli_in "$CWD" list
    assert_exit 0
    assert_output_contains "Local hello"
}

sc52() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    setup_cli update demo --local "$LOCAL_PKG"
    run_cli_in "$CWD" update demo --branch main
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "branch: main"
    assert_file_lacks "$CWD/skl.yaml" "local:"
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
}

sc53() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    run_cli_in "$CWD" add acme/skills --ns work --local "$LOCAL_PKG"
    assert_exit 0
    assert_file_contains "$CWD/skl.yaml" "namespace: work"
    assert_file_contains_path "$CWD/skl.yaml" "$LOCAL_PKG"
    assert_symlink "$CWD/.cursor/skills/work" "local-skills"
}

sc54() {
    scenario_env
    setup_cli init
    cp "$CWD/skl.yaml" "$SC_HOME/yaml.before"
    run_cli_in "$CWD" add acme/skills --ns extra --branch dev --local "$LOCAL_PKG"
    assert_failed
    if cmp -s "$CWD/skl.yaml" "$SC_HOME/yaml.before"; then
        pass "project YAML unchanged when both flags are set"
    else
        fail "project YAML changed when both flags are set"
    fi
}

sc55() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    run_cli_in "$CWD" update --branch main
    assert_failed
    assert_output_contains "package"
}

sc56() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add --from acme/skl-config:teams/platform.yaml --branch dev
    assert_failed
    assert_output_contains "--branch"
}

sc57() {
    scenario_env
    setup_cli init
    cp "$CWD/skl.yaml" "$SC_HOME/yaml.before"
    run_cli_in "$CWD" add acme/skills --ns extra --branch nosuchbranch
    assert_failed
    if cmp -s "$CWD/skl.yaml" "$SC_HOME/yaml.before"; then
        pass "project YAML unchanged on missing branch"
    else
        fail "project YAML changed on missing branch"
    fi
}

sc58() {
    scenario_env
    setup_cli init
    setup_cli add acme/skills --ns demo
    cp "$CWD/skl.yaml" "$SC_HOME/yaml.before"
    run_cli_in "$CWD" update demo --local "$SC_HOME/no-such-local-pkg"
    assert_failed
    if cmp -s "$CWD/skl.yaml" "$SC_HOME/yaml.before"; then
        pass "project YAML unchanged on missing local path"
    else
        fail "project YAML changed on missing local path"
    fi
}

sc59() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add /tmp/some-path --ns x
    assert_failed
}

####################################################################################################
#
# 60–73: the scratch directory linked as loc.
#
# No git in this section: the scratch directory is not a repository.
#
####################################################################################################

sc60() {
    scenario_env
    run_cli_in "$CWD" init
    assert_exit 0
    assert_output_contains "scratch"
    assert_dir_exists "$SCRATCH/skills"
    assert_dir_exists "$SCRATCH/commands"
    assert_symlink "$CWD/.cursor/skills/loc" ".skilled/scratch/skills"
    assert_symlink "$CWD/.cursor/commands/loc" ".skilled/scratch/commands"
    assert_symlink "$CWD/.claude/skills/loc" ".skilled/scratch/skills"
    assert_symlink "$CWD/.claude/commands/loc" ".skilled/scratch/commands"
}

sc61() {
    scenario_env
    setup_cli init
    write_scratch_items
    assert_file_contains "$CWD/.cursor/skills/loc/hello/SKILL.md" "Scratch hello"
    assert_file_contains "$CWD/.claude/skills/loc/hello/SKILL.md" "Scratch hello"
}

sc62() {
    scenario_env
    setup_cli init
    write_scratch_items
    assert_file_contains "$CWD/.cursor/commands/loc/plan/create.md" "Create a scratch plan"
    assert_file_contains "$CWD/.claude/commands/loc/plan/create.md" "Create a scratch plan"
}

sc63() {
    scenario_env
    setup_cli init
    write_scratch_items
    run_cli_in "$CWD" list
    assert_exit 0
    assert_output_contains "loc:hello"
    assert_output_contains "Scratch hello"
    assert_output_contains "loc:plan/create"
}

sc64() {
    scenario_env
    setup_cli init
    write_scratch_items
    rm "$CWD/.claude/commands/loc"
    run_cli_in "$CWD" install
    assert_exit 0
    assert_symlink "$CWD/.claude/commands/loc" ".skilled/scratch/commands"
    assert_file_contains "$CWD/.claude/commands/loc/plan/create.md" "Create a scratch plan"
}

sc65() {
    scenario_env
    setup_cli init
    write_scratch_items
    rm "$CWD/.cursor/skills/loc"
    run_cli_in "$CWD" update
    assert_exit 0
    assert_symlink "$CWD/.cursor/skills/loc" ".skilled/scratch/skills"
}

sc66() {
    scenario_env
    setup_cli init
    write_scratch_items
    setup_cli install
    run_cli_in "$CWD" install
    assert_exit 0
    assert_symlink "$CWD/.claude/skills/loc" ".skilled/scratch/skills"
    assert_file_contains "$SCRATCH/skills/hello/SKILL.md" "Scratch hello"
}

sc67() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" add acme/skills --ns loc
    assert_failed
    assert_output_contains "reserved"
    assert_file_lacks "$CWD/skl.yaml" "acme/skills"
    assert_symlink "$CWD/.cursor/skills/loc" ".skilled/scratch/skills"
}

sc68() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" remove loc
    assert_failed
    assert_output_contains "scratch directory"
    assert_symlink "$CWD/.claude/commands/loc" ".skilled/scratch/commands"
}

sc69() {
    scenario_env
    setup_cli init
    write_scratch_items
    setup_cli add acme/skills --ns demo
    assert_symlink "$CWD/.cursor/skills/demo" "github.com/acme/skills"
    run_cli_in "$CWD" remove demo
    assert_exit 0
    assert_not_symlink_path "$CWD/.cursor/skills/demo"
    assert_symlink "$CWD/.cursor/skills/loc" ".skilled/scratch/skills"
    assert_file_contains "$SCRATCH/skills/hello/SKILL.md" "Scratch hello"
}

sc70() {
    scenario_env
    write_empty_yaml "$CWD/skl.yaml"
    run_cli_in "$CWD" install
    assert_exit 0
    assert_symlink "$CWD/.cursor/commands/loc" ".skilled/scratch/commands"
    assert_symlink "$CWD/.claude/skills/loc" ".skilled/scratch/skills"
}

sc71() {
    scenario_env
    setup_cli init
    run_cli_in "$CWD" -g init
    assert_exit 0
    assert_dir_exists "$SC_HOME/.skilled/scratch/skills"
    assert_symlink "$SC_HOME/.cursor/skills/loc" ".skilled/scratch/skills"
    assert_symlink "$SC_HOME/.claude/commands/loc" ".skilled/scratch/commands"
    assert_symlink "$CWD/.cursor/skills/loc" "$CWD/.skilled/scratch/skills"
}

sc72() {
    scenario_env
    printf 'packages:\n  - repo: acme/skills\n    namespace: loc\n' >"$CWD/skl.yaml"
    run_cli_in "$CWD" list
    assert_failed
    assert_output_contains "reserved"
}

sc73() {
    scenario_env
    write_empty_yaml "$CWD/skl.yaml"
    mkdir -p "$CWD/.claude/skills"
    printf 'not a link\n' >"$CWD/.claude/skills/loc"
    run_cli_in "$CWD" install
    assert_failed
    assert_output_contains "will not overwrite"
    assert_file_contains "$CWD/.claude/skills/loc" "not a link"
}

####################################################################################################
#
# The driver.
#
# Scenarios are independent, so they run in lanes: --jobs lanes pull from one shared queue, and a
# lane takes the next scenario the instant it finishes the last one. Nothing waits for a batch to
# drain, so a slow scenario never leaves the other lanes idle.
#
# Each scenario writes into its own log and its own status file. The main shell prints those logs
# whole, in scenario order, as they finish, so output reads exactly like a serial run whatever
# order the lanes happen to run in.
#
####################################################################################################

SCENARIOS=(
    "sc01|1. --help, -h, and help list the subcommands"
    "sc02|2. --version, -V, and version print the same version"
    "sc03|3. skl with no args prints help and exits 0"
    "sc04|4. unknown command exits non-zero and names it"
    "sc05|5. --no-color list has no ANSI"
    "sc06|6. NO_COLOR=1 list has no ANSI"
    "sc07|7. -n add without --ns exits non-zero and does not hang"
    "sc08|8. SKL_NONINTERACTIVE=1 add without --ns same as 7"
    "sc09|9. skl init creates ./skl.yaml with packages: []"
    "sc10|10. second skl init exits 0 and does not wipe a non-empty packages list"
    "sc11|11. skl init -g creates the global config, not the project file"
    "sc12|12. init --from writes packages, clones and links them, deletes the temp config clone"
    "sc13|13. init -g --from writes global YAML from an SSH spec"
    "sc14|14. add --from blob URL is an idempotent merge (clone still SSH)"
    "sc15|15. add acme/skills --ns demo clones, writes YAML, and links Cursor skills and Claude commands"
    "sc16|16. add acme/cmds --ns cmd links Cursor commands and Claude commands (nested plan/create.md)"
    "sc17|17. add acme/both --ns both links skills and commands for Cursor and Claude"
    "sc18|18. add acme/empty --ns empty fails and does not write YAML"
    "sc19|19. add SSH github.example.com stores under that host segment"
    "sc20|20. duplicate namespace demo exits non-zero; YAML unchanged"
    "sc21|21. add acme/both --ns demo fails (namespace taken)"
    "sc22|22. skl -g add links global agent dirs and writes global YAML"
    "sc23|23. init --from clones and links; second install is idempotent"
    "sc24|24. skl i is install"
    "sc25|25. skl -g install installs from global YAML into global agent dirs"
    "sc26|26. remove demo unlinks, drops YAML, leaves the store clone"
    "sc27|27. remove cmds matches remaining acme/cmds by repo name"
    "sc28|28. skl -g remove acme/skills unlinks global dirs; project links stay"
    "sc29|29. remove nosuch exits non-zero"
    "sc30|30. update with HEAD unchanged prints unchanged; links still valid"
    "sc31|31. update demo after a new commit on the fixture remote"
    "sc32|32. skl -g update updates packages in the global YAML"
    "sc33|33. list prints packages and ns:name items, including nested commands"
    "sc34|34. skl -g list lists global packages, not the project file"
    "sc35|35. docs demo -n prints details and does not invoke SKL_BROWSER"
    "sc36|36. docs demo --open is unknown"
    "sc37|37. docs -n with no package name exits non-zero"
    "sc38|38. docs demo -n prints the Pages guess and does not open a browser"
    "sc39|39. stow: global yaml is a symlink; -g add writes through it"
    "sc40|40. invalid project skl.yaml → list exits non-zero with a parse error"
    "sc41|41. add never creates \$HOME/.cursor/skills-cursor"
    "sc42|42. add still clones via insteadOf when \$HOME/.ssh is renamed away"
    "sc43|43. add of a filesystem path exits non-zero"
    "sc44|44. add of an HTTPS URL exits non-zero"
    "sc45|45. init then add --from writes packages and does not clone"
    "sc46|46. add --from keeps an existing extra package and appends demo and cmd"
    "sc47|47. init --from refused when packages already exist; YAML unchanged"
    "sc48|48. add --branch dev clones that branch, writes YAML, and links the store"
    "sc49|49. second install is idempotent and stays on dev"
    "sc50|50. update demo --branch main switches the store and YAML"
    "sc51|51. update demo --local retargets links and writes absolute local"
    "sc52|52. update demo --branch main after local relinks the store"
    "sc53|53. add --local for a new namespace writes absolute local"
    "sc54|54. add --branch and --local together exits non-zero"
    "sc55|55. update --branch with no package query exits non-zero"
    "sc56|56. add --from with --branch exits non-zero"
    "sc57|57. add --branch nosuchbranch exits non-zero; YAML unchanged"
    "sc58|58. update --local of a missing path exits non-zero; YAML unchanged"
    "sc59|59. add of a filesystem path as the repo still exits non-zero"
    "sc60|60. skl init creates the scratch trees and links them into both agents"
    "sc61|61. a scratch skill is readable through the Cursor and Claude links"
    "sc62|62. a scratch command is readable through the Cursor and Claude links"
    "sc63|63. list prints the scratch skill and command as loc items"
    "sc64|64. install restores a deleted scratch link"
    "sc65|65. update with no arguments restores a deleted scratch link"
    "sc66|66. a second install is idempotent and keeps the scratch files"
    "sc67|67. add --ns loc exits non-zero and leaves the YAML and links alone"
    "sc68|68. remove loc names the scratch directory and leaves the links"
    "sc69|69. removing a real package leaves the scratch links alone"
    "sc70|70. install with an empty packages list still links the scratch directory"
    "sc71|71. init -g links the scratch directory under HOME, leaving the project one alone"
    "sc72|72. a skl.yaml that names the scratch namespace is a parse error"
    "sc73|73. a real file at a scratch link path fails install and is not overwritten"
)

#
# --only runs the scenarios whose function name or title matches, which is what makes a single
# scenario re-runnable on its own after a failure. Each one sets up everything it needs.
#
if [ -n "$ONLY" ]; then
    SELECTED=()
    for entry in "${SCENARIOS[@]}"; do
        case "$entry" in
            *"$ONLY"*) SELECTED+=("$entry") ;;
        esac
    done
    if [ "${#SELECTED[@]}" -eq 0 ]; then
        echo "No scenario matches --only \"$ONLY\""
        exit 1
    fi
    SCENARIOS=("${SELECTED[@]}")
fi

LOG_DIR="$FIXTURES/logs"
mkdir -p "$LOG_DIR"

echo -e "${BLUE}=== skl smoke tests ===${NC}"
echo -e "${BLUE}Driving the $CLI_DESCRIPTION${NC}"
echo -e "${BLUE}${#SCENARIOS[@]} scenarios, $JOBS lanes, each scenario in its own HOME${NC}"
echo ""

FAILED=()
TOTAL="${#SCENARIOS[@]}"

#
# One scenario: its own log, and a status file the printer waits on.
#
run_one() {
    local index="$1"
    local entry="${SCENARIOS[$index]}"
    local fn="${entry%%|*}"
    local title="${entry#*|}"
    local slot
    slot="$(printf '%03d' "$index")"
    local status=0

    (
        echo -e "${YELLOW}${title}${NC}"
        "$fn"
    ) >"$LOG_DIR/$slot.log" 2>&1 || status=$?

    printf '%s' "$status" >"$LOG_DIR/$slot.status"
}

QUEUE="$FIXTURES/queue"
LANES=()

if [ "$JOBS" -gt 1 ] && mkfifo "$QUEUE" 2>/dev/null; then
    #
    # The queue holds one line per scenario. A lane blocks on read until a line is there, so the
    # lanes share the work greedily rather than being handed a fixed slice of it. bash reads a
    # pipe one byte at a time, so two lanes cannot tear one line between them.
    #
    seq 0 "$((TOTAL - 1))" >"$QUEUE" &
    QUEUE_WRITER=$!
    exec 3<"$QUEUE"

    lane=0
    while [ "$lane" -lt "$JOBS" ]; do
        (
            while IFS= read -r queued_index <&3; do
                run_one "$queued_index"
            done
        ) &
        LANES+=("$!")
        lane=$((lane + 1))
    done
else
    QUEUE_WRITER=""
    (
        index=0
        while [ "$index" -lt "$TOTAL" ]; do
            run_one "$index"
            index=$((index + 1))
        done
    ) &
    LANES+=("$!")
fi

#
# Print in scenario order while the lanes are still working: wait for each scenario's status file,
# then print its log. A scenario that finished early is held back until the ones before it are out.
#
index=0
while [ "$index" -lt "$TOTAL" ]; do
    slot="$(printf '%03d' "$index")"
    while [ ! -f "$LOG_DIR/$slot.status" ]; do
        sleep 0.05
    done
    cat "$LOG_DIR/$slot.log"
    if [ "$(cat "$LOG_DIR/$slot.status")" != "0" ]; then
        entry="${SCENARIOS[$index]}"
        FAILED+=("${entry#*|}")
    fi
    index=$((index + 1))
done

for lane_pid in "${LANES[@]}"; do
    wait "$lane_pid" || true
done
if [ "$JOBS" -gt 1 ] && [ -n "$QUEUE_WRITER" ]; then
    exec 3<&-
    wait "$QUEUE_WRITER" || true
fi

echo ""
if [ "${#FAILED[@]}" -ne 0 ]; then
    echo -e "${RED}FAIL: ${#FAILED[@]} of $TOTAL scenarios failed${NC}"
    for title in "${FAILED[@]}"; do
        echo -e "${RED}  - $title${NC}"
    done
    exit 1
fi

echo -e "${BLUE}Fixtures left at $FIXTURES${NC}"
echo -e "${GREEN}PASS: all smoke checks passed${NC}"
