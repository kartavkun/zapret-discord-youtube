# shellcheck shell=bash
#
# Общие примитивы: вывод, вопросы, повышение привилегий, запись в защищённые пути.
# Подключается из bin/*: . "$ZDY_LIB/common.sh"
#
# Ничего не выполняет при подключении, кроме проверки версии bash и настройки
# цветов. set -euo pipefail здесь НЕ выставляется - это дело вызывающего скрипта.

[ -n "${ZDY_COMMON_SOURCED:-}" ] && return 0
ZDY_COMMON_SOURCED=1

if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "[ - ] нужен bash 4.0 или новее (установите пакет bash)." >&2
  exit 1
fi

# ---------------------------------------------------------------- вывод -----

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != "dumb" ]; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_DIM=$'\033[2m'
else
  C_RESET='' C_RED='' C_GREEN='' C_YELLOW='' C_DIM=''
fi

# Префиксы вместо галочек и прочих символов вне ASCII: они одинаково
# выглядят в любом терминале, переживают ssh в urxvt и не ломают ширину
# колонок в шрифтах без поддержки соответствующих глифов.
#
#   [ + ] сделано        [ * ] выполняется
#   [ - ] ошибка         [ i ] подсказка
#   [ ! ] предупреждение [ > ] запрос ввода
#
# Весь пользовательский вывод - на английском; комментарии в коде остаются
# на русском.
ZDY_P_OK="[ + ]"
ZDY_P_ERR="[ - ]"
ZDY_P_WARN="[ ! ]"
ZDY_P_INFO="[ * ]"
ZDY_P_HINT="[ i ]"
ZDY_P_ASK="[ > ]"

msg()   { printf '%s %s\n' "$ZDY_P_INFO" "$*"; }
ok()    { printf '%s%s %s%s\n' "$C_GREEN" "$ZDY_P_OK" "$*" "$C_RESET"; }
warn()  { printf '%s%s %s%s\n' "$C_YELLOW" "$ZDY_P_WARN" "$*" "$C_RESET" >&2; }
err()   { printf '%s%s %s%s\n' "$C_RED" "$ZDY_P_ERR" "$*" "$C_RESET" >&2; }
hint()  { printf '%s%s %s%s\n' "$C_DIM" "$ZDY_P_HINT" "$*" "$C_RESET"; }
# Строка без префикса - для таблиц, меню и вывода команд.
plain() { printf '%s\n' "$*"; }

die() {
  err "$@"
  exit 1
}

# ------------------------------------------------------------- утилиты ------

have_cmd() { command -v "$1" >/dev/null 2>&1; }

require_cmd() {
  local c
  for c in "$@"; do
    have_cmd "$c" || die "Не найдена команда '$c' - установите её и повторите."
  done
}

# ------------------------------------------------------------- очистка ------
#
# Единый EXIT-trap на весь процесс. Модули регистрируют временные пути через
# zdy_cleanup_add, а не вешают собственные trap'ы - иначе они затирают друг друга.

ZDY_CLEANUP_PATHS=()

zdy_cleanup_add() { ZDY_CLEANUP_PATHS+=("$1"); }

zdy_cleanup_run() {
  local p
  for p in "${ZDY_CLEANUP_PATHS[@]:-}"; do
    [ -n "$p" ] && rm -rf -- "$p"
  done
  ZDY_CLEANUP_PATHS=()
}

trap zdy_cleanup_run EXIT

zdy_tempdir() {
  local d
  d=$(mktemp -d "${TMPDIR:-/tmp}/zdy.XXXXXX") || return 1
  zdy_cleanup_add "$d"
  printf '%s\n' "$d"
}

zdy_tempfile() {
  local f
  f=$(mktemp "${TMPDIR:-/tmp}/zdy.XXXXXX") || return 1
  zdy_cleanup_add "$f"
  printf '%s\n' "$f"
}

# ---------------------------------------------------------------- ввод ------
#
# ZDY_ASSUME_YES=1 отвечает "да" на всё, не спрашивая (автотесты, CI).

