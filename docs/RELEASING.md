# Making a release

Push a version tag from an up-to-date `main`:

```sh
git tag -a vX.Y.Z -m "skl vX.Y.Z"
git push origin vX.Y.Z
```

Use the next version after the highest existing tag (`git tag --list 'v*' --sort=-v:refname | head -1`).

The tag push starts the Release workflow, which builds every platform's binary, runs the smoke tests on each, and publishes the GitHub Release. Follow it on the repo's Actions page or with `gh run watch`.

If the workflow fails, fix the problem on `main` and release the next version. A pushed tag is never moved.

The `/release` slash command in Claude Code or Cursor does all of this for you.
