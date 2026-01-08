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

`ww` uses `jj root` and creates workspaces at:

```
../<repo_name>__<name>
```

## Example

```sh
ww new -r @- feature-x
ww list
ww go -c -r @- feature-x
```

## Help

Use `-h` or `--help` to show help, or `ww help <command>` for command-specific usage.
