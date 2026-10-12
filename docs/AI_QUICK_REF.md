# skl quick reference for AI agents

`skl` installs git repos of skills and commands into Cursor and Claude.

## Packages

- A git repo with `skills/`, `commands/`, or both, at the top.
- Skill: `skills/<name>/SKILL.md` (one level deep only).
- Command: any `commands/**/*.md`; name is the path without `.md` (`plan/create`).
- Description: single-line frontmatter `description`, else first paragraph. Package description: first paragraph of `README.md`.
- Installed items are `ns:name`; commands run as `/ns:name`.

## Commands

Project scope by default; `-g` for global. Pass `-n` so `skl` never prompts.

- `skl init`: create `skl.yaml`. `--from owner/repo:path/skl.yaml` also installs that list.
- `skl add owner/repo --ns <ns>`: clone and link. `--branch <b>` or `--local <path>`.
- `skl add --from <spec>`, then `skl install`: append a shared list.
- `skl install`: clone and link everything in `skl.yaml`.
- `skl update [query]`: fast-forward clones. `--branch` / `--local` switch one package.
- `skl remove <query>`: unlink and drop from `skl.yaml`.
- `skl list`: every package and item.
- `skl docs [query]`: package details and its GitHub Pages URL.

## Files

- Config: `./skl.yaml`, or `~/.config/skilled/skl.yaml` with `-g`.
- Clones: `~/.skilled/store/<host>/<owner>/<repo>@<branch>/`.
- Links: `.cursor/{skills,commands}/<ns>` and `.claude/{skills,commands}/<ns>`.
- Scratch: `.skilled/scratch/{skills,commands}/`, linked as `loc`. No command needed after saving a file. `loc` is reserved.

## Writing a package

Link a working copy with `skl add owner/repo --ns <ns> --local <path>`; edits show up at once. Check `skl list` to see what was picked up. Full guide: [Writing a package](PACKAGE_AUTHORS.md).
