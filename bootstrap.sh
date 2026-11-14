#!/bin/sh
# Standalone entry point: no neighbouring files are needed.
set -eu
main() {
    [ -f /etc/openwrt_release ] || { echo 'Ошибка: нужен OpenWrt' >&2; exit 1; }
    [ "$(id -u)" = 0 ] || { echo 'Ошибка: запустите от root' >&2; exit 1; }
    # The official installer reads interactive answers from the SSH terminal.
    [ -r /dev/tty ] && [ -w /dev/tty ] || {
        echo 'Ошибка: запустите установку в интерактивной SSH-сессии' >&2
        exit 1
    }
    if command -v apk >/dev/null 2>&1; then
        apk update
        apk add ca-bundle curl
    elif command -v opkg >/dev/null 2>&1; then
        opkg update
        opkg install ca-bundle curl
    else
        echo 'Ошибка: не найден opkg/apk' >&2
        exit 1
    fi
    work=$(mktemp -d /tmp/zapret-bootstrap.XXXXXX)
    trap 'rm -rf "$work"' EXIT
    trap 'exit 1' HUP INT TERM
    curl -fL --retry 2 -o "$work/project.tar.gz" \
        https://codeload.github.com/kartavkun/zapret-discord-youtube/tar.gz/refs/heads/openwrt
    tar -xzf "$work/project.tar.gz" -C "$work"
    source_dir=$work/zapret-discord-youtube-openwrt
    for file in setup.sh install.sh utils-zapret.sh openwrt/common.sh configs/config.base; do
        [ -f "$source_dir/$file" ] || {
            echo "Ошибка: в архиве нет $file" >&2
            exit 1
        }
    done
    project=/root/zapret-configs
    # Keep an existing checkout intact until the complete new copy is ready.
    stage=$(mktemp -d /root/.zapret-configs.XXXXXX)
    trap 'rm -rf "$work" "$stage"' EXIT
    cp -R "$source_dir/." "$stage/"
    if [ -e "$project" ]; then
        backup=$(mktemp -d /root/zapret-configs.backup.XXXXXX)
        mv "$project" "$backup/project"
        echo "Предыдущая копия проекта сохранена: $backup/project"
    fi
    mv "$stage" "$project"
    # Do not let an interactive installer consume the remainder of curl | sh.
    sh "$project/setup.sh" "$@" </dev/tty
}
main "$@"
