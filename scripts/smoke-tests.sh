#!/bin/bash

# skl smoke tests
#
# Drives the real CLI as a real process and asserts exit codes, output, and filesystem effects
# (namespace symlinks, store clones, YAML writes). Unit tests cannot see those.
#
# Isolation: a throwaway HOME (and project cwds) from mktemp. Fixture git init/add/commit/config
# run only with GIT_DIR and GIT_WORK_TREE set to those throwaway paths; the script aborts if
# git rev-parse --show-toplevel is not that path. skl is invoked with those two unset.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RUN_CLI=("$PROJECT_DIR/zig-out/bin/skl")
if [ "${OS:-}" = "Windows_NT" ]; then
    RUN_CLI=("$PROJECT_DIR/zig-out/bin/skl.exe")
fi
CLI_DESCRIPTION="in-tree binary at ${RUN_CLI[0]}"

if [ "${1:-}" = "--binary" ]; then
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

echo -e "${BLUE}=== skl smoke tests ===${NC}"
echo -e "${BLUE}Driving the $CLI_DESCRIPTION${NC}"
echo ""

scenario() {
    echo -e "${YELLOW}$1${NC}"
}

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
    if grep -q $'\033' "$OUTPUT_FILE"; then
        fail "expected no ANSI escapes in output"
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
        pass "$path is absent"
    fi
}

write_empty_yaml() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    printf 'packages: []\n' >"$path"
}

####################################################################################################
#
# Throwaway HOME, fixture remotes, and project cwds.
#
# HOME comes from mktemp -d then pwd -P (macOS /var is a symlink). Product paths (~/.skilled,
# ~/.config, ~/.cursor, ~/.ssh) all land here. Two overlapping smoke runs cannot share it.
#
# GitHub Actions Linux sets XDG_CONFIG_HOME to the runner's real ~/.config. Release smoke
# then wrote global YAML there (`init -g` printed /home/runner/.config/...) instead of
# $HOME/.config. Unset it so -g uses <home>/.config/skilled/skl.yaml.
#
# Git Bash `ln -s` copies unless MSYS asks for native links. Release smoke test 39 then
# failed `[ -L $HOME/.config/skilled/skl.yaml ]` on Windows. Developer Mode is already
# enabled in the workflow; this makes `ln` use it.
#
# READ THIS BEFORE ADDING GIT COMMANDS.
#
# fixture_git is the only wrapper that may run git init / add / commit / config. It sets GIT_DIR
# and GIT_WORK_TREE to the throwaway path and aborts unless show-toplevel is that path. Never run
# those four commands against this checkout. skl is invoked with GIT_DIR and GIT_WORK_TREE unset.
#
####################################################################################################

HOME="$(cd "$(mktemp -d)" && pwd -P)"
export HOME
export USERPROFILE="$HOME"
unset XDG_CONFIG_HOME
if [ "${OS:-}" = "Windows_NT" ]; then
    export MSYS="winsymlinks:nativestrict"
fi
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export TMPDIR="$HOME/tmp"
export TMP="$HOME/tmp"
export TEMP="$HOME/tmp"
# If insteadOf failed to rewrite, fail immediately rather than waiting on SSH.
export GIT_SSH_COMMAND="false"

mkdir -p "$HOME/tmp" "$HOME/remotes" "$HOME/.ssh"

OUTPUT_FILE="$HOME/cli-output.txt"
BROWSER_LOG="$HOME/browser.log"
REMOTES="$HOME/remotes"

if command -v cygpath >/dev/null 2>&1; then
    INSTEAD_OF_BASE="file:///$(cygpath -m "$REMOTES")/"
else
    INSTEAD_OF_BASE="file://${REMOTES}/"
fi

cat >"$GIT_CONFIG_GLOBAL" <<EOF
[user]
	name = skl-smoke
	email = smoke@example.com
[safe]
	directory = *
[protocol "file"]
	allow = always
[url "$INSTEAD_OF_BASE"]
	insteadOf = git@github.com:
	insteadOf = git@github.example.com:
EOF

if [ "${OS:-}" = "Windows_NT" ]; then
    SKL_BROWSER="$HOME/skl-browser.cmd"
    cat >"$SKL_BROWSER" <<EOF
