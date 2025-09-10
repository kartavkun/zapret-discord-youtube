#!/bin/bash

# Функция для установки конфига по умолчанию
default_install() {
  if [ -f "/sys/fs/selinux/enforce" ]; then
    echo "Обнаружены следы selinux. Применяем правила."
    ./module/fixfilecontext.sh
  fi

  echo "Запуск install_easy.sh..."
  if ! sudo /opt/zapret/install_easy.sh; then
    echo "Ошибка: не удалось запустить install_easy.sh."
  fi

  # Проверка на Void Linux и настройка службы через runit
  if [ -f "/etc/os-release" ] && grep -q "PRETTY_NAME=\"Void Linux\"" /etc/os-release; then
    echo "Настройка службы zapret для Void Linux через runit..."
    sudo cp -r /opt/zapret/init.d/runit/zapret/ /etc/sv/
    sudo ln -s /etc/sv/zapret /var/service
    sudo sv up zapret
    echo "Служба zapret настроена и запущена для Void Linux."
  fi

  # Проверка на AntiX Linux и настройка службы через runit или sysVinit
  if [ -f "/usr/local/bin/antix" ]; then
    if ! command -v sv >/dev/null 2>&1; then
      echo "Настройка службы zapret для AntiX Linux..."
      sudo ln -s /opt/zapret/init.d/zapret /etc/init.d/
      sudo service zapret start
      sudo update-rd.d zapret defaults
      echo "Служба zapret настроена и запущена для AntiX Linux."
    else
      echo "Настройка службы zapret для AntiX Linux..."
      sudo cp -r /opt/zapret/init.d/runit/zapret/ /etc/sv/
      sudo ln -s /etc/sv/zapret/ /etc/service/
      sudo sv up zapret
      echo "Служба zapret настроена и запущена для AntiX Linux."
    fi

  fi

  # Проверка на Slackware и настройка службы через sysv
  if [ -f "/etc/os-release" ] && grep -q "^NAME=Slackware$" /etc/os-release; then
    echo "Настройка службы zapret для Slackware..."
    sudo ln -s /opt/zapret/init.d/sysv/zapret /etc/rc.d/rc.zapret
    sudo chmod +x /etc/rc.d/rc.zapret
    sudo /etc/rc.d/rc.zapret start
    echo -e "\n# Запуск службы zapret\nif [ -x /etc/rc.d/rc.zapret ]; then\n  /etc/rc.d/rc.zapret start\nfi" | sudo tee -a /etc/rc.d/rc.local
    echo "Служба zapret настроена и запущена для Slackware."
  fi

  # Проверка наличие системы инициализации s6 и настройка службы через s6
  if command -v s6-rc >/dev/null 2>&1; then
    echo "Настройка службы zapret для s6..."
    sudo cp -r /opt/zapret/init.d/s6/zapret/ /etc/s6/adminsv/
    sudo touch /etc/s6/adminsv/default/contents.d/zapret
    sudo s6-db-reload
    sudo s6-rc -u change zapret
    echo "Служба zapret настроена и запущена для s6."
  fi
}

clear

# Собираем список файлов
configs=("$HOME/zapret-configs/configs"/*)
if [ ${#configs[@]} -eq 0 ]; then
  echo "Ошибка: в папке $HOME/zapret-configs/configs/ нет файлов."
  exit 1
fi

while true; do
  clear

  echo "Выберите конфиг для установки:"
  for i in "${!configs[@]}"; do
    echo "$((i+1)). $(basename "${configs[$i]}")"
  done

  read -rp "Введите номер конфига: " choice

  # Проверка на корректность выбора
  # regex на число && число больше или равно 1 && число меньше или равно количеству элементов в массиве
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#configs[@]}" ]; then
    selected_config="${configs[$((choice-1))]}"
    echo "Установка конфига $(basename "$selected_config")..."
    if ! cp "$selected_config" "/opt/zapret/config"; then
      echo "Ошибка: не удалось скопировать конфиг."
      exit 1
    fi
    default_install
    break
  else
    echo "Неверный выбор. Попробуйте снова."
    echo
  fi
done

echo "Установка завершена успешно!"
