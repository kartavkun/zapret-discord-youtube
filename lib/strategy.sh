# shellcheck shell=bash
#
# Работа со стратегиями и фиксами.
#
# Схема из экспериментальной ветки: /opt/zapret/config - общий загрузчик,
# который при старте службы читает имя стратегии из zapret.strategy, список
# включённых фиксов из zapret.fixes и собирает NFQWS_OPT сам. Поэтому смена
# стратегии - это запись одной строки, а не подмена файла конфигурации.
#
# Правила именования фрагментов повторяют zapret_valid_fragment_name из
# config: только [A-Za-z0-9._-], чтобы имя нельзя было увести за пределы
# каталога.

[ -n "${ZDY_STRATEGY_SOURCED:-}" ] && return 0
ZDY_STRATEGY_SOURCED=1

ZDY_DEFAULT_STRATEGY="general"

fragment_name_valid() {
  case "${1:-}" in
    "" | *[!A-Za-z0-9._-]*) return 1 ;;
    . | ..) return 1 ;;
  esac
  return 0
}

# ------------------------------------------------------------- стратегии ----

# Старое имя -> новое. Таблица общая с nixos.
strategy_resolve_name() {
  local name="$1" old new map="$ZDY_STRATEGIES_SRC/legacy-names.map"

  [ -r "$map" ] || {
    printf '%s\n' "$name"
    return
  }

  while IFS=$'\t' read -r old new; do
    [ -n "$old" ] || continue
    if [ "$name" = "$old" ]; then
      warn "Имя стратегии '$old' устарело, использую '$new'"
      printf '%s\n' "$new"
      return
    fi
  done <"$map"

  printf '%s\n' "$name"
}

# Перечисляет доступные стратегии. Источник - установленный каталог, если он
# есть; иначе каталог проекта (например, до первой установки).
strategy_dir() {
  if [ -d "$ZAPRET_STRATEGIES" ]; then
    printf '%s\n' "$ZAPRET_STRATEGIES"
  else
    printf '%s\n' "$ZDY_STRATEGIES_SRC"
  fi
}

strategy_list() {
  local dir entry name
  dir=$(strategy_dir)

  # Без nullglob пустой каталог дал бы литерал 'dir/*' как единственный
  # элемент, и проверка на пустоту не сработала бы.
  local saved_nullglob
  # shopt -p возвращает 1, когда опция выключена; под set -e это молча
  # роняет вызывающий скрипт.
  saved_nullglob=$(shopt -p nullglob || true)
  shopt -s nullglob

  for entry in "$dir"/*; do
    [ -f "$entry" ] || continue
    name="${entry##*/}"
    [ "$name" = "legacy-names.map" ] && continue
    fragment_name_valid "$name" || continue
    printf '%s\n' "$name"
  done | LC_ALL=C sort

  eval "$saved_nullglob"
}

# Проверка фрагмента: имя, синтаксис, непустой результат.
#
# Последний шаг загружает фрагмент в отдельной оболочке, то есть проверка
# выполняется исполнением. Для файлов из своего репозитория это приемлемо,
# но именно проверкой в строгом смысле не является.
strategy_is_valid() {
  local name="$1" file
  file="$(strategy_dir)/$name"

  fragment_name_valid "$name" || return 1
  [ -f "$file" ] || return 1
  sh -n "$file" >/dev/null 2>&1 || return 1

  # ZAPRET_BASE нужен производным стратегиям: они подключают базовый фрагмент
  # по пути $ZAPRET_BASE/strategies/<имя>.
  env ZAPRET_BASE="$ZAPRET_DIR" sh -c '
    GAME_FILTER_TCP=1024-65535
    GAME_FILTER_UDP=1024-65535
    NFQWS_STRATEGY_OPT=
    . "$1"
    [ -n "$NFQWS_STRATEGY_OPT" ]
  ' sh "$file" >/dev/null 2>&1
}

strategy_current() {
  local name=""
  if [ -r "$ZDY_STRATEGY_STATE" ]; then
    IFS= read -r name <"$ZDY_STRATEGY_STATE" 2>/dev/null || name=""
    name="${name%$'\r'}"
  fi
  [ -n "$name" ] || name="$ZDY_DEFAULT_STRATEGY"
  printf '%s\n' "$name"
}