ask_yes_no() {
  local prompt="$1" default="${2:-y}" answer

  if [ "${ZDY_ASSUME_YES:-0}" = "1" ]; then
    [ "$default" = "y" ]
    return
  fi

  while true; do
    if [ "$default" = "y" ]; then
      printf '%s %s [Y/n]: ' "$ZDY_P_ASK" "$prompt"
    else
      printf '%s %s [y/N]: ' "$ZDY_P_ASK" "$prompt"
    fi

    if ! read -r answer; then
      printf '\n'
      return 1
    fi

    case "${answer,,}" in
      y | yes | д | да) return 0 ;;
      n | no | н | нет) return 1 ;;
      "") [ "$default" = "y" ]; return ;;
      *) warn "Ответьте Y или N (или Д/Н)." ;;
    esac
  done
}

ask_line() {
  local prompt="$1" __var="$2" value
  printf '%s %s' "$ZDY_P_ASK" "$prompt"
  read -r value || return 1
  printf -v "$__var" '%s' "$value"
}

pause_menu() {
  [ "${ZDY_ASSUME_YES:-0}" = "1" ] && return 0
  printf '\n'
  read -r -p "$ZDY_P_ASK Press Enter to continue..." _ || true
}

# ------------------------------------------- повышение привилегий -----------
#
# Раньше это была функция, возвращавшая имя команды через echo, и вызов
# ELEVATE_CMD=$(detect_privilege_escalation). Её exit 1 при отсутствии sudo
# завершал только подстановку команд, а скрипт продолжал работу с мусором
# в переменной. Здесь результат кладётся в глобальную переменную, а код
# возврата проверяется вызывающей стороной.

ZDY_ELEVATE=""
ZDY_ELEVATE_DETECTED=0

zdy_is_root() { [ "$(id -u)" -eq 0 ]; }

detect_elevation() {
  [ "$ZDY_ELEVATE_DETECTED" = "1" ] && { [ -n "$ZDY_ELEVATE" ] || zdy_is_root; return; }
  ZDY_ELEVATE_DETECTED=1
  ZDY_ELEVATE=""

  zdy_is_root && return 0

  local c
  for c in ${ZDY_ELEVATE_PREFERENCE:-doas sudo-rs sudo run0}; do
    if have_cmd "$c"; then
      ZDY_ELEVATE="$c"
      return 0
    fi
  done
  return 1
}

require_elevation() {
  detect_elevation && return 0
  err "Не найдена утилита повышения привилегий (sudo, sudo-rs, doas или run0)."
  return 1
}

run_elevated() {
  detect_elevation || {
    err "Нужны права root, но sudo/doas/run0 не найдены."
    return 1
  }
  if [ -z "$ZDY_ELEVATE" ]; then
    "$@"
  else
    "$ZDY_ELEVATE" "$@"
  fi
}

# ------------------------------------------- запись в защищённые пути -------
#
# /opt/zapret принадлежит root, поэтому писать туда напрямую нельзя. Но код
# не должен и предполагать обратное: на машинах, где старый setup.sh сделал
# chown на пользователя, sudo не нужен. Поэтому решение принимается по факту
# писабельности пути, а не по предположению о владельце. Побочный эффект:
# откат проекта на старую версию не ломает работу.

path_writable() {
  local path="$1" dir
  if [ -e "$path" ]; then
    [ -w "$path" ]
    return
  fi
  dir="${path%/*}"
  [ "$dir" = "$path" ] && dir="."
  [ -d "$dir" ] && [ -w "$dir" ]
}

# write_out <путь>  - принимает содержимое на stdin, перезаписывает файл.
write_out() {
  local path="$1"
  if path_writable "$path"; then
    cat >"$path"
  else
    run_elevated tee "$path" >/dev/null
  fi
}

# append_out <путь> - принимает содержимое на stdin, дописывает в конец.
append_out() {
  local path="$1"
  if path_writable "$path"; then
    cat >>"$path"
  else
    run_elevated tee -a "$path" >/dev/null
  fi
}

mkdir_out() {
  local path="$1"
  [ -d "$path" ] && return 0
  if path_writable "$path"; then
    mkdir -p "$path"
  else
    run_elevated mkdir -p "$path"
  fi
}

rm_out() {
  local path="$1"
  [ -e "$path" ] || return 0
  if path_writable "$path"; then
    rm -f "$path"
  else
    run_elevated rm -f "$path"
  fi
}

copy_out() {
  local src="$1" dst="$2"
  if path_writable "$dst"; then
    cp "$src" "$dst"
  else
    run_elevated cp "$src" "$dst"
  fi
}

chmod_out() {
  local mode="$1" path="$2"
  if path_writable "$path"; then
    chmod "$mode" "$path"
  else
    run_elevated chmod "$mode" "$path"
  fi
}