@echo off
echo %*>>"$BROWSER_LOG"
EOF
else
    SKL_BROWSER="$HOME/skl-browser"
    cat >"$SKL_BROWSER" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >>"$BROWSER_LOG"
EOF
    chmod +x "$SKL_BROWSER"
fi
export SKL_BROWSER
: >"$BROWSER_LOG"

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

REMOTE_SKILLS="$(write_remote "$REMOTES/acme/skills.git" \
    "README.md" "A pack of demo skills.
" \
    "skills/demo/SKILL.md" "---
description: Says hello
---

# Hello
")"

fixture_git "$REMOTE_SKILLS" checkout -b dev
printf 'Skills from the dev branch.\n' >"$REMOTE_SKILLS/README.md"
printf '%s' "---
description: Hello from dev
---

# Hello
" >"$REMOTE_SKILLS/skills/demo/SKILL.md"
fixture_git "$REMOTE_SKILLS" add -A
fixture_git "$REMOTE_SKILLS" commit --quiet -m "dev"
fixture_git "$REMOTE_SKILLS" checkout main

REMOTE_CMDS="$(write_remote "$REMOTES/acme/cmds.git" \
    "README.md" "A pack of demo commands.
" \
    "commands/plan/create.md" "---
description: Create a plan
---

Write a plan.
")"

REMOTE_BOTH="$(write_remote "$REMOTES/acme/both.git" \
    "README.md" "Skills and commands together.
" \
    "skills/hello/SKILL.md" "---
description: Says hello
---
" \
    "commands/plan/create.md" "---
description: Create a plan
---
")"

REMOTE_EMPTY="$(write_remote "$REMOTES/acme/empty.git" \
    "README.md" "Not a package.
")"

REMOTE_CONFIG="$(write_remote "$REMOTES/acme/skl-config.git" \
    "teams/platform.yaml" "packages:
  - repo: acme/skills
    namespace: demo
  - repo: acme/cmds
    namespace: cmd
")"

CWD_FLAGS="$(cd "$(mktemp -d)" && pwd -P)"
CWD_INIT="$(cd "$(mktemp -d)" && pwd -P)"
CWD_ADD="$(cd "$(mktemp -d)" && pwd -P)"
CWD_INSTALL="$(cd "$(mktemp -d)" && pwd -P)"
CWD_ADD_FROM="$(cd "$(mktemp -d)" && pwd -P)"
CWD_ADD_FROM_KEEP="$(cd "$(mktemp -d)" && pwd -P)"
CWD_STOW="$(cd "$(mktemp -d)" && pwd -P)"
CWD_BAD_YAML="$(cd "$(mktemp -d)" && pwd -P)"
CWD_SOURCE="$(cd "$(mktemp -d)" && pwd -P)"
LOCAL_PKG="$(write_local_package "$HOME/local-skills")"

STORE="$HOME/.skilled/store"
GLOBAL_YAML="$HOME/.config/skilled/skl.yaml"

echo -e "${BLUE}Throwaway HOME $HOME${NC}"
echo ""

####################################################################################################
#
# 1–8: root / global flags (cwd-flags)
#
####################################################################################################

scenario "1. --help, -h, and help list the subcommands"
for flag in --help -h help; do
    run_cli_in "$CWD_FLAGS" "$flag"
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

scenario "2. --version, -V, and version print the same version"
run_cli_in "$CWD_FLAGS" --version
assert_exit 0
VERSION="$(tr -d '[:space:]' < "$OUTPUT_FILE")"
if [ -z "$VERSION" ]; then
    fail "expected --version to print a version"
else
    pass "version is \"$VERSION\""
fi
for flag in --version -V version; do
    run_cli_in "$CWD_FLAGS" "$flag"
    assert_exit 0
    assert_output_contains "$VERSION"
done

scenario "3. skl with no args prints help and exits 0"
run_cli_in "$CWD_FLAGS"
assert_exit 0
assert_output_contains "Usage: skl"
assert_output_contains "init"

