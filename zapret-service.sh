#!/bin/sh

ZAPRET_ROOT=${ZAPRET_ROOT:-/opt/zapret}
ZAPRET_SERVICE_NAME=${ZAPRET_SERVICE_NAME:-zapret}
ZAPRET_ELEVATE_CMD=${ZAPRET_ELEVATE_CMD:-}

zapret_run_elevated()
{
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif [ -n "$ZAPRET_ELEVATE_CMD" ]; then
        $ZAPRET_ELEVATE_CMD "$@"
    else
        echo "zapret: root privileges are required" >&2
        return 1
    fi
}

zapret_detect_service_manager()
{
    if command -v systemctl >/dev/null 2>&1 &&
        { [ -f "/etc/systemd/system/$ZAPRET_SERVICE_NAME.service" ] ||
          [ -f "/lib/systemd/system/$ZAPRET_SERVICE_NAME.service" ] ||
          [ -f "/usr/lib/systemd/system/$ZAPRET_SERVICE_NAME.service" ] ||
          systemctl list-unit-files "$ZAPRET_SERVICE_NAME.service" --no-legend 2>/dev/null | grep -q .; }; then
        echo systemd
        return 0
    fi

    if command -v rc-service >/dev/null 2>&1 &&
        { [ -x "/etc/init.d/$ZAPRET_SERVICE_NAME" ] ||
          rc-service "$ZAPRET_SERVICE_NAME" status >/dev/null 2>&1; }; then
        echo openrc
        return 0
    fi

    if command -v dinitctl >/dev/null 2>&1 &&
        { [ -e "/etc/dinit.d/$ZAPRET_SERVICE_NAME" ] ||
          [ -e "/usr/lib/dinit.d/$ZAPRET_SERVICE_NAME" ]; }; then
        echo dinit
        return 0
    fi

    if command -v sv >/dev/null 2>&1 &&
        { [ -e "/var/service/$ZAPRET_SERVICE_NAME" ] ||
          [ -e "/etc/service/$ZAPRET_SERVICE_NAME" ] ||
          [ -d "/etc/sv/$ZAPRET_SERVICE_NAME" ]; }; then
        echo runit
        return 0
    fi

    if command -v s6-rc >/dev/null 2>&1 &&
        { [ -d "/etc/s6/adminsv/$ZAPRET_SERVICE_NAME" ] ||
          s6-rc -a list 2>/dev/null | grep -qx "$ZAPRET_SERVICE_NAME"; }; then
        echo s6
        return 0
    fi

    if [ -e "/etc/rc.d/rc.$ZAPRET_SERVICE_NAME" ]; then
        echo slackware
        return 0
    fi

    if command -v service >/dev/null 2>&1 &&
        { [ -e "/etc/init.d/$ZAPRET_SERVICE_NAME" ] ||
          service "$ZAPRET_SERVICE_NAME" status >/dev/null 2>&1; }; then
        echo sysvinit
        return 0
    fi

    return 1
}

zapret_detect_init_system()
{
    if [ -f /etc/os-release ] && grep -q '^NAME="?Slackware' /etc/os-release; then
        echo slackware
        return 0
    fi

    zapret_init_name=$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')
    case "$zapret_init_name" in
        systemd)
            echo systemd
            return 0
            ;;
        dinit)
            echo dinit
            return 0
            ;;
        runit|runit-init)
            echo runit
            return 0
            ;;
        s6-svscan)
            echo s6
            return 0
            ;;
        openrc-init)
            echo openrc
            return 0
            ;;
    esac

    if command -v rc-service >/dev/null 2>&1 && command -v rc-update >/dev/null 2>&1; then
        echo openrc
    elif command -v dinitctl >/dev/null 2>&1; then
        echo dinit
    elif command -v sv >/dev/null 2>&1; then
        echo runit
    elif command -v s6-rc >/dev/null 2>&1; then
        echo s6
    elif command -v service >/dev/null 2>&1 ||
        command -v update-rc.d >/dev/null 2>&1 ||
        command -v chkconfig >/dev/null 2>&1; then
        echo sysvinit
    else
        return 1
    fi
}

