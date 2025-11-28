#!/bin/bash

GREEN="\e[32m"
YELLOW="\e[33m"
RESET="\e[0m"
RED="\e[31m"

HOSTLISTS="/opt/zapret/hostlists/list-general.txt"
HOSTLISTS_EXCLUDE="/opt/zapret/hostlists/list-exclude.txt"
IPSET_FILE="/opt/zapret/hostlists/ipset-all.txt"
IPSET_EXCLUDE="/opt/zapret/hostlists/ipset-exclude.txt"

show_list() {
  local file="$1"
  clear
  echo -e "${YELLOW}Текущий список ($file):${RESET}"
  echo
  if [[ -s "$file" ]]; then
    cat "$file"
  else
    echo "(пусто)"
  fi
  echo
}

add_entry() {
  local file="$1"
  show_list "$file"

  read -rp "Введите строку для добавления: " entry

  if [[ -z "$entry" ]]; then
    echo -e "${RED}Введена пустая строка${RESET}"
  elif grep -Fxq "$entry" "$file"; then
    echo -e "${YELLOW}Уже существует:${RESET} $entry"
  else
    echo "$entry" >> "$file"
    echo -e "${GREEN}Добавлено:${RESET} $entry"
  fi

  read -rp "Enter..."
}

remove_entry() {
  local file="$1"
  show_list "$file"

  read -rp "Введите строку для удаления: " entry

  if [[ -z "$entry" ]]; then
    echo -e "${RED}Введена пустая строка${RESET}"
  elif grep -Fxq "$entry" "$file"; then
    grep -Fxv "$entry" "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    echo -e "${GREEN}Удалено:${RESET} $entry"
  else
    echo -e "${YELLOW}Нет такой записи:${RESET} $entry"
  fi

  read -rp "Enter..."
}

while true; do
  clear
  echo "Меню управления списками:"
  echo
  echo "1. Добавить в hostlists"
  echo "2. Удалить из hostlists"
  echo "3. Добавить в hostlists-exclude"
  echo "4. Удалить из hostlists-exclude"
  echo "5. Добавить в IPSet"
  echo "6. Удалить из IPSet"
  echo "7. Добавить в IPSet-exclude"
  echo "8. Удалить из IPSet-exclude"
  echo "0. Выход"
  echo
  read -rp "Выберите действие: " CHOICE

  case $CHOICE in
    1) add_entry "$HOSTLISTS" ;;
    2) remove_entry "$HOSTLISTS" ;;
    3) add_entry "$HOSTLISTS_EXCLUDE" ;;
    4) remove_entry "$HOSTLISTS_EXCLUDE" ;;
    5) add_entry "$IPSET_FILE" ;;
    6) remove_entry "$IPSET_FILE" ;;
    7) add_entry "$IPSET_EXCLUDE" ;;
    8) remove_entry "$IPSET_EXCLUDE" ;;
    0) clear; exit 0 ;;
    *) echo "Неверный выбор." 
       read -rp "Нажмите Enter для продолжения..." ;;
  esac
done
