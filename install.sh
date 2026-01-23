#!/bin/bash

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
    exit 1
  fi
}

# Определяем доступную утилиту повышения привилегий
ELEVATE_CMD=$(detect_privilege_escalation)

# Проверка активности SELinux
is_selinux_active() {
  if command -v getenforce &>/dev/null; then
    mode=$(getenforce 2>/dev/null)
    [[ "$mode" == "Enforcing" || "$mode" == "Permissive" ]]
    return
  fi

  # fallback, если getenforce отсутствует
  if [ -d /sys/fs/selinux ] && [ -e /sys/fs/selinux/enforce ]; then
    val=$(cat /sys/fs/selinux/enforce 2>/dev/null)
    [[ "$val" == "1" || "$val" == "0" ]]
    return
  fi

  return 1
}

# Основная функция установки
default_install() {
  if is_selinux_active; then
    echo "Обнаружен SELinux. Применяем правила..."

    # Определяем каталог, где лежит сам install.sh
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Запускаем fixfilecontext.sh напрямую без sudo (он сам использует sudo внутри)
    bash "$SCRIPT_DIR/module/fixfilecontext.sh" || {
      echo "Ошибка: не удалось запустить fixfilecontext.sh"
    }
  fi

  echo "Запуск install_easy.sh..."
  if ! $ELEVATE_CMD /opt/zapret/install_easy.sh; then
    echo "Ошибка: не удалось запустить install_easy.sh."
  fi

  # Проверка на Void Linux и настройка службы через runit
  if [ -f "/etc/os-release" ] && grep -q "PRETTY_NAME=\"Void Linux\"" /etc/os-release; then
    echo "Настройка службы zapret для Void Linux через runit..."
    $ELEVATE_CMD cp -r /opt/zapret/init.d/runit/zapret/ /etc/sv/
    $ELEVATE_CMD ln -s /etc/sv/zapret /var/service
    $ELEVATE_CMD sv up zapret
    echo "Служба zapret настроена и запущена для Void Linux."
  fi

  # Проверка на AntiX Linux и настройка службы через runit или sysVinit
  if [ -f "/usr/local/bin/antix" ]; then
    if ! command -v sv >/dev/null 2>&1; then
      echo "Настройка службы zapret для AntiX Linux..."
      $ELEVATE_CMD ln -s /opt/zapret/init.d/zapret /etc/init.d/
      $ELEVATE_CMD service zapret start
      $ELEVATE_CMD update-rd.d zapret defaults
      echo "Служба zapret настроена и запущена для AntiX Linux."
    else
      echo "Настройка службы zapret для AntiX Linux..."
      $ELEVATE_CMD cp -r /opt/zapret/init.d/runit/zapret/ /etc/sv/
      $ELEVATE_CMD ln -s /etc/sv/zapret/ /etc/service/
      $ELEVATE_CMD sv up zapret
      echo "Служба zapret настроена и запущена для AntiX Linux."
    fi
  fi

  # Проверка на Slackware и настройка службы через sysv
  if [ -f "/etc/os-release" ] && grep -q "^NAME=Slackware$" /etc/os-release; then
    echo "Настройка службы zapret для Slackware..."
    $ELEVATE_CMD ln -s /opt/zapret/init.d/sysv/zapret /etc/rc.d/rc.zapret
    $ELEVATE_CMD chmod +x /etc/rc.d/rc.zapret
    $ELEVATE_CMD /etc/rc.d/rc.zapret start
    echo -e "\n# Запуск службы zapret\nif [ -x /etc/rc.d/rc.zapret ]; then\n  /etc/rc.d/rc.zapret start\nfi" | $ELEVATE_CMD tee -a /etc/rc.d/rc.local
    echo "Служба zapret настроена и запущена для Slackware."
  fi

  # Проверка наличие системы инициализации s6 и настройка службы через s6
  if command -v s6-rc >/dev/null 2>&1; then
    echo "Настройка службы zapret для s6..."
    $ELEVATE_CMD cp -r /opt/zapret/init.d/s6/zapret/ /etc/s6/adminsv/
    $ELEVATE_CMD touch /etc/s6/adminsv/default/contents.d/zapret
    $ELEVATE_CMD s6-db-reload
    $ELEVATE_CMD s6-rc -u change zapret
    echo "Служба zapret настроена и запущена для s6."
  fi

  # Проверка на Bazzite и настройка systemd
  if [ -f "/etc/os-release" ] && grep -qi "bazzite" /etc/os-release; then
    echo "Настройка службы zapret для Bazzite..."
    $ELEVATE_CMD cp /opt/zapret/init.d/systemd/*.service /etc/systemd/system/ 2>/dev/null || true
    $ELEVATE_CMD systemctl enable zapret
    $ELEVATE_CMD systemctl start zapret
    echo "Служба zapret настроена и запущена для Bazzite."
  fi
}

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