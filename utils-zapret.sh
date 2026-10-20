#!/bin/bash

# Цвета
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# Пути к файлам
IPSET_FILE="/opt/zapret/hostlists/ipset-all.txt"
IPSET_BACKUP="${IPSET_FILE}.backup"
GAME_FILE="/opt/zapret/hostlists/.game_filter.enabled"
LIST_GENERAL="/opt/zapret/hostlists/list-general-user.txt"
LIST_EXCLUDE="/opt/zapret/hostlists/list-exclude-user.txt"
CONFIG_FILE="/opt/zapret/config"
IP="203.0.113.113/32"
SERVICE_NAME="zapret"
PROJECT_DIR="$HOME/zapret-configs"
UPDATE_STATE_DIR="$PROJECT_DIR/.updates"
UPDATE_BACKUP_DIR="$UPDATE_STATE_DIR/backups"
UPDATE_BRANCH="main"
UPDATE_ARCHIVE_URL="https://codeload.github.com/kartavkun/zapret-discord-youtube/tar.gz/refs/heads/$UPDATE_BRANCH"
SELECTED_BACKUP_DIR=""

# Функция для определения доступной утилиты повышения привилегий
detect_privilege_escalation() {
  if command -v doas &>/dev/null; then
    echo "doas"
  elif command -v sudo-rs &>/dev/null; then
    echo "sudo-rs"
  elif command -v sudo &>/dev/null; then
    echo "sudo"
  elif command -v run0 &>/dev/null; then
    echo "run0"
  else
    echo ""
  fi
}

ELEVATE_CMD=$(detect_privilege_escalation)

pause_menu() {
  echo
  read -rp "Нажмите Enter для продолжения..." || true
}

run_elevated() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return $?
  fi

  if [ -z "$ELEVATE_CMD" ]; then
    return 1
  fi

  "$ELEVATE_CMD" "$@"
}

ensure_elevation() {
  if [ "$(id -u)" -eq 0 ] || [ -n "$ELEVATE_CMD" ]; then
    return 0
  fi

  echo -e "${RED}Ошибка: не найдена утилита повышения привилегий (sudo/doas/run0)${RESET}"
  return 1
}

detect_service_manager() {
  if command -v systemctl >/dev/null && systemctl list-unit-files "${SERVICE_NAME}.service" --no-legend 2>/dev/null | grep -q .; then
    echo "systemd"
    return
  fi

  if command -v rc-service >/dev/null && { [ -x "/etc/init.d/$SERVICE_NAME" ] || rc-service "$SERVICE_NAME" status >/dev/null 2>&1; }; then
    echo "openrc"
    return
  fi

  if command -v dinitctl >/dev/null && { [ -e "/etc/dinit.d/$SERVICE_NAME" ] || [ -e "/usr/lib/dinit.d/$SERVICE_NAME" ]; }; then
    echo "dinit"
    return
  fi

  if command -v sv >/dev/null && { [ -e "/var/service/$SERVICE_NAME" ] || [ -e "/etc/service/$SERVICE_NAME" ] || [ -d "/etc/sv/$SERVICE_NAME" ]; }; then
    echo "runit"
    return
  fi

  if command -v s6-rc >/dev/null && { s6-rc -a list 2>/dev/null | grep -qx "$SERVICE_NAME" || [ -d "/etc/s6/adminsv/$SERVICE_NAME" ]; }; then
    echo "s6"
    return
  fi

  if [ -e "/etc/rc.d/rc.$SERVICE_NAME" ]; then
    echo "slackware"
    return
  fi

  if command -v service >/dev/null && { [ -e "/etc/init.d/$SERVICE_NAME" ] || service "$SERVICE_NAME" status >/dev/null 2>&1; }; then
    echo "sysvinit"
    return
  fi

  echo ""
}

service_is_active() {
  local manager="$1"

  case "$manager" in
    systemd) systemctl is-active --quiet "$SERVICE_NAME" ;;
    openrc) rc-service "$SERVICE_NAME" status >/dev/null 2>&1 ;;
    dinit)
      dinitctl is-started "$SERVICE_NAME" >/dev/null 2>&1 ||
        dinitctl status "$SERVICE_NAME" 2>/dev/null | grep -qi 'started'
      ;;
    runit) sv status "$SERVICE_NAME" 2>/dev/null | grep -q '^run:' ;;
    s6) s6-rc -a list 2>/dev/null | grep -qx "$SERVICE_NAME" ;;
    slackware) pgrep -f '/opt/zapret/.*/nfqws|/opt/zapret/.*/tpws|/opt/zapret/nfq/nfqws|/opt/zapret/tpws/tpws' >/dev/null 2>&1 ;;
    sysvinit) service "$SERVICE_NAME" status >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