scenario "4. unknown command exits non-zero and names it"
run_cli_in "$CWD_FLAGS" nosuch
assert_failed
assert_output_contains "unknown command"
assert_output_contains "nosuch"

scenario "5. --no-color list has no ANSI"
run_cli_in "$CWD_FLAGS" init
assert_exit 0
run_cli_in "$CWD_FLAGS" --no-color list
assert_exit 0
assert_no_ansi

scenario "6. NO_COLOR=1 list has no ANSI"
NO_COLOR=1 run_cli_in "$CWD_FLAGS" list
assert_exit 0
assert_no_ansi

scenario "7. -n add without --ns exits non-zero and does not hang"
run_cli_in "$CWD_FLAGS" -n add acme/skills
assert_failed
assert_output_contains "--ns"

scenario "8. SKL_NONINTERACTIVE=1 add without --ns same as 7"
SKL_NONINTERACTIVE=1 run_cli_in "$CWD_FLAGS" add acme/skills
assert_failed
assert_output_contains "--ns"

####################################################################################################
#
# 9–14, 47: init (cwd-init); 11/13 write global YAML
#
####################################################################################################

scenario "9. skl init creates ./skl.yaml with packages: []"
run_cli_in "$CWD_INIT" init
assert_exit 0
assert_file_exists "$CWD_INIT/skl.yaml"
assert_file_contains "$CWD_INIT/skl.yaml" "packages: []"

scenario "10. second skl init exits 0 and does not wipe a non-empty packages list"
printf 'packages:\n  - repo: acme/keep\n    namespace: keep\n' >"$CWD_INIT/skl.yaml"
run_cli_in "$CWD_INIT" init
assert_exit 0
assert_file_contains "$CWD_INIT/skl.yaml" "acme/keep"
assert_file_contains "$CWD_INIT/skl.yaml" "namespace: keep"
write_empty_yaml "$CWD_INIT/skl.yaml"

scenario "11. skl init -g creates the global config, not the project file"
run_cli_in "$CWD_INIT" init -g
assert_exit 0
assert_file_exists "$GLOBAL_YAML"
assert_file_contains "$GLOBAL_YAML" "packages: []"
assert_file_contains "$CWD_INIT/skl.yaml" "packages: []"

scenario "12. init --from writes packages, clones and links them, deletes the temp config clone"
run_cli_in "$CWD_INIT" init --from acme/skl-config:teams/platform.yaml
assert_exit 0
assert_file_contains "$CWD_INIT/skl.yaml" "acme/skills"
assert_file_contains "$CWD_INIT/skl.yaml" "namespace: demo"
assert_file_contains "$CWD_INIT/skl.yaml" "acme/cmds"
assert_file_contains "$CWD_INIT/skl.yaml" "namespace: cmd"
assert_not_exists "$STORE/github.com/acme/skl-config"
assert_dir_exists "$STORE/github.com/acme/skills"
assert_symlink "$CWD_INIT/.cursor/skills/demo" "github.com/acme/skills"
assert_symlink "$CWD_INIT/.claude/commands/demo" "github.com/acme/skills"
assert_symlink "$CWD_INIT/.cursor/commands/cmd" "github.com/acme/cmds"
assert_symlink "$CWD_INIT/.claude/commands/cmd" "github.com/acme/cmds"

scenario "13. init -g --from writes global YAML from an SSH spec"
run_cli_in "$CWD_INIT" init -g --from git@github.com:acme/skl-config.git:teams/platform.yaml
assert_exit 0
assert_file_contains "$GLOBAL_YAML" "acme/skills"
assert_file_contains "$GLOBAL_YAML" "namespace: demo"
assert_file_contains "$GLOBAL_YAML" "acme/cmds"
assert_not_exists "$STORE/github.com/acme/skl-config"
# 22 needs --ns demo free on the global file. 13 already asserted the --from write.
write_empty_yaml "$GLOBAL_YAML"

scenario "14. add --from blob URL is an idempotent merge (clone still SSH)"
run_cli_in "$CWD_INIT" add --from https://github.com/acme/skl-config/blob/main/teams/platform.yaml
assert_exit 0
assert_file_contains "$CWD_INIT/skl.yaml" "acme/skills"
assert_file_contains "$CWD_INIT/skl.yaml" "acme/cmds"
assert_not_exists "$STORE/github.com/acme/skl-config"