zapret_service_is_active()
{
    zapret_manager=$1
    case "$zapret_manager" in
        systemd)
            systemctl is-active --quiet "$ZAPRET_SERVICE_NAME"
            ;;
        openrc)
            rc-service "$ZAPRET_SERVICE_NAME" status >/dev/null 2>&1
            ;;
        dinit)
            dinitctl is-started "$ZAPRET_SERVICE_NAME" >/dev/null 2>&1 ||
                dinitctl status "$ZAPRET_SERVICE_NAME" 2>/dev/null | grep -qi started
            ;;
        runit)
            sv status "$ZAPRET_SERVICE_NAME" 2>/dev/null | grep -q '^run:'
            ;;
        s6)
            s6-rc -a -u list 2>/dev/null | grep -qx "$ZAPRET_SERVICE_NAME"
            ;;
        slackware)
            pgrep -f "$ZAPRET_ROOT/.*/nfqws|$ZAPRET_ROOT/.*/tpws|$ZAPRET_ROOT/nfq/nfqws|$ZAPRET_ROOT/tpws/tpws" >/dev/null 2>&1
            ;;
        sysvinit)
            if command -v service >/dev/null 2>&1; then
                service "$ZAPRET_SERVICE_NAME" status >/dev/null 2>&1
            else
                "/etc/init.d/$ZAPRET_SERVICE_NAME" status >/dev/null 2>&1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

zapret_service_is_enabled()
{
    zapret_manager=$1
    case "$zapret_manager" in
        systemd)
            systemctl is-enabled --quiet "$ZAPRET_SERVICE_NAME"
            ;;
        openrc)
            rc-update show default 2>/dev/null | grep -Eq "^[[:space:]]*$ZAPRET_SERVICE_NAME[[:space:]]"
            ;;
        dinit)
            dinitctl is-enabled "$ZAPRET_SERVICE_NAME" >/dev/null 2>&1 ||
                [ -e "/etc/dinit.d/boot.d/$ZAPRET_SERVICE_NAME" ] ||
                [ -e "/etc/dinit.d/boot.d/$ZAPRET_SERVICE_NAME.d" ]
            ;;
        runit)
            [ -e "/var/service/$ZAPRET_SERVICE_NAME" ] ||
                [ -e "/etc/service/$ZAPRET_SERVICE_NAME" ]
            ;;
        s6)
            [ -e "/etc/s6/adminsv/default/contents.d/$ZAPRET_SERVICE_NAME" ]
            ;;
        slackware)
            [ -x "/etc/rc.d/rc.$ZAPRET_SERVICE_NAME" ] &&
                grep -q "rc.$ZAPRET_SERVICE_NAME start" /etc/rc.d/rc.local 2>/dev/null
            ;;
        sysvinit)
            if command -v update-rc.d >/dev/null 2>&1; then
                find /etc/rc*.d -name "S??$ZAPRET_SERVICE_NAME" -print -quit 2>/dev/null | grep -q .
            elif command -v chkconfig >/dev/null 2>&1; then
                chkconfig --list "$ZAPRET_SERVICE_NAME" 2>/dev/null | grep -q ':on'
            else
                return 1
            fi
            ;;
        *)
            return 1
            ;;
    esac
}