service_is_enabled() {
  local manager="$1"

  case "$manager" in
    systemd) systemctl is-enabled --quiet "$SERVICE_NAME" ;;
    openrc) rc-update show default 2>/dev/null | grep -Eq "^[[:space:]]*$SERVICE_NAME[[:space:]]" ;;
    dinit)
      dinitctl is-enabled "$SERVICE_NAME" >/dev/null 2>&1 ||
        [ -e "/etc/dinit.d/boot.d/$SERVICE_NAME" ] ||
        [ -e "/etc/dinit.d/boot.d/$SERVICE_NAME.d" ]
      ;;
    runit) [ -e "/var/service/$SERVICE_NAME" ] || [ -e "/etc/service/$SERVICE_NAME" ] ;;
    s6) [ -e "/etc/s6/adminsv/default/contents.d/$SERVICE_NAME" ] ;;
    slackware) [ -x "/etc/rc.d/rc.$SERVICE_NAME" ] && grep -q "rc.$SERVICE_NAME start" /etc/rc.d/rc.local 2>/dev/null ;;
    sysvinit)
      if command -v update-rc.d >/dev/null 2>&1; then
        find /etc/rc*.d -name "S??$SERVICE_NAME" -print -quit 2>/dev/null | grep -q .
      elif command -v chkconfig >/dev/null 2>&1; then
        chkconfig --list "$SERVICE_NAME" 2>/dev/null | grep -q ':on'
      else
        return 1
      fi
      ;;
    *) return 1 ;;
  esac
}

service_action() {
  local action="$1"
  local manager
  manager=$(detect_service_manager)

  if [ -z "$manager" ]; then
    echo -e "${RED}Служба $SERVICE_NAME не найдена${RESET}"
    return 1
  fi

  if ! ensure_elevation; then
    return 1
  fi

  case "$manager:$action" in
    systemd:*) run_elevated systemctl "$action" "$SERVICE_NAME" ;;
    openrc:start|openrc:stop|openrc:restart) run_elevated rc-service "$SERVICE_NAME" "$action" ;;
    openrc:enable) run_elevated rc-update add "$SERVICE_NAME" default ;;
    openrc:disable) run_elevated rc-update del "$SERVICE_NAME" default ;;
    dinit:*) run_elevated dinitctl "$action" "$SERVICE_NAME" ;;
    runit:start) run_elevated sv up "$SERVICE_NAME" ;;
    runit:stop) run_elevated sv down "$SERVICE_NAME" ;;
    runit:restart) run_elevated sv restart "$SERVICE_NAME" ;;
    runit:enable)
      if [ -d "/etc/sv/$SERVICE_NAME" ]; then
        if [ -d /var/service ]; then
          run_elevated ln -sfn "/etc/sv/$SERVICE_NAME" "/var/service/$SERVICE_NAME"
        elif [ -d /etc/service ]; then
          run_elevated ln -sfn "/etc/sv/$SERVICE_NAME" "/etc/service/$SERVICE_NAME"
        else
          echo -e "${RED}Ошибка: не найден каталог /var/service или /etc/service${RESET}"
          return 1
        fi
      else
        echo -e "${RED}Ошибка: не найден /etc/sv/$SERVICE_NAME${RESET}"
        return 1
      fi
      ;;
    runit:disable)
      [ -L "/var/service/$SERVICE_NAME" ] && run_elevated rm -f "/var/service/$SERVICE_NAME"
      [ -L "/etc/service/$SERVICE_NAME" ] && run_elevated rm -f "/etc/service/$SERVICE_NAME"
      ;;
    s6:start) run_elevated s6-rc -u change "$SERVICE_NAME" ;;
    s6:stop) run_elevated s6-rc -d change "$SERVICE_NAME" ;;
    s6:restart)
      run_elevated s6-rc -d change "$SERVICE_NAME" &&
        run_elevated s6-rc -u change "$SERVICE_NAME"
      ;;
    s6:enable)
      run_elevated mkdir -p /etc/s6/adminsv/default/contents.d
      run_elevated touch "/etc/s6/adminsv/default/contents.d/$SERVICE_NAME"
      run_elevated s6-db-reload
      ;;
    s6:disable)
      run_elevated rm -f "/etc/s6/adminsv/default/contents.d/$SERVICE_NAME"
      run_elevated s6-db-reload
      ;;
    slackware:start|slackware:stop|slackware:restart) run_elevated "/etc/rc.d/rc.$SERVICE_NAME" "$action" ;;
    slackware:enable)
      run_elevated chmod +x "/etc/rc.d/rc.$SERVICE_NAME"
      if ! grep -q "rc.$SERVICE_NAME start" /etc/rc.d/rc.local 2>/dev/null; then
        printf '\n# Запуск службы zapret\nif [ -x /etc/rc.d/rc.zapret ]; then\n  /etc/rc.d/rc.zapret start\nfi\n' |
          run_elevated tee -a /etc/rc.d/rc.local >/dev/null
      fi
      ;;
    slackware:disable) run_elevated chmod -x "/etc/rc.d/rc.$SERVICE_NAME" ;;
    sysvinit:start|sysvinit:stop|sysvinit:restart) run_elevated service "$SERVICE_NAME" "$action" ;;
    sysvinit:enable)
      if command -v update-rc.d >/dev/null 2>&1; then
        run_elevated update-rc.d "$SERVICE_NAME" defaults
      elif command -v chkconfig >/dev/null 2>&1; then
        run_elevated chkconfig --add "$SERVICE_NAME"
        run_elevated chkconfig "$SERVICE_NAME" on
      else
        echo -e "${RED}Ошибка: не найден update-rc.d или chkconfig${RESET}"
        return 1
      fi
      ;;
    sysvinit:disable)
      if command -v update-rc.d >/dev/null 2>&1; then
        run_elevated update-rc.d "$SERVICE_NAME" remove
      elif command -v chkconfig >/dev/null 2>&1; then
        run_elevated chkconfig "$SERVICE_NAME" off
      else
        echo -e "${RED}Ошибка: не найден update-rc.d или chkconfig${RESET}"
        return 1
      fi
      ;;
    *) echo -e "${RED}Действие $action не поддерживается для $manager${RESET}"; return 1 ;;
  esac
}

