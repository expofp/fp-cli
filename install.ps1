# Installs fp on Windows, or upgrades it, from Windows PowerShell 5.1 or PowerShell 7:
#   irm https://raw.githubusercontent.com/expofp/fp-cli/main/install.ps1 | iex
# Puts fp.cmd and fp.ps1 from the latest release ($env:FP_VERSION = '0.2.0' picks one) into
# %LOCALAPPDATA%\Programs\fp and adds that folder to the user PATH. No administrator rights.
# fp itself runs with PowerShell 7. FP_BASE_URL replaces the releases' address, for tests.
# Written for Windows PowerShell 5.1 too: no PowerShell 7 syntax here.

& {
	$ErrorActionPreference = 'Stop'
	$ProgressPreference = 'SilentlyContinue'

	# An error, not exit: under irm | iex, exit would close the person's window.
	function Fail([string]$Text) { [Console]::Error.WriteLine("fp install: $Text"); throw 'fp install failed' }

	$base = if ($env:FP_BASE_URL) { $env:FP_BASE_URL } else { 'https://github.com/expofp/fp-cli/releases' }
	if ($env:OS -ne 'Windows_NT' -and -not $env:FP_BASE_URL) {
		Fail 'this installer is for Windows; on macOS and Linux: curl -fsSL https://raw.githubusercontent.com/expofp/fp-cli/main/install.sh | sh'
	}
	$version = "$env:FP_VERSION".TrimStart('v')
	$from = if ($version) { "$base/download/v$version" } else { "$base/latest/download" }
	$dir = Join-Path (Join-Path $env:LOCALAPPDATA 'Programs') 'fp'

	try { New-Item -ItemType Directory -Force -Path $dir | Out-Null } catch { Fail "cannot make $dir" }
	try {
		[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
	} catch { }
	$web = New-Object Net.WebClient
	$got = $null
	foreach ($name in 'fp.ps1', 'fp.cmd') {
		$tmp = Join-Path $dir ".$name.tmp$PID"
		try { $web.DownloadFile("$from/$name", $tmp) } catch { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue; Fail "cannot download $from/$name" }
		if ($name -eq 'fp.ps1') {
			$m = Select-String -LiteralPath $tmp -Pattern "^\`$FpVersion = '([^']+)'" | Select-Object -First 1
			if (-not $m) { Remove-Item -LiteralPath $tmp -Force; Fail "$from/$name is not fp" }
			$got = $m.Matches[0].Groups[1].Value
		}
		Move-Item -LiteralPath $tmp -Destination (Join-Path $dir $name) -Force
	}
	Write-Host "fp $got installed: $dir"

	if ($env:OS -eq 'Windows_NT') {
		$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
		$parts = @("$userPath".Split(';') | Where-Object { $_ })
		if ($parts -notcontains $dir) {
			[Environment]::SetEnvironmentVariable('Path', (@($parts) + $dir) -join ';', 'User')
			Write-Host "$dir added to your user PATH; open a new terminal for it."
		}
		if (@("$env:Path".Split(';')) -notcontains $dir) { $env:Path = "$env:Path;$dir" }
	}

	if ($PSVersionTable.PSVersion.Major -lt 7 -and -not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
		Write-Host 'fp runs with PowerShell 7, which is not installed: winget install Microsoft.PowerShell' -ForegroundColor Yellow
	}
}
