# Writing a package

A package is a git repo that `skl` clones and links into Cursor and Claude. Anyone with SSH access to the repo can install it.

## Layout

```
README.md
skills/
  review/SKILL.md
commands/
  hello.md
  plan/create.md
```

- `skills/`: each immediate subdirectory that contains a `SKILL.md` is a skill, named after the subdirectory (`review`). A `SKILL.md` nested deeper (`skills/a/b/SKILL.md`) is ignored.
- `commands/`: every `*.md` file under it, at any depth, is a command. Its name is the path below `commands/` without `.md` (`commands/plan/create.md` is `plan/create`).
- A package needs `skills/`, `commands/`, or both, at the top of the repo. An empty directory is fine.

## Names

The person installing the package picks its namespace with `--ns`. With `--ns acme`, the items above appear as `acme:review`, `acme:hello` and `acme:plan/create`, and a command runs as `/acme:hello`. The namespace `loc` is reserved for the scratch directory, so it cannot be used.

## Descriptions

`skl list` and `skl docs` show a description for the package and for each item.

- Package: the first paragraph of `README.md` (or `readme.md`).
- Skill or command: the `description` field in the file's YAML frontmatter when it is a single line, otherwise the first paragraph of the body.

```markdown
---
description: Say hello to the user.
---

Greet the user by name.
```

## Trying it out while you write it

Link your working copy instead of a clone, so every save shows up in Cursor and Claude without running anything:

```sh
skl init
skl add acme/skills --ns acme --local ~/src/skills
skl list
```

`skl list` prints every skill and command `skl` found, so a file that does not show up there is in the wrong place. When you are done, switch back to the published copy with `skl update acme --branch main`.

## Publishing

Push the repo to GitHub. Users install it with:

```sh
skl add acme/skills --ns acme
```

That follows `main`, and `skl update` brings them up to its latest commit. To publish work in progress without touching `main`, push a branch and have testers add it with `--branch <name>`.

A repo on another host is installed by its SSH URL (`skl add git@host:owner/repo.git --ns acme`).

## Docs page

`skl docs <namespace>` opens `https://<owner>.github.io/<repo>/`, so a GitHub Pages site for the repo is where users land when they ask for the package's docs.

## Sharing a package list

To hand a team a set of packages, commit a `skl.yaml` to any repo:

```yaml
packages:
  - repo: acme/skills
    namespace: acme
```

Team members install it with `skl init --from acme/config:skl.yaml`, or add it to an existing setup with `skl add --from acme/config:skl.yaml` followed by `skl install`. [Command reference](COMMANDS.md) lists every form `--from` accepts.
