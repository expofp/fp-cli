#!/usr/bin/env pwsh
# Runs tests/scenarios.txt against fp.ps1 under pwsh (PowerShell 7).
# usage: pwsh tests/run.ps1
#Requires -Version 7.0
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$Fp = (Resolve-Path (Join-Path $PSScriptRoot '..' 'fp.ps1')).ProviderPath
$Table = Join-Path $PSScriptRoot 'scenarios.txt'
$Pwsh = [Environment]::ProcessPath
$Sep = [IO.Path]::PathSeparator

$Tmp = Join-Path ([IO.Path]::GetTempPath()) "fp-tests.$PID"
New-Item -ItemType Directory -Force $Tmp | Out-Null
$Tmp = (Resolve-Path $Tmp).ProviderPath
if ($IsMacOS -and $Tmp.StartsWith('/var/')) { $Tmp = "/private$Tmp" }
$Fix = Join-Path $Tmp 'fix'

# --- fixtures: the PATH, the git repo

$git = (Get-Command git -CommandType Application | Select-Object -First 1).Source
foreach ($d in 'bin', 'nogit') { New-Item -ItemType Directory -Force (Join-Path $Fix $d) | Out-Null }
if ($IsWindows) {
	# Windows: a folder with git, and fpecho; without it, fpecho only.
	Set-Content (Join-Path $Fix 'bin' 'fpecho.ps1') 'Write-Output "fpecho: $($args -join '' '')"'
	Copy-Item (Join-Path $Fix 'bin' 'fpecho.ps1') (Join-Path $Fix 'nogit')
	$BinPath = (Join-Path $Fix 'bin') + $Sep + (Split-Path $git)
} else {
	foreach ($t in 'uname', 'mkdir', 'mv', 'rm', 'grep', 'cat', 'git') {
		$c = Get-Command $t -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
		if (-not $c) { continue }
		New-Item -ItemType SymbolicLink -Path (Join-Path $Fix 'bin' $t) -Target $c.Source | Out-Null
		if ($t -ne 'git') { New-Item -ItemType SymbolicLink -Path (Join-Path $Fix 'nogit' $t) -Target $c.Source | Out-Null }
	}
	foreach ($d in 'bin', 'nogit') {
		$f = Join-Path $Fix $d 'fpecho'
		Set-Content $f "#!/bin/sh`necho `"fpecho: `$*`""
		chmod +x $f
	}
	$BinPath = Join-Path $Fix 'bin'
}
$NoGitPath = Join-Path $Fix 'nogit'