# Функция перезапуска zapret
restart_zapret() {
  echo
  echo "Перезапуск службы zapret..."

  local manager
  manager=$(detect_service_manager)
  if [ -z "$manager" ]; then
    echo -e "${YELLOW}Не найдена система инициализации, пожалуйста, перезапустите zapret вручную${RESET}"
    return 1
  fi

  if service_action restart; then
    echo -e "${GREEN}Служба zapret перезапущена ($manager)${RESET}"
    return 0
  fi

  echo -e "${RED}Ошибка: не удалось перезапустить службу zapret ($manager)${RESET}"
  return 1
}

get_ipset_state() {
  if [ ! -f "$IPSET_FILE" ]; then
    echo "any"
    return
  fi
  
  local non_empty_count
  non_empty_count=$(grep -c '[^[:space:]]' "$IPSET_FILE" 2>/dev/null || true)
  non_empty_count=${non_empty_count:-0}
  
  if [ "$non_empty_count" -eq 0 ]; then
    echo "any"
  elif [ "$non_empty_count" -eq 1 ] && grep -Fqx -- "$IP" "$IPSET_FILE" 2>/dev/null; then
    echo "none"
  else
    echo "loaded"
  fi
}

# Проверка состояния ipset
check_ipset() {
  case "$(get_ipset_state)" in
    any)
      echo -e "IPSet: ${YELLOW}any${RESET}"
      ;;
    none)
      echo -e "IPSet: ${YELLOW}none${RESET}"
      ;;
    loaded)
      echo -e "IPSet: ${GREEN}loaded${RESET}"
      ;;
  esac
}

create_ipset_backup() {
  if [ ! -f "$IPSET_BACKUP" ] && [ -f "$IPSET_FILE" ]; then
    cp "$IPSET_FILE" "$IPSET_BACKUP"
    echo -e "${GREEN}Резервная копия создана${RESET}"
  fi
}

set_ipset_mode() {
  local mode="$1"
  local value="$2"
  local current_state
  current_state=$(get_ipset_state)

  if [ "$current_state" = "$mode" ]; then
    echo -e "${YELLOW}Уже в режиме $mode${RESET}"
    return
  fi

  echo "Установка режима $mode..."
  create_ipset_backup
  printf '%s\n' "$value" > "$IPSET_FILE"
  echo -e "${GREEN}IPSet установлен в режим $mode${RESET}"
  restart_zapret
}

restore_ipset_loaded() {
  if [ "$(get_ipset_state)" = "loaded" ]; then
    echo -e "${YELLOW}Уже в режиме loaded${RESET}"
    return
  fi

  echo "Установка режима loaded..."
  if [ -f "$IPSET_BACKUP" ]; then
    cp "$IPSET_BACKUP" "$IPSET_FILE"
    rm -f "$IPSET_BACKUP"
    echo -e "${GREEN}IPSet установлен в режим loaded, резервная копия удалена${RESET}"
    restart_zapret
  else
    echo -e "${RED}Ошибка: нет резервной копии для восстановления${RESET}"
    return
  fi
}

# Проверка состояния game filter
check_game() {
  if [ ! -f "$GAME_FILE" ]; then
    echo -e "Game Filter: ${YELLOW}выключен${RESET}"
    return
  fi
  
  local mode=$(cat "$GAME_FILE" 2>/dev/null)
  case "$mode" in
    all)
      echo -e "Game Filter: ${GREEN}включён (TCP и UDP)${RESET}"
      ;;
    tcp)
      echo -e "Game Filter: ${GREEN}включён (только TCP)${RESET}"
      ;;
    udp)
      echo -e "Game Filter: ${GREEN}включён (только UDP)${RESET}"
      ;;
    *)
      echo -e "Game Filter: ${YELLOW}включён (неизвестный режим)${RESET}"
      ;;
  esac
}

