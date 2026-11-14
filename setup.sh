#!/bin/sh
# Run from a local checkout/archive of the openwrt branch.
set -eu
. "$(dirname "$0")/openwrt/common.sh"
require_router
# An existing installation is never replaced implicitly.
if [ -x "$ZAPRET_DIR/nfq/nfqws" ] && [ -x "$SERVICE" ]; then
    exec sh "$PROJECT_DIR/install.sh" "${1:-general}"
fi
if [ "$#" -gt 0 ]; then
    upstream=$(CDPATH= cd -- "$1" && pwd)
    [ -f "$upstream/install_easy.sh" ] || fail "нет install_easy.sh в $upstream"
    (cd "$upstream" && sh ./install_easy.sh)
else
    work=$(mktemp -d /tmp/zapret-install.XXXXXX)
    trap 'rm -rf "$work"' EXIT HUP INT TERM
    fetch https://api.github.com/repos/bol-van/zapret/releases/latest "$work/release.json"
    version=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$work/release.json" | head -n 1)
    case "$version" in ''|*[!a-zA-Z0-9._-]*) fail "не удалось определить версию zapret";; esac
    fetch "https://github.com/bol-van/zapret/releases/download/$version/zapret-$version.tar.gz" "$work/zapret.tar.gz"
    tar -xzf "$work/zapret.tar.gz" -C "$work"
    upstream=
    for dir in "$work"/zapret-*/; do
        [ -f "$dir/install_easy.sh" ] && upstream=$dir
    done
    [ -n "$upstream" ] || fail "в архиве нет install_easy.sh"
    (cd "$upstream" && sh ./install_easy.sh)
fi
[ -x "$SERVICE" ] && [ -x "$ZAPRET_DIR/nfq/nfqws" ] || fail "штатная установка zapret не завершена"
sh "$PROJECT_DIR/install.sh" general
