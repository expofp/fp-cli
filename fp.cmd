@echo off
rem fp: runs the tool a folder is pinned to. https://github.com/expofp/fp-cli
rem Runs fp.ps1, next to this file, with PowerShell 7 and every argument.
setlocal
where pwsh 1>NUL 2>NUL
if errorlevel 1 (
  echo fp needs PowerShell 7: winget install Microsoft.PowerShell 1>&2
  exit /b 1
)
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0fp.ps1" %*
exit /b %ERRORLEVEL%