set_game_filter() {
  local mode="$1"
  local label="$2"

  echo "Включение game filter ($label)..."
  echo "$mode" > "$GAME_FILE"
  echo -e "${GREEN}Game Filter включён ($label)${RESET}"
  restart_zapret
}

disable_game_filter() {
  if [ -f "$GAME_FILE" ]; then
    echo "Отключение game filter..."
    rm -f "$GAME_FILE"
    echo -e "${GREEN}Game Filter выключен${RESET}"
    restart_zapret
  else
    echo -e "${YELLOW}Game Filter уже выключен${RESET}"
  fi
}

# Показ текущей стратегии
show_current_strategy() {
  if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "Стратегия: ${YELLOW}не установлена${RESET}"
    return
  fi
  
  # Читаем первую строку конфига и удаляем "# " в начале
  local strategy=$(head -1 "$CONFIG_FILE" 2>/dev/null | sed 's/^# //')
  
  if [ -z "$strategy" ]; then
    echo -e "Стратегия: ${YELLOW}неизвестна${RESET}"
  else
    echo -e "Стратегия: ${GREEN}$strategy${RESET}"
  fi
}

check_zapret_service() {
  local manager
  manager=$(detect_service_manager)

  if [ -z "$manager" ]; then
    echo -e "Служба zapret: ${YELLOW}не найдена${RESET}"
    return
  fi

  echo -e "Служба zapret: $(service_status_text "$manager") (${manager}, $(service_autostart_text "$manager"))"
}

show_service_status() {
  local manager
  manager=$(detect_service_manager)

  echo
  if [ -z "$manager" ]; then
    echo -e "${RED}Служба zapret не найдена${RESET}"
    return 1
  fi

  echo "Система инициализации: $manager"
  echo -e "Статус: $(service_status_text "$manager")"
  echo -e "Автозапуск: $(service_autostart_text "$manager" short)"
}

service_status_text() {
  local manager="$1"

  if service_is_active "$manager"; then
    echo -e "${GREEN}запущена${RESET}"
  else
    echo -e "${RED}остановлена${RESET}"
  fi
}

service_autostart_text() {
  local manager="$1"
  local mode="$2"

  if service_is_enabled "$manager"; then
    if [ "$mode" = "short" ]; then
      echo -e "${GREEN}включён${RESET}"
    else
      echo -e "${GREEN}автозапуск включён${RESET}"
    fi
  elif [ "$mode" = "short" ]; then
    echo -e "${YELLOW}выключен${RESET}"
  else
    echo -e "${YELLOW}автозапуск выключен${RESET}"
  fi
}

manage_zapret_service() {
  while true; do
    clear
    echo "УПРАВЛЕНИЕ СЛУЖБОЙ ZAPRET"
    echo "----------------------------------------"
    show_service_status
    echo
    echo "1. Запустить службу"
    echo "2. Остановить службу"
    echo "3. Перезапустить службу"
    echo "4. Включить автозапуск"
    echo "5. Отключить автозапуск"
    echo "0. Назад"
    echo
    read -rp "Выберите действие: " service_choice || return

    case $service_choice in
      1) run_service_menu_action start "Служба zapret запущена" ;;
      2) run_service_menu_action stop "Служба zapret остановлена" ;;
      3) run_service_menu_action restart "Служба zapret перезапущена" ;;
      4) run_service_menu_action enable "Автозапуск zapret включён" ;;
      5) run_service_menu_action disable "Автозапуск zapret отключён" ;;
      0) return ;;
      *) echo -e "${RED}Неверный выбор${RESET}" ;;
    esac

    pause_menu
  done
}

run_service_menu_action() {
  local action="$1"
  local success_msg="$2"

  service_action "$action" &&
    echo -e "${GREEN}${success_msg}${RESET}"
}

# Меню выбора режима ipset
ipset_menu() {
  # Создаем директорию если не существует
  mkdir -p "$(dirname "$IPSET_FILE")"

  echo
  echo "1. Режим 'any' (пустой список)"
  echo "2. Режим 'none' (только заглушка)"
  echo "3. Режим 'loaded' (полный список)"
  echo "0. Назад"
  echo
  read -rp "Выберите режим: " ipset_choice || return
  
  case $ipset_choice in
    1) set_ipset_mode "any" "" ;;
    2) set_ipset_mode "none" "$IP" ;;
    3) restore_ipset_loaded ;;
    0) return ;;
    *) echo -e "${RED}Неверный выбор${RESET}" ;;
  esac
}

