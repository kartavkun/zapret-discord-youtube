#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZAPRET_ROOT=${ZAPRET_ROOT:-/opt/zapret}
STRATEGIES_DIR="$ZAPRET_ROOT/strategies"
STRATEGY_STATE="$ZAPRET_ROOT/zapret.strategy"
SERVICE_MODULE="$SCRIPT_DIR/zapret-service.sh"

detect_privilege_escalation() {
  if command -v doas >/dev/null 2>&1; then
    echo doas
  elif command -v sudo-rs >/dev/null 2>&1; then
    echo sudo-rs
  elif command -v sudo >/dev/null 2>&1; then
    echo sudo
  elif command -v run0 >/dev/null 2>&1; then
    echo run0
  fi
}

ELEVATE_CMD=$(detect_privilege_escalation)
ZAPRET_ELEVATE_CMD="$ELEVATE_CMD"
export ZAPRET_ROOT ZAPRET_ELEVATE_CMD

if [ ! -f "$SERVICE_MODULE" ]; then
  echo "Ошибка: не найден $SERVICE_MODULE" >&2
  exit 1
fi

# shellcheck source=zapret-service.sh
. "$SERVICE_MODULE"

valid_fragment_name() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

strategy_is_valid() {
  local strategy_name="$1"
  local strategy_file="$STRATEGIES_DIR/$strategy_name"

  valid_fragment_name "$strategy_name" || return 1
  [ -f "$strategy_file" ] || return 1
  sh -n "$strategy_file" >/dev/null 2>&1 || return 1

  sh -c '
    GAME_FILTER_TCP=1024-65535
    GAME_FILTER_UDP=1024-65535
    NFQWS_STRATEGY_OPT=
    . "$1"
    [ -n "$NFQWS_STRATEGY_OPT" ]
  ' sh "$strategy_file"
}

write_strategy_state() {
  local strategy_name="$1"
  local state_tmp

  state_tmp=$(mktemp "${TMPDIR:-/tmp}/zapret-strategy.XXXXXX") || return 1
  printf '%s\n' "$strategy_name" > "$state_tmp"

  if ! zapret_run_elevated cp "$state_tmp" "$STRATEGY_STATE" ||
      ! zapret_run_elevated chmod 644 "$STRATEGY_STATE"; then
    rm -f "$state_tmp"
    return 1
  fi

  rm -f "$state_tmp"
}

sync_runtime_assets() {
  [ -f "$SCRIPT_DIR/config" ] || {
    echo "Ошибка: в проекте не найден общий config" >&2
    return 1
  }
  [ -d "$SCRIPT_DIR/strategies" ] || {
    echo "Ошибка: в проекте не найден каталог strategies" >&2
    return 1
  }
  [ -d "$SCRIPT_DIR/fixes" ] || {
    echo "Ошибка: в проекте не найден каталог fixes" >&2
    return 1
  }

  zapret_run_elevated mkdir -p "$STRATEGIES_DIR" "$ZAPRET_ROOT/fixes" || return 1
  zapret_run_elevated cp -R "$SCRIPT_DIR/strategies/." "$STRATEGIES_DIR/" || return 1
  zapret_run_elevated cp -R "$SCRIPT_DIR/fixes/." "$ZAPRET_ROOT/fixes/" || return 1

  if [ ! -f "$ZAPRET_ROOT/config" ]; then
    zapret_run_elevated cp "$SCRIPT_DIR/config" "$ZAPRET_ROOT/config" || return 1
    zapret_run_elevated chmod 644 "$ZAPRET_ROOT/config" || return 1
  fi
}

check_bootstrap_files() {
  local required_file

  for required_file in \
    "$ZAPRET_ROOT/config" \
    "$ZAPRET_ROOT/install_bin.sh" \
    "$ZAPRET_ROOT/init.d/sysv/zapret" \
    "$ZAPRET_ROOT/init.d/sysv/functions"; do
    if [ ! -f "$required_file" ]; then
      echo "Ошибка: отсутствует $required_file" >&2
      return 1
    fi
  done
}

check_runtime_dependencies() {
  local command_name
  local missing=()

  for command_name in curl iptables ip6tables ipset; do
    command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
  done

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Ошибка: не установлены необходимые команды: ${missing[*]}" >&2
    echo "Запустите setup.sh, чтобы установить зависимости." >&2
    return 1
  fi
}

apply_platform_fixes() {
  local os_release_text=""

  [ ! -f /etc/os-release ] || os_release_text=$(cat /etc/os-release)

  if command -v getenforce >/dev/null 2>&1 &&
      [ "$(getenforce 2>/dev/null)" != "Disabled" ] &&
      [ -f "$SCRIPT_DIR/module/fixfilecontext.sh" ]; then
    echo "Применение правил SELinux..."
    bash "$SCRIPT_DIR/module/fixfilecontext.sh" || true
  fi

  if printf '%s\n' "$os_release_text" | grep -qi 'secureblue'; then
    command -v ujust >/dev/null 2>&1 &&
      ujust override-enable-module nfnetlink_queue >/dev/null 2>&1 || true
  fi

  if printf '%s\n' "$os_release_text" | grep -Eqi 'secureblue|altlinux' &&
      [ "$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null)" = "0" ]; then
    zapret_run_elevated sh -c \
      'printf "%s\n" "net.ipv4.tcp_timestamps = 1" > /etc/sysctl.d/90-zapret-tcp-timestamps.conf'
    zapret_run_elevated sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1 || true
  fi

  if command -v modprobe >/dev/null 2>&1; then
    zapret_run_elevated modprobe nfnetlink_queue >/dev/null 2>&1 || true
  fi
}

