#!/bin/sh
set -eu
. "$(dirname "$0")/openwrt/common.sh"
case "${1:-help}" in
    help|--help)
        echo 'Использование: sh utils-zapret.sh КОМАНДА [АРГУМЕНТ]'
        echo 'Команды: list, switch ИМЯ, start, stop, restart, status, enable, disable,'
        echo '         game off|tcp|udp|all, log, restore'
        exit 0;;
    list) exec sh "$PROJECT_DIR/install.sh" --list;;
    switch) shift; exec sh "$PROJECT_DIR/install.sh" "$@";;
esac
require_router
[ -x "$SERVICE" ] || fail "служба zapret не установлена"
case "$1" in
    start|stop|restart|status|enable|disable) exec "$SERVICE" "$1";;
    log) logread -e zapret; exit;;
    restore)
        [ -f "$ZAPRET_DIR/config.backup" ] || fail "нет config.backup"
        cp -p "$ZAPRET_DIR/config.backup" "$ZAPRET_DIR/config"
        exec "$SERVICE" restart;;
    game)
        mode=${2:-}
        marker=$ZAPRET_DIR/hostlists/.game_filter.enabled
        case "$mode" in
            off) rm -f "$marker";;
            tcp|udp|all) printf '%s\n' "$mode" > "$marker";;
            *) fail "game off|tcp|udp|all";;
        esac
        exec "$SERVICE" restart;;
    *) fail "неизвестная команда: $1";;
esac
