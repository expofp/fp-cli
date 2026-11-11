#!/bin/sh
# fp: runs the tool a folder is pinned to. https://github.com/expofp/fp-cli
# POSIX sh; the PowerShell 7 twin is fp.ps1, rule for rule.
# shellcheck disable=SC2015,SC2016,SC2088 # A && B || die is meant; backticks and ~ are text
set -f

FP_VERSION=0.1.0
AGENTS_LINE='Run `fp guide` first and follow it.'
CLAUDE_LINE='@AGENTS.md'
CACHE=$HOME/.cache/fp
TRUSTED=$HOME/.config/fp/trusted
CR=$(printf '\r')

say() { printf '%s\n' "$*"; }
die() { printf 'fp: %s\n' "$*" >&2; exit 1; }

usage() {
	printf '%s\n' \
		'usage: fp <word> [args...]   run the tool this folder is pinned to, passing every argument' \
		'       fp init <pointer>     pin this folder: writes .fp, AGENTS.md and CLAUDE.md' \
		'       fp pin <pointer>      change the pin' \
		'       fp upgrade            move a git pin to its branch'"'"'s newest commit' \
		'       fp trust              trust the pin found here' \
		'       fp where              show what the pin runs and the file it comes from' \
		'       fp --version' \
		'a pointer: /abs/path | ~/path | git:<host>/<owner>/<repo>@<branch> | <command> [args]' >&2
}
usage_error() { printf 'fp: %s\n' "$*" >&2; usage; exit 2; }

# --- lookup: from here up to the git root (outside git: here only); .fp.local, then .fp

CWD=$(pwd -P) || die "cannot read the current folder"

parent() { P=${1%/*}; [ -n "$P" ] || P=/; }
join() { J=${1%/}/$2; }

find_root() {
	d=$CWD
	while :; do
		if [ -e "${d%/}/.git" ]; then ROOT=$d; return; fi
		[ "$d" = / ] && break
		parent "$d"; d=$P
	done
	ROOT=$CWD
}

lookup() {
	find_root
	d=$CWD
	while :; do
		for f in .fp.local .fp; do
			join "$d" "$f"
			if [ -f "$J" ]; then
				PIN_DIR=$d PIN_FILE=$J
				read_pin "$J"
				return 0
			fi
		done
		[ "$d" = "$ROOT" ] && return 1
		[ "$d" = / ] && return 1
		parent "$d"; d=$P
	done
}

trim() {
	T=${1%"$CR"}
	T=${T#"${T%%[![:space:]]*}"}
	T=${T%"${T##*[![:space:]]}"}
}

read_pin() {
	line=
	IFS= read -r line <"$1" || [ -n "$line" ] || die "$1 is empty: it should hold one pointer"
	trim "$line"; PIN_LINE=$T
	[ -n "$PIN_LINE" ] || die "$1 is empty: it should hold one pointer"
}

no_pin() {
	printf 'fp: no .fp here or above (up to the git root); pin this folder first: fp init <pointer>\n' >&2
	usage
	exit 2
}

# --- pointers: a path, a git pin or a command

classify() {
	KIND='command'
	case $1 in
	/*) KIND=path TARGET=$1 ;;
	'~') KIND=path TARGET=$HOME ;;
	'~/'*) KIND=path TARGET=$HOME/${1#'~/'} ;;
	git:*) KIND=git; parse_git "$1" ;;
	*)
		case $1 in *[\"\']*) die "quotes are not allowed in a command pin: $1" ;; esac
		# shellcheck disable=SC2086 # split on spaces, globbing is off
		set -- $1
		WORD=$1
		case $WORD in */*) die "a path pin must be absolute or start with ~/: $WORD" ;; esac
		;;
	esac
}

