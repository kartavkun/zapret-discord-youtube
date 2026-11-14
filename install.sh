#!/bin/sh
set -eu
. "$(dirname "$0")/openwrt/common.sh"
if [ "${1:-}" = --help ]; then
    echo 'Использование: sh install.sh [имя стратегии | --list]'
    exit 0
fi
if [ "${1:-}" = --list ]; then
    for file in "$PROJECT_DIR"/configs/*; do
        [ -f "$file" ] && [ "${file##*/}" != config.base ] && basename "$file"
    done
    exit 0
fi
require_router
strategy=${1:-general}
case "$strategy" in ''|*/*|config.base) fail "укажите имя стратегии из --list";; esac
strategy_file=$PROJECT_DIR/configs/$strategy
[ -f "$strategy_file" ] || fail "неизвестная стратегия: $strategy"
[ -x "$SERVICE" ] && [ -x "$ZAPRET_DIR/nfq/nfqws" ] || fail "сначала выполните sh setup.sh"
work=$(mktemp -d "$ZAPRET_DIR/.configure.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
# Preserve local network settings separately from the selected strategy.
{
    printf '# %s\n' "$strategy"
    cat "$PROJECT_DIR/configs/config.base"
    printf '\n'
    [ ! -f "$ZAPRET_DIR/config.router" ] || cat "$ZAPRET_DIR/config.router"
    printf '\n'
    cat "$strategy_file"
} > "$work/config"
sh -n "$work/config"
mkdir -p "$ZAPRET_DIR/hostlists" "$ZAPRET_DIR/files/fake"
for file in "$PROJECT_DIR"/hostlists/*.txt; do
    name=${file##*/}
    case "$name" in
        *-user.txt) [ ! -e "$ZAPRET_DIR/hostlists/$name" ] || continue;;
    esac
    cp "$file" "$ZAPRET_DIR/hostlists/$name"
done
# Download only payloads referenced by this strategy, not every upstream asset.
for file in $(grep -oE '/opt/zapret/files/fake/[A-Za-z0-9_.-]+' "$strategy_file" | sort -u); do
    [ ! -s "$file" ] || continue
    name=${file##*/}
    fetch "https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/bin/$name" "$work/$name"
    [ -s "$work/$name" ] || fail "пустой файл $name"
    mv "$work/$name" "$file"
done
# Evaluate in a subshell; do not pollute installation variables with the config.
(
    . "$work/config"
    [ -n "${NFQWS_OPT:-}" ] || fail "NFQWS_OPT пуст"
    set -f
    # Upstream likewise splits NFQWS_OPT into arguments (paths have no spaces).
    "$ZAPRET_DIR/nfq/nfqws" --dry-run $NFQWS_OPT
) || fail "nfqws отклонил стратегию; прежний config сохранён"
backup=$ZAPRET_DIR/config.backup
[ ! -f "$ZAPRET_DIR/config" ] || cp -p "$ZAPRET_DIR/config" "$backup"
mv "$work/config" "$ZAPRET_DIR/config"
if ! "$SERVICE" restart; then
    if [ -f "$backup" ]; then
        cp -p "$backup" "$ZAPRET_DIR/config"
        "$SERVICE" restart || true
    fi
    fail "не удалось перезапустить zapret; восстановлен предыдущий config, если он существовал"
fi
"$SERVICE" enable
echo "Применена стратегия: $strategy. Резервная копия: $backup"
