#!/bin/zsh

# Основная функция установки
default_install() {
  echo "Запуск install_easy.sh..."
  sudo /opt/zapret/install_easy.sh
  INSTALL_EXIT_CODE=$?
  if [ $INSTALL_EXIT_CODE -ne 0 ]; then
    echo -e "install_easy.sh завершился с кодом $INSTALL_EXIT_CODE\n(возможно, вы отменили установку или выбрали выход)."
  fi
}

# Попытка обеспечить реальный TTY (если есть), иначе пометка noninteractive
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

# Собираем список конфигов
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
    for i in $(seq 1 ${#entries[@]}); do
      name="$(basename "${entries[$i]}")"
      if [ -d "${entries[$i]}" ]; then
        echo "$i. [Папка] $name"
      else
        echo "$i. $name"
      fi
    done
    echo "0. Назад"

    read -r "?Введите номер: " choice

    if [ "$choice" = "0" ]; then
      return 1
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#entries[@]}" ]; then
      selected="${entries[$choice]}"
      if [ -d "$selected" ]; then
        choose_config "$selected" || continue
        return
      else
        echo "Установка конфига $(basename "$selected")..."
        if ! cp "$selected" "/opt/zapret/config"; then
          echo "Ошибка: не удалось скопировать конфиг."
          exit 1
        fi
        default_install
        echo "Установка завершена успешно!"
        return
      fi
    else
      echo "Неверный выбор. Попробуйте снова."
      echo
    fi
  done
}

if [ -n "$NONINTERACTIVE" ]; then
  exit 1
fi

# Запуск выбора с корневого каталога configs
choose_config "$HOME/zapret-configs/configs"