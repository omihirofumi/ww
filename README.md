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
ww new <name>
ww go <name>
ww list
ww init zsh
```

### Commands

- `new <name>`
  - Runs `jj workspace add` to create a workspace.
- `go <name>`
  - Prints a `cd ...` command for the workspace path.
- `list`
  - Shows workspace names from `jj workspace list`.
- `init zsh`
  - Prints a zsh function that interprets `ww` output.

## zsh Integration

To make `ww go` actually change directories, add the function to your shell:

```sh
eval "$(ww init zsh)"
```

After that, `ww go <name>` will move your current directory.

## Workspace Location

`ww` uses `jj root` and creates workspaces at:

```
$HOME/.jj-workspace/<repo_name>/<name>
```

## Example

```sh
ww new feature-x
ww list
ww go feature-x
```
