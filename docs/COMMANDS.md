# Command reference

## Commands

| Command | What it does |
|---------|----------------|
| `skl help` | Same as `--help` / `-h`. |
| `skl version` | Same as `--version` / `-V`. |
| `skl init` | Create `skl.yaml` with `packages: []`. `--from` also installs those packages. |
| `skl install` / `skl i` | Clone/update every package in the active YAML and link them. |
| `skl add <repo>` | Clone, scan, append YAML, and link. Requires `--ns`. |
| `skl add --from <spec>` | Append packages from a YAML file in git into the existing `skl.yaml`. |
| `skl remove <query>` | Unlink the namespace and drop that YAML entry. Leaves the store clone. |
| `skl update [repo]` | Fast-forward store clones and repair missing links. |
| `skl list` | Print packages and each skill/command as `ns:name`. |
| `skl docs [package]` | Print package details and open the GitHub Pages guess. |

Scope is project by default. `-g` / `--global` selects the global YAML and the
global Cursor/Claude roots (`~/.cursor/skills`, `~/.claude/skills`,
`~/.claude/commands`). Cursor command files are linked under `~/.cursor/skills`.
Project roots are the same paths under the current working directory.

`add <repo>` requires `--ns <namespace>`. In a TTY it can prompt; with
`--non-interactive` / `-n` (or `SKL_NONINTERACTIVE=1`, or a non-TTY stdin) it
errors if `--ns` is omitted. Clone and scan run before the YAML is updated.
`add --from` does not take `<repo>` or `--ns`; namespaces come from the file.

`install` is idempotent. If package *k* of *N* fails, packages `1..k-1` stay
cloned and linked; the next `install` continues the rest.

`remove` matches a query against the YAML `repo` string, the canonical SSH URL,
`owner/repo`, the repo name, then the namespace. Ambiguous matches error; pass a
unique `owner/repo` or the namespace.

`update` fast-forwards only (`git merge --ff-only`). Dirty, detached, diverged,
or missing-upstream store trees are an error.

Interactive `docs` opens the GitHub Pages guess in a browser (see `SKL_BROWSER`).
Non-interactive `docs` prints that URL and does not open a browser. Non-interactive
`docs` without a package name errors.

Bare `skl` prints help and exits 0.

If there is no `skl.yaml` in the active scope, commands other than `init` exit
with `no skl.yaml; run skl init`.

## `--from`

`--from <spec>` locates a YAML file inside a git repo. `skl` clones that repo
into a temporary directory, reads one file with `git show`, and deletes the temp
clone.

`skl init --from <spec>` creates `skl.yaml` from that file when the config is
missing or still `packages: []`, then clones and links the packages it lists. If
the file already lists packages, `init --from` errors; use `skl add --from`
instead.

`skl add --from <spec>` requires an existing `skl.yaml`. It appends packages
from the file and keeps entries already there. An incoming namespace that is
already used by a different repo is an error (YAML unchanged). The same
namespace and same package is skipped. `<repo>` and `--from` are mutually
exclusive; `--ns` is not used with `--from`. Run `skl install` after `add
--from` to clone and link.

First matching split rule wins:

1. Spec starts with `https://` — GitHub UI URL; the clone is still SSH.
   `https://github.com/ashleydavis/skl-example-config/blob/main/my-team/skl.yaml` → host
   `github.com`, owner `ashleydavis`, repo `skl-example-config`, ref `main`, path
   `my-team/skl.yaml`. `https://github.com/ashleydavis/skl-example-config/my-team/skl.yaml`
   (no `/blob/`) → ref defaults to `HEAD`.
2. Spec starts with `git@` — SSH. The first `:` separates `git@host` from
   `owner/repo`. A second `:` (after optional `.git`) starts the file path.
   Example: `git@github.com:ashleydavis/skl-example-config.git:my-team/skl.yaml`. No second
   colon is an error (path required).
3. Otherwise shorthand: split on the **first** `:`. Left is `owner/repo`, right
   is the path (`ashleydavis/skl-example-config:my-team/skl.yaml`). A spec with no colon is
   an error.

After the temp clone (default branch, SSH), the file is read with
`git show <ref>:<path>` (`HEAD` when the spec had no ref). If that ref or
path is missing, `skl` errors. The temp clone is deleted even on error.

Plain `init` (no `--from`) refuses to wipe a `skl.yaml` that already lists
packages.

## Flags and environment

| Flag / env | Effect |
|------------|--------|
| `-g`, `--global` | Use the global config and global agent roots. |
| `--ns <namespace>` | Namespace for `add <repo>` (required). Not used with `add --from`. |
| `-n`, `--non-interactive` | Never prompt. Also set by `SKL_NONINTERACTIVE=1` or non-TTY stdin. |
| `--no-color` | Disable color and icons. Also disabled when `NO_COLOR` is set (any value), `SKL_NO_COLOR=1`, or stdout is not a TTY. |
| `--from <spec>` | `init` and `add`: fetch a YAML file from a git repo (rules above). |
| `-V`, `--version` | Print version. Same as `skl version`. |
| `-h`, `--help` | Print help. Same as `skl help`. |
| `XDG_CONFIG_HOME` | Directory that contains `skilled/skl.yaml`. |
| `SKL_BROWSER` | Optional. If set to a non-empty path, interactive `docs` spawns `{ SKL_BROWSER, url }` instead of `xdg-open` (Linux), `open` (macOS), or `cmd.exe /C start` (Windows). |

`--global`, `--no-color`, and `--non-interactive` work before or after the
subcommand (`skl -g add` and `skl add -g`).
