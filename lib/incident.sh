# shellcheck shell=bash
#
# Снимок состояния перед перезапуском службы.
#
# Смысл: перезапуск лечит симптом и одновременно уничтожает улики. Если
# сначала не снять состояние, через месяц у нас будет только ощущение
# "иногда подтупливает" и ни одного факта. Снимаем ровно то, что после
# перезапуска уже не восстановить.
#
# Снимок делается без повышения привилегий: всё читается из procfs и
# обычных файлов. Если что-то недоступно - в отчёте будет отметка, а не
# запрос пароля.

[ -n "${ZDY_INCIDENT_SOURCED:-}" ] && return 0
ZDY_INCIDENT_SOURCED=1

ZDY_INCIDENT_DIR="$ZDY_STATE_DIR/incidents"
# Сколько снимков хранить. Их объём - единицы килобайт, но бесконечно
# копить бессмысленно.
ZDY_INCIDENT_KEEP="${ZDY_INCIDENT_KEEP:-30}"

# Возраст файла в днях. Печатает "неизвестно", если файла нет.
file_age_days() {
  local file="$1" mtime now
  [ -e "$file" ] || {
    printf 'unknown\n'
    return 1
  }
  # date -r есть и в coreutils, и в busybox, и в BSD.
  mtime=$(date -r "$file" '+%s' 2>/dev/null) || {
    printf 'unknown\n'
    return 1
  }
  now=$(date '+%s')
  printf '%s\n' "$(((now - mtime) / 86400))"
}

# Время работы процесса в секундах, из /proc/<pid>/stat и /proc/uptime.
proc_uptime_seconds() {
  local pid="$1" stat_line uptime_line starttime clk
  [ -r "$ZDY_PROC/$pid/stat" ] || return 1
  IFS= read -r stat_line <"$ZDY_PROC/$pid/stat" || return 1
  IFS= read -r uptime_line <"$ZDY_PROC/uptime" 2>/dev/null || return 1

  # 22-е поле - starttime в тиках. Имя процесса в скобках может содержать
  # пробелы, поэтому отрезаем всё до закрывающей скобки.
  stat_line="${stat_line#*) }"
  # shellcheck disable=SC2086
  set -- $stat_line
  starttime="${20:-}"
  [ -n "$starttime" ] || return 1

  clk=$(getconf CLK_TCK 2>/dev/null) || clk=100
  uptime_line="${uptime_line%% *}"
  uptime_line="${uptime_line%%.*}"

  printf '%s\n' "$((uptime_line - starttime / clk))"
}

incident_collect_processes() {
  local pid cmdline uptime found=0

  while IFS= read -r pid; do
    [ -r "$ZDY_PROC/$pid/cmdline" ] || continue
    cmdline=$(tr '\0' ' ' <"$ZDY_PROC/$pid/cmdline")
    uptime=$(proc_uptime_seconds "$pid") || uptime="?"
    printf 'pid=%s uptime_sec=%s\n%s\n\n' "$pid" "$uptime" "$cmdline"
    found=1
  done < <(proc_pgrep "nfqws"; proc_pgrep "tpws")

  [ "$found" = "1" ] || printf 'Процессы nfqws/tpws не найдены.\n'
}

incident_collect_lists() {
  printf 'ipset-all.txt: '
  if [ -f "$ZDY_IPSET_FILE" ]; then
    printf 'строк: %s, обновлён %s дн. назад\n' \
      "$(grep -c '[^[:space:]]' "$ZDY_IPSET_FILE" 2>/dev/null || printf '?')" \
      "$(file_age_days "$ZDY_IPSET_FILE")"
  else
    printf 'отсутствует\n'
  fi

  printf 'блок в %s: ' "$ZDY_HOSTS_FILE"
  if hosts_has_block; then
    printf 'есть, файл менялся %s дн. назад\n' "$(file_age_days "$ZDY_HOSTS_FILE")"
  else
    printf 'отсутствует\n'
  fi

  printf 'режим ipset: %s\n' "$(ipset_state)"
  printf 'game filter: %s\n' "$(game_filter_label)"

  printf '\nФайлы, на которые ссылается конфиг, но которых нет на диске:\n'
  if [ -f "$ZAPRET_CONFIG" ]; then
    local missing
    missing=$(nfqws_missing_files "$ZAPRET_CONFIG" 2>/dev/null)
    if [ -n "$missing" ]; then
      printf '%s\n' "$missing"
    else
      printf '(таких нет)\n'
    fi
  else
    printf '(конфиг не установлен)\n'
  fi
}

incident_collect_queue() {
  local src="$ZDY_PROC/net/netfilter/nfnetlink_queue"
  if [ -r "$src" ]; then
    printf 'queue portid  waiting  copymode  copyrange  queuedropped  userdropped  seq\n'
    cat -- "$src"
  else
    printf 'Нет доступа к %s\n' "$src"
  fi
}

incident_collect_summary() {
  local reason="$1" manager

  printf 'Дата:            %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf 'Причина:         %s\n' "$reason"
  printf 'Дистрибутив:     %s\n' "$(os_release_field PRETTY_NAME 2>/dev/null || printf 'unknown')"
  printf 'Init-система:    %s\n' "$(init_system_name 2>/dev/null || printf 'unknown')"
  printf 'Ядро:            %s\n' "$(uname -r 2>/dev/null || printf 'unknown')"

  if manager=$(detect_service_manager); then
    printf 'Служба:          %s, ' "$manager"
    if service_is_active "$manager"; then
      printf 'запущена'
    else
      printf 'остановлена'
    fi
    if service_is_enabled "$manager"; then
      printf ', автозапуск включён\n'
    else
      printf ', автозапуск выключен\n'
    fi
  else
    printf 'Служба:          не найдена\n'
  fi

  printf 'Стратегия:       %s\n' "$(strategy_current 2>/dev/null || printf 'не установлена')"
  printf 'Автоперезапуск:  %s\n' "$(autorestart_status_text 2>/dev/null || printf 'unknown')"
}

# Создаёт снимок и печатает путь к нему.
incident_snapshot() {
  local reason="${1:-manual restart}" dir

  dir="$ZDY_INCIDENT_DIR/$(date '+%Y-%m-%d_%H-%M-%S')"
  mkdir -p "$dir" || return 1
  chmod 700 "$dir" 2>/dev/null || true

  incident_collect_summary "$reason" >"$dir/summary.txt" 2>&1
  incident_collect_processes >"$dir/processes.txt" 2>&1
  incident_collect_lists >"$dir/lists.txt" 2>&1
  incident_collect_queue >"$dir/nfqueue.txt" 2>&1

  if [ -f "$ZAPRET_CONFIG" ]; then
    cp "$ZAPRET_CONFIG" "$dir/config" 2>/dev/null || true
  fi

  incident_prune
  printf '%s\n' "$dir"
}

incident_prune() {
  local -a dirs=()
  local d count

  while IFS= read -r d; do
    [ -n "$d" ] && dirs+=("$d")
  done < <(find "$ZDY_INCIDENT_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | LC_ALL=C sort)

  count=${#dirs[@]}
  [ "$count" -le "$ZDY_INCIDENT_KEEP" ] && return 0

  local remove=$((count - ZDY_INCIDENT_KEEP)) i=0
  while [ "$i" -lt "$remove" ]; do
    rm -rf -- "${dirs[$i]}"
    i=$((i + 1))
  done
}

incident_count() {
  find "$ZDY_INCIDENT_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | grep -c . || printf '0\n'
}
