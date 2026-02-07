# ww

A small CLI tool to make `jj` (Jujutsu) workspaces easier to manage.
It helps with `jj workspace add` and provides a zsh function for moving between workspaces.

## Prerequisites

- `jj` (Jujutsu) installed: https://github.com/jj-vcs/jj

## Install (Homebrew)

Install via a Homebrew tap:

```sh
brew tap omihirofumi/tap
brew install ww
```

## Usage

```sh
ww new [options] <name>
ww go [options] <name>
ww list
ww default
ww init zsh
ww completion zsh
ww help [command]
```

### Commands

- `new [options] <name>`
  - Runs `jj workspace add` to create a workspace.
  - Options:
    - `-r, --revision <revision>`: revision to use when creating.
- `go [options] <name>`
  - Prints a `cd ...` command for the workspace path.
  - Options:
    - `-c, --create`: create workspace if missing.
    - `-r, --revision <revision>`: revision to use when creating.
- `list`
  - Shows workspace names from `jj workspace list`.
- `default`
  - Prints a `cd ...` command for the default workspace.
- `init zsh`
  - Prints a zsh function that interprets `ww` output.
- `completion zsh`
  - Prints a zsh completion script.
- `help [command]`
  - Shows help for `ww` or a specific command.

## zsh Integration

To make `ww go` actually change directories, add the function to your shell:

```sh
eval "$(ww init zsh)"
```

After that, `ww go <name>` will move your current directory.

## Completion

`ww completion` is available (zsh only for now).

## Workspace Location

`ww` supports two workspace location strategies:

| Strategy | Path Pattern | Description |
|----------|--------------|-------------|
| `sibling` (default) | `<repo>__<name>` | Workspace created as sibling directory |
| `internal` | `<repo>/.workspaces/<name>` | Workspace created inside repo |

## Configuration

Configuration is loaded from two locations (per-repo overrides global):

1. **Global**: `~/.config/ww/config.toml`
2. **Per-repo**: `<repo>/.jj/ww.toml`

### Config Format

```toml
# Choose workspace location strategy
workspace_location = sibling  # or "internal"
```

### Examples

**Global config** (`~/.config/ww/config.toml`):
```toml
# Default to internal workspaces for all repos
workspace_location = internal
```

**Per-repo override** (`<repo>/.jj/ww.toml`):
```toml
# This specific repo uses sibling workspaces
workspace_location = sibling
```

## Hooks

`ww` supports optional hooks that run after workspace operations.

| Hook | Location | Trigger |
|------|----------|---------|
| `post-workspace-add` | `<repo>/.jj/hooks/post-workspace-add` | After `ww new` or `ww go -c` |
| `post-workspace-forget` | `<repo>/.jj/hooks/post-workspace-forget` | After `ww forget` |

### Hook Environment

All hooks run with:

- **Working directory**: Repository root
- **Environment variables**:
  - `WW_WORKSPACE_NAME`: Name of the workspace
  - `WW_WORKSPACE_PATH`: Path to the workspace

If a hook fails (non-zero exit), a warning is printed but the command still succeeds.

### Example: post-workspace-add

```sh
#!/bin/sh
# .jj/hooks/post-workspace-add
# Copy local config files to new workspace

# Copy .env file if it exists
if [ -f ".env" ]; then
    cp .env "$WW_WORKSPACE_PATH/"
fi

# Copy local settings
if [ -f ".vscode/settings.local.json" ]; then
    mkdir -p "$WW_WORKSPACE_PATH/.vscode"
    cp .vscode/settings.local.json "$WW_WORKSPACE_PATH/.vscode/"
fi
```

### Example: post-workspace-forget

```sh
#!/bin/sh
# .jj/hooks/post-workspace-forget
# Clean up workspace directory after forgetting

if [ -d "$WW_WORKSPACE_PATH" ]; then
    echo "Removing workspace directory: $WW_WORKSPACE_PATH"
    rm -rf "$WW_WORKSPACE_PATH"
fi
```

Make sure hooks are executable:
```sh
chmod +x .jj/hooks/post-workspace-add
chmod +x .jj/hooks/post-workspace-forget
```

## Example

```sh
ww new -r @- feature-x
ww list
ww go -c -r @- feature-x
```

## Help

Use `-h` or `--help` to show help, or `ww help <command>` for command-specific usage.