scenario "47. init --from refused when packages already exist; YAML unchanged"
cp "$CWD_INIT/skl.yaml" "$HOME/cwd-init-yaml.before"
run_cli_in "$CWD_INIT" init --from acme/skl-config:teams/platform.yaml
assert_failed
assert_output_contains "add --from"
if cmp -s "$CWD_INIT/skl.yaml" "$HOME/cwd-init-yaml.before"; then
    pass "cwd-init YAML unchanged"
else
    fail "cwd-init YAML changed after refused init --from"
fi

####################################################################################################
#
# 15–22: add (cwd-add)
#
####################################################################################################

scenario "15. add acme/skills --ns demo clones, writes YAML, and links Cursor skills and Claude commands"
run_cli_in "$CWD_ADD" init
assert_exit 0
run_cli_in "$CWD_ADD" add acme/skills --ns demo
assert_exit 0
assert_dir_exists "$STORE/github.com/acme/skills"
assert_file_exists "$STORE/github.com/acme/skills/skills/demo/SKILL.md"
assert_file_contains "$CWD_ADD/skl.yaml" "acme/skills"
assert_file_contains "$CWD_ADD/skl.yaml" "namespace: demo"
assert_symlink "$CWD_ADD/.cursor/skills/demo" "github.com/acme/skills"
assert_symlink "$CWD_ADD/.claude/commands/demo" "github.com/acme/skills"
assert_not_symlink_path "$CWD_ADD/.cursor/commands/demo"
assert_not_symlink_path "$CWD_ADD/.claude/skills/demo"

scenario "16. add acme/cmds --ns cmd links Cursor commands and Claude commands (nested plan/create.md)"
run_cli_in "$CWD_ADD" add acme/cmds --ns cmd
assert_exit 0
assert_symlink "$CWD_ADD/.cursor/commands/cmd" "github.com/acme/cmds"
assert_symlink "$CWD_ADD/.claude/commands/cmd" "github.com/acme/cmds"
assert_file_exists "$CWD_ADD/.cursor/commands/cmd/plan/create.md"
assert_not_symlink_path "$CWD_ADD/.cursor/skills/cmd"

scenario "17. add acme/both --ns both links skills and commands for Cursor and Claude"
run_cli_in "$CWD_ADD" add acme/both --ns both
assert_exit 0
assert_symlink "$CWD_ADD/.cursor/skills/both" "github.com/acme/both"
assert_symlink "$CWD_ADD/.claude/skills/both" "github.com/acme/both"
assert_symlink "$CWD_ADD/.cursor/commands/both" "github.com/acme/both"
assert_symlink "$CWD_ADD/.claude/commands/both" "github.com/acme/both"

scenario "18. add acme/empty --ns empty fails and does not write YAML"
run_cli_in "$CWD_ADD" add acme/empty --ns empty
assert_failed
assert_file_lacks "$CWD_ADD/skl.yaml" "namespace: empty"
assert_file_lacks "$CWD_ADD/skl.yaml" "acme/empty"

scenario "19. add SSH github.example.com stores under that host segment"
run_cli_in "$CWD_ADD" add git@github.example.com:acme/skills.git --ns ent
assert_exit 0
assert_dir_exists "$STORE/github.example.com/acme/skills"
assert_file_contains "$CWD_ADD/skl.yaml" "github.example.com"

scenario "20. duplicate namespace demo exits non-zero; YAML unchanged"
cp "$CWD_ADD/skl.yaml" "$HOME/cwd-add-yaml.before"
run_cli_in "$CWD_ADD" add acme/skills --ns demo
assert_failed
if cmp -s "$CWD_ADD/skl.yaml" "$HOME/cwd-add-yaml.before"; then
    pass "cwd-add YAML unchanged on duplicate ns"
else
    fail "cwd-add YAML changed on duplicate namespace"
fi

scenario "21. add acme/both --ns demo fails (namespace taken)"
run_cli_in "$CWD_ADD" add acme/both --ns demo
assert_failed
assert_output_contains "demo"

