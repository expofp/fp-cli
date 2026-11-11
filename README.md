# fp

`fp` is a small global command that knows nothing about any tool. In a folder it finds the
folder's pin, a `.fp` file, and runs what the pin names, passing every argument through and
returning its exit code. One folder can point `fp` at a local worktree, another at a git commit,
a third at an `npx` package.

It has no dependencies and never installs anything. A tool it needs and cannot find is an error
that says how to install it.

## Install

macOS and Linux:

```sh
curl -fsSL https://raw.githubusercontent.com/expofp/fp-cli/main/install.sh | sh
```

Windows, in PowerShell (Windows PowerShell 5.1 or PowerShell 7):

```powershell
irm https://raw.githubusercontent.com/expofp/fp-cli/main/install.ps1 | iex
```

Both take `fp` from the latest release, never from `main`, and print the version installed; run
again to upgrade. `FP_VERSION=0.2.0` before `sh` (Windows: `$env:FP_VERSION = '0.2.0'` first)
picks a release. Neither needs `sudo` or administrator rights.

- `install.sh` puts `fp`, a POSIX `sh` script, into `~/.local/bin`. It edits no shell file: when
  that folder is not on your `PATH`, it prints the line to add.
- `install.ps1` puts `fp.cmd` and `fp.ps1` into `%LOCALAPPDATA%\Programs\fp` and adds that folder
  to your user `PATH`. `fp` itself runs with PowerShell 7; the installer says so when it is
  missing (`winget install Microsoft.PowerShell`). `fp.cmd` runs `fp.ps1` with `pwsh`, so `fp`
  works from `cmd`, PowerShell and other programs alike.

By hand, the same from the release's files:

```sh
mkdir -p ~/.local/bin
curl -fsSL https://github.com/expofp/fp-cli/releases/latest/download/fp -o ~/.local/bin/fp && chmod +x ~/.local/bin/fp
```

```powershell
$dir = "$env:LOCALAPPDATA\Programs\fp"
New-Item -ItemType Directory -Force $dir | Out-Null
irm https://github.com/expofp/fp-cli/releases/latest/download/fp.cmd -OutFile "$dir\fp.cmd"
irm https://github.com/expofp/fp-cli/releases/latest/download/fp.ps1 -OutFile "$dir\fp.ps1"
# once: add $dir to your user PATH
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ";$dir", 'User')
```

## The pin

`fp` looks for the pin from the current folder up to the filesystem root. In each folder it reads
`.fp.local` first, then `.fp`; the first one found wins. Git plays no part in it, so a `~/.fp` is a
default for every folder under your home. `.fp` is meant to be committed; `.fp.local` is a personal override, meant to
be git-ignored (`fp` does not touch `.gitignore`).

A pin is one line, one of three kinds of pointer:

| Pointer | Runs |
| --- | --- |
| `/abs/path` or `~/path` | `<path>/bin/fp` (Windows: `<path>\bin\fp.ps1` with `pwsh`) |
| `git:<host>/<owner>/<repo>@<branch>#<sha>` | `bin/fp` of that commit, checked out once under `~/.cache/fp/` (Windows: `%LOCALAPPDATA%\fp\`) |
| a command, e.g. `npx -y @expofp/fp@1.2.0` | the command, with the arguments after it |

- A **git** pin uses the system's `git` and your own git login, so private repositories work as they
  do for you. Each repository is cloned once, its file contents fetched only as needed
  (`--filter=blob:none`); each commit is checked out once and reused. `fp init` and `fp pin` write
  the branch's newest commit; `fp upgrade` moves to a newer one. A checkout already made runs without
  the network, and without `git`.
- A **command** is split on spaces; quotes are refused. Its first word must be on the `PATH`.

## The words

These words are `fp`'s own; every other word goes to the target.

| Word | Does |
| --- | --- |
| `fp init <pointer>` | pins this folder: checks the pointer can run, then writes `.fp`; `AGENTS.md` with the one line ``Run `fp guide` first and follow it.``; `CLAUDE.md` with `@AGENTS.md`. An existing `AGENTS.md` or `CLAUDE.md` is kept, the line added at the top when it is missing. Nothing else: no folders, no `git init`, no call to the target. Refused where a `.fp` exists. |
| `fp pin <pointer>` | the same checks, then rewrites the pin `fp` finds (or this folder's `.fp`) |
| `fp upgrade` | a git pin only: resolves its branch again and writes the new commit |
| `fp where` | prints what the pin resolves to (the path, the checkout or the command) and the file it comes from |
| `fp --version` | `fp`'s own version |

With no pin found, any other word is an error that names `fp init`.

```sh
fp init ~/projects/efp                      # a local checkout or worktree
fp init git:github.com/expofp/efp@main      # writes git:github.com/expofp/efp@main#<the newest sha>
fp init npx -y @expofp/fp                   # a command
fp guide                                    # runs the pinned tool's guide
```

## No trust prompt

`fp` runs the pin it finds, as `npm install` or `make` run what a cloned repository holds: running
`fp` in a folder trusts that folder. `fp where` shows what a pin runs before you run it.

## Errors

`fp`'s own errors start with `fp:` and exit with 1; a usage error (no pin, a word missing its
pointer) exits with 2 and prints the usage. Every other exit code is the target's. The tools it may
need, and what it says when one is missing:

| Missing | Needed for | The fix it names |
| --- | --- | --- |
| `git` | a git pin's first checkout, `init`, `pin`, `upgrade` of git pins | macOS: `xcode-select --install`; Linux: the package manager; Windows: `winget install Git.Git` |
| a command pin's first word | running it | ``npx`` / ``npm`` / ``node``: Node, https://nodejs.org; otherwise "`<word>` is not on the PATH" |
| PowerShell 7 | Windows | `winget install Microsoft.PowerShell` |

## The target's contract

A folder or repository `fp` can point at provides:

- `bin/fp`, an executable (`sh` or anything with a shebang), and `bin/fp.ps1`, its PowerShell 7
  twin for Windows;
- the word `guide`, which prints how to work with it: `AGENTS.md` written by `fp init` tells agents
  to run `fp guide` first;
- no words of its own named `init`, `pin`, `upgrade`, `where` or `--version`: `fp` keeps
  those and never passes them on.

The target runs in the folder `fp` was run in, with every argument as given; its exit code is
`fp`'s.

## Tests

`tests/scenarios.txt` is one table of scenarios; `tests/run.sh` runs it against `fp` under `/bin/sh`
and `dash`, `tests/run.ps1` against `fp.ps1` under `pwsh`. Each runner then tries its installer
against a fake release in a temporary folder (`FP_BASE_URL`, for tests only):

```sh
shellcheck fp install.sh tests/run.sh && tests/run.sh && pwsh tests/run.ps1
```

`fp.cmd` has no test of its own, nor `install.ps1` under Windows PowerShell 5.1 or on Windows.
