# 10. Linker

## Goal

Symlink each package's `skills/` and `commands/` trees into Cursor and Claude agent directories under a per-package namespace. Never copy files; never touch `skills-cursor`.

## Files

- `src/lib/link.zig` + `src/lib/link.test.zig`
- Re-export from `src/lib/lib.zig`. Wire `test { _ = @import("link.test.zig"); }`.

## Behaviour

Namespace is already validated in step 6, so `skills/ns` cannot contain `..`. For a package with namespace `ns` and store path `store_dir`:

- If `store_dir/skills` exists as a directory, ensure agent `skills/` is a **real directory**, then create `skills/ns` → `store_dir/skills` (one symlink per package, not per skill). Same for `commands/ns` → `store_dir/commands`.
- Do this for both Cursor and Claude roots in the active scope (global or project).
- Logical id `ns:name` is **not** a filename; on disk the namespace is a directory (`ns/name`). That is the portable colon normalisation (Windows forbids `:` in names).
- `linkPackage` is idempotent: if the symlink already points at the correct dest, leave it; if it points elsewhere or is a real file, error (do not `--adopt`).
- `unlinkPackage` removes only `skills/ns` and `commands/ns` if they are symlinks owned by this scheme (symlink to the store). Do not delete store clones on remove (other scopes may still use them). Do not touch `skills-cursor`.
- Creating parent `.cursor` / `.claude` as real directories (never a single symlink to the store) — same tree-folding hazard GNU stow has.

On Windows, if symlink creation fails, surface an error telling the user to enable Developer Mode; do not silently copy.

Pass `io: std.Io` on every filesystem call.

## Tests

Temp dirs:

- Create links, idempotent second link, unlink.
- Refuse clobbering a real file.
- Project vs global roots.
- Both agents; skills + commands.
- Windows Developer Mode error **text** mentions Developer Mode (fake the syscall failure).

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

Added `src/lib/link.zig` (with co-located tests) and re-exported it from `lib.zig`.

- `linkPackage` validates the namespace, then for each of Cursor/Claude skills and commands: if `store_dir/<tree>` is a directory, ensure `.cursor`/`.claude` and the agent tree are **real directories** (a symlink parent is refused — stow tree-folding), then create `<tree>/<ns>` → `store_dir/<tree>`. Idempotent when the symlink already names that dest; a real file or a symlink to somewhere else is an error (no `--adopt`, no copy). Skills-only packages get no commands links, and vice versa. `skills-cursor` is never a path this module writes.
- `unlinkPackage` deletes `<tree>/<ns>` only when it is a symlink to this package's store tree. Missing links, real files, and foreign symlinks are left alone. The store clone is not deleted.
- `mapSymlinkError` is pub so tests can fake a syscall failure: AccessDenied/PermissionDenied mention Developer Mode; the create path never falls back to copying.
- Tests use a unique `TemporaryDir` per case (parallel-safe). Coverage: both agents + both trees, idempotent relink, unlink leaves the store, project vs global, clobber file / wrong symlink, folded `.cursor`, invalid namespace, Developer Mode error text.
- Parallel-test rule added to `CLAUDE.md` / `AGENTS.md` (kept in lockstep): unit and smoke tests must be safe overlapping with themselves. Existing disk tests already used `TemporaryDir`; added a two-thread `TemporaryDir` test. Smoke tests are still step 13.
- Not wired into `main` yet (CLI is step 11). `zig build` and `zig build test` pass; the test count moved when `link.test.zig` was added.