scenario "22. skl -g add links global agent dirs and writes global YAML"
run_cli_in "$CWD_ADD" -g add acme/skills --ns demo
assert_exit 0
assert_file_contains "$GLOBAL_YAML" "acme/skills"
assert_file_contains "$GLOBAL_YAML" "namespace: demo"
assert_symlink "$HOME/.cursor/skills/demo" "github.com/acme/skills"
assert_symlink "$HOME/.claude/commands/demo" "github.com/acme/skills"
if [ -e "$CWD_ADD/.cursor/skills/demo" ]; then
    pass "project skills/demo still present"
else
    fail "project skills/demo was removed by -g add"
fi

####################################################################################################
#
# 23–25: install (cwd-install is separate; 25 uses global YAML)
#
####################################################################################################

scenario "23. init --from clones and links; second install is idempotent"
run_cli_in "$CWD_INSTALL" init --from acme/skl-config:teams/platform.yaml
assert_exit 0
assert_symlink "$CWD_INSTALL/.cursor/skills/demo" "github.com/acme/skills"
assert_symlink "$CWD_INSTALL/.claude/commands/demo" "github.com/acme/skills"
assert_symlink "$CWD_INSTALL/.cursor/commands/cmd" "github.com/acme/cmds"
assert_symlink "$CWD_INSTALL/.claude/commands/cmd" "github.com/acme/cmds"
run_cli_in "$CWD_INSTALL" install
assert_exit 0
assert_symlink "$CWD_INSTALL/.cursor/skills/demo" "github.com/acme/skills"

scenario "24. skl i is install"
run_cli_in "$CWD_INSTALL" i
assert_exit 0

scenario "25. skl -g install installs from global YAML into global agent dirs"
run_cli_in "$CWD_INSTALL" -g install
assert_exit 0
assert_symlink "$HOME/.cursor/skills/demo" "github.com/acme/skills"
assert_symlink "$HOME/.claude/commands/demo" "github.com/acme/skills"

####################################################################################################
#
# 30–38: update / list / docs while cwd-add packages still exist
#
####################################################################################################

scenario "30. update with HEAD unchanged prints unchanged; links still valid"
run_cli_in "$CWD_ADD" update
assert_exit 0
assert_output_contains "unchanged"
assert_symlink "$CWD_ADD/.cursor/skills/demo" "github.com/acme/skills"

scenario "31. update demo after a new commit on the fixture remote"
OLD_SHA="$(cat "$STORE/github.com/acme/skills/.git/refs/heads/main")"
printf '\nextra line\n' >>"$REMOTE_SKILLS/README.md"
fixture_git "$REMOTE_SKILLS" add README.md
fixture_git "$REMOTE_SKILLS" commit --quiet -m "extra"
run_cli_in "$CWD_ADD" update demo
assert_exit 0
NEW_SHA="$(cat "$STORE/github.com/acme/skills/.git/refs/heads/main")"
if [ "$OLD_SHA" = "$NEW_SHA" ]; then
    fail "store HEAD did not move after update"
else
    pass "store HEAD moved $OLD_SHA -> $NEW_SHA"
fi
assert_output_contains "$OLD_SHA"
assert_output_contains "$NEW_SHA"
assert_symlink "$CWD_ADD/.cursor/skills/demo" "github.com/acme/skills"
assert_file_contains "$STORE/github.com/acme/skills/README.md" "extra line"

scenario "32. skl -g update updates packages in the global YAML"
run_cli_in "$CWD_ADD" -g update
assert_exit 0

scenario "33. list prints packages and ns:name items, including nested commands"
run_cli_in "$CWD_ADD" list
assert_exit 0
assert_output_contains "demo"
assert_output_contains "acme/skills"
assert_output_contains "demo:demo"
assert_output_contains "Says hello"
assert_output_contains "cmd:plan/create"
assert_output_contains "Create a plan"
assert_output_contains "A pack of demo skills"

scenario "34. skl -g list lists global packages, not the project file"
run_cli_in "$CWD_ADD" -g list
assert_exit 0
assert_output_contains "acme/skills"
assert_output_contains "demo"
assert_output_lacks "acme/both"
assert_output_lacks "both:"

