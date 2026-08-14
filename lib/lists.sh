# shellcheck shell=bash
#
# Списки и режимы: ipset, game filter, пользовательские домены, /etc/hosts.
# Все записи в /opt/zapret идут через write_out/append_out из common.sh,
# то есть с повышением привилегий там и только там, где это нужно.

[ -n "${ZDY_LISTS_SOURCED:-}" ] && return 0
ZDY_LISTS_SOURCED=1

# ---------------------------------------------------------------- ipset -----

ipset_state() {
  [ -f "$ZDY_IPSET_FILE" ] || {
    printf 'any\n'
    return
  }

  local count
  count=$(grep -c '[^[:space:]]' "$ZDY_IPSET_FILE" 2>/dev/null) || count=0
  count=${count:-0}

  if [ "$count" -eq 0 ]; then
    printf 'any\n'
  elif [ "$count" -eq 1 ] && grep -Fqx -- "$ZDY_IPSET_STUB_IP" "$ZDY_IPSET_FILE" 2>/dev/null; then
    printf 'none\n'
  else
    printf 'loaded\n'
  fi
}

ipset_backup_create() {
  if [ ! -f "$ZDY_IPSET_BACKUP" ] && [ -f "$ZDY_IPSET_FILE" ]; then
    copy_out "$ZDY_IPSET_FILE" "$ZDY_IPSET_BACKUP" || return 1
    ok "Резервная копия списка создана"
  fi
}

ipset_set_mode() {
  local mode="$1" value="$2"

  if [ "$(ipset_state)" = "$mode" ]; then
    warn "Уже в режиме $mode"
    return 0
  fi

  msg "Установка режима $mode..."
  mkdir_out "$ZAPRET_HOSTLISTS" || return 1
  ipset_backup_create || return 1
  printf '%s\n' "$value" | write_out "$ZDY_IPSET_FILE" || return 1
  ok "IPSet установлен в режим $mode"
  restart_zapret
}

ipset_restore_loaded() {
  if [ "$(ipset_state)" = "loaded" ]; then
    warn "Уже в режиме loaded"
    return 0
  fi

  if [ ! -f "$ZDY_IPSET_BACKUP" ]; then
    err "Нет резервной копии для восстановления. Загрузите список заново (пункт "Обновить список IPSet")."
    return 1
  fi

  msg "Установка режима loaded..."
  copy_out "$ZDY_IPSET_BACKUP" "$ZDY_IPSET_FILE" || return 1
  rm_out "$ZDY_IPSET_BACKUP"
  ok "IPSet установлен в режим loaded, резервная копия удалена"
  restart_zapret
}

ipset_update() {
  local tmp
  msg "Обновление ipset-all из $ZDY_FLOWSEAL_SLUG..."

  tmp=$(zdy_tempfile) || return 1
  mkdir_out "$ZAPRET_HOSTLISTS" || return 1

  if ! fetch_url "$ZDY_FLOWSEAL_IPSET_URL" "$tmp" || [ ! -s "$tmp" ]; then
    err "Ошибка при обновлении списка"
    return 1
  fi

  write_out "$ZDY_IPSET_FILE" <"$tmp" || return 1
  chmod_out 644 "$ZDY_IPSET_FILE"
  ok "Список ipset-all успешно обновлён"
  restart_zapret
}

# ----------------------------------------------------------- game filter ----

game_filter_mode() {
  [ -f "$ZDY_GAME_FILE" ] || {
    printf 'off\n'
    return
  }
  local mode
  IFS= read -r mode <"$ZDY_GAME_FILE" 2>/dev/null || mode=""
  case "$mode" in
    all | tcp | udp) printf '%s\n' "$mode" ;;
    *) printf 'unknown\n' ;;
  esac
}

game_filter_label() {
  case "${1:-$(game_filter_mode)}" in
    off) printf 'выключен\n' ;;
    all) printf 'включён (TCP и UDP)\n' ;;
    tcp) printf 'включён (только TCP)\n' ;;
    udp) printf 'включён (только UDP)\n' ;;
    *) printf 'включён (неизвестный режим)\n' ;;
  esac
}

game_filter_set() {
  local mode="$1"
  msg "Включение game filter ($(game_filter_label "$mode"))..."
  mkdir_out "$ZAPRET_HOSTLISTS" || return 1
  printf '%s\n' "$mode" | write_out "$ZDY_GAME_FILE" || return 1
  ok "Game Filter: $(game_filter_label "$mode")"
  restart_zapret
}

game_filter_disable() {
  if [ ! -f "$ZDY_GAME_FILE" ]; then
    warn "Game Filter уже выключен"
    return 0
  fi
  msg "Отключение game filter..."
  rm_out "$ZDY_GAME_FILE" || return 1
  ok "Game Filter выключен"
  restart_zapret
}

# --------------------------------------------------------------- домены -----

