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
LIST_GENERAL="/opt/zapret/hostlists/list-general.txt"
LIST_EXCLUDE="/opt/zapret/hostlists/list-exclude.txt"
CONFIG_FILE="/opt/zapret/config"
IP="203.0.113.113/32"

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
  
  # Если файл пустой или содержит только пустые строки
  if [ "$line_count" -eq 0 ] || [ "$line_count" -eq 1 ] && [ -z "$(cat "$IPSET_FILE" 2>/dev/null)" ]; then
    echo -e "IPSet: ${YELLOW}any${RESET}"
  # Если файл содержит только одну строку с тестовым IP
  elif [ "$line_count" -eq 1 ] && grep -q "^$IP$" "$IPSET_FILE" 2>/dev/null; then
    echo -e "IPSet: ${YELLOW}none${RESET}"
  # Если файл содержит много строк (полный список)
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

# Меню выбора режима ipset
ipset_menu() {
  # Создаем директорию если не существует
  mkdir -p "$(dirname "$IPSET_FILE")"
  
  # Определяем текущее состояние
  local current_state="any"
  if [ -f "$IPSET_FILE" ]; then
    local line_count
    line_count=$(wc -l < "$IPSET_FILE" 2>/dev/null || echo "0")
    
    # Если файл пустой или содержит только пустые строки
    if [ "$line_count" -eq 0 ] || [ "$line_count" -eq 1 ] && [ -z "$(cat "$IPSET_FILE" 2>/dev/null)" ]; then
      current_state="any"
    # Если файл содержит только одну строку с тестовым IP
    elif [ "$line_count" -eq 1 ] && grep -q "^$IP$" "$IPSET_FILE" 2>/dev/null; then
      current_state="none"
    # Если файл содержит много строк (полный список)
    else
      current_state="loaded"
    fi
  fi
  
  echo
  echo "1. Режим 'any' (пустой список)"
  echo "2. Режим 'none' (только заглушка)"
  echo "3. Режим 'loaded' (полный список)"
  echo "0. Назад"
  echo
  read -rp "Выберите режим: " ipset_choice
  
  case $ipset_choice in
    1)
      if [ "$current_state" = "any" ]; then
        echo -e "${YELLOW}Уже в режиме any${RESET}"
        return
      fi
      echo "Установка режима any..."
      # Создаём backup если его нет (переходим из loaded)
      if [ ! -f "$IPSET_BACKUP" ] && [ -f "$IPSET_FILE" ]; then
        cp "$IPSET_FILE" "$IPSET_BACKUP"
        echo -e "${GREEN}Резервная копия создана${RESET}"
      fi
      echo '' > "$IPSET_FILE"
      echo -e "${GREEN}IPSet установлен в режим any${RESET}"
      restart_zapret
      ;;
    2)
      if [ "$current_state" = "none" ]; then
        echo -e "${YELLOW}Уже в режиме none${RESET}"
        return
      fi
      echo "Установка режима none..."
      # Создаём backup если его нет (переходим из loaded)
      if [ ! -f "$IPSET_BACKUP" ] && [ -f "$IPSET_FILE" ]; then
        cp "$IPSET_FILE" "$IPSET_BACKUP"
        echo -e "${GREEN}Резервная копия создана${RESET}"
      fi
      echo "$IP" > "$IPSET_FILE"
      echo -e "${GREEN}IPSet установлен в режим none${RESET}"
      restart_zapret
      ;;
    3)
      if [ "$current_state" = "loaded" ]; then
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
      ;;
    0) return ;;
    *) echo -e "${RED}Неверный выбор${RESET}" ;;
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
  local first_line=$(head -1 "$temp_file")
  local last_line=$(tail -1 "$temp_file")
  
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
    read -rp "Добавить содержимое в $hosts_file? [Y/n]: " response
    
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
  
  # Создаем директорию если не существует
  mkdir -p "$(dirname "$IPSET_FILE")"
  
  if curl -L -o "$IPSET_FILE" "$url"; then
    echo -e "${GREEN}Список ipset-all успешно обновлён${RESET}"
    restart_zapret
  else
    echo -e "${RED}Ошибка при обновлении списка${RESET}"
  fi
}

# Функция добавления домена в список
add_domain() {
  local input="$1"
  local list_file="$2"
  local domain
  
  # Если это URL, извлекаем домен
  if [[ "$input" =~ ^https?:// ]]; then
    # Парсим домен из URL (например: https://github.com/user/repo -> github.com)
    domain=$(echo "$input" | sed -E 's|^https?://([^/]+).*|\1|')
  else
    domain="$input"
  fi
  
  # Удаляем www. если есть
  domain="${domain#www.}"
  
  # Проверяем, есть ли уже такой домен
  if grep -q "^${domain}$" "$list_file" 2>/dev/null; then
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
  echo "1. Добавить в list-general.txt"
  echo "2. Добавить в list-exclude.txt"
  echo "0. Назад"
  echo
  read -rp "Выберите действие: " choice
  
  case $choice in
    1)
      read -rp "Введите домен или URL: " input
      add_domain "$input" "$LIST_GENERAL"
      ;;
    2)
      read -rp "Введите домен или URL: " input
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
  echo
  echo ":: ПАРАМЕТРЫ"
  echo "1. Game Filter"
  echo "2. IPSet Filter"
  echo
  echo ":: ОБНОВЛЕНИЯ"
  echo "3. Обновить список IPSet"
  echo "4. Обновить файл hosts"
  echo
  echo ":: ИНСТРУМЕНТЫ"
  echo "5. Добавить домен в список"
  echo "6. Запустить тесты"
  echo
  echo "----------------------------------------"
  echo "0. Выход"
  echo
  read -rp "Выберите опцию (0-6): " CHOICE
  case $CHOICE in
    1) toggle_game ;;
    2) ipset_menu ;;
    3) update_ipset ;;
    4) update_hosts ;;
    5) add_domains_menu ;;
    6) run_zapret_tests ;;
    0) clear; exit 0 ;;
    *) echo -e "${RED}Неверный выбор.${RESET}" ;;
  esac
  
  # Небольшая пауза для чтения сообщений
  sleep 1
done