scenario "35. docs demo -n prints details and does not invoke SKL_BROWSER"
: >"$BROWSER_LOG"
run_cli_in "$CWD_ADD" docs demo -n
assert_exit 0
assert_output_contains "acme/skills"
assert_output_contains "demo"
if [ -s "$BROWSER_LOG" ]; then
    fail "SKL_BROWSER was invoked; log is not empty"
else
    pass "SKL_BROWSER was not invoked"
fi

scenario "36. docs demo --open is unknown"
run_cli_in "$CWD_ADD" docs demo --open
assert_failed
assert_output_contains "unknown option"

scenario "37. docs -n with no package name exits non-zero"
run_cli_in "$CWD_ADD" docs -n
assert_failed
assert_output_contains "package"

scenario "38. docs demo -n prints the Pages guess and does not open a browser"
: >"$BROWSER_LOG"
run_cli_in "$CWD_ADD" docs demo -n
assert_exit 0
assert_output_contains "github.io"
if [ -s "$BROWSER_LOG" ]; then
    fail "SKL_BROWSER was invoked; log is not empty"
else
    pass "SKL_BROWSER was not invoked"
fi

####################################################################################################
#
# 26–29: remove (after update/list/docs)
#
####################################################################################################

scenario "26. remove demo unlinks, drops YAML, leaves the store clone"
run_cli_in "$CWD_ADD" remove demo
assert_exit 0
assert_not_exists "$CWD_ADD/.cursor/skills/demo"
assert_not_exists "$CWD_ADD/.claude/commands/demo"
assert_file_lacks "$CWD_ADD/skl.yaml" "namespace: demo"
assert_dir_exists "$STORE/github.com/acme/skills"

scenario "27. remove cmds matches remaining acme/cmds by repo name"
run_cli_in "$CWD_ADD" remove cmds
assert_exit 0
assert_not_exists "$CWD_ADD/.cursor/commands/cmd"
assert_file_lacks "$CWD_ADD/skl.yaml" "acme/cmds"

scenario "28. skl -g remove acme/skills unlinks global dirs; project links stay"
run_cli_in "$CWD_ADD" -g remove acme/skills
assert_exit 0
assert_not_exists "$HOME/.cursor/skills/demo"
assert_not_exists "$HOME/.claude/commands/demo"
assert_symlink "$CWD_ADD/.cursor/skills/both" "github.com/acme/both"

scenario "29. remove nosuch exits non-zero"
run_cli_in "$CWD_ADD" remove nosuch
assert_failed

####################################################################################################
#
# 39–44: safety / IO
#
####################################################################################################

scenario "39. stow: global yaml is a symlink; -g add writes through it"
DOTFILES="$HOME/dotfiles"
mkdir -p "$DOTFILES" "$HOME/.config/skilled"
write_empty_yaml "$DOTFILES/skl.yaml"
rm -f "$GLOBAL_YAML"
ln -s "$DOTFILES/skl.yaml" "$GLOBAL_YAML"
if [ ! -L "$GLOBAL_YAML" ]; then
    fail "failed to create stow symlink at $GLOBAL_YAML"
fi
run_cli_in "$CWD_STOW" -g add acme/cmds --ns cmd
assert_exit 0
if [ -L "$GLOBAL_YAML" ]; then
    pass "global yaml is still a symlink"
else
    fail "global yaml is no longer a symlink"
fi
assert_file_contains "$DOTFILES/skl.yaml" "acme/cmds"
assert_file_contains "$DOTFILES/skl.yaml" "namespace: cmd"

scenario "40. invalid project skl.yaml → list exits non-zero with a parse error"
printf 'packages: [\n' >"$CWD_BAD_YAML/skl.yaml"
run_cli_in "$CWD_BAD_YAML" list
assert_failed
assert_output_contains "skl.yaml"

scenario "41. add never creates \$HOME/.cursor/skills-cursor"
assert_not_exists "$HOME/.cursor/skills-cursor"

