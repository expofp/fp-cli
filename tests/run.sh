#!/bin/sh
# Runs tests/scenarios.txt against fp under /bin/sh and under dash (each one found).
# usage: tests/run.sh [shell...]      e.g. tests/run.sh dash
# shellcheck disable=SC2016,SC2154,SC2086 # $X is table text; the row's fields come by eval; splitting is meant
set -f
here=$(cd "$(dirname "$0")" && pwd -P)
FP=$here/../fp
TABLE=$here/scenarios.txt
shells=${*:-/bin/sh dash}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/fp-tests.XXXXXX") && TMP=$(cd "$TMP" && pwd -P) || exit 1
trap 'rm -rf "$TMP"' EXIT
FIX=$TMP/fix

replace() { # text from to: sets R
	R='' s=$1
	while :; do
		case $s in
		*"$2"*) R=$R${s%%"$2"*}$3 s=${s#*"$2"} ;;
		*) R=$R$s; break ;;
		esac
	done
}
subst() { # text: sets S
	replace "$1" '$W' "$W"; replace "$R" '$HOME' "$W/home"
	replace "$R" '$SHA1' "$SHA1"; replace "$R" '$SHA2' "$SHA2"; S=$R
}
trim() { T=${1#"${1%%[! ]*}"}; T=${T%"${T##*[! ]}"}; }

# --- fixtures: the PATH, the git repo

mkdir -p "$FIX/bin" "$FIX/nogit"
for t in uname mkdir mv rm grep cat git; do
	p=$(command -v "$t") || continue
	ln -s "$p" "$FIX/bin/$t"
	[ "$t" = git ] || ln -s "$p" "$FIX/nogit/$t"
done
printf '#!/bin/sh\necho "fpecho: $*"\n' >"$FIX/bin/fpecho"
chmod +x "$FIX/bin/fpecho"
cp "$FIX/bin/fpecho" "$FIX/nogit/fpecho"

make_target() { # dir label
	mkdir -p "$1/bin"
	printf '#!/bin/sh\necho "%s: $*"\n[ "$1" = exit ] && exit "$2"\nexit 0\n' "$2" >"$1/bin/fp"
	printf 'Write-Output "%s: $($args -join '"' '"')"\nif ($args[0] -eq "exit") { exit [int]$args[1] }\nexit 0\n' "$2" >"$1/bin/fp.ps1"
	chmod +x "$1/bin/fp"
}

export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=fp GIT_AUTHOR_EMAIL=fp@example.test GIT_COMMITTER_NAME=fp GIT_COMMITTER_EMAIL=fp@example.test
work=$TMP/work
git init -q -b main "$work"
make_target "$work" "git v1"
git -C "$work" add -A && git -C "$work" commit -qm v1
SHA1=$(git -C "$work" rev-parse HEAD)
git -C "$work" checkout -qb next
make_target "$work" "git v2"
git -C "$work" commit -qam v2
SHA2=$(git -C "$work" rev-parse HEAD)
git clone -q --bare "$work" "$FIX/tool.git"
git -C "$FIX/tool.git" config uploadpack.allowFilter true
git -C "$FIX/tool.git" config uploadpack.allowAnySHA1InWant true

# --- one row

fail() { printf 'FAIL %s [%s]: %s\n' "$name" "$sh" "$*"; ok=; }

run_fp() { # dir args... : sets OUT CODE
	d=$1; shift
	OUT=$(cd "$d" && HOME=$W/home PATH=$rowpath "$sh" "$FP" "$@" </dev/null 2>&1)
	CODE=$?
}

row() {
	W=$TMP/w; rm -rf "$W"; mkdir -p "$W/home" "$W/repos/example.test/acme"
	cp -R "$FIX/tool.git" "$W/repos/example.test/acme/tool.git"
	printf '[url "file://%s/repos/example.test/"]\n\tinsteadOf = https://example.test/\n' "$W" >"$W/home/.gitconfig"
	rowpath=$FIX/bin nogit=
	ok=1
	IFS=';'
	for step in $setup; do
		IFS=' '; trim "$step"; subst "$T"; set -- $S
		verb=${1-}; [ $# -gt 0 ] && shift
		case $verb in
		'') ;;
		repo) mkdir -p "$W/$1/.git" ;;
		dir) mkdir -p "$W/$1" ;;
		target) make_target "$W/$1" "${1##*/}" ;;
		write) f=$1; shift; mkdir -p "$(dirname "$W/$f")"; if [ $# -gt 0 ]; then printf '%s\n' "$*"; fi >"$W/$f" ;;
		remove) rm -f "$W/$1" "$W/$1.ps1" ;;
		fp) d=$1; shift; run_fp "$W/$d" "$@"; [ "$CODE" = 0 ] || { fail "setup fp $*: $CODE $OUT"; return; } ;;
		commit) git -C "$W/repos/example.test/acme/tool.git" update-ref refs/heads/main "$SHA2" ;;
		nogit) nogit=1 ;;
		*) fail "unknown setup step $verb"; return ;;
		esac
	done
	IFS=' '
	[ -n "$nogit" ] && rowpath=$FIX/nogit
	subst "$args"
	run_fp "$W/$folder" $S
	[ "$CODE" = "$code" ] || fail "exit $CODE, expected $code; output: $OUT"
	IFS=';'
	for check in $expect; do
		IFS=' '; trim "$check"; subst "$T"; c=$S
		verb=${c%% *} text=${c#* }
		case $verb in
		'') ;;
		out) case $OUT in *"$text"*) ;; *) fail "no \"$text\" in: $OUT" ;; esac ;;
		noout) case $OUT in *"$text"*) fail "\"$text\" in: $OUT" ;; esac ;;
		first | has)
			f=${text%% *} want=${text#* }
			if [ ! -f "$W/$f" ]; then fail "no $f"; continue; fi
			if [ "$verb" = first ]; then
				IFS= read -r got <"$W/$f"; IFS=' '
				[ "$got" = "$want" ] || fail "$f starts with \"$got\", expected \"$want\""
			else
				grep -qxF "$want" "$W/$f" || fail "$f has no line \"$want\""
			fi
			;;
		nofile) [ ! -e "$W/$text" ] || fail "$text exists" ;;
		*) fail "unknown check $verb" ;;
		esac
	done
	IFS=' '
	[ -n "$ok" ]
}

