# 12. `init --from` and `add --from`

## Goal

`--from <spec>` locates a YAML file inside a git repo, clones that repo into a **temporary directory** (not the package store), reads one file, and deletes the temp clone.

- `skl init --from <spec>` **creates** `skl.yaml` from that file when the config is missing or still `packages: []`.
- `skl add --from <spec>` **appends** that file’s packages into an existing `skl.yaml` and keeps entries already there.

Neither form replaces a YAML that already lists packages.

## Shared behaviour

- Do not `scan` the config repo.
- Do not require `skills/` or `commands/`.
- Do not link.
- Do not clone the skill packages listed in the file; the user runs `skl install`.
- After the temp clone (default branch, SSH), read the file with `git show -- <ref>:<path>` (`HEAD` when the spec had no ref). If that ref or path is missing, error; do not silently substitute the default-branch file.
- The temp clone is deleted even on error.
- Clone URL is still SSH. HTTPS in the spec is only a GitHub UI locator.
- Owner/repo/host/path segments still go through step 6 validation before any clone or `git show`.

## `init --from`

- If `skl.yaml` is missing, create it with the fetched packages (stow-safe write).
- If it exists and is empty / `packages: []`, write the fetched packages (still initializing).
- If it already lists packages, **error** and tell the user to run `skl add --from`. Do not write.
- Plain `init` (no `--from`) still refuses to wipe a file that already lists packages.

## `add --from`

- Requires an existing `skl.yaml` (same missing-config error as other commands: `no skl.yaml; run skl init`).
- `<repo>` and `--from` are mutually exclusive. `--ns` is not used; namespaces come from the file. `add --from` with `--ns` or with a repo argument errors.
- Parse the existing file and the fetched file. Keep existing packages in order. Append each incoming package whose namespace is not already present.
- Incoming namespace already used by the **same** package (exact `repo` string, or the same package after canonical SSH / `owner/repo` comparison): skip.
- Incoming namespace already used by a **different** repo: error, YAML unchanged.
- Stow-safe write after a successful merge. Second `add --from` of the same spec is idempotent.

Declare `add`’s positional as optional `[repo]`. The command validates: `add <repo> --ns` **or** `add --from <spec>`, never both, never neither.

## Split rules (first match wins)

1. Spec starts with `https://` — GitHub UI URL only; the clone is still SSH. `https://github.com/owner/repo/blob/<ref>/path` → host `github.com`, owner, repo, ref, path. `https://github.com/owner/repo/path` (no `/blob/`) → ref defaults to `HEAD`, path is the rest after `owner/repo/`. Reject non-github.com HTTPS hosts in v1.
2. Spec starts with `git@` — SSH. The first `:` separates `git@host` from `owner/repo`. A **second** `:` (after optional `.git`) starts the file path. Example: `git@github.com:acme/skl-config.git:teams/platform.yaml` → host `github.com`, repo `acme/skl-config`, path `teams/platform.yaml`. No second colon → error (path required).
3. Otherwise shorthand: split on the **first** `:`. Left is `owner/repo`, right is path. `owner/repo:path/to/file.yaml`. A spec with no colon, or with `owner/repo` only, is an error.

## Files

Extend `src/cmd/init.zig` + `src/cmd/init.test.zig` and `src/cmd/add.zig` + `src/cmd/add.test.zig` (and a spec-parser helper if it keeps those files small — still a real module with comments and tests, not an empty scaffold). Spec parsing may live in `src/lib/` if tests need it without the full command.

## Tests

- Spec parsing: shorthand, SSH with two colons, blob URL with ref, HTTPS without blob.
- `git show --` argv.
- Missing file at ref/path.
- Bad spec.
- `init --from` creates a missing file; fills `packages: []`; errors when packages are already listed (YAML unchanged).
- `add --from` after `init` appends packages; keeps an existing extra package; skips the same namespace+package; errors on namespace taken by a different repo (YAML unchanged); errors when `skl.yaml` is missing; errors when combined with `<repo>` or `--ns`.
- Temp clone is not left in the package store.

Use a fake git runner. No network.

The code must compile and all tests (unit and smoke/e2e) must pass before marking this step complete.

## Summary

`--from` now fetches a YAML file from git without using the package store.

- Added `src/lib/from.zig` (+ `from.test.zig`): spec parse (shorthand, SSH two-colon, GitHub blob / no-blob HTTPS), throwaway clone + `git show -- <ref>:<path>`, delete-even-on-error, and `mergePackages` (keep extras, skip same ns+package including SSH vs shorthand, error on ns taken by a different repo).
- Temp clones land under `TMPDIR`/`TMP`/`TEMP` (else `/tmp`) as `skl-from-<random>/<repo>`, never `~/.skilled/store`. Scenario tests set `TMPDIR` to their `TemporaryDir`.
- `init --from` writes a missing or empty `skl.yaml`; a file that already lists packages errors with `use skl add --from` and does not clone.
- `add --from` requires an existing config, is exclusive with `<repo>` and `--ns`, merges, does not link or clone skill packages.
- `FakeGit` scripts `git show` YAML (and missing-file failures). The Commander `init --from` path writes YAML instead of refusing.

Nothing deferred except smoke coverage, which is step 13.
