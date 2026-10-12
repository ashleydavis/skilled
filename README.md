# skl

`skl` allows users to publish and share their Claude and Cursor skills and stay up to date.

- A package is a git repo with `skills/` and `commands/` directories. `skl add` clones it and links it into Cursor and Claude under a namespace you choose, for one project or for your whole machine (`-g`).
- Each package follows `main`, or a branch you name. `skl update` brings every package up to the latest commit on its branch.
- A team can keep its package list in one YAML file in a git repo, and everyone installs that list with `skl init --from`.
- A package can point at a local copy you are editing (`--local`), so changes show up immediately.
- Each project, and your machine, also gets a scratch directory for skills and commands that belong in no package.

## Install

You need the [GitHub CLI](https://cli.github.com/).

This downloads the latest `skl` release and puts the binary in `~/.local/bin`.

**Linux:**
```sh
gh release download --repo ashleydavis/skilled --pattern 'skl-linux-x64.tar.gz' --clobber && tar -xzf skl-linux-x64.tar.gz && chmod +x skl && mkdir -p ~/.local/bin && mv skl ~/.local/bin && rm skl-linux-x64.tar.gz
```

**macOS (Intel):**
```sh
gh release download --repo ashleydavis/skilled --pattern 'skl-macos-x64.tar.gz' --clobber && tar -xzf skl-macos-x64.tar.gz && chmod +x skl && xattr -c skl && mkdir -p ~/.local/bin && mv skl ~/.local/bin && rm skl-macos-x64.tar.gz
```

**macOS (Apple Silicon):**
```sh
gh release download --repo ashleydavis/skilled --pattern 'skl-macos-arm64.tar.gz' --clobber && tar -xzf skl-macos-arm64.tar.gz && chmod +x skl && xattr -c skl && mkdir -p ~/.local/bin && mv skl ~/.local/bin && rm skl-macos-arm64.tar.gz
```

**Windows:**
```powershell
gh release download --repo ashleydavis/skilled --pattern 'skl-windows-x64.zip' --clobber; Expand-Archive -Force skl-windows-x64.zip .; New-Item -ItemType Directory -Force "$HOME\.local\bin" | Out-Null; Move-Item -Force skl.exe "$HOME\.local\bin\"; Remove-Item skl-windows-x64.zip
```

**Verify installation:**
```sh
skl --version
```

## Quick start

You need SSH access to GitHub.

From scratch in a project:

```sh
skl init
skl add ashleydavis/skl-example-skills --ns demo
```

That creates `./skl.yaml`, clones the package, and links it into Cursor and Claude under namespace `demo`. 

Start Claude Code from that directory:

```sh
claude
```

Or if using the Claude Code plugin for VS Code:

```sh
code .
```

Or if using Cursor:

```sh
cursor .
```

Then run the demo command:

```sh
/demo:hello
```

Add `-g` / `--global` to `init` or `add` to work with your global config under `~/.cursor` and `~/.claude`.

### Scratch skills and commands

`skl init` also creates a scratch directory for skills and commands you do not want in a package:

```sh
code .skilled/scratch/commands/hello.md
```

Once saved, that command is `loc:hello` in Cursor and Claude without running anything else; run it with `/loc:hello`. Skills go under `.skilled/scratch/skills/<name>/SKILL.md`, and `skl list` prints what is there.

With `-g` the directory is `~/.skilled/scratch` and the links are global. `skl
install` and `skl update` put back a link that was deleted. The namespace `loc`
is reserved for it.

### A branch

A package can be cloned from a named branch:

```sh
skl add owner/repo --ns demo --branch feature
```

That clones `feature` and records `branch: feature` in `skl.yaml`. Switch a package already in `skl.yaml` to another branch with `update`:

```sh
skl update demo --branch main
```

### A local copy

Clone the package somewhere you will edit, then point `skl` at that directory:

```sh
git clone git@github.com:ashleydavis/skl-example-skills.git ~/src/skl-example-skills
skl add ashleydavis/skl-example-skills --ns demo --local ~/src/skl-example-skills
```

Agent links go to that path, so edits show up without `update`. The YAML `repo`
is still the remote identity. Switch a package already in `skl.yaml` the same way,
then back to a remote branch:

```sh
skl update demo --local ~/src/skl-example-skills
skl update demo --branch main
```

`skl install` has no package argument; it applies each row’s `branch` / `local`.

## Setup

### Machine global

#### Add a package

```sh
skl init -g
skl -g add ashleydavis/skl-example-skills --ns demo
```

#### Bootstrap configuration from a YAML file

```sh
skl init -g --from https://github.com/ashleydavis/skl-example-config/blob/main/my-team/skl.yaml
```

After a bare `skl init -g`, add that file’s packages into the existing YAML:

```sh
skl init -g
skl -g add --from https://github.com/ashleydavis/skl-example-config/blob/main/my-team/skl.yaml
skl -g install
```

### Project local

#### Add a package

```sh
skl init
skl add ashleydavis/skl-example-skills --ns demo
```

#### Bootstrap configuration from a YAML file

```sh
skl init --from https://github.com/ashleydavis/skl-example-config/blob/main/my-team/skl.yaml
```

After a bare `skl init`, add that file’s packages into the existing YAML:

```sh
skl init
skl add --from https://github.com/ashleydavis/skl-example-config/blob/main/my-team/skl.yaml
skl install
```

## References

- [How it works](docs/HOW_IT_WORKS.md)
- [Command reference](docs/COMMANDS.md)
- [Development](docs/DEVELOPMENT.md)
- [Making a release](docs/RELEASING.md)
