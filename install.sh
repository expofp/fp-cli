#!/bin/sh
# Installs fp on macOS and Linux, or upgrades it:
#   curl -fsSL https://raw.githubusercontent.com/expofp/fp-cli/main/install.sh | sh
# Puts fp from the latest release (FP_VERSION=0.2.0 picks one) into ~/.local/bin. No sudo, no
# shell file edited. FP_BASE_URL replaces the releases' address, for tests.
# shellcheck disable=SC2088,SC2016 # the ~ and $ in hints are for the person to paste
set -eu

base=${FP_BASE_URL:-https://github.com/expofp/fp-cli/releases}
version=${FP_VERSION:-}
version=${version#v}
if [ -n "$version" ]; then url=$base/download/v$version/fp; else url=$base/latest/download/fp; fi
dir=$HOME/.local/bin

die() { printf 'fp install: %s\n' "$*" >&2; exit 1; }

mkdir -p "$dir" || die "cannot make $dir"
tmp=$dir/.fp.tmp$$
trap 'rm -f "$tmp"' EXIT
if command -v curl >/dev/null 2>&1; then
	curl -fsSL "$url" -o "$tmp" || die "cannot download $url"
elif command -v wget >/dev/null 2>&1; then
	wget -qO "$tmp" "$url" || die "cannot download $url"
else
	die "needs curl or wget to download fp"
fi
got=$(sed -n 's/^FP_VERSION=//p' "$tmp")
[ -n "$got" ] || die "$url is not fp"
chmod +x "$tmp"
mv -f "$tmp" "$dir/fp" || die "cannot write $dir/fp"
printf 'fp %s installed: %s\n' "$got" "$dir/fp"

case ":$PATH:" in
*":$dir:"*) ;;
*)
	case ${SHELL##*/} in
	zsh) rc='~/.zshrc' ;;
	bash) if [ "$(uname -s)" = Darwin ]; then rc='~/.bash_profile'; else rc='~/.bashrc'; fi ;;
	fish) rc= ;;
	*) rc='~/.profile' ;;
	esac
	printf '%s is not on your PATH; to add it:\n' "$dir"
	if [ -n "$rc" ]; then printf '  echo '"'"'export PATH="$HOME/.local/bin:$PATH"'"'"' >> %s\n' "$rc"; else printf '  fish_add_path ~/.local/bin\n'; fi
	printf 'then open a new terminal.\n'
	;;
esac