strategy_apply() {
  local name="$1"

  name=$(strategy_resolve_name "$name")

  if ! strategy_is_valid "$name"; then
    err "Стратегия '$name' не найдена или некорректна"
    hint "Доступные: zapret-config --list"
    return 1
  fi

  if [ "$(strategy_current)" = "$name" ]; then
    warn "Стратегия '$name' уже выбрана"
    return 0
  fi

  printf '%s\n' "$name" | write_out "$ZDY_STRATEGY_STATE" || return 1
  chmod_out 644 "$ZDY_STRATEGY_STATE"
  ok "Стратегия: $name"
}

# ----------------------------------------------------------------- фиксы ----

fix_list() {
  local entry name
  [ -d "$ZAPRET_FIXES" ] || return 0

  local saved_nullglob
  # shopt -p возвращает 1, когда опция выключена; под set -e это молча
  # роняет вызывающий скрипт.
  saved_nullglob=$(shopt -p nullglob || true)
  shopt -s nullglob

  for entry in "$ZAPRET_FIXES"/*; do
    [ -f "$entry" ] || continue
    name="${entry##*/}"
    fragment_name_valid "$name" || continue
    printf '%s\n' "$name"
  done | LC_ALL=C sort

  eval "$saved_nullglob"
}

fix_is_valid() {
  local name="$1" file="$ZAPRET_FIXES/$1"
  fragment_name_valid "$name" || return 1
  [ -f "$file" ] || return 1
  sh -n "$file" >/dev/null 2>&1
}

fix_enabled_list() {
  local name
  [ -r "$ZDY_FIXES_STATE" ] || return 0

  while IFS= read -r name || [ -n "$name" ]; do
    name="${name%$'\r'}"
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    case "$name" in
      "" | \#*) continue ;;
    esac
    fragment_name_valid "$name" || continue
    printf '%s\n' "$name"
  done <"$ZDY_FIXES_STATE"
}

fix_is_enabled() {
  fix_enabled_list | grep -Fqx -- "$1"
}

fix_enable() {
  local name="$1"

  fix_is_valid "$name" || {
    err "Фикс '$name' не найден или содержит синтаксическую ошибку"
    return 1
  }

  if fix_is_enabled "$name"; then
    warn "Фикс '$name' уже включён"
    return 0
  fi

  {
    fix_enabled_list
    printf '%s\n' "$name"
  } | write_out "$ZDY_FIXES_STATE" || return 1
  chmod_out 644 "$ZDY_FIXES_STATE"
  ok "Фикс '$name' включён"
}

fix_disable() {
  local name="$1"

  if ! fix_is_enabled "$name"; then
    warn "Фикс '$name' и так выключен"
    return 0
  fi

  fix_enabled_list | grep -Fvx -- "$name" | write_out "$ZDY_FIXES_STATE" || return 1
  chmod_out 644 "$ZDY_FIXES_STATE"
  ok "Фикс '$name' выключен"
}

fix_toggle() {
  if fix_is_enabled "$1"; then
    fix_disable "$1"
  else
    fix_enable "$1"
  fi
}

# Строка для шапки менеджера.
fix_enabled_text() {
  local list
  list=$(fix_enabled_list | paste -sd ',' - 2>/dev/null) || list=""
  if [ -z "$list" ]; then
    printf 'нет\n'
  else
    printf '%s\n' "${list//,/, }"
  fi
}

# ------------------------------------------------- итоговый набор правил ----

# Разворачивает конфиг ровно так, как это сделает служба, и печатает
# получившийся NFQWS_OPT. Используется в doctor и в проверке ссылок.
strategy_effective_nfqws_opt() {
  local config="${1:-$ZAPRET_CONFIG}"
  [ -r "$config" ] || return 1

  # ZAPRET_BASE передаётся явно: config берёт из него пути к фрагментам.
  env ZAPRET_BASE="$ZAPRET_DIR" sh -c '
    . "$1" >/dev/null 2>&1
    printf "%s\n" "$NFQWS_OPT"
  ' sh "$config" 2>/dev/null
}