# Переключение game filter с режимами
toggle_game() {
  # Создаем директорию если не существует
  mkdir -p "$(dirname "$GAME_FILE")"
  
  echo
  echo "Выберите режим game filter:"
  echo "1. Отключить"
  echo "2. TCP и UDP"
  echo "3. Только TCP"
  echo "4. Только UDP"
  echo "0. Назад"
  echo
  read -rp "Выберите опцию: " game_choice || return
  
  case $game_choice in
    1) disable_game_filter ;;
    2) set_game_filter "all" "TCP и UDP" ;;
    3) set_game_filter "tcp" "только TCP" ;;
    4) set_game_filter "udp" "только UDP" ;;
    0) return ;;
    *)
      echo -e "${RED}Неверный выбор${RESET}"
      ;;
  esac
}

# Функция обновления hosts файла из репозитория Flowseal
update_hosts() {
  echo "Обновление hosts файла..."
  
  local hosts_file="/etc/hosts"
  local hosts_url="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/hosts"
  local temp_file="/tmp/zapret_hosts.txt"
  
  # Скачиваем файл
  if ! curl -L -s -o "$temp_file" "$hosts_url"; then
    echo -e "${RED}Ошибка: не удалось скачать файл hosts из репозитория${RESET}"
    echo "Скачайте файл вручную с: $hosts_url"
    return 1
  fi
  
  if [ ! -f "$temp_file" ]; then
    echo -e "${RED}Ошибка: временный файл не создан${RESET}"
    return 1
  fi
  
  # Получаем первую и последнюю строку из скачанного файла
  local first_line
  local last_line
  first_line=$(head -1 "$temp_file") || { rm -f "$temp_file"; return 1; }
  last_line=$(tail -1 "$temp_file") || { rm -f "$temp_file"; return 1; }
  
  # Проверяем, нужно ли обновлять
  local needs_update=0
  
  if ! grep -q "^${first_line}$" "$hosts_file" 2>/dev/null; then
    echo "Первая строка из репозитория не найдена в hosts файле"
    needs_update=1
  fi
  
  if ! grep -q "^${last_line}$" "$hosts_file" 2>/dev/null; then
    echo "Последняя строка из репозитория не найдена в hosts файле"
    needs_update=1
  fi
  
  if [ "$needs_update" -eq 1 ]; then
    echo
    echo -e "${YELLOW}Hosts файл требует обновления${RESET}"
    echo "Содержимое для добавления:"
    echo "---"
    cat "$temp_file"
    echo "---"
    echo
    read -rp "Добавить содержимое в $hosts_file? [Y/n]: " response || {
      echo "Обновление отменено"
      rm -f "$temp_file"
      return 1
    }
    
    case "${response,,}" in
      y|yes|"")
        if [ -z "$ELEVATE_CMD" ]; then
          echo -e "${RED}Ошибка: не найдена утилита повышения привилегий${RESET}"
          return 1
        fi
        
        # Добавляем пустую строку перед новым содержимым
        echo "" | $ELEVATE_CMD tee -a "$hosts_file" > /dev/null
        cat "$temp_file" | $ELEVATE_CMD tee -a "$hosts_file" > /dev/null
        
        echo -e "${GREEN}Hosts файл успешно обновлён${RESET}"
        rm -f "$temp_file"
        return 0
        ;;
      n|no)
        echo "Обновление отменено"
        rm -f "$temp_file"
        return 1
        ;;
      *)
        echo -e "${RED}Неверный ввод${RESET}"
        rm -f "$temp_file"
        return 1
        ;;
    esac
  else
    echo -e "${GREEN}Hosts файл уже актуален${RESET}"
    rm -f "$temp_file"
    return 0
  fi
}

# Функция обновления ipset
update_ipset() {
  echo "Обновление ipset-all из Flowseal/zapret-discord-youtube..."
  local url="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/lists/ipset-all.txt.backup"
  local temp_file
  temp_file=$(mktemp "/tmp/zapret-ipset-all.XXXXXX") || {
    echo -e "${RED}Ошибка: не удалось создать временный файл${RESET}"
    return 1
  }
  
  # Создаем директорию если не существует
  if ! mkdir -p "$(dirname "$IPSET_FILE")"; then
    echo -e "${RED}Ошибка: не удалось создать директорию ipset${RESET}"
    rm -f "$temp_file"
    return 1
  fi
  
  if curl -fsSL -o "$temp_file" "$url" && [ -s "$temp_file" ]; then
    if ! mv "$temp_file" "$IPSET_FILE"; then
      echo -e "${RED}Ошибка: не удалось заменить $IPSET_FILE${RESET}"
      rm -f "$temp_file"
      return 1
    fi
    chmod 644 "$IPSET_FILE"
    echo -e "${GREEN}Список ipset-all успешно обновлён${RESET}"
    restart_zapret
  else
    echo -e "${RED}Ошибка при обновлении списка${RESET}"
    rm -f "$temp_file"
    return 1
  fi
}

download_file() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$output" "$url"
  else
    echo -e "${RED}Ошибка: curl или wget не найден${RESET}"
    return 1
  fi
}

