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
IP="203.0.113.113/32"

# Функция для определения доступной утилиты повышения привилегий
detect_privilege_escalation() {
  if command -v doas &>/dev/null; then
    echo "doas"
  elif command -v sudo &>/dev/null; then
    echo "sudo"
  else
    echo ""
  fi
}

ELEVATE_CMD=$(detect_privilege_escalation)

# Функция перезапуска zapret
restart_zapret() {
  echo
  echo "Перезапуск службы zapret..."
  
  if [ -z "$ELEVATE_CMD" ]; then
    echo -e "${RED}Ошибка: не найдена утилита повышения привилегий (sudo/doas)${RESET}"
    echo "Пожалуйста, перезапустите zapret вручную"
    return 1
  fi
  
  try_restart() {
    if eval "$1"; then
      echo -e "${GREEN}Служба zapret перезапущена ($2)${RESET}"
      return 0
    fi
    return 1
  }
  
  # systemd
  if command -v systemctl >/dev/null; then
    systemctl is-active --quiet zapret 2>/dev/null &&
      try_restart "$ELEVATE_CMD systemctl restart zapret" "systemd" && return 0
  fi
  
  # OpenRC
  if command -v rc-service >/dev/null; then
    rc-service zapret status &>/dev/null &&
      try_restart "$ELEVATE_CMD rc-service zapret restart" "OpenRC" && return 0
  fi
  
  # runit
  if command -v sv >/dev/null; then
    if [ -d /var/service/zapret ] || [ -d /etc/service/zapret ]; then
      try_restart "$ELEVATE_CMD sv restart zapret" "runit" && return 0
    fi
  fi
  
  # s6
  if command -v s6-rc >/dev/null; then
    try_restart "$ELEVATE_CMD s6-rc -d change zapret && $ELEVATE_CMD s6-rc -u change zapret" "s6" && return 0
  fi
  
  # sysvinit
  if command -v service >/dev/null; then
    service zapret status &>/dev/null 2>&1 &&
      try_restart "$ELEVATE_CMD service zapret restart" "sysvinit" && return 0
  fi
  
  # Slackware
  if [ -x /etc/rc.d/rc.zapret ]; then
    try_restart "$ELEVATE_CMD /etc/rc.d/rc.zapret restart" "Slackware" && return 0
  fi
  
  echo -e "${YELLOW}Не найдена система инициализации, пожалуйста, перезапустите zapret вручную${RESET}"
  return 1
}

# Проверка состояния ipset
check_ipset() {
  if [ ! -f "$IPSET_FILE" ]; then
    echo -e "IPSet: ${YELLOW}any${RESET}"
    return
  fi
  
  local line_count
  line_count=$(wc -l < "$IPSET_FILE" 2>/dev/null || echo "0")
  
  if [ "$line_count" -eq 0 ]; then
    echo -e "IPSet: ${YELLOW}any${RESET}"
  elif grep -q "^$IP$" "$IPSET_FILE" 2>/dev/null; then
    echo -e "IPSet: ${YELLOW}none${RESET}"
  else
    echo -e "IPSet: ${GREEN}loaded${RESET}"
  fi
}

# Проверка состояния game filter
check_game() {
  if [ -f "$GAME_FILE" ]; then
    echo -e "Game Filter: ${GREEN}включён${RESET}"
  else
    echo -e "Game Filter: ${YELLOW}выключен${RESET}"
  fi
}

# Переключение ipset
toggle_ipset() {
  # Создаем директорию если не существует
  mkdir -p "$(dirname "$IPSET_FILE")"
  
  # Определяем текущее состояние
  local current_state="any"
  if [ -f "$IPSET_FILE" ]; then
    local line_count
    line_count=$(wc -l < "$IPSET_FILE" 2>/dev/null || echo "0")
    if [ "$line_count" -eq 0 ]; then
      current_state="any"
    elif grep -q "^$IP$" "$IPSET_FILE" 2>/dev/null; then
      current_state="none"
    else
      current_state="loaded"
    fi
  fi
  
  case "$current_state" in
    "loaded")
      echo "Переключение в режим none..."
      if [ ! -f "$IPSET_BACKUP" ]; then
        mv "$IPSET_FILE" "$IPSET_BACKUP"
      else
        rm -f "$IPSET_BACKUP"
        mv "$IPSET_FILE" "$IPSET_BACKUP"
      fi
      echo "$IP" > "$IPSET_FILE"
      echo -e "${GREEN}IPSet переключён в режим none${RESET}"
      restart_zapret
      ;;
    "none")
      echo "Переключение в режим any..."
      true > "$IPSET_FILE"  # Создаем пустой файл
      echo -e "${GREEN}IPSet переключён в режим any${RESET}"
      restart_zapret
      ;;
    "any")
      echo "Переключение в режим loaded..."
      if [ -f "$IPSET_BACKUP" ]; then
        rm -f "$IPSET_FILE"
        mv "$IPSET_BACKUP" "$IPSET_FILE"
        echo -e "${GREEN}IPSet переключён в режим loaded${RESET}"
        restart_zapret
      else
        echo -e "${RED}Ошибка: нет резервной копии для восстановления. Сначала обновите список${RESET}"
        return
      fi
      ;;
  esac
}

# Переключение game filter
toggle_game() {
  # Создаем директорию если не существует
  mkdir -p "$(dirname "$GAME_FILE")"
  
  if [ -f "$GAME_FILE" ]; then
    echo "Отключение game filter..."
    rm -f "$GAME_FILE"
    echo -e "${GREEN}Game Filter выключен${RESET}"
    restart_zapret
  else
    echo "Включение game filter..."
    echo "ENABLED" > "$GAME_FILE"
    echo -e "${GREEN}Game Filter включён${RESET}"
    restart_zapret
  fi
}

# Функция обновления ipset
update_ipset() {
  echo "Обновление ipset-all из kartavkun/zapret-discord-youtube..."
  local url="https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/hostlists/ipset-all.txt"
  
  # Создаем директорию если не существует
  mkdir -p "$(dirname "$IPSET_FILE")"
  
  if curl -L -o "$IPSET_FILE" "$url"; then
    echo -e "${GREEN}Список ipset-all успешно обновлён${RESET}"
    restart_zapret
  else
    echo -e "${RED}Ошибка при обновлении списка${RESET}"
  fi
}

# Основное меню
while true; do
  clear
  echo "Состояние:"
  check_ipset
  check_game
  echo
  echo "1. Переключить IPSet"
  echo "2. Переключить Game Filter"
  echo "3. Обновить ipset список"
  echo "0. Выход"
  echo
  read -rp "Выберите действие: " CHOICE
  case $CHOICE in
    1) toggle_ipset ;;
    2) toggle_game ;;
    3) update_ipset ;;
    0) clear; exit 0 ;;
    *) echo -e "${RED}Неверный выбор.${RESET}" ;;
  esac
  
  # Небольшая пауза для чтения сообщений
  sleep 1
done
