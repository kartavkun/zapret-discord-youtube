# shellcheck shell=bash
#
# Модуль подключается из bin/*, а не сам по себе: общие функции и пути
# приходят из lib/common.sh, lib/compat.sh и lib/paths.sh, подключённых
# вызывающим скриптом раньше. Отсюда директивы source ниже - без них
# shellcheck считает эти имена неопределёнными.
# shellcheck source=common.sh
# shellcheck source=compat.sh
# shellcheck source=paths.sh
# shellcheck source=service.sh
# shellcheck source=lists.sh
# shellcheck source=autorestart.sh
#
# Удаление всего, что ставит проект.
#
# Раньше пути назад не было: после установки на машине оставались
# /opt/zapret, блок в /etc/hosts, симлинки в ~/.local/bin, systemd-таймер,
# файл в /etc/sysctl.d, SELinux-модуль и каталоги состояния. Вычищать это
# руками нереалистично, а значит проект нельзя было честно "попробовать".
#
# Принцип: сначала показать полный список того, что будет удалено, и только
# потом спрашивать подтверждение. Ничего не удаляется молча.

[ -n "${ZDY_UNINSTALL_SOURCED:-}" ] && return 0
ZDY_UNINSTALL_SOURCED=1

# Каждый пункт: "признак наличия<TAB>описание<TAB>тег"
uninstall_plan() {
  local init

  [ -d "$ZAPRET_DIR" ] &&
    printf '%s\t%s\n' "$ZAPRET_DIR" "каталог zapret вместе со стратегиями и фиксами"
  [ -d "$ZAPRET_DIR.bak" ] &&
    printf '%s\t%s\n' "$ZAPRET_DIR.bak" "резервная копия предыдущей установки zapret"

  if init=$(detect_service_manager 2>/dev/null); then
    printf '%s\t%s\n' "служба zapret" "будет остановлена и снята с автозапуска ($init)"
  fi

  [ "$(autorestart_status 2>/dev/null)" != "off" ] &&
    printf '%s\t%s\n' "таймер автоперезапуска" "systemd-юниты"

  [ -e "$ZDY_AUTORESTART_HELPER" ] &&
    printf '%s\t%s\n' "$ZDY_AUTORESTART_HELPER" "helper планового перезапуска"
  [ -e "$ZDY_AUTORESTART_LOG" ] &&
    printf '%s\t%s\n' "$ZDY_AUTORESTART_LOG" "лог плановых перезапусков"
  [ -d "$ZDY_AUTORESTART_SNAPSHOT_DIR" ] &&
    printf '%s\t%s\n' "$ZDY_AUTORESTART_SNAPSHOT_DIR" "слепки от планового перезапуска"

  hosts_has_block 2>/dev/null &&
    printf '%s\t%s\n' "$ZDY_HOSTS_FILE" "блок zapret между маркерами (остальное не тронем)"

  [ -e /etc/sysctl.d/90-zapret-tcp-timestamps.conf ] &&
    printf '%s\t%s\n' "/etc/sysctl.d/90-zapret-tcp-timestamps.conf" "настройка tcp_timestamps"

  local cmd
  for cmd in "${ZDY_COMMANDS[@]}" zapret-utils; do
    [ -L "$ZDY_USER_BIN/$cmd" ] &&
      printf '%s\t%s\n' "$ZDY_USER_BIN/$cmd" "симлинк команды"
  done

  [ -d "$ZDY_INSTALL_DIR" ] &&
    printf '%s\t%s\n' "$ZDY_INSTALL_DIR" "копия проекта"
  [ -d "$ZDY_LEGACY_DIR" ] &&
    printf '%s\t%s\n' "$ZDY_LEGACY_DIR" "копия проекта в старом месте"
  [ -d "$ZDY_CACHE_DIR" ] &&
    printf '%s\t%s\n' "$ZDY_CACHE_DIR" "кеш загрузок"

  return 0
}

uninstall_show_plan() {
  local target description found=0

  msg "Будет удалено:"
  printf '\n'
  while IFS=$'\t' read -r target description; do
    [ -n "$target" ] || continue
    found=1
    printf '  %s\n' "$target"
    printf '      %s%s%s\n' "$C_DIM" "$description" "$C_RESET"
  done < <(uninstall_plan)

  if [ "$found" = "0" ]; then
    warn "Похоже, ничего из установленного не найдено."
    return 1
  fi

  printf '\n'
  msg "Будет сохранено:"
  printf '  %s\n' "$ZDY_STATE_DIR"
  printf '      %sсостояние, резервные копии, логи и снимки инцидентов%s\n' "$C_DIM" "$C_RESET"
  hint "Их можно удалить отдельно: zapret-setup --uninstall --purge"
  printf '\n'
}

