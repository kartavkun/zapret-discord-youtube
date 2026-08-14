# shellcheck shell=bash
#
# Работа со службой zapret поверх семи систем инициализации.
# Требует common.sh, compat.sh и paths.sh.

[ -n "${ZDY_SERVICE_SOURCED:-}" ] && return 0
ZDY_SERVICE_SOURCED=1

ZDY_SERVICE_MANAGER_CACHE=""

detect_service_manager() {
  if [ -n "$ZDY_SERVICE_MANAGER_CACHE" ]; then
    printf '%s\n' "$ZDY_SERVICE_MANAGER_CACHE"
    return 0
  fi

  local name="$ZDY_SERVICE_NAME" found=""

  if have_cmd systemctl &&
    systemctl list-unit-files "$name.service" --no-legend 2>/dev/null | grep -q .; then
    found="systemd"
  elif have_cmd rc-service && { [ -x "/etc/init.d/$name" ] || rc-service "$name" status >/dev/null 2>&1; }; then
    found="openrc"
  elif have_cmd dinitctl && { [ -e "/etc/dinit.d/$name" ] || [ -e "/usr/lib/dinit.d/$name" ]; }; then
    found="dinit"
  elif have_cmd sv && { [ -e "/var/service/$name" ] || [ -e "/etc/service/$name" ] || [ -d "/etc/sv/$name" ]; }; then
    found="runit"
  elif have_cmd s6-rc && { s6-rc -a list 2>/dev/null | grep -qx "$name" || [ -d "/etc/s6/adminsv/$name" ]; }; then
    found="s6"
  elif [ -e "/etc/rc.d/rc.$name" ]; then
    found="slackware"
  elif have_cmd service && { [ -e "/etc/init.d/$name" ] || service "$name" status >/dev/null 2>&1; }; then
    found="sysvinit"
  fi

  ZDY_SERVICE_MANAGER_CACHE="$found"
  [ -n "$found" ] || return 1
  printf '%s\n' "$found"
}

service_is_active() {
  local manager="$1" name="$ZDY_SERVICE_NAME"

  case "$manager" in
    systemd) systemctl is-active --quiet "$name" ;;
    openrc) rc-service "$name" status >/dev/null 2>&1 ;;
    dinit)
      dinitctl is-started "$name" >/dev/null 2>&1 ||
        dinitctl status "$name" 2>/dev/null | grep -qi 'started'
      ;;
    runit) sv status "$name" 2>/dev/null | grep -q '^run:' ;;
    s6) s6-rc -a list 2>/dev/null | grep -qx "$name" ;;
    slackware)
      # pgrep -f есть не во всех сборках busybox, поэтому читаем procfs.
      [ -n "$(proc_pgrep "$ZAPRET_DIR/nfq/nfqws")$(proc_pgrep "$ZAPRET_DIR/tpws/tpws")" ]
      ;;
    sysvinit) service "$name" status >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

service_is_enabled() {
  local manager="$1" name="$ZDY_SERVICE_NAME"

  case "$manager" in
    systemd) systemctl is-enabled --quiet "$name" ;;
    # SC1087: без фигурных скобок bash разберёт $name[ как индексацию массива.
    openrc) rc-update show default 2>/dev/null | grep -Eq "^[[:space:]]*${name}[[:space:]]" ;;
    dinit)
      dinitctl is-enabled "$name" >/dev/null 2>&1 ||
        [ -e "/etc/dinit.d/boot.d/$name" ] ||
        [ -e "/etc/dinit.d/boot.d/$name.d" ]
      ;;
    runit) [ -e "/var/service/$name" ] || [ -e "/etc/service/$name" ] ;;
    s6) [ -e "/etc/s6/adminsv/default/contents.d/$name" ] ;;
    slackware)
      [ -x "/etc/rc.d/rc.$name" ] && grep -q "rc.$name start" /etc/rc.d/rc.local 2>/dev/null
      ;;
    sysvinit)
      if have_cmd update-rc.d; then
        find /etc/rc*.d -name "S??$name" -print 2>/dev/null | grep -q .
      elif have_cmd chkconfig; then
        chkconfig --list "$name" 2>/dev/null | grep -q ':on'
      else
        return 1
      fi
      ;;
    *) return 1 ;;
  esac
}

