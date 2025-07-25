#!/bin/bash

clear

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

# Функции для установки различных конфигов
general() {
  echo "Установка конфига general..."
  if ! cp "$HOME/zapret-configs/configs/general" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general."
    exit 1
  fi
  default_install
}

general_ALT() {
  echo "Установка конфига general(ALT)..."
  if ! cp "$HOME/zapret-configs/configs/general(ALT)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(ALT)."
    exit 1
  fi
  default_install
}

general_ALT2() {
  echo "Установка конфига general(ALT2)..."
  if ! cp "$HOME/zapret-configs/configs/general(ALT2)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(ALT2)."
    exit 1
  fi
  default_install
}

general_ALT3() {
  echo "Установка конфига general(ALT3)..."
  if ! cp "$HOME/zapret-configs/configs/general(ALT3)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(ALT3)."
    exit 1
  fi
  default_install
}

general_ALT4() {
  echo "Установка конфига general(ALT4)..."
  if ! cp "$HOME/zapret-configs/configs/general(ALT4)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(ALT4)."
    exit 1
  fi
  default_install
}

general_ALT5() {
  echo "Установка конфига general(ALT5)..."
  if ! cp "$HOME/zapret-configs/configs/general(ALT5)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(ALT5)."
    exit 1
  fi
  default_install
}

general_ALT6() {
  echo "Установка конфига general(ALT6)..."
  if ! cp "$HOME/zapret-configs/configs/general(ALT6)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(ALT6)."
    exit 1
  fi
  default_install
}

general_MGTS() {
  echo "Установка конфига general(МГТС)..."
  if ! cp "$HOME/zapret-configs/configs/general(МГТС)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(МГТС)."
    exit 1
  fi
  default_install
}

general_MGTS2() {
  echo "Установка конфига general(МГТС2)..."
  if ! cp "$HOME/zapret-configs/configs/general(МГТС2)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(МГТС2)."
    exit 1
  fi
  default_install
}

general_FAKE_TLS() {
  echo "Установка конфига general(FAKE TLS)..."
  if ! cp "$HOME/zapret-configs/configs/general_(FAKE_TLS)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(FAKE TLS)."
    exit 1
  fi
  default_install
}

general_FAKE_TLS_ALT() {
  echo "Установка конфига general(FAKE TLS ALT)..."
  if ! cp "$HOME/zapret-configs/configs/general_(FAKE_TLS_ALT)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(FAKE TLS ALT)."
    exit 1
  fi
  default_install
}

general_FAKE_TLS_AUTO_ALT() {
  echo "Установка конфига general(FAKE TLS AUTO ALT)..."
  if ! cp "$HOME/zapret-configs/configs/general_(FAKE_TLS_AUTO_ALT)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(FAKE TLS AUTO ALT)."
    exit 1
  fi
  default_install
}

general_FAKE_TLS_AUTO_ALT2() {
  echo "Установка конфига general(FAKE TLS AUTO ALT2)..."
  if ! cp "$HOME/zapret-configs/configs/general_(FAKE_TLS_AUTO_ALT2)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(FAKE TLS AUTO ALT2)."
    exit 1
  fi
  default_install
}

general_FAKE_TLS_AUTO() {
  echo "Установка конфига general(FAKE TLS AUTO)..."
  if ! cp "$HOME/zapret-configs/configs/general_(FAKE_TLS_AUTO)" /opt/zapret/config; then
    echo "Ошибка: не удалось скопировать конфиг general(FAKE TLS AUTO)."
    exit 1
  fi
  default_install
}

# Меню для выбора конфига
echo "Выберите конфиг для установки:"
select config in "general" "general_ALT" "general_ALT2" "general_ALT3" "general_ALT4" "general_ALT5" "general_ALT6" "general_MGTS" "general_MGTS2" "general_FAKE_TLS" "general_FAKE_TLS_AUTO" "general_FAKE_TLS_AUTO_ALT" "general_FAKE_TLS_AUTO_ALT2" "general_FAKE_TLS_ALT"; do
  case $config in
  "general")
    general
    break
    ;;
  "general_ALT")
    general_ALT
    break
    ;;
  "general_ALT2")
    general_ALT2
    break
    ;;
  "general_ALT3")
    general_ALT3
    break
    ;;
  "general_ALT4")
    general_ALT4
    break
    ;;
  "general_ALT5")
    general_ALT5
    break
    ;;
  "general_ALT6")
    general_ALT6
    break
    ;;
  "general_MGTS")
    general_MGTS
    break
    ;;
  "general_MGTS2")
    general_MGTS2
    break
    ;;
  "general_FAKE_TLS")
    general_FAKE_TLS
    break
    ;;
  "general_FAKE_TLS_AUTO")
    general_FAKE_TLS_AUTO
    break
    ;;
  "general_(FAKE_TLS_AUTO_ALT)")
    general_FAKE_TLS_AUTO_ALT
    break
    ;;
  "general_FAKE_TLS_AUTO_ALT2")
    general_FAKE_TLS_AUTO_ALT2
    break
    ;;
  "general_FAKE_TLS_ALT")
    general_FAKE_TLS_ALT
    break
    ;;
  *)
    echo "Неверный выбор. Пожалуйста, выберите снова."
    ;;
  esac
done

echo "Установка завершена успешно!"
