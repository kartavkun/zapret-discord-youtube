#!/bin/bash

# Функция для определения доступной утилиты повышения привилегий
detect_privilege_escalation() {
  if command -v doas &>/dev/null; then
    echo "doas"
  elif command -v sudo &>/dev/null; then
    echo "sudo"
  else
    exit 1
  fi
}

# Определяем доступную утилиту повышения привилегий
ELEVATE_CMD=$(detect_privilege_escalation)



# попытка обеспечить реальный TTY (если есть), иначе пометка noninteractive
if [ ! -t 0 ] || [ ! -t 1 ]; then
  if [ -e /dev/tty ]; then
    exec </dev/tty >/dev/tty 2>&1
  else
    NONINTERACTIVE=1
  fi
fi

if [ -z "$NONINTERACTIVE" ] && [ -t 1 ]; then
  clear
fi


choose_config() {
  local dir="$1"
  local entries=("$dir"/*)

  if [ ${#entries[@]} -eq 0 ]; then
    echo "Ошибка: в папке $dir нет файлов или подкаталогов."
    exit 1
  fi

  while true; do
    if [ -z "$NONINTERACTIVE" ] && [ -t 1 ]; then
      clear
    fi

    echo "Выберите конфиг или папку для входа:"
    for i in "${!entries[@]}"; do
      name="$(basename "${entries[$i]}")"
      if [ -d "${entries[$i]}" ]; then
        echo "$((i+1)). [Папка] $name"
      else
        echo "$((i+1)). $name"
      fi
    done
    echo "0. Назад"

    read -rp "Введите номер: " choice

    if [ "$choice" = "0" ]; then
      return 1
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#entries[@]}" ]; then
      selected="${entries[$((choice-1))]}"
      if [ -d "$selected" ]; then
        choose_config "$selected" || continue
        return
      else
        echo "Установка конфига $(basename "$selected")..."
        if ! cp "$selected" "/opt/zapret/config"; then
          echo "Ошибка: не удалось скопировать конфиг."
          exit 1
        fi
        $ELEVATE_CMD systemctl restart zapret
        echo "Установка завершена успешно!"
        return
      fi
    else
      echo "Неверный выбор. Попробуйте снова."
      echo
    fi
  done
}

# Запуск выбора с корневого каталога configs
choose_config "$HOME/zapret-configs/configs"