scenario "42. add still clones via insteadOf when \$HOME/.ssh is renamed away"
if [ -e "$HOME/.ssh" ] || [ -L "$HOME/.ssh" ]; then
    mv "$HOME/.ssh" "$HOME/.ssh.away"
fi
run_cli_in "$CWD_ADD" add acme/skills --ns demo
assert_exit 0
assert_dir_exists "$STORE/github.com/acme/skills"
assert_symlink "$CWD_ADD/.cursor/skills/demo" "github.com/acme/skills"
if [ -e "$HOME/.ssh.away" ] || [ -L "$HOME/.ssh.away" ]; then
    mv "$HOME/.ssh.away" "$HOME/.ssh"
fi

scenario "43. add of a filesystem path exits non-zero"
run_cli_in "$CWD_ADD" add /tmp/some-path --ns x
assert_failed

scenario "44. add of an HTTPS URL exits non-zero"
run_cli_in "$CWD_ADD" add https://github.com/acme/skills --ns x
assert_failed

####################################################################################################
#
# 45–46: add --from in dedicated cwds
#
####################################################################################################

scenario "45. init then add --from writes packages and does not clone"
run_cli_in "$CWD_ADD_FROM" init
assert_exit 0
run_cli_in "$CWD_ADD_FROM" add --from acme/skl-config:teams/platform.yaml
assert_exit 0
assert_file_contains "$CWD_ADD_FROM/skl.yaml" "acme/skills"
assert_file_contains "$CWD_ADD_FROM/skl.yaml" "acme/cmds"
assert_not_exists "$STORE/github.com/acme/skl-config"
assert_not_exists "$CWD_ADD_FROM/.cursor/skills/demo"

scenario "46. add --from keeps an existing extra package and appends demo and cmd"
printf 'packages:\n  - repo: acme/both\n    namespace: keep\n' >"$CWD_ADD_FROM_KEEP/skl.yaml"
run_cli_in "$CWD_ADD_FROM_KEEP" add --from acme/skl-config:teams/platform.yaml
assert_exit 0
assert_file_contains "$CWD_ADD_FROM_KEEP/skl.yaml" "namespace: keep"
assert_file_contains "$CWD_ADD_FROM_KEEP/skl.yaml" "acme/both"
assert_file_contains "$CWD_ADD_FROM_KEEP/skl.yaml" "namespace: demo"
assert_file_contains "$CWD_ADD_FROM_KEEP/skl.yaml" "namespace: cmd"

####################################################################################################
#
# 48–59: --branch and --local (cwd-source)
#
####################################################################################################

SKILLS_STORE="$STORE/github.com/acme/skills"

store_branch() {
    git -C "$SKILLS_STORE" rev-parse --abbrev-ref HEAD
}

scenario "48. add --branch dev clones that branch, writes YAML, and links the store"
run_cli_in "$CWD_SOURCE" init
assert_exit 0
run_cli_in "$CWD_SOURCE" add acme/skills --ns demo --branch dev
assert_exit 0
assert_file_contains "$CWD_SOURCE/skl.yaml" "acme/skills"
assert_file_contains "$CWD_SOURCE/skl.yaml" "branch: dev"
assert_file_lacks "$CWD_SOURCE/skl.yaml" "local:"
if [ "$(store_branch)" = "dev" ]; then
    pass "store HEAD is dev"
else
    fail "expected store HEAD to be dev, got $(store_branch)"
fi
assert_symlink "$CWD_SOURCE/.cursor/skills/demo" "github.com/acme/skills"
run_cli_in "$CWD_SOURCE" list
assert_exit 0
assert_output_contains "Hello from dev"

scenario "49. second install is idempotent and stays on dev"
run_cli_in "$CWD_SOURCE" install
assert_exit 0
if [ "$(store_branch)" = "dev" ]; then
    pass "store HEAD is still dev"
else
    fail "expected store HEAD to stay dev, got $(store_branch)"
fi
assert_file_contains "$CWD_SOURCE/skl.yaml" "branch: dev"

scenario "50. update demo --branch main switches the store and YAML"
run_cli_in "$CWD_SOURCE" update demo --branch main
assert_exit 0
assert_file_contains "$CWD_SOURCE/skl.yaml" "branch: main"
assert_file_lacks "$CWD_SOURCE/skl.yaml" "local:"
if [ "$(store_branch)" = "main" ]; then
    pass "store HEAD is main"