get_current_project_commit() {
  if [ -f "$UPDATE_STATE_DIR/current_commit" ]; then
    head -n 1 "$UPDATE_STATE_DIR/current_commit"
    return
  fi

  if command -v git >/dev/null 2>&1 && [ -d "$PROJECT_DIR/.git" ]; then
    git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null && return
  fi

  echo "unknown"
}

ensure_project_dir() {
  if [ -d "$PROJECT_DIR" ]; then
    return 0
  fi

  echo -e "${RED}Ошибка: папка $PROJECT_DIR не найдена${RESET}"
  return 1
}

validate_update_source() {
  local source_dir="$1"
  local required_path

  for required_path in setup.sh install.sh utils-zapret.sh configs hostlists utils; do
    if [ ! -e "$source_dir/$required_path" ]; then
      echo -e "${RED}Ошибка: в архиве нет $required_path${RESET}"
      return 1
    fi
  done
}

get_archive_commit() {
  local source_dir="$1"
  local archive_name
  local archive_commit

  archive_name=$(basename "$source_dir")
  archive_commit="${archive_name##*-}"

  if [[ "$archive_commit" =~ ^[0-9a-f]{40}$ ]]; then
    echo "$archive_commit"
  else
    echo "$UPDATE_BRANCH"
  fi
}

create_project_backup() {
  local backup_dir="$1"
  local from_commit="$2"
  local to_commit="$3"

  mkdir -p "$backup_dir/files" || return 1
  tar -C "$PROJECT_DIR" \
    --exclude='./.updates' \
    --exclude='./.git' \
    -cf - . | tar -C "$backup_dir/files" -xf - || return 1

  {
    printf 'from_commit=%s\n' "$from_commit"
    printf 'to_commit=%s\n' "$to_commit"
    printf 'date=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  } > "$backup_dir/metadata"
}

clear_project_files() {
  find "$PROJECT_DIR" -mindepth 1 -maxdepth 1 \
    ! -name '.updates' \
    ! -name '.git' \
    -exec rm -rf {} +
}

copy_project_tree() {
  local source_dir="$1"

  tar -C "$source_dir" -cf - . | tar -C "$PROJECT_DIR" -xf -
}

apply_project_update() {
  local source_dir="$1"

  clear_project_files || return 1
  copy_project_tree "$source_dir"
}

update_project_files() {
  local current_commit
  local latest_commit
  local archive_file
  local temp_dir
  local source_dir
  local backup_dir
  local last_backup_dir
  local answer

  echo "Обновление файлов zapret-discord-youtube..."
  echo "Будет изменена только папка: $PROJECT_DIR"
  echo
  ensure_project_dir || return 1
  read -rp "Продолжить? [Y/n]: " answer || return 1
  case "${answer,,}" in
    y|yes|"") ;;
    n|no) echo "Обновление отменено"; return 1 ;;
    *) echo -e "${RED}Неверный ввод${RESET}"; return 1 ;;
  esac

  if ! command -v tar >/dev/null 2>&1; then
    echo -e "${RED}Ошибка: tar не найден${RESET}"
    return 1
  fi

  current_commit=$(get_current_project_commit)
  archive_file=$(mktemp "/tmp/zapret-update.XXXXXX.tar.gz") || return 1
  temp_dir=$(mktemp -d "/tmp/zapret-update.XXXXXX") || {
    rm -f "$archive_file"
    return 1
  }

  if ! download_file "$UPDATE_ARCHIVE_URL" "$archive_file"; then
    echo -e "${RED}Ошибка: не удалось скачать архив обновления${RESET}"
    rm -rf "$temp_dir" "$archive_file"
    return 1
  fi

  if ! tar -xzf "$archive_file" -C "$temp_dir"; then
    echo -e "${RED}Ошибка: не удалось распаковать архив обновления${RESET}"
    rm -rf "$temp_dir" "$archive_file"
    return 1
  fi

  source_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  if [ -z "$source_dir" ] || ! validate_update_source "$source_dir"; then
    rm -rf "$temp_dir" "$archive_file"
    return 1
  fi
  latest_commit=$(get_archive_commit "$source_dir")

  if project_matches_tree "$source_dir"; then
    rm -rf "$temp_dir" "$archive_file"
    echo -e "${GREEN}Файлы уже актуальны, обновление не требуется${RESET}"
    return 0
  fi

  last_backup_dir=$(latest_backup_dir)
  if project_matches_backup "$last_backup_dir"; then
    backup_dir="$last_backup_dir"
    echo -e "${YELLOW}Резервная копия уже актуальна: $backup_dir${RESET}"
  else
    backup_dir="$UPDATE_BACKUP_DIR/$(date '+%Y-%m-%d_%H-%M-%S')"
    if ! create_project_backup "$backup_dir" "$current_commit" "$latest_commit"; then
      echo -e "${RED}Ошибка: не удалось создать резервную копию${RESET}"
      rm -rf "$temp_dir" "$archive_file"
      return 1
    fi
    echo -e "${GREEN}Резервная копия создана: $backup_dir${RESET}"
    prune_backup_dirs
  fi

  if ! apply_project_update "$source_dir"; then
    echo -e "${RED}Ошибка: не удалось обновить файлы${RESET}"
    echo "Резервная копия: $backup_dir"
    rm -rf "$temp_dir" "$archive_file"
    return 1
  fi

  mkdir -p "$UPDATE_STATE_DIR"
  printf '%s\n' "$latest_commit" > "$UPDATE_STATE_DIR/current_commit"
  rm -rf "$temp_dir" "$archive_file"
  echo -e "${GREEN}Файлы успешно обновлены${RESET}"
  exit 0
}

