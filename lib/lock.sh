# shellcheck shell=bash
#
# Модуль подключается из bin/*, а не сам по себе: общие функции и пути
# приходят из lib/common.sh, lib/compat.sh и lib/paths.sh, подключённых
# вызывающим скриптом раньше. Отсюда директивы source ниже - без них
# shellcheck считает эти имена неопределёнными.
# shellcheck source=common.sh
# shellcheck source=compat.sh
# shellcheck source=paths.sh
#
# Чтение zapret.lock и проверка контрольных сумм.
#
# README обещает "оригинальные бинарники с проверяемыми хэшами", но в
# shell-пути ничего не проверялось: тарбол zapret скачивался без хеша, а
# .bin-файлы тянулись с движущейся ветки main чужого репозитория. Здесь это
# и исправляется.

[ -n "${ZDY_LOCK_SOURCED:-}" ] && return 0
ZDY_LOCK_SOURCED=1

ZDY_LOCK_FILE="$ZDY_ROOT/zapret.lock"

# Строгий режим: незаполненный или несовпавший хеш прерывает установку.
ZDY_STRICT_CHECKSUMS="${ZDY_STRICT_CHECKSUMS:-0}"

# lock_get <ключ> [подключ]
lock_get() {
  local want_key="$1" want_sub="${2:-}" key sub value line

  [ -r "$ZDY_LOCK_FILE" ] || return 1

  while IFS= read -r line; do
    case "$line" in
      '#'* | '') continue ;;
    esac

    if [ -n "$want_sub" ]; then
      read -r key sub value <<<"$line"
      [ "$key" = "$want_key" ] && [ "$sub" = "$want_sub" ] || continue
    else
      read -r key value <<<"$line"
      [ "$key" = "$want_key" ] || continue
    fi

    [ -n "$value" ] || return 1
    printf '%s\n' "$value"
    return 0
  done <"$ZDY_LOCK_FILE"

  return 1
}

lock_value_is_set() {
  local v="$1"
  [ -n "$v" ] && [ "$v" != "unset" ]
}

# Проверяет файл против ожидаемого хеша.
#   0 - совпал, либо хеш не задан и мы не в строгом режиме
#   1 - не совпал, либо хеш не задан в строгом режиме
lock_verify_file() {
  local file="$1" expected="$2" label="$3" actual

  if ! lock_value_is_set "$expected"; then
    if [ "$ZDY_STRICT_CHECKSUMS" = "1" ]; then
      err "Строгий режим: в zapret.lock нет контрольной суммы для $label"
      return 1
    fi
    warn "Контрольная сумма для $label не задана в zapret.lock - проверка пропущена"
    return 0
  fi

  actual=$(sha256_file "$file") || {
    if [ "$ZDY_STRICT_CHECKSUMS" = "1" ]; then
      err "Строгий режим: нечем посчитать sha256 (нет sha256sum, shasum и openssl)"
      return 1
    fi
    warn "Нечем посчитать sha256 - проверка $label пропущена"
    return 0
  }

  if [ "$actual" = "$expected" ]; then
    hint "sha256 совпал: $label"
    return 0
  fi

  err "Контрольная сумма не совпала: $label"
  err "  ожидалось: $expected"
  err "  получено:  $actual"
  return 1
}

# Скачивает файл и сверяет его с хешем из lock-файла.
lock_fetch_verified() {
  local url="$1" dest="$2" expected="$3" label="$4"

  fetch_url "$url" "$dest" || {
    err "Не удалось скачать $label"
    return 1
  }

  [ -s "$dest" ] || {
    err "Скачанный файл пуст: $label"
    return 1
  }

  lock_verify_file "$dest" "$expected" "$label"
}

lock_warn_if_unpinned() {
  local commit
  commit=$(lock_get flowseal_commit) || commit="unset"
  lock_value_is_set "$commit" && return 0

  warn "В zapret.lock не зафиксирован коммит Flowseal - .bin-файлы будут скачаны"
  warn "с ветки main, содержимое которой может измениться в любой момент."
  hint "Заполнить: tools/update-lock.sh"
}

# Печатает имена файлов, для которых в zapret.lock есть строка bin_sha256.
# Это и есть список того, что нужно скачать: он формируется
# tools/update-lock.sh перечислением каталога bin/ у Flowseal.
lock_list_binaries() {
  local key name value line
  [ -r "$ZDY_LOCK_FILE" ] || return 1

  while IFS= read -r line; do
    case "$line" in
      '#'* | '') continue ;;
    esac
    read -r key name value <<<"$line"
    [ "$key" = "bin_sha256" ] || continue
    [ -n "$name" ] || continue
    printf '%s\n' "$name"
  done <"$ZDY_LOCK_FILE"
}
