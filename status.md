# fp-cli v0.2.0: status

Worker `fp-cli` for `lead`, expofp/efp issue 429, decision 29:
https://github.com/expofp/efp/issues/429#issuecomment-6794635489. Questions go to lead with a
recommendation: `herdr-tools say lead 'from fp-cli: …'`.

## The work

In `fp` and `fp.ps1` alike, the scenario table and the README; version 0.2.0.
1. Lookup walks up from the current folder to `/`; in each folder `.fp.local` first, then `.fp`;
   the first found wins. No `.git` boundary.
2. Trust removed entirely: the `trust` word, the prompt, `~/.config/fp/trusted`, their rows.
   `fp where` still shows what a pin runs.

Gate: shellcheck, `tests/run.sh` (sh, dash), `pwsh tests/run.ps1`. Report the PR to lead; lead
merges; tag `v0.2.0` and release (`fp`, `fp.cmd`, `fp.ps1`) on lead's word.

## Where it stands

Branch `fp-v0.2` in worktree `.claude/worktrees/fp-v0.2`; draft PR opened. Next: the code.
