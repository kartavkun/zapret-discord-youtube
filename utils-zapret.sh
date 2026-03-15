#!/bin/zsh

# Цвета
GREEN="\e[32m"
YELLOW="\e[33m"
RED="\e[31m"
RESET="\e[0m"

# Пути к файлам
IPSET_FILE="/opt/zapret/hostlists/ipset-all.txt"
IPSET_BACKUP="${IPSET_FILE}.backup"
LIST_GENERAL="/opt/zapret/hostlists/list-general-user.txt"
LIST_EXCLUDE="/opt/zapret/hostlists/list-exclude-user.txt"
CONFIG_FILE="/opt/zapret/config"
IP="203.0.113.113/32"
ZAPRET_INIT="/opt/zapret/init.d/macos/zapret"

# Функция перезапуска zapret (macOS)
restart_zapret() {
  echo
  echo "Перезапуск службы zapret..."

  if [ ! -x "$ZAPRET_INIT" ]; then
    echo -e "${RED}Ошибка: не найден init-скрипт $ZAPRET_INIT${RESET}"
    return 1
  fi

  if sudo "$ZAPRET_INIT" restart; then
    echo -e "${GREEN}Служба zapret перезапущена${RESET}"
    return 0
  fi

  echo -e "${YELLOW}Не удалось перезапустить zapret. Попробуйте вручную:${RESET}"
  echo "  sudo $ZAPRET_INIT restart"
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
  read -r "?Выберите режим: " ipset_choice
  
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
    read -r "?Добавить содержимое в $hosts_file? [Y/n]: " response
    
    case "${(L)response}" in
      y|yes|"")
        # Добавляем пустую строку перед новым содержимым
        echo "" | sudo tee -a "$hosts_file" > /dev/null
        sudo tee -a "$hosts_file" < "$temp_file" > /dev/null
        
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
  echo "1. Добавить в list-general-user.txt"
  echo "2. Добавить в list-exclude-user.txt"
  echo "0. Назад"
  echo
  read -r "?Выберите действие: " choice
  
  case $choice in
    1)
      read -r "?Введите домен или URL: " input
      add_domain "$input" "$LIST_GENERAL"
      ;;
    2)
      read -r "?Введите домен или URL: " input
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
  show_current_strategy
  echo
  echo ":: ПАРАМЕТРЫ"
  echo "1. IPSet Filter"
  echo
  echo ":: ОБНОВЛЕНИЯ"
  echo "2. Обновить список IPSet"
  echo "3. Обновить файл hosts"
  echo
  echo ":: ИНСТРУМЕНТЫ"
  echo "4. Добавить домен в список"
  echo "5. Запустить тесты"
  echo
  echo "----------------------------------------"
  echo "0. Выход"
  echo
  read -r "?Выберите опцию (0-5): " CHOICE
  case $CHOICE in
    1) ipset_menu ;;
    2) update_ipset ;;
    3) update_hosts ;;
    4) add_domains_menu ;;
    5) run_zapret_tests ;;
    0) clear; exit 0 ;;
    *) echo -e "${RED}Неверный выбор.${RESET}" ;;
  esac
  
  # Небольшая пауза для чтения сообщений
  sleep 1
done
