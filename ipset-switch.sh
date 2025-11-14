#!/bin/bash

# Цвета
GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"

# Пути к файлам
IPSET_FILE="/opt/zapret/hostlists/ipset-all.txt"
IPSET_BACKUP="${IPSET_FILE}.backup"
GAME_FILE="/opt/zapret/hostlists/.game_filter.enabled"
IP="203.0.113.113/32"

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
      ;;
    "none")
      echo "Переключение в режим any..."
      true > "$IPSET_FILE"  # Создаем пустой файл
      ;;
    "any")
      echo "Переключение в режим loaded..."
      if [ -f "$IPSET_BACKUP" ]; then
        rm -f "$IPSET_FILE"
        mv "$IPSET_BACKUP" "$IPSET_FILE"
      else
        echo "Ошибка: нет резервной копии для восстановления. Сначала обновите список"
        read -rp "Нажмите Enter для продолжения..."
        return
      fi
      ;;
  esac
  
  read -rp "Нажмите Enter для продолжения..."
}

# Переключение game filter
toggle_game() {
  # Создаем директорию если не существует
  mkdir -p "$(dirname "$GAME_FILE")"
  
  if [ -f "$GAME_FILE" ]; then
    echo "Отключение game filter..."
    rm -f "$GAME_FILE"
    echo -e "${YELLOW}Перезапустите zapret для применения изменений${RESET}"
  else
    echo "Включение game filter..."
    echo "ENABLED" > "$GAME_FILE"
    echo -e "${YELLOW}Перезапустите zapret для применения изменений${RESET}"
  fi
  
  read -rp "Нажмите Enter для продолжения..."
}

# Функция обновления ipset
update_ipset() {
  echo "Обновление ipset-all из kartavkun/zapret-discord-youtube..."
  local url="https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/hostlists/ipset-all.txt"
  
  # Создаем директорию если не существует
  mkdir -p "$(dirname "$IPSET_FILE")"
  
  curl -L -o "$IPSET_FILE" "$url"
  
  echo "Завершено"
  read -rp "Нажмите Enter для продолжения..."
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
    *) echo "Неверный выбор." 
       read -rp "Нажмите Enter для продолжения..." ;;
  esac
done
