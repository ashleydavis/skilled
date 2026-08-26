# 8. Package layout discovery and frontmatter

## Goal

Scan a cloned package for skills and commands, and extract a description from YAML frontmatter or the first body paragraph. Vendored `yaml.zig` does not parse markdown or multi-line scalars, so frontmatter is a separate step.

## Files

- `src/lib/frontmatter.zig` + `src/lib/frontmatter.test.zig`
- `src/lib/package.zig` + `src/lib/package.test.zig`
- Re-export from `src/lib/lib.zig`. Wire `test { _ = @import("….test.zig"); }` in each code file.

## Frontmatter

If a file starts with `---\n`, take bytes until the next `\n---\n` (or `\n---\r\n`); parse that inner mapping with `yaml.zig`; read `description` only when it is a plain or quoted **single-line** scalar.

If the fence is missing, the YAML fails, or `description` is absent, fall back to the first paragraph of the body (text up to the first blank line). Multi-line YAML scalars in frontmatter are unsupported in v1 and fall back to the body.

## Package scan

After a clone, a valid package has a top-level `skills/` directory and/or a top-level `commands/` directory. **Error only when both are missing as directories.** An empty `skills/` (no `SKILL.md`) is still a skills tree: link it, `scan` may return no skill items. Same for an empty `commands/`.

Treat the two trees as the same kind of artifact, with different fan-out:

- **Skills (one level):** each **immediate** subdirectory of `skills/` that contains `SKILL.md` is a skill. Nested `skills/a/b/SKILL.md` is ignored.
- **Commands (recursive):** each `*.md` file under `commands/` is a command. `name` is the path relative to `commands/` with `.md` stripped, using `/` (`commands/plan/create.md` → `plan/create`, not `create`).

Package description: first sentence/paragraph of repo `README.md` / `readme.md` (fallback: none; GitHub is not queried). Skill/command description: frontmatter `description` else first paragraph of the body.

```zig
pub const Item = struct { kind: enum { skill, command }, rel_path: []u8, name: []u8, description: []u8 };
```

`scan(io, allocator, pkg_root) []Item`.

## Tests

Temp fixtures in the test file (not in the code file):

- Skills-only, commands-only, both.
- Both-trees-missing (error).
- Empty `skills/` present (valid, zero skill items).
- Nested `commands/plan/create.md` named `plan/create`.
- Ignored nested `SKILL.md`.
- Missing README.
- Single-line frontmatter description.
- Missing frontmatter falls back to body.
- Multi-line scalar in frontmatter falls back to body.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Added `src/lib/frontmatter.zig` and `src/lib/package.zig` (with co-located tests) and re-exported both from `lib.zig`.

- `frontmatter.extract` splits a leading `---` fence (`\n` or `\r\n`), parses the inner mapping with vendored `yaml.zig`, and uses `description` only when it is a non-empty single-line string. Missing fence, unclosed fence, YAML failure, multi-line scalars (`|` / `>`), missing key, and non-string values all fall back to the first body paragraph.
- `package.scan` errors only when both `skills/` and `commands/` are missing as directories. Skills are one-level `skills/<name>/SKILL.md`; nested `SKILL.md` is ignored. Commands are every `*.md` under `commands/`, with `name` as the `/`-separated path minus `.md` (`plan/create`). Empty trees are valid and contribute no items.
- `package.readmeDescription` (pub for tests and later list/docs) reads `README.md` then `readme.md` through the same extract path; missing file is null, not an error. Scan itself does not require a README.
- `scan` takes `fail: *Failure` like `config.parse`, rather than the abbreviated plan signature.
- Not wired into `main` yet (CLI is step 11). Smoke tests are step 13; not run. `zig build` and `zig build test` pass; the test count moved when the two `*.test.zig` files were added.
