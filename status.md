# fp-cli: status

Worker `fp-cli` (Opus, medium), for `lead` (pane w9:pC), run 5 of expofp/efp, issue 429.
The decision and the owner's words, verbatim: https://github.com/expofp/efp/issues/429#issuecomment-6792202663
(read it first; item 3 there is the shape, this brief fills in the details). Questions and stops go to
lead with your recommendation, never to the owner: `herdr-tools say lead 'from fp-cli: …'`.

## What fp is

A global command that knows nothing about any map tool. In a folder, it finds the pin and runs what
the pin names, passing every argument through and returning its exit code. The owner's rules: no
dependencies (a tool it needs and cannot find is an error that says how to install it, per
platform); never installs anything; the one thing it knows about a target is that it has `guide`.

## The work

1. The repo is empty, public, no license. First commit on `main`: a one-line `README.md`; push.
   Then branch `fp-v0`, a draft PR, this file committed there (removed in the last commit before
   the merge).
2. `fp`: POSIX `sh`, executable, `shellcheck` clean, runs under macOS `/bin/sh` and `dash`.
3. `fp.cmd` and `fp.ps1`: PowerShell 7 (`pwsh`). `fp.cmd` finds `pwsh` (else: "fp needs PowerShell
   7: winget install Microsoft.PowerShell") and runs `fp.ps1` with all arguments. Same behavior as
   `fp`, rule for rule.
4. Tests: one scenario table, language-neutral (a file of rows: name, setup, folder, arguments,
   expected exit code, expected output or error text), and one runner per shell: `tests/run.sh`
   (the table against `fp` under `/bin/sh` and under `dash`) and `tests/run.ps1` (against `fp.ps1`
   under `pwsh`). Targets are fixtures made by the runner (a folder with `bin/fp` and
   `bin/fp.ps1` that print their arguments); git pins use a local repo (a test-only way to point
   `git:` at it is fine). No CI; no Windows machine here, so `fp.cmd` is checked by reading only.
5. `README.md`: what fp is; install on macOS and Linux (`curl -fsSL
   https://raw.githubusercontent.com/expofp/fp-cli/main/fp -o ~/.local/bin/fp && chmod +x …`) and
   Windows (`irm` of `fp.cmd` and `fp.ps1` into a folder on the PATH; PowerShell 7 needed); what
   `.fp` holds; the words; trust; the errors; the target's contract. No brew, no scoop yet.

## The rules

- **Lookup:** from the current folder up to the git root (outside a git repo: the current folder
  only). In each folder `.fp.local` first, then `.fp`; the first found wins. `.fp.local` is meant
  to be git-ignored (fp does not touch `.gitignore`).
- **A pin is one line**, one of:
  - an absolute path (or `~/…`): runs `<path>/bin/fp` (Windows: `<path>\bin\fp.ps1` with `pwsh`);
    the file missing is an error;
  - `git:<host>/<owner>/<repo>@<branch>#<sha>`: the system's git; one clone per repo with file
    contents fetched as needed (`--filter=blob:none`) under `~/.cache/fp/` (Windows:
    `%LOCALAPPDATA%\fp\`), a checkout per sha made once and reused, then its `bin/fp`; the person's
    own git login gives access to private repos;
  - anything else: a command, split on spaces, quotes refused; its first word must be on the PATH,
    else an error with a hint for known words (`npx`: Node, https://nodejs.org) or "`<word>` is
    not on the PATH".
- **fp's own words** (a target must not use them; README says so): `init <pointer>`, `pin
  <pointer>`, `upgrade`, `trust`, `where`, `--version`. Any other word goes to the target. With no
  pin found, any other word is an error that names `fp init` and prints fp's usage.
  - `init <pointer>`: refused if `.fp` exists in this folder (names `fp pin` and `fp upgrade`).
    Checks the pointer can run (path has `bin/fp`; git: `ls-remote` resolves the branch, the sha
    written is the branch's now; command: first word on the PATH). Writes `.fp`; `AGENTS.md` with
    the one line `Run \`fp guide\` first and follow it.`; `CLAUDE.md` with `@AGENTS.md`. An
    existing `AGENTS.md` or `CLAUDE.md` is kept: the line is added at the top when missing, never
    overwritten. Nothing else: no folders, no `git init`, no call to the target.
  - `pin <pointer>`: the same checks, rewrites the `.fp` that lookup found (or the current folder's).
  - `upgrade`: git pins only; resolves the pin's branch again and rewrites the sha.
  - `trust`: trusts the pin lookup finds, asking on a terminal.
  - `where`: prints what the pin resolves to (the path, the checkout, or the command) and which file
    it came from.
  - `--version`: fp's own version (`0.1.0`).
- **Trust:** a pin written by `init` or `pin` on this machine is trusted at once. Any other pin (a
  cloned map's) asks once on a terminal ("Run `<pointer>` for `<folder>`? [y/N]"); without a
  terminal (agents run fp without one) it is an error naming `fp trust`. Trusted pins are kept by a
  hash of the folder and the pin line in `~/.config/fp/trusted` (Windows: `%APPDATA%\fp\trusted`).
- **Missing tools:** git only for git pins (macOS: `xcode-select --install`; Linux: the package
  manager; Windows: `winget install Git.Git`); `shasum -a 256` or `sha256sum`, whichever exists.

## efp's side, after fp-cli's PR is ready

An efp worktree `fp-entry` from `origin/main`: `git -C /Users/emt/projects/efp worktree add
.claude/worktrees/fp-entry -b fp-entry origin/main`. efp's `AGENTS.md` rules apply (Conventional
Commits with a scope, a Russian tl;dr on top of the PR, `Part of #429`, never a closing word next to
429).

- `bin/fp` (`sh`) and `bin/fp.ps1`: the only word is `guide`, printing `guides/guide.md` (found
  next to the script, not by the current folder); any other word: "fp: only `guide` so far; the
  old CLI is `fpl`", exit 2.
- `guides/guide.md`: `TBD` (the owner writes it).
- `docs/architecture.md` → Units: one row for `bin/` and `guides/` (the entry fp-cli runs; the
  agent's guide, the new fp growing while fpl is replaced). Show lead the wording in your report.
- Gate: `pnpm check`, `node scripts/checks/flow.mjs`; and end to end: in a temp folder, `fp init
  <the fp-entry worktree>` then `fp guide` prints `TBD`.

## Reporting

Each PR ready: `herdr-tools say lead 'from fp-cli: PR <url> ready, gate: <what ran, results>'`, and
a wait mark `󰔟 lead: merge`. Lead merges (squash). After fp-cli's merge, on lead's word: tag
`v0.1.0` and a GitHub release with `fp`, `fp.cmd`, `fp.ps1`. Keep this file and `now.md` true;
commit by path; push after every commit.

## Where it stands

- `main`: README, pushed. Work on branch `fp-v0` in the worktree `.claude/worktrees/fp-v0` (`.claude/` and `now.md` excluded in `.git/info/exclude`).
- Next: `fp`, `fp.ps1`, `fp.cmd`, the scenario table and its runners, README.
