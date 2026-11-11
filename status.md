# fp-cli installers: status

Worker `fp-cli` for `lead`, expofp/efp issue 429, decision 30:
https://github.com/expofp/efp/issues/429#issuecomment-6794749417 (item 1 here; item 2 is efp's
PR from a worktree `fp-guide-topics`). Questions go to lead with a recommendation.

## The work

- `install.sh` (`curl … | sh`) and `install.ps1` (`irm … | iex`, Windows PowerShell 5.1 and 7):
  the folder (`~/.local/bin`; Windows `%LOCALAPPDATA%\Programs\fp`), `fp` (Windows `fp.cmd`,
  `fp.ps1`) from `releases/latest/download` or `releases/download/v$FP_VERSION`, never main; the
  installed version printed; a PATH hint on macOS and Linux, the user PATH set on Windows; a rerun
  upgrades; no sudo; install.ps1 says when PowerShell 7 is missing.
- Tests against a local fake release (`FP_BASE_URL`, test-only); README install = the two lines,
  the manual steps as a fallback. No new release unless fp changes.

## Where it stands

Branch `installers`, draft PR. Next: install.sh, install.ps1, their tests.