else
    fail "expected store HEAD to be main, got $(store_branch)"
fi
assert_symlink "$CWD_SOURCE/.cursor/skills/demo" "github.com/acme/skills"

scenario "51. update demo --local retargets links and writes absolute local"
run_cli_in "$CWD_SOURCE" update demo --local "$LOCAL_PKG"
assert_exit 0
assert_file_contains "$CWD_SOURCE/skl.yaml" "local:"
assert_file_contains_path "$CWD_SOURCE/skl.yaml" "$LOCAL_PKG"
assert_file_lacks "$CWD_SOURCE/skl.yaml" "branch:"
assert_symlink "$CWD_SOURCE/.cursor/skills/demo" "local-skills"
run_cli_in "$CWD_SOURCE" list
assert_exit 0
assert_output_contains "Local hello"

scenario "52. update demo --branch main after local relinks the store"
run_cli_in "$CWD_SOURCE" update demo --branch main
assert_exit 0
assert_file_contains "$CWD_SOURCE/skl.yaml" "branch: main"
assert_file_lacks "$CWD_SOURCE/skl.yaml" "local:"
assert_symlink "$CWD_SOURCE/.cursor/skills/demo" "github.com/acme/skills"

scenario "53. add --local for a new namespace writes absolute local"
run_cli_in "$CWD_SOURCE" add acme/skills --ns work --local "$LOCAL_PKG"
assert_exit 0
assert_file_contains "$CWD_SOURCE/skl.yaml" "namespace: work"
assert_file_contains_path "$CWD_SOURCE/skl.yaml" "$LOCAL_PKG"
assert_symlink "$CWD_SOURCE/.cursor/skills/work" "local-skills"

scenario "54. add --branch and --local together exits non-zero"
cp "$CWD_SOURCE/skl.yaml" "$HOME/cwd-source-yaml.before"
run_cli_in "$CWD_SOURCE" add acme/skills --ns extra --branch dev --local "$LOCAL_PKG"
assert_failed
if cmp -s "$CWD_SOURCE/skl.yaml" "$HOME/cwd-source-yaml.before"; then
    pass "cwd-source YAML unchanged when both flags are set"
else
    fail "cwd-source YAML changed when both flags are set"
fi

scenario "55. update --branch with no package query exits non-zero"
run_cli_in "$CWD_SOURCE" update --branch main
assert_failed
assert_output_contains "package"

scenario "56. add --from with --branch exits non-zero"
run_cli_in "$CWD_SOURCE" add --from acme/skl-config:teams/platform.yaml --branch dev
assert_failed
assert_output_contains "--branch"

scenario "57. add --branch nosuchbranch exits non-zero; YAML unchanged"
cp "$CWD_SOURCE/skl.yaml" "$HOME/cwd-source-yaml.before"
run_cli_in "$CWD_SOURCE" add acme/skills --ns extra --branch nosuchbranch
assert_failed
if cmp -s "$CWD_SOURCE/skl.yaml" "$HOME/cwd-source-yaml.before"; then
    pass "cwd-source YAML unchanged on missing branch"
else
    fail "cwd-source YAML changed on missing branch"
fi

scenario "58. update --local of a missing path exits non-zero; YAML unchanged"
cp "$CWD_SOURCE/skl.yaml" "$HOME/cwd-source-yaml.before"
run_cli_in "$CWD_SOURCE" update demo --local "$HOME/no-such-local-pkg"
assert_failed
if cmp -s "$CWD_SOURCE/skl.yaml" "$HOME/cwd-source-yaml.before"; then
    pass "cwd-source YAML unchanged on missing local path"
else
    fail "cwd-source YAML changed on missing local path"
fi

scenario "59. add of a filesystem path as the repo still exits non-zero"
run_cli_in "$CWD_SOURCE" add /tmp/some-path --ns x
assert_failed

echo ""
echo -e "${BLUE}Throwaway HOME left at $HOME${NC}"
echo -e "${GREEN}PASS: all smoke checks passed${NC}"
