# fp: runs the tool a folder is pinned to. https://github.com/expofp/fp-cli
# PowerShell 7; the POSIX sh twin is fp, rule for rule. On Windows fp.cmd runs this file.
#Requires -Version 7.0
Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$FpVersion = '0.1.0'
$AgentsLine = 'Run `fp guide` first and follow it.'
$ClaudeLine = '@AGENTS.md'
if ($IsWindows) {
	$Cache = Join-Path $env:LOCALAPPDATA 'fp'
	$Trusted = Join-Path $env:APPDATA 'fp' 'trusted'
	$UserHome = $env:USERPROFILE
} else {
	$Cache = "$env:HOME/.cache/fp"
	$Trusted = "$env:HOME/.config/fp/trusted"
	$UserHome = $env:HOME
}

function Say([string]$Text) { [Console]::Out.WriteLine($Text) }
function Die([string]$Text) { [Console]::Error.WriteLine("fp: $Text"); exit 1 }

function Show-Usage {
	[Console]::Error.WriteLine(@(
		'usage: fp <word> [args...]   run the tool this folder is pinned to, passing every argument'
		'       fp init <pointer>     pin this folder: writes .fp, AGENTS.md and CLAUDE.md'
		'       fp pin <pointer>      change the pin'
		"       fp upgrade            move a git pin to its branch's newest commit"
		'       fp trust              trust the pin found here'
		'       fp where              show what the pin runs and the file it comes from'
		'       fp --version'
		'a pointer: /abs/path | ~/path | git:<host>/<owner>/<repo>@<branch> | <command> [args]'
	) -join "`n")
}
function Stop-Usage([string]$Text) { [Console]::Error.WriteLine("fp: $Text"); Show-Usage; exit 2 }

# --- lookup: from here up to the git root (outside git: here only); .fp.local, then .fp

$Cwd = (Get-Location).ProviderPath

function Find-Root {
	$d = $Cwd
	while ($d) {
		if (Test-Path -LiteralPath (Join-Path $d '.git')) { return $d }
		$d = [IO.Path]::GetDirectoryName($d)
	}
	return $Cwd
}

# Returns @{ Dir; File; Line } or $null.
function Find-Pin {
	$root = Find-Root
	$d = $Cwd
	while ($d) {
		foreach ($f in '.fp.local', '.fp') {
			$file = Join-Path $d $f
			if (Test-Path -LiteralPath $file -PathType Leaf) {
				return @{ Dir = $d; File = $file; Line = (Read-Pin $file) }
			}
		}
		if ($d -eq $root) { return $null }
		$d = [IO.Path]::GetDirectoryName($d)
	}
	return $null
}

function Read-Pin([string]$File) {
	$first = [IO.File]::ReadLines($File) | Select-Object -First 1
	$line = if ($null -eq $first) { '' } else { $first.Trim() }
	if (-not $line) { Die "$File is empty: it should hold one pointer" }
	return $line
}

function Stop-NoPin {
	[Console]::Error.WriteLine('fp: no .fp here or above (up to the git root); pin this folder first: fp init <pointer>')
	Show-Usage
	exit 2
}

# --- pointers: a path, a git pin or a command

