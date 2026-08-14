# shellcheck shell=bash
#
# Диагностика: разовый отчёт (doctor) и слепки состояния при инцидентах.
#
# Слепок снимается ПЕРЕД перезапуском службы. Смысл в том, что перезапуск
# стирает ровно то состояние, по которому можно понять причину: живые
# процессы, счётчики очереди, записи conntrack. Без слепков через месяц у нас
# останется только ощущение "иногда подтупливает".

# Требует lib/incident.sh: оттуда берутся file_age_days и сбор состояния.

[ -n "${ZDY_DIAG_SOURCED:-}" ] && return 0
ZDY_DIAG_SOURCED=1

# ------------------------------------------------------------- сбор данных --

diag_nfqws_processes() {
  local pid cmdline
  while IFS= read -r pid; do
    [ -r "$ZDY_PROC/$pid/cmdline" ] || continue
    cmdline=$(tr '\0' ' ' <"$ZDY_PROC/$pid/cmdline" 2>/dev/null) || continue
    printf 'pid=%s %s\n' "$pid" "$cmdline"
  done < <(proc_pgrep "nfqws")
}

diag_process_uptime() {
  local pid="$1"
  [ -r "$ZDY_PROC/$pid/stat" ] || return 1
  # Проще и переносимее, чем разбирать поле starttime: возраст каталога.
  date -r "$ZDY_PROC/$pid" '+%Y-%m-%d %H:%M:%S' 2>/dev/null
}

diag_nfqueue_counters() {
  # Переполнение очереди проявится ростом колонок queue_dropped и
  # user_dropped - одна из рабочих гипотез по "подтупливанию".
  if [ -r "$ZDY_PROC/net/netfilter/nfnetlink_queue" ]; then
    printf 'queue_num port_id queue_total copy_mode copy_range queue_dropped user_dropped id_sequence\n'
    cat "$ZDY_PROC/net/netfilter/nfnetlink_queue"
  else
    printf 'нет данных (%s/net/netfilter/nfnetlink_queue недоступен)\n' "$ZDY_PROC"
  fi
}

diag_conntrack_discord() {
  if [ -r "$ZDY_PROC/net/nf_conntrack" ]; then
    grep -E 'dport=(443|50[0-9]{3}|19[23][0-9]{2})' "$ZDY_PROC/net/nf_conntrack" 2>/dev/null | head -n 40
  else
    printf 'нет данных (nf_conntrack не загружен или недоступен)\n'
  fi
}

diag_kernel_modules() {
  local m
  for m in nfnetlink_queue nf_conntrack xt_connbytes; do
    if [ -r "$ZDY_PROC/modules" ] && grep -q "^$m " "$ZDY_PROC/modules" 2>/dev/null; then
      printf '  %-18s загружен\n' "$m"
    else
      printf '  %-18s НЕ загружен\n' "$m"
    fi
  done
}

diag_sysctl() {
  local v
  v=$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null) || v="?"
  printf 'net.ipv4.tcp_timestamps = %s\n' "$v"
}

# Проверка, что все hostlists и .bin, на которые ссылается конфиг, существуют.
# Отсутствующий файл zapret не считает ошибкой - он просто молча не фильтрует
# часть трафика, и это ровно тот класс симптомов, который мы ищем.
diag_config_references() {
  local config="${1:-$ZAPRET_CONFIG}" opt tmp

  [ -r "$config" ] || {
    printf 'Конфиг не установлен: %s\n' "$config"
    return 1
  }

  # Проверяем не отдельный фрагмент, а развёрнутый NFQWS_OPT - то, что
  # реально увидит служба со всеми включёнными фиксами.
  opt=$(strategy_effective_nfqws_opt "$config") || opt=""
  if [ -z "$opt" ]; then
    printf 'Не удалось развернуть NFQWS_OPT из %s\n' "$config"
    return 1
  fi

  tmp=$(zdy_tempfile) || return 1
  printf 'NFQWS_OPT="\n%s\n"\n' "$opt" >"$tmp"

  local missing
  if missing=$(nfqws_missing_paths "$tmp"); then
    printf 'Все файлы, на которые ссылается стратегия, на месте\n'
    return 0
  fi
  printf '%s\n' "$missing" | while IFS= read -r path; do
    [ -n "$path" ] && printf 'ОТСУТСТВУЕТ: %s\n' "$path"
  done
  return 1
}


# ------------------------------------------------------------------ doctor --