zapret_service_action()
{
    zapret_action=$1
    zapret_manager=${2:-}
    [ -n "$zapret_manager" ] || zapret_manager=$(zapret_detect_service_manager) || return 1

    case "$zapret_manager:$zapret_action" in
        systemd:start|systemd:stop|systemd:restart|systemd:enable|systemd:disable)
            zapret_run_elevated systemctl "$zapret_action" "$ZAPRET_SERVICE_NAME"
            ;;
        openrc:start|openrc:stop|openrc:restart)
            zapret_run_elevated rc-service "$ZAPRET_SERVICE_NAME" "$zapret_action"
            ;;
        openrc:enable)
            zapret_run_elevated rc-update add "$ZAPRET_SERVICE_NAME" default
            ;;
        openrc:disable)
            zapret_run_elevated rc-update del "$ZAPRET_SERVICE_NAME" default
            ;;
        dinit:start|dinit:stop|dinit:restart|dinit:enable|dinit:disable)
            zapret_run_elevated dinitctl "$zapret_action" "$ZAPRET_SERVICE_NAME"
            ;;
        runit:start)
            zapret_run_elevated sv up "$ZAPRET_SERVICE_NAME"
            ;;
        runit:stop)
            zapret_run_elevated sv down "$ZAPRET_SERVICE_NAME"
            ;;
        runit:restart)
            zapret_run_elevated sv restart "$ZAPRET_SERVICE_NAME"
            ;;
        runit:enable)
            if [ -d /var/service ]; then
                zapret_run_elevated ln -sfn "/etc/sv/$ZAPRET_SERVICE_NAME" "/var/service/$ZAPRET_SERVICE_NAME"
            elif [ -d /etc/service ]; then
                zapret_run_elevated ln -sfn "/etc/sv/$ZAPRET_SERVICE_NAME" "/etc/service/$ZAPRET_SERVICE_NAME"
            else
                echo "zapret: runit service directory not found" >&2
                return 1
            fi
            ;;
        runit:disable)
            [ ! -L "/var/service/$ZAPRET_SERVICE_NAME" ] ||
                zapret_run_elevated rm -f "/var/service/$ZAPRET_SERVICE_NAME"
            [ ! -L "/etc/service/$ZAPRET_SERVICE_NAME" ] ||
                zapret_run_elevated rm -f "/etc/service/$ZAPRET_SERVICE_NAME"
            ;;
        s6:start)
            zapret_run_elevated s6-rc -u change "$ZAPRET_SERVICE_NAME"
            ;;
        s6:stop)
            zapret_run_elevated s6-rc -d change "$ZAPRET_SERVICE_NAME"
            ;;
        s6:restart)
            zapret_run_elevated s6-rc -d change "$ZAPRET_SERVICE_NAME" &&
                zapret_run_elevated s6-rc -u change "$ZAPRET_SERVICE_NAME"
            ;;
        s6:enable)
            zapret_run_elevated mkdir -p /etc/s6/adminsv/default/contents.d &&
                zapret_run_elevated touch "/etc/s6/adminsv/default/contents.d/$ZAPRET_SERVICE_NAME" &&
                zapret_run_elevated s6-db-reload
            ;;
        s6:disable)
            zapret_run_elevated rm -f "/etc/s6/adminsv/default/contents.d/$ZAPRET_SERVICE_NAME" &&
                zapret_run_elevated s6-db-reload
            ;;
        slackware:start|slackware:stop|slackware:restart)
            zapret_run_elevated "/etc/rc.d/rc.$ZAPRET_SERVICE_NAME" "$zapret_action"
            ;;
        slackware:enable)
            zapret_run_elevated chmod +x "/etc/rc.d/rc.$ZAPRET_SERVICE_NAME" || return 1
            if ! grep -q "rc.$ZAPRET_SERVICE_NAME start" /etc/rc.d/rc.local 2>/dev/null; then
                printf '\n# Start zapret\nif [ -x /etc/rc.d/rc.zapret ]; then\n  /etc/rc.d/rc.zapret start\nfi\n' |
                    zapret_run_elevated tee -a /etc/rc.d/rc.local >/dev/null
            fi
            ;;
        slackware:disable)
            zapret_run_elevated chmod -x "/etc/rc.d/rc.$ZAPRET_SERVICE_NAME"
            ;;
        sysvinit:start|sysvinit:stop|sysvinit:restart)
            if command -v service >/dev/null 2>&1; then
                zapret_run_elevated service "$ZAPRET_SERVICE_NAME" "$zapret_action"
            else
                zapret_run_elevated "/etc/init.d/$ZAPRET_SERVICE_NAME" "$zapret_action"
            fi
            ;;
        sysvinit:enable)
            if command -v update-rc.d >/dev/null 2>&1; then
                zapret_run_elevated update-rc.d "$ZAPRET_SERVICE_NAME" defaults
            elif command -v chkconfig >/dev/null 2>&1; then
                zapret_run_elevated chkconfig --add "$ZAPRET_SERVICE_NAME" &&
                    zapret_run_elevated chkconfig "$ZAPRET_SERVICE_NAME" on
            else
                echo "zapret: update-rc.d or chkconfig not found" >&2
                return 1
            fi
            ;;
        sysvinit:disable)
            if command -v update-rc.d >/dev/null 2>&1; then
                zapret_run_elevated update-rc.d "$ZAPRET_SERVICE_NAME" remove
            elif command -v chkconfig >/dev/null 2>&1; then
                zapret_run_elevated chkconfig "$ZAPRET_SERVICE_NAME" off
            else
                return 1
            fi
            ;;
        *)
            echo "zapret: action '$zapret_action' is not supported for '$zapret_manager'" >&2
            return 1
            ;;
    esac
}

zapret_download_file()
{
    zapret_url=$1
    zapret_output=$2
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$zapret_output" "$zapret_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$zapret_output" "$zapret_url"
    else
        return 1
    fi
}