latest_backup_dir() {
  find "$UPDATE_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -n 1
}

list_backup_dirs() {
  find "$UPDATE_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

# Храним только 5 последних бэкапов, остальное сносим (сортировка по новой направлению: свежие сверху)
prune_backup_dirs() {
  list_backup_dirs | sort -r | tail -n +6 | xargs -r rm -rf --
}

select_backup_dir() {
  local -a backups
  local backup
  local choice
  local index

  SELECTED_BACKUP_DIR=""
  mapfile -t backups < <(list_backup_dirs)
  case "${#backups[@]}" in
    0) return 1 ;;
    1)
      SELECTED_BACKUP_DIR="${backups[0]}"
      return 0
      ;;
  esac

  echo "Найдено несколько резервных копий:"
  echo "1. Использовать последнюю: ${backups[$((${#backups[@]} - 1))]}"
  echo "2. Выбрать вручную"
  echo "0. Назад"
  echo
  read -rp "Выберите действие: " choice || return 2

  case "$choice" in
    1) SELECTED_BACKUP_DIR="${backups[$((${#backups[@]} - 1))]}" ;;
    2)
      echo
      echo "Доступные резервные копии:"
      index=1
      for backup in "${backups[@]}"; do
        echo "[$index] $backup"
        index=$((index + 1))
      done
      echo "0. Назад"
      echo
      read -rp "Выберите резервную копию: " choice || return 2
      if [ "$choice" = "0" ]; then
        return 2
      fi
      if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
        echo -e "${RED}Неверный выбор${RESET}"
        return 2
      fi
      SELECTED_BACKUP_DIR="${backups[$((choice - 1))]}"
      ;;
    0) return 2 ;;
    *)
      echo -e "${RED}Неверный выбор${RESET}"
      return 2
      ;;
  esac
}

project_matches_backup() {
  local backup_dir="$1"

  [ -d "$backup_dir/files" ] || return 1
  command -v diff >/dev/null 2>&1 || return 1
  diff -qr -x .updates -x .git "$PROJECT_DIR" "$backup_dir/files" >/dev/null 2>&1
}

project_matches_tree() {
  local source_dir="$1"

  command -v diff >/dev/null 2>&1 || return 1
  diff -qr -x .updates -x .git "$PROJECT_DIR" "$source_dir" >/dev/null 2>&1
}

rollback_project_update() {
  local backup_dir
  local from_commit
  local answer
  local select_status

  ensure_project_dir || return 1
  select_backup_dir
  select_status=$?
  case "$select_status" in
    0) ;;
    1) echo -e "${YELLOW}Нет резервной копии для отката${RESET}"; return 1 ;;
    *) echo "Откат отменён"; return 1 ;;
  esac
  backup_dir="$SELECTED_BACKUP_DIR"
  if [ -z "$backup_dir" ] || [ ! -d "$backup_dir/files" ]; then
    echo -e "${YELLOW}Нет резервной копии для отката${RESET}"
    return 1
  fi

  echo "Откат файлов zapret-discord-youtube..."
  echo "Резервная копия: $backup_dir"
  echo "Будет изменена только папка: $PROJECT_DIR"
  echo
  read -rp "Продолжить? [Y/n]: " answer || return 1
  case "${answer,,}" in
    y|yes|"") ;;
    n|no) echo "Откат отменён"; return 1 ;;
    *) echo -e "${RED}Неверный ввод${RESET}"; return 1 ;;
  esac

  clear_project_files || return 1
  copy_project_tree "$backup_dir/files" || return 1

  if grep -q '^from_commit=' "$backup_dir/metadata" 2>/dev/null; then
    from_commit=$(sed -n 's/^from_commit=//p' "$backup_dir/metadata" | head -n 1)
    mkdir -p "$UPDATE_STATE_DIR"
    printf '%s\n' "$from_commit" > "$UPDATE_STATE_DIR/current_commit"
  fi

  if rm -rf "$backup_dir"; then
    echo -e "${GREEN}Использованная резервная копия удалена${RESET}"
  else
    echo -e "${YELLOW}Откат выполнен, но резервную копию удалить не удалось: $backup_dir${RESET}"
  fi

  echo -e "${GREEN}Откат успешно выполнен${RESET}"
  exit 0
}