zapret_installation_ready() {
  [ -x "$ZAPRET_ROOT/nfq/nfqws" ] || return 1
  zapret_detect_service_manager >/dev/null 2>&1
}

bootstrap_zapret() {
  local manager

  check_bootstrap_files || return 1
  check_runtime_dependencies || return 1
  apply_platform_fixes

  echo "Установка бинарников zapret..."
  if ! zapret_run_elevated sh "$ZAPRET_ROOT/install_bin.sh"; then
    echo "Ошибка: не удалось подобрать и установить бинарники zapret" >&2
    return 1
  fi
  if [ ! -x "$ZAPRET_ROOT/nfq/nfqws" ]; then
    echo "Ошибка: после install_bin.sh не найден исполняемый nfqws" >&2
    return 1
  fi

  manager=$(zapret_detect_service_manager 2>/dev/null || true)
  if [ -z "$manager" ]; then
    manager=$(zapret_detect_init_system 2>/dev/null || true)
  fi
  if [ -z "$manager" ]; then
    echo "Ошибка: не удалось определить систему инициализации" >&2
    return 1
  fi

  echo "Настройка службы zapret ($manager)..."
  if ! zapret_install_service "$manager"; then
    echo "Ошибка: не удалось установить или запустить службу zapret ($manager)" >&2
    return 1
  fi

  echo "Zapret установлен и запущен."
}

activate_strategy() {
  local strategy_name="$1"

  if ! strategy_is_valid "$strategy_name"; then
    echo "Ошибка: стратегия '$strategy_name' отсутствует, пуста или содержит ошибку" >&2
    return 1
  fi

  if ! write_strategy_state "$strategy_name"; then
    echo "Ошибка: не удалось записать $STRATEGY_STATE" >&2
    return 1
  fi

  if zapret_installation_ready; then
    echo "Выбрана стратегия: $strategy_name"
    echo "Перезапуск zapret..."
    if ! zapret_service_action restart; then
      echo "Ошибка: стратегию записали, но службу перезапустить не удалось" >&2
      return 1
    fi
    echo "Стратегия применена."
  else
    echo "Выбрана стартовая стратегия: $strategy_name"
    bootstrap_zapret
  fi
}

read_current_strategy() {
  local current_strategy="general"

  if [ -f "$STRATEGY_STATE" ]; then
    current_strategy=$(sed -n '1{s/\r$//;p;}' "$STRATEGY_STATE" 2>/dev/null)
  fi
  valid_fragment_name "$current_strategy" || current_strategy="general"
  printf '%s\n' "$current_strategy"
}

choose_strategy() {
  local strategy_paths=()
  local strategy_path
  local strategy_name
  local current_strategy
  local choice
  local index

  while IFS= read -r strategy_path; do
    strategy_paths+=("$strategy_path")
  done < <(find "$STRATEGIES_DIR" -mindepth 1 -maxdepth 1 -type f -print | sort)

  if [ "${#strategy_paths[@]}" -eq 0 ]; then
    echo "Ошибка: в $STRATEGIES_DIR нет стратегий" >&2
    return 1
  fi

  current_strategy=$(read_current_strategy)
  while true; do
    clear
    echo "ВЫБОР СТРАТЕГИИ ZAPRET"
    echo "----------------------------------------"
    echo "Текущая стратегия: $current_strategy"
    echo

    index=1
    for strategy_path in "${strategy_paths[@]}"; do
      strategy_name=$(basename "$strategy_path")
      if [ "$strategy_name" = "$current_strategy" ]; then
        printf '%2d. %s (текущая)\n' "$index" "$strategy_name"
      else
        printf '%2d. %s\n' "$index" "$strategy_name"
      fi
      index=$((index + 1))
    done

    echo " 0. Выход"
    echo
    read -rp "Введите номер: " choice || return 1

    if [ "$choice" = "0" ]; then
      return 0
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] &&
        [ "$choice" -ge 1 ] &&
        [ "$choice" -le "${#strategy_paths[@]}" ]; then
      strategy_name=$(basename "${strategy_paths[$((choice - 1))]}")
      activate_strategy "$strategy_name"
      return $?
    fi

    echo "Неверный выбор."
    read -rp "Нажмите Enter для продолжения..." || true
  done
}

sync_runtime_assets || exit 1

case "${1:-}" in
  --strategy)
    [ -n "${2:-}" ] || {
      echo "Использование: $0 --strategy <идентификатор>" >&2
      exit 1
    }
    activate_strategy "$2"
    ;;
  --bootstrap)
    bootstrap_zapret
    ;;
  --sync-only)
    exit 0
    ;;
  "")
    if [ ! -t 0 ] || [ ! -t 1 ]; then
      echo "Для интерактивного выбора стратегии нужен терминал." >&2
      echo "Неинтерактивный вариант: $0 --strategy general" >&2
      exit 1
    fi
    choose_strategy
    ;;
  *)
    echo "Использование: $0 [--strategy <идентификатор>|--bootstrap|--sync-only]" >&2
    exit 1
    ;;
esac