zapret_prepare_dinit()
{
    [ -f "$ZAPRET_ROOT/init.d/dinit/zapret" ] && return 0

    zapret_dinit_commit=0f9f0bd74e1dca5f6a3def00bf88d7bf177cab2a
    zapret_dinit_url="https://raw.githubusercontent.com/Lintech-1/zapret/$zapret_dinit_commit/init.d/dinit"
    zapret_dinit_tmp=$(mktemp -d "${TMPDIR:-/tmp}/zapret-dinit.XXXXXX") || return 1

    for zapret_dinit_file in zapret-start.sh zapret-stop.sh zapret; do
        if ! zapret_download_file "$zapret_dinit_url/$zapret_dinit_file" "$zapret_dinit_tmp/$zapret_dinit_file"; then
            rm -rf "$zapret_dinit_tmp"
            return 1
        fi
    done

    zapret_run_elevated mkdir -p "$ZAPRET_ROOT/init.d/dinit" &&
        zapret_run_elevated cp "$zapret_dinit_tmp/zapret-start.sh" "$ZAPRET_ROOT/init.d/dinit/zapret-start.sh" &&
        zapret_run_elevated cp "$zapret_dinit_tmp/zapret-stop.sh" "$ZAPRET_ROOT/init.d/dinit/zapret-stop.sh" &&
        zapret_run_elevated cp "$zapret_dinit_tmp/zapret" "$ZAPRET_ROOT/init.d/dinit/zapret"
    zapret_dinit_status=$?
    rm -rf "$zapret_dinit_tmp"
    [ "$zapret_dinit_status" -eq 0 ] || return "$zapret_dinit_status"

    zapret_run_elevated chmod 755 \
        "$ZAPRET_ROOT/init.d/dinit/zapret-start.sh" \
        "$ZAPRET_ROOT/init.d/dinit/zapret-stop.sh"
    zapret_run_elevated chmod 644 "$ZAPRET_ROOT/init.d/dinit/zapret"
}

zapret_install_service()
{
    zapret_manager=${1:-}
    [ -n "$zapret_manager" ] || zapret_manager=$(zapret_detect_init_system) || {
        echo "zapret: could not detect the init system" >&2
        return 1
    }

    case "$zapret_manager" in
        systemd)
            [ -f "$ZAPRET_ROOT/init.d/systemd/zapret.service" ] || return 1
            zapret_run_elevated cp "$ZAPRET_ROOT/init.d/systemd/zapret.service" "/etc/systemd/system/$ZAPRET_SERVICE_NAME.service" &&
                zapret_run_elevated chmod 644 "/etc/systemd/system/$ZAPRET_SERVICE_NAME.service" &&
                zapret_run_elevated systemctl daemon-reload
            ;;
        openrc)
            [ -f "$ZAPRET_ROOT/init.d/openrc/zapret" ] || return 1
            zapret_run_elevated chmod 755 "$ZAPRET_ROOT/init.d/openrc/zapret" &&
                zapret_run_elevated ln -sfn "$ZAPRET_ROOT/init.d/openrc/zapret" "/etc/init.d/$ZAPRET_SERVICE_NAME"
            ;;
        dinit)
            zapret_prepare_dinit || return 1
            zapret_run_elevated mkdir -p /etc/dinit.d &&
                zapret_run_elevated ln -sfn "$ZAPRET_ROOT/init.d/dinit/zapret" "/etc/dinit.d/$ZAPRET_SERVICE_NAME"
            ;;
        runit)
            [ -d "$ZAPRET_ROOT/init.d/runit/zapret" ] || return 1
            zapret_run_elevated mkdir -p "/etc/sv/$ZAPRET_SERVICE_NAME" &&
                zapret_run_elevated cp -R "$ZAPRET_ROOT/init.d/runit/zapret/." "/etc/sv/$ZAPRET_SERVICE_NAME/"
            ;;
        s6)
            [ -d "$ZAPRET_ROOT/init.d/s6/zapret" ] || return 1
            zapret_run_elevated mkdir -p "/etc/s6/adminsv/$ZAPRET_SERVICE_NAME" &&
                zapret_run_elevated cp -R "$ZAPRET_ROOT/init.d/s6/zapret/." "/etc/s6/adminsv/$ZAPRET_SERVICE_NAME/"
            ;;
        slackware)
            [ -f "$ZAPRET_ROOT/init.d/sysv/zapret" ] || return 1
            zapret_run_elevated mkdir -p /etc/rc.d &&
                zapret_run_elevated ln -sfn "$ZAPRET_ROOT/init.d/sysv/zapret" "/etc/rc.d/rc.$ZAPRET_SERVICE_NAME"
            ;;
        sysvinit)
            [ -f "$ZAPRET_ROOT/init.d/sysv/zapret" ] || return 1
            zapret_run_elevated chmod 755 "$ZAPRET_ROOT/init.d/sysv/zapret" &&
                zapret_run_elevated ln -sfn "$ZAPRET_ROOT/init.d/sysv/zapret" "/etc/init.d/$ZAPRET_SERVICE_NAME"
            ;;
        *)
            return 1
            ;;
    esac || return 1

    zapret_service_action enable "$zapret_manager" || return 1
    if zapret_service_is_active "$zapret_manager"; then
        zapret_service_action restart "$zapret_manager"
    else
        zapret_service_action start "$zapret_manager"
    fi
}
