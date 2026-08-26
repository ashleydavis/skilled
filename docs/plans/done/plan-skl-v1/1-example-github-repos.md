# 1. Example GitHub repos

## Goal

Publish the public example GitHub repos that Getting Started in `README.md` uses. They are separate repos, not trees inside this checkout.

## Repos

Create them under `ashleydavis` with `gh` (public). If a repo already exists, update its default branch to match this layout rather than inventing a second name.

**`ashleydavis/skl-example-skills`** — a valid v1 package (at least one of `skills/` or `commands/` as a directory):

- `README.md` — one short paragraph (this is the package description `skl list` shows).
- `skills/hello/SKILL.md` — one-level skill with a single-line YAML frontmatter `description`.

No company, department, or team names in the files. Commit on `main` and push so `skl add ashleydavis/skl-example-skills --ns demo` can clone over SSH.

**`ashleydavis/skl-example-config`** — a config repo (no `skills/` or `commands/` required):

- `my-team/skl.yaml`:

```yaml
packages:
  - repo: ashleydavis/skl-example-skills
    namespace: demo
```

Commit on `main` and push so
`skl init --from https://github.com/ashleydavis/skl-example-config/blob/main/my-team/skl.yaml`
can `git show` that path.

Fixture remotes in smoke tests (step 13) stay generic `acme/…` under a throwaway `HOME`.

## Verify

- `gh repo view ashleydavis/skl-example-skills` and `gh repo view ashleydavis/skl-example-config` succeed (public).
- Default branch has the files listed above.
- This checkout still has no copy of those trees.

Do not require `zig build`.

## Summary

Published two public GitHub repos under `ashleydavis` (not trees in this checkout). Commits use `Ashley Davis <ashley@codecapers.com.au>` via `GIT_AUTHOR_*` / `GIT_COMMITTER_*` env vars (git config was not changed). A first `skl-example-skills` commit used a global git identity; that repo was deleted and recreated.

- [`ashleydavis/skl-example-skills`](https://github.com/ashleydavis/skl-example-skills) — `README.md` (first paragraph is the package description; rest is install + layout) and `skills/hello/SKILL.md` with a single-line `description` frontmatter. Default branch `main`.
- [`ashleydavis/skl-example-config`](https://github.com/ashleydavis/skl-example-config) — `README.md` for `init --from` and `add --from`, plus `my-team/skl.yaml` listing `ashleydavis/skl-example-skills` under namespace `demo`. Default branch `main`.

README Getting Started already pointed at these URLs; no checkout files were added. `zig build` was not run (not required for this step; no Zig sources yet). Local commit messages also carry a Cursor `Co-authored-by` trailer from the commit hook.