# Функция добавления домена в список
add_domain() {
  local input="$1"
  local list_file="$2"
  local domain
  local list_dir

  input=$(printf '%s' "$input" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
  
  # Если это URL, извлекаем домен
  if [[ "$input" =~ ^https?:// ]]; then
    # Парсим домен из URL (например: https://github.com/user/repo -> github.com)
    domain=$(echo "$input" | sed -E 's|^https?://([^/]+).*|\1|')
  else
    domain="$input"
  fi
  
  # Удаляем www. если есть
  domain="${domain,,}"
  domain="${domain%%:*}"
  domain="${domain#www.}"
  domain=$(printf '%s' "$domain" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')

  if [ -z "$domain" ]; then
    echo -e "${RED}Ошибка: пустой домен${RESET}"
    return 1
  fi

  if [[ ! "$domain" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; then
    echo -e "${RED}Ошибка: некорректный домен ($domain)${RESET}"
    return 1
  fi

  list_dir=$(dirname "$list_file")
  mkdir -p "$list_dir"
  
  # Проверяем, есть ли уже такой домен
  if grep -Fqx -- "$domain" "$list_file" 2>/dev/null; then
    echo -e "${YELLOW}Домен $domain уже в списке${RESET}"
    return 1
  fi
  
  # Добавляем домен
  # Проверяем, заканчивается ли файл на новую строку
  if [ -f "$list_file" ] && [ -s "$list_file" ] && [ "$(tail -c 1 "$list_file" | wc -l)" -eq 0 ]; then
    # Файл существует, не пустой и не заканчивается на \n
    echo "" >> "$list_file"
  fi
  echo "$domain" >> "$list_file"
  echo -e "${GREEN}Домен $domain добавлен в список${RESET}"
  return 0
}

# Меню добавления доменов
add_domains_menu() {
  echo
  echo "Добавление доменов в списки"
  echo "1. Добавить в list-general-user.txt"
  echo "2. Добавить в list-exclude-user.txt"
  echo "0. Назад"
  echo
  read -rp "Выберите действие: " choice || return
  
  case $choice in
    1)
      read -rp "Введите домен или URL: " input || return
      add_domain "$input" "$LIST_GENERAL"
      ;;
    2)
      read -rp "Введите домен или URL: " input || return
      add_domain "$input" "$LIST_EXCLUDE"
      ;;
    0) return ;;
    *) echo -e "${RED}Неверный выбор${RESET}" ;;
  esac
}

# Функция запуска тестов zapret
run_zapret_tests() {
  local test_script="$HOME/zapret-configs/utils/test-zapret.lua"
  
  if [ ! -f "$test_script" ]; then
    echo -e "${RED}Ошибка: тестовый скрипт не найден ($test_script)${RESET}"
    return 1
  fi
  
  if ! command -v lua &>/dev/null; then
    echo -e "${RED}Ошибка: lua не установлена${RESET}"
    return 1
  fi
  
  echo
  echo -e "${GREEN}Запуск тестирования конфигураций zapret...${RESET}"
  echo "Это может занять несколько минут."
  echo
  
  lua "$test_script"
}

# Параллельный запуск может одновременно переписать ipset и конфиг
if command -v flock >/dev/null 2>&1; then
  exec 9>/tmp/zapret-utils.lock
  flock -n 9 || { echo -e "${RED}zapret-utils уже запущен в другом терминале${RESET}"; exit 1; }
fi

# Основное меню
while true; do
  clear
  echo "МЕНЕДЖЕР ZAPRET"
  echo "----------------------------------------"
  echo
  echo ":: СОСТОЯНИЕ"
  check_ipset
  check_game
  show_current_strategy
  check_zapret_service
  echo
  echo ":: ПАРАМЕТРЫ"
  echo "1. Game Filter"
  echo "2. IPSet Filter"
  echo "3. Управление службой zapret"
  echo
  echo ":: ОБНОВЛЕНИЯ"
  echo "4. Обновить список IPSet"
  echo "5. Обновить файл hosts"
  echo "6. Обновить файлы проекта"
  echo "7. Откатить последнее обновление"
  echo
  echo ":: ИНСТРУМЕНТЫ"
  echo "8. Добавить домен в список"
  echo "9. Запустить тесты"
  echo
  echo "----------------------------------------"
  echo "0. Выход"
  echo
  read -rp "Выберите опцию (0-9): " CHOICE || exit 0
  case $CHOICE in
    1) toggle_game ;;
    2) ipset_menu ;;
    3) manage_zapret_service ;;
    4) update_ipset ;;
    5) update_hosts ;;
    6) update_project_files ;;
    7) rollback_project_update ;;
    8) add_domains_menu ;;
    9) run_zapret_tests ;;
    0) clear; exit 0 ;;
    *) echo -e "${RED}Неверный выбор.${RESET}" ;;
  esac
  
  pause_menu
done