pass=0 failed=0
for sh in $shells; do
	sh=$(command -v "$sh") || { echo "no $sh here, skipped"; continue; }
	while IFS= read -r line; do
		case $line in '' | '#'*) continue ;; esac
		rest=$line
		for v in name setup folder args code expect; do
			case $rest in
			*'|'*) f=${rest%%'|'*} rest=${rest#*'|'} ;;
			*) f=$rest rest= ;;
			esac
			trim "$f"; eval "$v=\$T"
		done
		if row; then pass=$((pass + 1)); else failed=$((failed + 1)); fi
	done <"$TABLE"
done
# --- install.sh, against a fake release: latest is this fp, v0.1.0 an older one, v0.0.1 no fp

REL=$TMP/release
mkdir -p "$REL/latest/download" "$REL/download/v0.1.0" "$REL/download/v0.0.1"
cp "$FP" "$REL/latest/download/fp"
sed 's/^FP_VERSION=.*/FP_VERSION=0.1.0/' "$FP" >"$REL/download/v0.1.0/fp"
printf '<html>Not Found</html>\n' >"$REL/download/v0.0.1/fp"
now=$(sed -n 's/^FP_VERSION=//p' "$FP")
IH=$TMP/ihome

install_case() { # name code expected-output env...
	name=$1 code=$2 want=$3; shift 3
	OUT=$(env HOME="$IH" FP_BASE_URL="file://$REL" "$@" "$sh" "$here/../install.sh" 2>&1)
	CODE=$?
	ok=1
	[ "$CODE" = "$code" ] || fail "exit $CODE, expected $code; output: $OUT"
	case $OUT in *"$want"*) ;; *) fail "no \"$want\" in: $OUT" ;; esac
	installed=$("$IH/.local/bin/fp" --version 2>&1)
}
check_installed() { [ "$installed" = "$1" ] || fail "installed fp says $installed, expected $1"; }
count() { if [ -n "$ok" ]; then pass=$((pass + 1)); else failed=$((failed + 1)); fi; }

for sh in $shells; do
	sh=$(command -v "$sh") || continue
	rm -rf "$IH"; mkdir -p "$IH"
	install_case "install: the latest" 0 "fp $now installed: $IH/.local/bin/fp" PATH="$PATH"; check_installed "$now"; count
	install_case "install: a PATH hint" 0 "$IH/.local/bin is not on your PATH" PATH="$PATH"; count
	install_case "install: no hint on the PATH" 0 "installed" PATH="$IH/.local/bin:$PATH"
	case $OUT in *"not on your PATH"*) fail "a hint: $OUT" ;; esac; count
	install_case "install: FP_VERSION picks one" 0 "fp 0.1.0 installed" FP_VERSION=0.1.0 PATH="$PATH"; check_installed 0.1.0; count
	install_case "install: a v in FP_VERSION" 0 "fp 0.1.0 installed" FP_VERSION=v0.1.0 PATH="$PATH"; check_installed 0.1.0; count
	install_case "install: a rerun upgrades" 0 "fp $now installed" PATH="$PATH"; check_installed "$now"; count
	install_case "install: a missing version" 1 "cannot download file://$REL/download/v9.9.9/fp" FP_VERSION=9.9.9 PATH="$PATH"; check_installed "$now"; count
	install_case "install: a download that is not fp" 1 "is not fp" FP_VERSION=0.0.1 PATH="$PATH"; check_installed "$now"; count
done

echo "$pass passed, $failed failed"
[ "$failed" = 0 ]