diag_report() {
  local manager

  printf '===== zapret-discord-youtube :: doctor =====\n'
  printf 'Дата:            %s\n' "$(date '+%Y-%m-%d %H:%M:%S %z')"
  printf 'Каталог проекта: %s (%s)\n' "$ZDY_ROOT" "$(zdy_mode)"
  printf 'Коммит:          %s\n' "$(state_commit)"
  printf 'Схема состояния: %s\n' "$(state_schema)"
  printf '\n'

  printf '%s\n' '--- система ---'
  printf 'Дистрибутив:     %s\n' "$(os_release_field PRETTY_NAME 2>/dev/null || printf 'неизвестно')"
  printf 'Ядро:            %s\n' "$(uname -r 2>/dev/null || printf '?')"
  printf 'Init-система:    %s\n' "$(init_system_name 2>/dev/null || printf 'неизвестно')"
  printf 'bash:            %s\n' "${BASH_VERSION:-?}"
  printf '\n'

  printf '%s\n' '--- служба ---'
  if manager=$(detect_service_manager); then
    printf 'Менеджер служб:  %s\n' "$manager"
    printf 'Статус:          %s\n' "$(service_status_text "$manager")"
    printf 'Автозапуск:      %s\n' "$(service_autostart_text "$manager")"
  else
    printf 'Менеджер служб:  не найден\n'
  fi
  printf 'Автоперезапуск:  %s\n' "$(autorestart_status_text)"
  printf '\n'

  printf '%s\n' '--- конфигурация ---'
  printf 'Стратегия:       %s\n' "$(strategy_current 2>/dev/null || printf 'не установлена')"
  printf 'Фиксы:           %s\n' "$(fix_enabled_text 2>/dev/null || printf 'нет')"
  local ipset_age
  ipset_age=$(file_age_days "$ZDY_IPSET_FILE")
  if [[ "$ipset_age" =~ ^[0-9]+$ ]]; then
    printf 'IPSet:           %s (обновлён %s дн. назад)\n' "$(ipset_state)" "$ipset_age"
  else
    printf 'IPSet:           %s (ни разу не обновлялся)\n' "$(ipset_state)"
  fi
  printf 'Game Filter:     %s\n' "$(game_filter_label)"
  printf 'Блок в hosts:    %s\n' "$(hosts_has_block && printf 'есть' || printf 'нет')"
  printf '\n'
  diag_config_references
  printf '\n'

  printf '%s\n' '--- ядро и сеть ---'
  diag_kernel_modules
  diag_sysctl
  printf '\n'

  printf '%s\n' '--- процессы nfqws ---'
  diag_nfqws_processes
  printf '\n'

  printf '%s\n' '--- счётчики nfqueue ---'
  diag_nfqueue_counters
  printf '\n'

  local age
  age=$(file_age_days "$ZDY_IPSET_FILE")
  if [[ "$age" =~ ^[0-9]+$ ]] && [ "$age" -ge 30 ]; then
    printf '[ ! ] Список ipset-all не обновлялся %s дней.\n' "$age"
    printf '      Discord меняет адреса - это первое, что стоит обновить.\n'
  fi
}

# ------------------------------------------------------------------ отчёт ---

# Собирает всё, что обычно просят в issue, в один файл. Смысл в том, чтобы
# человеку не приходилось пересказывать вывод команд своими словами.
diag_bundle() {
  local dest="${1:-}" latest

  state_dir_init
  [ -n "$dest" ] || dest="$ZDY_STATE_DIR/report-$(date '+%Y-%m-%d_%H-%M-%S').txt"

  # Внутри отчёта ненулевой код - норма (например, конфиг ещё не установлен),
  # но под set -e он оборвал бы сбор на первой же такой команде.
  {
    diag_report || true
    printf '\n'

    printf '%s\n' '--- последний снимок инцидента ---'
    latest=$(find "$ZDY_INCIDENT_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null |
      LC_ALL=C sort | tail -n 1)
    if [ -n "$latest" ]; then
      printf 'каталог: %s\n\n' "$latest"
      local f
      for f in summary.txt processes.txt lists.txt nfqueue.txt; do
        [ -r "$latest/$f" ] || continue
        printf '== %s ==\n' "$f"
        cat "$latest/$f" || true
        printf '\n'
      done
    else
      printf 'снимков пока нет\n'
    fi

    printf '\n%s\n' '--- выбранная стратегия ---'
    local strategy_file
    strategy_file="$(strategy_dir)/$(strategy_current)"
    if [ -r "$strategy_file" ]; then
      cat "$strategy_file"
    else
      printf 'файл стратегии не найден: %s\n' "$strategy_file"
    fi
  } >"$dest" 2>&1 || true

  chmod 600 "$dest" 2>/dev/null || true

  ok "Отчёт собран: $dest"
  hint "Проверьте его перед отправкой: там есть адреса из conntrack."
  printf '%s\n' "$dest"
}
