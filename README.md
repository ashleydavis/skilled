# skl

`skl` installs Cursor and Claude skill packages from git.

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

## Setup

### Machine global

#### Add a package

```sh
skl init -g
skl -g add ashleydavis/skl-example-skills --ns demo
```

#### From a YAML file

```sh
skl init -g --from https://github.com/ashleydavis/skl-example-config/blob/main/my-team/skl.yaml
skl -g install
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

#### From a YAML file

```sh
skl init --from https://github.com/ashleydavis/skl-example-config/blob/main/my-team/skl.yaml
skl install
```

After a bare `skl init`, add that file’s packages into the existing YAML:

```sh
skl init
skl add --from https://github.com/ashleydavis/skl-example-config/blob/main/my-team/skl.yaml
skl install
```

See [How it works](docs/HOW_IT_WORKS.md) and [Command reference](docs/COMMANDS.md).

## Development

Build from source with Zig 0.16:

```sh
zig build
```

The release step writes `bin/<arch>/<os>/skl` (`.exe` on Windows).

```sh
zig build
zig build test
./scripts/smoke-tests.sh
./scripts/smoke-tests.sh --binary
./scripts/test-everything.sh
```

`zig build release` is required before `--binary` so the smoke suite can find
`bin/<arch>/<os>/skl`.