function New-Target([string]$Dir, [string]$Label) {
	New-Item -ItemType Directory -Force (Join-Path $Dir 'bin') | Out-Null
	Set-Content (Join-Path $Dir 'bin' 'fp') "#!/bin/sh`necho `"${Label}: `$*`"`n[ `"`$1`" = exit ] && exit `"`$2`"`nexit 0"
	Set-Content (Join-Path $Dir 'bin' 'fp.ps1') "Write-Output `"${Label}: `$(`$args -join ' ')`"`nif (`$args[0] -eq 'exit') { exit [int]`$args[1] }`nexit 0"
	if (-not $IsWindows) { chmod +x (Join-Path $Dir 'bin' 'fp') }
}

$env:GIT_CONFIG_NOSYSTEM = '1'
$env:GIT_AUTHOR_NAME = 'fp'; $env:GIT_AUTHOR_EMAIL = 'fp@example.test'
$env:GIT_COMMITTER_NAME = 'fp'; $env:GIT_COMMITTER_EMAIL = 'fp@example.test'
$work = Join-Path $Tmp 'work'
& $git init -q -b main $work
New-Target $work 'git v1'
& $git -C $work add -A; & $git -C $work commit -qm v1
$Sha1 = & $git -C $work rev-parse HEAD
& $git -C $work checkout -qb next
New-Target $work 'git v2'
& $git -C $work commit -qam v2
$Sha2 = & $git -C $work rev-parse HEAD
& $git clone -q --bare $work (Join-Path $Fix 'tool.git')
& $git -C (Join-Path $Fix 'tool.git') config uploadpack.allowFilter true
& $git -C (Join-Path $Fix 'tool.git') config uploadpack.allowAnySHA1InWant true

# --- one row

function Expand([string]$Text) {
	$Text.Replace('$W', $W).Replace('$HOME', "$W/home").Replace('$SHA1', $Sha1).Replace('$SHA2', $Sha2)
}

# Runs fp.ps1 in a process of its own: no terminal, the row's HOME and PATH, the arguments as they
# are (pwsh would expand a ~ in them).
function Invoke-Fp([string]$Dir, [string[]]$FpArgs, [string]$PathVar) {
	$psi = [Diagnostics.ProcessStartInfo]::new($Pwsh)
	foreach ($a in @('-NoLogo', '-NoProfile', '-File', $Fp) + $FpArgs) { $psi.ArgumentList.Add($a) }
	$psi.WorkingDirectory = $Dir
	$psi.RedirectStandardInput = $true
	$psi.RedirectStandardOutput = $true
	$psi.RedirectStandardError = $true
	$psi.Environment['HOME'] = "$W/home"
	$psi.Environment['PATH'] = $PathVar
	if ($IsWindows) {
		$psi.Environment['USERPROFILE'] = "$W/home"
		$psi.Environment['LOCALAPPDATA'] = "$W/home/.cache"
		$psi.Environment['APPDATA'] = "$W/home/.config"
	}
	$p = [Diagnostics.Process]::Start($psi)
	$p.StandardInput.Close()
	$err = $p.StandardError.ReadToEndAsync()
	$out = $p.StandardOutput.ReadToEnd()
	$p.WaitForExit()
	return @{ Out = ($out + $err.Result).TrimEnd(); Code = $p.ExitCode }
}

function Split-Words([string]$Text) { @($Text.Trim() -split ' +' | Where-Object { $_ -ne '' }) }

$script:pass = 0; $script:failed = 0
$rows = Get-Content $Table | Where-Object { $_ -and -not $_.StartsWith('#') }
foreach ($row in $rows) {
	$name, $setup, $folder, $argsText, $code, $expect = @($row.Split('|') | ForEach-Object { $_.Trim() })
	$W = Join-Path $Tmp 'w'
	if (Test-Path $W) { Remove-Item -Recurse -Force $W }
	New-Item -ItemType Directory -Force "$W/home", "$W/repos/example.test/acme" | Out-Null
	Copy-Item -Recurse (Join-Path $Fix 'tool.git') "$W/repos/example.test/acme/tool.git"
	Set-Content "$W/home/.gitconfig" "[url `"file://$W/repos/example.test/`"]`n`tinsteadOf = https://example.test/"
	$pathVar = $BinPath
	$fails = [Collections.Generic.List[string]]::new()
	$broken = $false
	foreach ($step in $setup.Split(';')) {
		$words = Split-Words (Expand $step)
		if (-not $words) { continue }
		$verb, $rest = $words
		$rest = @($rest | Where-Object { $_ -ne $null })
		switch ($verb) {
			'repo' { New-Item -ItemType Directory -Force "$W/$($rest[0])/.git" | Out-Null }
			'dir' { New-Item -ItemType Directory -Force "$W/$($rest[0])" | Out-Null }
			'target' { New-Target "$W/$($rest[0])" (Split-Path -Leaf $rest[0]) }
			'write' {
				$f = "$W/$($rest[0])"
				New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
				$text = if ($rest.Count -gt 1) { ($rest[1..($rest.Count - 1)] -join ' ') + "`n" } else { '' }
				[IO.File]::WriteAllText($f, $text)
			}
			'remove' { Remove-Item -Force "$W/$($rest[0])", "$W/$($rest[0]).ps1" -ErrorAction SilentlyContinue }
			'fp' {
				$r = Invoke-Fp "$W/$($rest[0])" @($rest | Select-Object -Skip 1) $BinPath
				if ($r.Code -ne 0) { $fails.Add("setup fp $($rest -join ' '): $($r.Code) $($r.Out)"); $broken = $true }
			}
			'commit' { & $git -C "$W/repos/example.test/acme/tool.git" update-ref refs/heads/main $Sha2 }
			'nogit' { $pathVar = $NoGitPath }
			default { $fails.Add("unknown setup step $verb"); $broken = $true }
		}
		if ($broken) { break }
	}
	if (-not $broken) {
		$r = Invoke-Fp "$W/$folder" (Split-Words (Expand $argsText)) $pathVar
		$out = $r.Out
		if ("$($r.Code)" -ne $code) { $fails.Add("exit $($r.Code), expected $code; output: $out") }
		foreach ($check in $expect.Split(';')) {
			$c = (Expand $check).Trim()
			if (-not $c) { continue }
			$verb, $text = $c.Split(' ', 2)
			switch ($verb) {
				'out' { if (-not $out.Contains($text)) { $fails.Add("no `"$text`" in: $out") } }
				'noout' { if ($out.Contains($text)) { $fails.Add("`"$text`" in: $out") } }
				{ $_ -in 'first', 'has' } {
					$f, $want = $text.Split(' ', 2)
					if (-not (Test-Path -LiteralPath "$W/$f" -PathType Leaf)) { $fails.Add("no $f"); break }
					$lines = @([IO.File]::ReadAllLines("$W/$f"))
					if ($verb -eq 'first') {
						$got = if ($lines) { $lines[0] } else { '' }
						if ($got -cne $want) { $fails.Add("$f starts with `"$got`", expected `"$want`"") }
					} elseif ($lines -cnotcontains $want) { $fails.Add("$f has no line `"$want`"") }
				}
				'nofile' { if (Test-Path -LiteralPath "$W/$text") { $fails.Add("$text exists") } }
				default { $fails.Add("unknown check $verb") }
			}
		}
	}
	if ($fails.Count) {
		$script:failed++
		foreach ($f in $fails) { Write-Output "FAIL $name [pwsh]: $f" }
	} else { $script:pass++ }
}
# --- install.ps1, against a fake release: latest is this fp, v0.1.0 an older one, v0.0.1 no fp

$Rel = Join-Path $Tmp 'release'
foreach ($d in 'latest/download', 'download/v0.1.0', 'download/v0.0.1') { New-Item -ItemType Directory -Force "$Rel/$d" | Out-Null }
$Cmd = Join-Path $PSScriptRoot '..' 'fp.cmd'
Copy-Item $Fp, $Cmd "$Rel/latest/download"
(Get-Content -Raw $Fp) -replace "(?m)^\`$FpVersion = '[^']+'", "`$FpVersion = '0.1.0'" | Set-Content -NoNewline "$Rel/download/v0.1.0/fp.ps1"
Copy-Item $Cmd "$Rel/download/v0.1.0"
Set-Content "$Rel/download/v0.0.1/fp.ps1" '<html>Not Found</html>'
Copy-Item $Cmd "$Rel/download/v0.0.1"
$Now = [regex]::Match((Get-Content -Raw $Fp), "\`$FpVersion = '([^']+)'").Groups[1].Value
$Local = Join-Path $Tmp 'local'
$Installed = "$Local/Programs/fp"

function Invoke-Install([hashtable]$Env) {
	$psi = [Diagnostics.ProcessStartInfo]::new($Pwsh)
	foreach ($a in '-NoLogo', '-NoProfile', '-File', (Join-Path $PSScriptRoot '..' 'install.ps1')) { $psi.ArgumentList.Add($a) }
	$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
	$psi.Environment['LOCALAPPDATA'] = $Local
	$psi.Environment['FP_BASE_URL'] = "file://$Rel"
	$psi.Environment.Remove('FP_VERSION') | Out-Null
	foreach ($k in $Env.Keys) { if ($null -eq $Env[$k]) { $psi.Environment.Remove($k) | Out-Null } else { $psi.Environment[$k] = $Env[$k] } }
	$p = [Diagnostics.Process]::Start($psi)
	$p.StandardInput.Close()
	$err = $p.StandardError.ReadToEndAsync()
	$out = $p.StandardOutput.ReadToEnd()
	$p.WaitForExit()
	return @{ Out = ($out + $err.Result); Code = $p.ExitCode }
}
function Get-Installed {
	if (-not (Test-Path "$Installed/fp.ps1")) { return '' }
	[regex]::Match((Get-Content -Raw "$Installed/fp.ps1"), "\`$FpVersion = '([^']+)'").Groups[1].Value
}
function Test-Install([string]$Name, [hashtable]$Env, [int]$Code, [string]$Want, [string]$Version) {
	$r = Invoke-Install $Env
	$fails = @()
	if ($r.Code -ne $Code) { $fails += "exit $($r.Code), expected $Code; output: $($r.Out)" }
	if (-not $r.Out.Contains($Want)) { $fails += "no `"$Want`" in: $($r.Out)" }
	if ($Version -and (Get-Installed) -ne $Version) { $fails += "installed fp.ps1 is $(Get-Installed), expected $Version" }
	if ($Version -and -not (Test-Path "$Installed/fp.cmd")) { $fails += 'no fp.cmd' }
	if ($fails) { $script:failed++; foreach ($f in $fails) { Write-Output "FAIL $Name [pwsh]: $f" } } else { $script:pass++ }
}

$withPwsh = Split-Path $Pwsh
Test-Install 'install: the latest' @{ PATH = $withPwsh } 0 "fp $Now installed: $Installed" $Now
Test-Install 'install: FP_VERSION picks one' @{ PATH = $withPwsh; FP_VERSION = '0.1.0' } 0 'fp 0.1.0 installed' '0.1.0'
Test-Install 'install: a v in FP_VERSION' @{ PATH = $withPwsh; FP_VERSION = 'v0.1.0' } 0 'fp 0.1.0 installed' '0.1.0'
Test-Install 'install: a rerun upgrades' @{ PATH = $withPwsh } 0 "fp $Now installed" $Now
Test-Install 'install: a missing version' @{ PATH = $withPwsh; FP_VERSION = '9.9.9' } 1 "cannot download file://$Rel/download/v9.9.9/fp.ps1" $Now
Test-Install 'install: a download that is not fp' @{ PATH = $withPwsh; FP_VERSION = '0.0.1' } 1 'is not fp' $Now
# PowerShell 7 missing is said under Windows PowerShell 5.1 alone, which this Mac has not: read only.
if (-not $IsWindows) {
	Test-Install 'install: Windows only' @{ PATH = $withPwsh; FP_BASE_URL = $null } 1 'this installer is for Windows; on macOS and Linux: curl' $Now
}

Remove-Item -Recurse -Force $Tmp
Write-Output "$($script:pass) passed, $($script:failed) failed"
exit ([int]($script:failed -ne 0))