uninstall_stop_service() {
  # Если менеджер служб не определился, останавливать нечего.
  detect_service_manager >/dev/null 2>&1 || return 0

  msg "Останавливаю службу..."
  service_action stop >/dev/null 2>&1 || warn "Служба уже была остановлена"
  service_action disable >/dev/null 2>&1 || warn "Автозапуск уже был отключён"
  ok "Служба остановлена и снята с автозапуска"
}

uninstall_selinux_module() {
  have_cmd semodule || return 0
  local name
  for name in zapret zapret-bazzite zapret-secureblue; do
    if semodule -l 2>/dev/null | grep -qx "$name"; then
      msg "Удаляю SELinux-модуль $name..."
      run_elevated semodule -r "$name" >/dev/null 2>&1 ||
        warn "Не удалось удалить модуль $name"
    fi
  done
  if have_cmd semanage; then
    run_elevated semanage fcontext -d "$ZAPRET_DIR(/.*)?" >/dev/null 2>&1 || true
    run_elevated semanage fcontext -d "$ZAPRET_DIR/init.d/sysv/zapret" >/dev/null 2>&1 || true
  fi
}

uninstall_commands() {
  local cmd
  for cmd in "${ZDY_COMMANDS[@]}" zapret-utils; do
    [ -L "$ZDY_USER_BIN/$cmd" ] && rm -f "$ZDY_USER_BIN/$cmd"
  done
  remove_legacy_aliases >/dev/null 2>&1 || true
  ok "Команды удалены"
}

# Основной сценарий. purge=1 - удалить ещё и состояние со снимками.
uninstall_run() {
  local purge="${1:-0}"

  msg "=== Удаление zapret-discord-youtube ==="
  printf '\n'

  uninstall_show_plan || return 1

  if [ "$purge" = "1" ]; then
    warn "Режим --purge: состояние, бэкапы и снимки инцидентов тоже будут удалены."
    printf '\n'
  fi

  ask_yes_no "Удалить всё перечисленное?" n || {
    msg "Удаление отменено"
    return 1
  }

  require_elevation || return 1

  uninstall_stop_service
  autorestart_disable >/dev/null 2>&1 || true

  # autorestart_disable оставляет helper и лог намеренно - при удалении
  # проекта их держать уже незачем.
  local leftover
  for leftover in "$ZDY_AUTORESTART_HELPER" "$ZDY_AUTORESTART_LOG"; do
    [ -e "$leftover" ] && rm_out "$leftover"
  done
  if [ -d "$ZDY_AUTORESTART_SNAPSHOT_DIR" ]; then
    run_elevated rm -rf -- "$ZDY_AUTORESTART_SNAPSHOT_DIR" &&
      ok "Слепки планового перезапуска удалены"
  fi
  [ -d "$ZDY_HELPER_DIR" ] && run_elevated rmdir "$ZDY_HELPER_DIR" 2>/dev/null
  true
  uninstall_selinux_module

  if hosts_has_block; then
    msg "Убираю блок из $ZDY_HOSTS_FILE..."
    local new
    new=$(zdy_tempfile) || return 1
    hosts_without_block >"$new"
    hosts_backup || warn "Резервную копию hosts сделать не удалось"
    write_out "$ZDY_HOSTS_FILE" <"$new" && ok "Блок из hosts удалён"
  fi

  if [ -e /etc/sysctl.d/90-zapret-tcp-timestamps.conf ]; then
    rm_out /etc/sysctl.d/90-zapret-tcp-timestamps.conf
    ok "Настройка sysctl удалена"
  fi

  local dir
  for dir in "$ZAPRET_DIR" "$ZAPRET_DIR.bak"; do
    if [ -d "$dir" ]; then
      msg "Удаляю $dir..."
      run_elevated rm -rf -- "$dir" && ok "$dir удалён"
    fi
  done

  uninstall_commands

  # Каталог проекта удаляется последним и не самим собой: этот скрипт
  # выполняется из него, а bash дочитывает файл с диска по ходу работы.
  for dir in "$ZDY_INSTALL_DIR" "$ZDY_LEGACY_DIR" "$ZDY_CACHE_DIR"; do
    [ -d "$dir" ] || continue
    case "$ZDY_ROOT" in
      "$dir" | "$dir"/*)
        warn "Каталог $dir удалить отсюда нельзя - из него сейчас выполняется скрипт."
        hint "Удалите вручную: rm -rf \"$dir\""
        continue
        ;;
    esac
    rm -rf -- "$dir" && ok "$dir удалён"
  done

  if [ "$purge" = "1" ]; then
    rm -rf -- "$ZDY_STATE_DIR" && ok "Состояние и снимки удалены"
  else
    hint "Состояние сохранено: $ZDY_STATE_DIR"
  fi

  printf '\n'
  ok "Удаление завершено."
}