# Returns @{ Kind = path, Target } | @{ Kind = git, Repo, Branch, Sha, Url, Checkout } | @{ Kind = command, Words }.
function Get-Pointer([string]$Line) {
	if ($Line -eq '~') { return @{ Kind = 'path'; Target = $UserHome } }
	if ($Line.StartsWith('~/') -or $Line.StartsWith('~\')) { return @{ Kind = 'path'; Target = (Join-Path $UserHome $Line.Substring(2)) } }
	if ([IO.Path]::IsPathFullyQualified($Line)) { return @{ Kind = 'path'; Target = $Line } }
	if ($Line.StartsWith('git:')) { return (Get-GitPointer $Line) }
	if ($Line -match "[`"']") { Die "quotes are not allowed in a command pin: $Line" }
	$words = @($Line -split '\s+')
	if ($words[0] -match '[/\\]') { Die "a path pin must be absolute or start with ~/: $($words[0])" }
	return @{ Kind = 'command'; Words = $words }
}

function Get-GitPointer([string]$Line) {
	$rest = $Line.Substring(4)
	$shape = "a git pin is git:<host>/<owner>/<repo>@<branch>: $Line"
	$badSha = "the #<sha> of a git pin is a full commit hash: $Line"
	if ($rest -cmatch '[^A-Za-z0-9._~/@#+-]') { Die "a git pin has only letters, digits and ._~/@#+- : $Line" }
	if (-not $rest.Contains('@')) { Die "a git pin needs @<branch>: $Line" }
	$at = $rest.IndexOf('@')
	$repo = $rest.Substring(0, $at)
	$ref = $rest.Substring($at + 1)
	$sha = ''
	if ($ref.Contains('#')) {
		$hash = $ref.LastIndexOf('#')
		$sha = $ref.Substring($hash + 1)
		$branch = $ref.Substring(0, $hash)
	} else {
		$branch = $ref
	}
	if (-not $repo.Contains('/')) { Die $shape }
	if ("/$repo/" -match '//|/\.\./|/\./') { Die $shape }
	if (-not $branch -or $branch.Contains('@')) { Die "a git pin needs one @<branch>: $Line" }
	if ($ref.Contains('#')) {
		if ($sha -cnotmatch '^[0-9a-f]+$' -or ($sha.Length -ne 40 -and $sha.Length -ne 64)) { Die $badSha }
	}
	return @{
		Kind = 'git'; Repo = $repo; Branch = $branch; Sha = $sha
		Url = "https://$repo.git"; Checkout = "$Cache/checkouts/$repo/$sha"
	}
}

function Assert-Git {
	if (Get-Command git -CommandType Application -ErrorAction SilentlyContinue) { return }
	$hint = if ($IsWindows) { 'winget install Git.Git' }
	elseif ($IsMacOS) { 'xcode-select --install' }
	else { 'install it with your package manager (apt install git, dnf install git, pacman -S git, ...)' }
	Die "a git pin needs git, which is not on the PATH: $hint"
}

function Assert-Word([string]$Word) {
	if (Get-Command $Word -CommandType Application, ExternalScript -ErrorAction SilentlyContinue) { return }
	if ($Word -in 'npx', 'npm', 'node') { Die "``$Word`` is not on the PATH: it comes with Node, https://nodejs.org" }
	Die "``$Word`` is not on the PATH"
}

# Resolves a git pin's branch now: sets its Sha.
function Resolve-Branch($P) {
	Assert-Git
	$out = & git ls-remote $P.Url "refs/heads/$($P.Branch)"
	if ($LASTEXITCODE -ne 0) { Die "cannot reach $($P.Url)" }
	$sha = if ($out) { (@($out)[0] -split '\s+')[0] } else { '' }
	if (-not $sha) { Die "no branch $($P.Branch) in $($P.Url)" }
	$P.Sha = $sha
}

# Checks a pointer given to init or pin can run; returns the pin line to write.
function Test-Pointer([string]$Text) {
	$line = $Text.Trim()
	if (-not $line) { Stop-Usage 'a pointer is needed' }
	$p = Get-Pointer $line
	switch ($p.Kind) {
		'path' {
			$exe = Join-Path $p.Target 'bin' 'fp.ps1'
			if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Die "$exe not found" }
			return $line
		}
		'git' { Resolve-Branch $p; return "git:$($p.Repo)@$($p.Branch)#$($p.Sha)" }
		'command' { Assert-Word $p.Words[0]; return ($p.Words -join ' ') }
	}
}

# --- trust: by a hash of the folder and the pin line

function Get-PinHash([string]$Dir, [string]$Line) {
	$bytes = [Text.Encoding]::UTF8.GetBytes("$Dir`n$Line")
	return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Test-Trusted([string]$Dir, [string]$Line) {
	if (-not (Test-Path -LiteralPath $Trusted -PathType Leaf)) { return $false }
	return ([IO.File]::ReadAllLines($Trusted) -contains (Get-PinHash $Dir $Line))
}

function Add-Trust([string]$Dir, [string]$Line) {
	if (Test-Trusted $Dir $Line) { return }
	try {
		New-Item -ItemType Directory -Force -Path (Split-Path $Trusted) | Out-Null
		[IO.File]::AppendAllText($Trusted, "$(Get-PinHash $Dir $Line)`n")
	} catch { Die "cannot write $Trusted" }
}

# 0: yes, 1: no, 2: no terminal to ask on.
function Read-Trust($Pin) {
	if ([Console]::IsInputRedirected) { return 2 }
	[Console]::Error.Write("Run ``$($Pin.Line)`` for $($Pin.Dir)? [y/N] ")
	$ans = [Console]::In.ReadLine()
	if ($ans -cin 'y', 'Y', 'yes', 'Yes', 'YES') { return 0 }
	return 1
}

# --- the words

function Write-PinFile([string]$File, [string]$Line) {
	try {
		$tmp = "$File.fp$PID"
		[IO.File]::WriteAllText($tmp, "$Line`n")
		Move-Item -LiteralPath $tmp -Destination $File -Force
	} catch { Die "cannot write $File" }
}

function Add-Line([string]$File, [string]$Line) {
	try {
		if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
			[IO.File]::WriteAllText((Join-Path $Cwd $File), "$Line`n")
			Say "${File}: written"
		} elseif (@([IO.File]::ReadAllLines((Join-Path $Cwd $File)) | ForEach-Object { $_.TrimEnd("`r") }) -ccontains $Line) {
			Say "${File}: has the line, kept"
		} else {
			$path = Join-Path $Cwd $File
			$tmp = "$path.fp$PID"
			[IO.File]::WriteAllText($tmp, "$Line`n`n" + [IO.File]::ReadAllText($path))
			Move-Item -LiteralPath $tmp -Destination $path -Force
			Say "${File}: the line added at the top"
		}
	} catch { Die "cannot write $File" }
}

function Invoke-Init([string[]]$Rest) {
	if (-not $Rest) { Stop-Usage 'fp init needs a pointer' }
	if (Test-Path -LiteralPath (Join-Path $Cwd '.fp')) { Die '.fp already exists here; change it with fp pin <pointer> (or fp upgrade for a git pin)' }
	$line = Test-Pointer ($Rest -join ' ')
	Write-PinFile (Join-Path $Cwd '.fp') $line
	Add-Trust $Cwd $line
	Say ".fp: $line"
	Add-Line 'AGENTS.md' $AgentsLine
	Add-Line 'CLAUDE.md' $ClaudeLine
}

function Invoke-Pin([string[]]$Rest) {
	if (-not $Rest) { Stop-Usage 'fp pin needs a pointer' }
	$pin = Find-Pin
	if ($pin) { $file = $pin.File; $dir = $pin.Dir } else { $file = Join-Path $Cwd '.fp'; $dir = $Cwd }
	$line = Test-Pointer ($Rest -join ' ')
	Write-PinFile $file $line
	Add-Trust $dir $line
	Say "${file}: $line"
}

function Invoke-Upgrade {
	$pin = Find-Pin
	if (-not $pin) { Stop-NoPin }
	$p = Get-Pointer $pin.Line
	if ($p.Kind -ne 'git') { Die "fp upgrade moves git pins only; $($pin.File) pins $($pin.Line)" }
	$old = $p.Sha
	Resolve-Branch $p
	if ($old -eq $p.Sha) { Say "$($pin.File): $($pin.Line), already the newest"; return }
	$line = "git:$($p.Repo)@$($p.Branch)#$($p.Sha)"
	$wasTrusted = Test-Trusted $pin.Dir $pin.Line
	Write-PinFile $pin.File $line
	if ($wasTrusted) { Add-Trust $pin.Dir $line }
	Say "$($pin.File): $line"
}

function Invoke-Trust {
	$pin = Find-Pin
	if (-not $pin) { Stop-NoPin }
	if (Test-Trusted $pin.Dir $pin.Line) { Say "already trusted: $($pin.Line) for $($pin.Dir)"; return }
	switch (Read-Trust $pin) {
		0 { Add-Trust $pin.Dir $pin.Line; Say "trusted: $($pin.Line) for $($pin.Dir)" }
		2 { Die 'fp trust asks on a terminal; run it in one' }
		default { Die 'not trusted' }
	}
}

function Invoke-Where {
	$pin = Find-Pin
	if (-not $pin) { Stop-NoPin }
	$p = Get-Pointer $pin.Line
	switch ($p.Kind) {
		'path' { Say $p.Target }
		'git' {
			if (-not $p.Sha) { Die "the git pin in $($pin.File) has no #<sha>; fp upgrade writes its branch's newest" }
			if (Test-Path -LiteralPath $p.Checkout -PathType Container) { Say $p.Checkout } else { Say "$($p.Checkout) (not fetched yet)" }
		}
		'command' { Say $pin.Line }
	}
	Say "pinned in $($pin.File)"
	if (-not (Test-Trusted $pin.Dir $pin.Line)) { Say 'not trusted here yet: fp trust' }
}

# --- running the pin

function New-Checkout($P) {
	Assert-Git
	$repo = "$Cache/git/$($P.Repo).git"
	try { New-Item -ItemType Directory -Force -Path (Split-Path $repo) | Out-Null } catch { Die "cannot write $Cache" }
	if (-not (Test-Path -LiteralPath $repo -PathType Container)) {
		$tmp = "$repo.tmp$PID"
		& git clone -q --bare --filter=blob:none $P.Url $tmp
		if ($LASTEXITCODE -ne 0) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue; Die "cannot clone $($P.Url)" }
		if (-not (Test-Path -LiteralPath $repo)) { Move-Item -LiteralPath $tmp -Destination $repo }
		Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
	}
	& git "--git-dir=$repo" cat-file -e "$($P.Sha)^{commit}" 2>$null
	if ($LASTEXITCODE -ne 0) {
		& git "--git-dir=$repo" fetch -q origin '+refs/heads/*:refs/heads/*'
		if ($LASTEXITCODE -ne 0) { Die "cannot fetch $($P.Url)" }
		& git "--git-dir=$repo" cat-file -e "$($P.Sha)^{commit}" 2>$null
		if ($LASTEXITCODE -ne 0) {
			& git "--git-dir=$repo" fetch -q origin $P.Sha 2>$null
			if ($LASTEXITCODE -ne 0) { Die "no commit $($P.Sha) in $($P.Url)" }
		}
	}
	$tmp = "$($P.Checkout).tmp$PID"
	try { New-Item -ItemType Directory -Force -Path $tmp | Out-Null } catch { Die "cannot write $tmp" }
	$env:GIT_INDEX_FILE = "$tmp.index"
	& git "--git-dir=$repo" "--work-tree=$tmp" read-tree --reset -u $P.Sha
	$code = $LASTEXITCODE
	Remove-Item Env:GIT_INDEX_FILE
	Remove-Item -LiteralPath "$tmp.index" -Force -ErrorAction SilentlyContinue
	if ($code -ne 0) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue; Die "cannot check out $($P.Sha) of $($P.Url)" }
	if (-not (Test-Path -LiteralPath $P.Checkout)) { Move-Item -LiteralPath $tmp -Destination $P.Checkout }
	Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

function Invoke-Target([string]$Dir, $Pin, [string[]]$Rest) {
	$exe = Join-Path $Dir 'bin' 'fp.ps1'
	if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { Die "$exe not found (pinned in $($Pin.File))" }
	$pwsh = [Environment]::ProcessPath
	$opts = @('-NoLogo', '-NoProfile')
	if ($IsWindows) { $opts += @('-ExecutionPolicy', 'Bypass') }
	& $pwsh @opts -File $exe @Rest
	exit $LASTEXITCODE
}

function Invoke-Pinned([string[]]$Rest) {
	$pin = Find-Pin
	if (-not $pin) { Stop-NoPin }
	$p = Get-Pointer $pin.Line
	if (-not (Test-Trusted $pin.Dir $pin.Line)) {
		switch (Read-Trust $pin) {
			0 { Add-Trust $pin.Dir $pin.Line }
			2 { Die "$($pin.File) pins ``$($pin.Line)``, not trusted on this machine yet; a person runs fp trust in a terminal there" }
			default { Die "not run: ``$($pin.Line)`` is not trusted for $($pin.Dir)" }
		}
	}
	switch ($p.Kind) {
		'path' { Invoke-Target $p.Target $pin $Rest }
		'git' {
			if (-not $p.Sha) { Die "the git pin in $($pin.File) has no #<sha>; fp upgrade writes its branch's newest" }
			if (-not (Test-Path -LiteralPath $p.Checkout -PathType Container)) { New-Checkout $p }
			Invoke-Target $p.Checkout $pin $Rest
		}
		'command' {
			Assert-Word $p.Words[0]
			$first, $more = $p.Words
			$more = @($more | Where-Object { $_ -ne $null })
			& $first @more @Rest
			exit $LASTEXITCODE
		}
	}
}

function Assert-NoArgs([string]$Word, [string[]]$Rest) {
	if ($Rest) { Stop-Usage "fp $Word takes no arguments" }
}

[string[]]$all = @($args)
$word = if ($args.Count) { [string]$args[0] } else { '' }
[string[]]$rest = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
switch -CaseSensitive ($word) {
	'--version' { Assert-NoArgs '--version' $rest; Say $FpVersion }
	'init' { Invoke-Init $rest }
	'pin' { Invoke-Pin $rest }
	'upgrade' { Assert-NoArgs 'upgrade' $rest; Invoke-Upgrade }
	'trust' { Assert-NoArgs 'trust' $rest; Invoke-Trust }
	'where' { Assert-NoArgs 'where' $rest; Invoke-Where }
	default { Invoke-Pinned $all }
}
exit 0
