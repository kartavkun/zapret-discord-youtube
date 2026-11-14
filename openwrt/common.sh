# Shared helpers for BusyBox ash. Source from an entry point.
PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ZAPRET_DIR=/opt/zapret
SERVICE=/etc/init.d/zapret
fail() { echo "Ошибка: $*" >&2; exit 1; }
require_router() {
    [ -f /etc/openwrt_release ] || fail "нужен OpenWrt"
    [ "$(id -u)" = 0 ] || fail "запустите от root"
}
fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 2 -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$2" "$1"
    else
        fail "установите wget и ca-bundle через opkg или apk"
    fi
}