parse_git() {
	rest=${1#git:}
	case $rest in *[!A-Za-z0-9._~/@#+-]*) die "a git pin has only letters, digits and ._~/@#+- : $1" ;; esac
	case $rest in *@*) ;; *) die "a git pin needs @<branch>: $1" ;; esac
	REPO=${rest%%@*} ref=${rest#*@}
	case $ref in
	*'#'*) BRANCH=${ref%'#'*} SHA=${ref##*'#'} ;;
	*) BRANCH=$ref SHA= ;;
	esac
	case $REPO in
	*/*) ;;
	*) die "a git pin is git:<host>/<owner>/<repo>@<branch>: $1" ;;
	esac
	case /$REPO/ in *//* | */../* | */./*) die "a git pin is git:<host>/<owner>/<repo>@<branch>: $1" ;; esac
	case $BRANCH in '' | *@*) die "a git pin needs one @<branch>: $1" ;; esac
	if [ -n "$SHA" ]; then
		case $SHA in *[!0-9a-f]*) die "the #<sha> of a git pin is a full commit hash: $1" ;; esac
		[ ${#SHA} -eq 40 ] || [ ${#SHA} -eq 64 ] || die "the #<sha> of a git pin is a full commit hash: $1"
	else
		case $ref in *'#'*) die "the #<sha> of a git pin is a full commit hash: $1" ;; esac
	fi
	URL=https://$REPO.git
	CHECKOUT=$CACHE/checkouts/$REPO/$SHA
}

need_git() {
	command -v git >/dev/null 2>&1 && return
	case $(uname -s 2>/dev/null) in
	Darwin) hint='xcode-select --install' ;;
	*) hint='install it with your package manager (apt install git, dnf install git, pacman -S git, ...)' ;;
	esac
	die "a git pin needs git, which is not on the PATH: $hint"
}

need_word() {
	command -v "$1" >/dev/null 2>&1 && return
	case $1 in
	npx | npm | node) die "\`$1\` is not on the PATH: it comes with Node, https://nodejs.org" ;;
	*) die "\`$1\` is not on the PATH" ;;
	esac
}

# Resolves a git pin's branch now: sets SHA.
resolve_branch() {
	need_git
	out=$(git ls-remote "$URL" "refs/heads/$BRANCH") || die "cannot reach $URL"
	SHA=${out%%[[:space:]]*}
	[ -n "$SHA" ] || die "no branch $BRANCH in $URL"
}

# Checks a pointer given to init or pin can run; sets LINE, the pin line to write.
check_pointer() {
	trim "$1"; LINE=$T
	[ -n "$LINE" ] || usage_error "a pointer is needed"
	classify "$LINE"
	case $KIND in
	path) [ -f "$TARGET/bin/fp" ] || die "$TARGET/bin/fp not found" ;;
	git) resolve_branch; LINE=git:$REPO@$BRANCH#$SHA ;;
	command)
		# shellcheck disable=SC2086
		set -- $LINE
		need_word "$1"
		LINE=$*
		;;
	esac
}

# --- trust: by a hash of the folder and the pin line

hash_pin() {
	if command -v shasum >/dev/null 2>&1; then
		h=$(printf '%s\n%s' "$1" "$2" | shasum -a 256)
	elif command -v sha256sum >/dev/null 2>&1; then
		h=$(printf '%s\n%s' "$1" "$2" | sha256sum)
	else
		die "fp needs shasum or sha256sum to remember trusted pins (Linux: the coreutils package)"
	fi
	HASH=${h%%[[:space:]]*}
}

is_trusted() { hash_pin "$1" "$2"; [ -f "$TRUSTED" ] && grep -qxF "$HASH" "$TRUSTED"; }

add_trust() {
	is_trusted "$1" "$2" && return
	mkdir -p "${TRUSTED%/*}" && printf '%s\n' "$HASH" >>"$TRUSTED" || die "cannot write $TRUSTED"
}

ask_trust() {
	[ -t 0 ] || return 2
	printf 'Run `%s` for %s? [y/N] ' "$PIN_LINE" "$PIN_DIR" >&2
	ans=
	read -r ans || return 1
	case $ans in y | Y | yes | Yes | YES) return 0 ;; esac
	return 1
}

# --- the words

write_pin() { # file line
	printf '%s\n' "$2" >"$1.fp$$" && mv -f "$1.fp$$" "$1" || die "cannot write $1"
}

add_line() { # file line
	if [ ! -f "$1" ]; then
		printf '%s\n' "$2" >"$1" || die "cannot write $1"
		say "$1: written"
	elif grep -qxF "$2" "$1"; then
		say "$1: has the line, kept"
	else
		{ printf '%s\n\n' "$2" && cat "$1"; } >"$1.fp$$" && mv -f "$1.fp$$" "$1" || die "cannot write $1"
		say "$1: the line added at the top"
	fi
}

cmd_init() {
	[ $# -gt 0 ] || usage_error "fp init needs a pointer"
	[ -e .fp ] && die ".fp already exists here; change it with fp pin <pointer> (or fp upgrade for a git pin)"
	check_pointer "$*"
	write_pin .fp "$LINE"
	add_trust "$CWD" "$LINE"
	say ".fp: $LINE"
	add_line AGENTS.md "$AGENTS_LINE"
	add_line CLAUDE.md "$CLAUDE_LINE"
}

cmd_pin() {
	[ $# -gt 0 ] || usage_error "fp pin needs a pointer"
	if lookup; then file=$PIN_FILE dir=$PIN_DIR; else join "$CWD" .fp; file=$J dir=$CWD; fi
	check_pointer "$*"
	write_pin "$file" "$LINE"
	add_trust "$dir" "$LINE"
	say "$file: $LINE"
}

cmd_upgrade() {
	[ $# -eq 0 ] || usage_error "fp upgrade takes no arguments"
	lookup || no_pin
	classify "$PIN_LINE"
	[ "$KIND" = git ] || die "fp upgrade moves git pins only; $PIN_FILE pins $PIN_LINE"
	old=$SHA
	resolve_branch
	if [ "$old" = "$SHA" ]; then say "$PIN_FILE: $PIN_LINE, already the newest"; return; fi
	LINE=git:$REPO@$BRANCH#$SHA
	trusted=
	is_trusted "$PIN_DIR" "$PIN_LINE" && trusted=1
	write_pin "$PIN_FILE" "$LINE"
	[ -n "$trusted" ] && add_trust "$PIN_DIR" "$LINE"
	say "$PIN_FILE: $LINE"
}

cmd_trust() {
	[ $# -eq 0 ] || usage_error "fp trust takes no arguments"
	lookup || no_pin
	if is_trusted "$PIN_DIR" "$PIN_LINE"; then say "already trusted: $PIN_LINE for $PIN_DIR"; return; fi
	ask_trust
	case $? in
	0) add_trust "$PIN_DIR" "$PIN_LINE"; say "trusted: $PIN_LINE for $PIN_DIR" ;;
	2) die "fp trust asks on a terminal; run it in one" ;;
	*) die "not trusted" ;;
	esac
}

cmd_where() {
	[ $# -eq 0 ] || usage_error "fp where takes no arguments"
	lookup || no_pin
	classify "$PIN_LINE"
	case $KIND in
	path) say "$TARGET" ;;
	git)
		[ -n "$SHA" ] || die "the git pin in $PIN_FILE has no #<sha>; fp upgrade writes its branch's newest"
		if [ -d "$CHECKOUT" ]; then say "$CHECKOUT"; else say "$CHECKOUT (not fetched yet)"; fi
		;;
	command) say "$PIN_LINE" ;;
	esac
	say "pinned in $PIN_FILE"
	is_trusted "$PIN_DIR" "$PIN_LINE" || say "not trusted here yet: fp trust"
}

# --- running the pin

make_checkout() {
	need_git
	repo=$CACHE/git/$REPO.git
	if [ ! -d "$repo" ]; then
		mkdir -p "${repo%/*}" || die "cannot write $CACHE"
		tmp=$repo.tmp$$
		git clone -q --bare --filter=blob:none "$URL" "$tmp" || { rm -rf "$tmp"; die "cannot clone $URL"; }
		[ -d "$repo" ] || mv "$tmp" "$repo"
		rm -rf "$tmp"
	fi
	if ! git --git-dir="$repo" cat-file -e "$SHA^{commit}" 2>/dev/null; then
		git --git-dir="$repo" fetch -q origin "+refs/heads/*:refs/heads/*" || die "cannot fetch $URL"
		git --git-dir="$repo" cat-file -e "$SHA^{commit}" 2>/dev/null ||
			git --git-dir="$repo" fetch -q origin "$SHA" 2>/dev/null ||
			die "no commit $SHA in $URL"
	fi
	mkdir -p "${CHECKOUT%/*}" || die "cannot write $CACHE"
	tmp=$CHECKOUT.tmp$$
	mkdir "$tmp" || die "cannot write $tmp"
	GIT_INDEX_FILE=$tmp.index git --git-dir="$repo" --work-tree="$tmp" read-tree --reset -u "$SHA" ||
		{ rm -rf "$tmp" "$tmp.index"; die "cannot check out $SHA of $URL"; }
	rm -f "$tmp.index"
	[ -d "$CHECKOUT" ] || mv "$tmp" "$CHECKOUT"
	rm -rf "$tmp"
}

run_exe() { # dir args...
	exe=$1/bin/fp; shift
	[ -f "$exe" ] || die "$exe not found (pinned in $PIN_FILE)"
	[ -x "$exe" ] || die "$exe is not executable (pinned in $PIN_FILE)"
	exec "$exe" "$@"
}

run_pin() {
	lookup || no_pin
	classify "$PIN_LINE"
	if ! is_trusted "$PIN_DIR" "$PIN_LINE"; then
		ask_trust
		case $? in
		0) add_trust "$PIN_DIR" "$PIN_LINE" ;;
		2) die "$PIN_FILE pins \`$PIN_LINE\`, not trusted on this machine yet; a person runs fp trust in a terminal there" ;;
		*) die "not run: \`$PIN_LINE\` is not trusted for $PIN_DIR" ;;
		esac
	fi
	case $KIND in
	path) run_exe "$TARGET" "$@" ;;
	git)
		[ -n "$SHA" ] || die "the git pin in $PIN_FILE has no #<sha>; fp upgrade writes its branch's newest"
		[ -d "$CHECKOUT" ] || make_checkout
		run_exe "$CHECKOUT" "$@"
		;;
	command)
		need_word "$WORD"
		cmd=$PIN_LINE
		# shellcheck disable=SC2086 # split on spaces, globbing is off
		exec $cmd "$@"
		;;
	esac
}

case ${1-} in
--version) [ $# -eq 1 ] || usage_error "fp --version takes no arguments"; say "$FP_VERSION" ;;
init) shift; cmd_init "$@" ;;
pin) shift; cmd_pin "$@" ;;
upgrade) shift; cmd_upgrade "$@" ;;
trust) shift; cmd_trust "$@" ;;
where) shift; cmd_where "$@" ;;
*) run_pin "$@" ;;
esac