# Приводит ввод (домен или URL) к голому домену. Печатает результат в stdout.
domain_normalize() {
  local input="$1" domain

  # Обрезка пробелов средствами bash: sed -i и sed -E ведут себя по-разному
  # в busybox и BSD-userland, поэтому здесь их нет.
  input="${input#"${input%%[![:space:]]*}"}"
  input="${input%"${input##*[![:space:]]}"}"

  domain="$input"
  case "$domain" in
    http://* | https://*)
      domain="${domain#*://}"
      domain="${domain%%/*}"
      ;;
  esac

  domain="${domain,,}"
  domain="${domain%%/*}"
  domain="${domain%%:*}"
  domain="${domain#www.}"

  [ -n "$domain" ] || return 1
  [[ "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] || return 2

  printf '%s\n' "$domain"
}

domain_add() {
  local input="$1" list_file="$2" domain status

  domain=$(domain_normalize "$input")
  status=$?
  case "$status" in
    1)
      err "Пустой домен"
      return 1
      ;;
    2)
      err "Некорректный домен: $input"
      return 1
      ;;
  esac

  mkdir_out "${list_file%/*}" || return 1

  if grep -Fqx -- "$domain" "$list_file" 2>/dev/null; then
    warn "Домен $domain уже в списке"
    return 1
  fi

  # Если файл не заканчивается переводом строки, дописанная строка склеится
  # с последней существующей.
  if [ -s "$list_file" ] && [ -n "$(tail -c 1 "$list_file")" ]; then
    printf '\n' | append_out "$list_file" || return 1
  fi

  printf '%s\n' "$domain" | append_out "$list_file" || return 1
  ok "Домен $domain добавлен в список"
}

# --------------------------------------------------------------- /etc/hosts -

ZDY_HOSTS_BEGIN="# >>> zapret-discord-youtube >>>"
ZDY_HOSTS_END="# <<< zapret-discord-youtube <<<"

hosts_has_block() {
  grep -Fqx -- "$ZDY_HOSTS_BEGIN" "$ZDY_HOSTS_FILE" 2>/dev/null
}

# Печатает содержимое hosts без нашего блока.
hosts_without_block() {
  local line inside=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$ZDY_HOSTS_BEGIN") inside=1; continue ;;
      "$ZDY_HOSTS_END") inside=0; continue ;;
    esac
    [ "$inside" = "1" ] && continue
    printf '%s\n' "$line"
  done <"$ZDY_HOSTS_FILE"
}

hosts_backup() {
  local dest
  state_dir_init
  dest="$ZDY_STATE_DIR/hosts.bak.$(date '+%Y-%m-%d_%H-%M-%S')"
  cp "$ZDY_HOSTS_FILE" "$dest" 2>/dev/null || return 1
  hint "Резервная копия hosts: $dest"
}

# Раньше содержимое просто дописывалось в конец: при изменении апстрима
# старые записи оставались навсегда, и удалить их было нечем. Теперь блок
# ограничен маркерами и заменяется целиком.
hosts_update() {
  local tmp new

  msg "Обновление файла hosts..."
  tmp=$(zdy_tempfile) || return 1

  if ! fetch_url "$ZDY_FLOWSEAL_HOSTS_URL" "$tmp" || [ ! -s "$tmp" ]; then
    err "Не удалось скачать файл hosts"
    hint "Адрес: $ZDY_FLOWSEAL_HOSTS_URL"
    return 1
  fi

  new=$(zdy_tempfile) || return 1
  {
    hosts_without_block
    printf '%s\n' "$ZDY_HOSTS_BEGIN"
    cat -- "$tmp"
    printf '%s\n' "$ZDY_HOSTS_END"
  } >"$new"

  if [ "$(sha256_file "$new")" = "$(sha256_file "$ZDY_HOSTS_FILE")" ]; then
    ok "Файл hosts уже актуален"
    return 0
  fi

  msg "Блок, который будет записан в $ZDY_HOSTS_FILE:"
  plain "---"
  cat -- "$tmp"
  plain "---"
  printf '\n'

  ask_yes_no "Apply?" y || {
    msg "Обновление отменено"
    return 1
  }

  hosts_backup || warn "Не удалось создать резервную копию hosts, продолжаю"
  write_out "$ZDY_HOSTS_FILE" <"$new" || return 1
  ok "Файл hosts обновлён"
}

hosts_remove() {
  if ! hosts_has_block; then
    warn "В $ZDY_HOSTS_FILE нет блока zapret"
    return 0
  fi

  ask_yes_no "Удалить блок zapret из $ZDY_HOSTS_FILE?" y || return 1

  local new
  new=$(zdy_tempfile) || return 1
  hosts_without_block >"$new"

  hosts_backup || warn "Не удалось создать резервную копию hosts, продолжаю"
  write_out "$ZDY_HOSTS_FILE" <"$new" || return 1
  ok "Блок zapret удалён из hosts"
}