service_action() {
  local action="$1" manager name="$ZDY_SERVICE_NAME"

  manager=$(detect_service_manager) || {
    err "Служба $name не найдена ни в одной из поддерживаемых систем инициализации."
    return 1
  }

  require_elevation || return 1

  case "$manager:$action" in
    systemd:*) run_elevated systemctl "$action" "$name" ;;

    openrc:start | openrc:stop | openrc:restart) run_elevated rc-service "$name" "$action" ;;
    openrc:enable) run_elevated rc-update add "$name" default ;;
    openrc:disable) run_elevated rc-update del "$name" default ;;

    dinit:*) run_elevated dinitctl "$action" "$name" ;;

    runit:start) run_elevated sv up "$name" ;;
    runit:stop) run_elevated sv down "$name" ;;
    runit:restart) run_elevated sv restart "$name" ;;
    runit:enable)
      [ -d "/etc/sv/$name" ] || {
        err "Не найден /etc/sv/$name"
        return 1
      }
      if [ -d /var/service ]; then
        run_elevated ln -sfn "/etc/sv/$name" "/var/service/$name"
      elif [ -d /etc/service ]; then
        run_elevated ln -sfn "/etc/sv/$name" "/etc/service/$name"
      else
        err "Не найден каталог /var/service или /etc/service"
        return 1
      fi
      ;;
    runit:disable)
      [ -L "/var/service/$name" ] && run_elevated rm -f "/var/service/$name"
      [ -L "/etc/service/$name" ] && run_elevated rm -f "/etc/service/$name"
      true
      ;;

    s6:start) run_elevated s6-rc -u change "$name" ;;
    s6:stop) run_elevated s6-rc -d change "$name" ;;
    s6:restart)
      run_elevated s6-rc -d change "$name" && run_elevated s6-rc -u change "$name"
      ;;
    s6:enable)
      run_elevated mkdir -p /etc/s6/adminsv/default/contents.d &&
        run_elevated touch "/etc/s6/adminsv/default/contents.d/$name" &&
        run_elevated s6-db-reload
      ;;
    s6:disable)
      run_elevated rm -f "/etc/s6/adminsv/default/contents.d/$name" &&
        run_elevated s6-db-reload
      ;;

    slackware:start | slackware:stop | slackware:restart)
      run_elevated "/etc/rc.d/rc.$name" "$action"
      ;;
    slackware:enable)
      run_elevated chmod +x "/etc/rc.d/rc.$name"
      if ! grep -q "rc.$name start" /etc/rc.d/rc.local 2>/dev/null; then
        printf '\n# Запуск службы zapret\nif [ -x /etc/rc.d/rc.%s ]; then\n  /etc/rc.d/rc.%s start\nfi\n' \
          "$name" "$name" | append_out /etc/rc.d/rc.local
      fi
      ;;
    slackware:disable) run_elevated chmod -x "/etc/rc.d/rc.$name" ;;

    sysvinit:start | sysvinit:stop | sysvinit:restart) run_elevated service "$name" "$action" ;;
    sysvinit:enable)
      if have_cmd update-rc.d; then
        run_elevated update-rc.d "$name" defaults
      elif have_cmd chkconfig; then
        run_elevated chkconfig --add "$name" && run_elevated chkconfig "$name" on
      else
        err "Не найден update-rc.d или chkconfig"
        return 1
      fi
      ;;
    sysvinit:disable)
      if have_cmd update-rc.d; then
        run_elevated update-rc.d "$name" remove
      elif have_cmd chkconfig; then
        run_elevated chkconfig "$name" off
      else
        err "Не найден update-rc.d или chkconfig"
        return 1
      fi
      ;;

    *)
      err "Действие '$action' не поддерживается для $manager"
      return 1
      ;;
  esac
}

restart_zapret() {
  local manager
  manager=$(detect_service_manager) || {
    warn "Система инициализации не определена - перезапустите zapret вручную."
    return 1
  }

  msg "Перезапуск службы zapret..."
  if service_action restart; then
    ok "Служба zapret перезапущена ($manager)"
    return 0
  fi

  err "Не удалось перезапустить службу zapret ($manager)"
  return 1
}

service_status_text() {
  if service_is_active "$1"; then
    printf '%sзапущена%s\n' "$C_GREEN" "$C_RESET"
  else
    printf '%sостановлена%s\n' "$C_RED" "$C_RESET"
  fi
}

service_autostart_text() {
  if service_is_enabled "$1"; then
    printf '%sвключён%s\n' "$C_GREEN" "$C_RESET"
  else
    printf '%sвыключен%s\n' "$C_YELLOW" "$C_RESET"
  fi
}
