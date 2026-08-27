# How `skl` works

## Layers

1. **Store** — clones live under `~/.skilled/store/<host>/<owner>/<repo>/`.
   That path is on purpose: v1 does not honour `XDG_DATA_HOME`. Hostnames such
   as `github.com` are ordinary directory names.
2. **YAML** — user intent (`skl.yaml` in the active scope).
3. **Symlinks** — each package namespace under Cursor and Claude skill/command
   dirs.

`skl` never writes under `~/.cursor/skills-cursor/` (Cursor-managed). If there
is no `skl.yaml` in the active scope, commands other than `init` tell you to
run `skl init`.

Logical ids use a colon (`ns:name`). On disk the namespace is a directory
(`ns/name`) because Windows forbids `:` in filenames.

## Package layout

- **Skills (one level):** each immediate subdirectory of `skills/` that contains
  `SKILL.md` is a skill.
- **Commands (recursive):** each `*.md` file under `commands/` is a command.
  The name is the path relative to `commands/` with `.md` stripped, using `/`
  (`commands/plan/create.md` → `plan/create`).

A package is valid when at least one of `skills/` or `commands/` exists as a
directory. An empty tree is still linked. Cursor links both trees under
`skills/<ns>` (that is where Cursor loads user workflows). Claude keeps
`skills/<ns>` and `commands/<ns>`. A package with `skills/` and no `commands/`
is Cursor `skills/<ns>` and Claude `commands/<ns>`, both pointing at the store
`skills/` tree. When both trees exist, Cursor `skills/<ns>` points at store
`skills/` so the two trees do not share one namespace path; Claude still gets
both.

Description for a package is the first paragraph of `README.md` / `readme.md`.
Description for a skill or command is YAML frontmatter `description` when it is
a single-line scalar, otherwise the first paragraph of the body.

## Config files

**Project:** `./skl.yaml`, with links under `./.cursor` and `./.claude`.

**Global:** `~/.config/skilled/skl.yaml`, or `$XDG_CONFIG_HOME/skilled/skl.yaml`
when `XDG_CONFIG_HOME` is set. Links under `~/.cursor` and `~/.claude`. For
namespace `ns`, Cursor uses `skills/ns`; Claude uses `skills/ns` and
`commands/ns`.

```yaml
packages:
  - repo: acme/skills
    namespace: demo
  - repo: git@github.example.com:acme/cmds.git
    namespace: cmd
```

`repo` is `owner/repo` (cloned as `git@github.com:owner/repo.git`) or a full SSH
URL.

Namespaces are unique per config file.

`skl init --from` creates `skl.yaml` from a YAML file in a git repo when the
config is missing or still `packages: []`, then clones and links the packages
that file lists. `skl add --from` appends that file’s packages into an existing
`skl.yaml` and keeps entries already there; run `skl install` after `add --from`.

Writes to `skl.yaml` are stow-safe: if the path is a symlink to a regular file,
`skl` opens that file and writes through it. If the path does not exist, `skl`
creates the parent directory and the file. Anything other than a regular file
(or a symlink to one) is an error.

## Git and SSH

Remotes are SSH:

- `owner/repo` → `git@github.com:owner/repo.git`
- `git@host:owner/repo.git` or `git@host:owner/repo` → used as-is

Host, owner, repo, and namespace must be non-empty, not `.` or `..`, and match
`[A-Za-z0-9._-]+` per segment (no `/`, `\`, `:`, or Windows-illegal `<>"|?*`).

## Windows

Creating agent symlinks on Windows requires Developer Mode (or an equivalent
privilege). If symlink creation fails, `skl` prints that and exits.
