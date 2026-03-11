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
  $ELEVATE_CMD /opt/zapret/install_easy.sh
  INSTALL_EXIT_CODE=$?
  if [ $INSTALL_EXIT_CODE -ne 0 ]; then
    echo -e "install_easy.sh завершился с кодом $INSTALL_EXIT_CODE\n(возможно, вы отменили установку или выбрали выход)."
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

  # Проверка на Secureblue и настройка systemd
  if [ -f "/etc/os-release" ] && grep -qi "secureblue" /etc/os-release; then
    echo "Настройка службы zapret для Secureblue..."
    
    # Включаем tcp_timestamps если отключен
    if [ "$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null)" = "0" ]; then
      run0 sh -c 'echo "net.ipv4.tcp_timestamps = 1" > /etc/sysctl.d/90-zapret-tcp-timestamps.conf'
      run0 sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null
    fi
    
    # Установка правильных прав на hostlists
    chmod 755 /opt/zapret/hostlists/
    chmod -R 644 /opt/zapret/hostlists/*
    $ELEVATE_CMD chcon -t bin_t /opt/zapret/init.d/sysv/zapret
    $ELEVATE_CMD cp /opt/zapret/init.d/systemd/*.service /etc/systemd/system/ 2>/dev/null || true
    ujust override-enable-module nfnetlink_queue
    $ELEVATE_CMD modrope nfnetlink_queue
    /opt/zapret/install_bin.sh
    $ELEVATE_CMD systemctl enable zapret
    $ELEVATE_CMD systemctl start zapret
    echo "Служба zapret настроена и запущена для Secureblue."
  fi

  # Проверка на ALT Linux и настройка systemd
  if [ -f "/etc/os-release" ] && grep -qi "altlinux" /etc/os-release; then
    echo "Настройка службы zapret для ALT Linux..."
    
    # Установка bind-utils если отсутствует
    if ! rpm -q bind-utils >/dev/null 2>&1; then
      echo "Установка bind-utils..."
      $ELEVATE_CMD apt-get install -y bind-utils
    fi
    
    # Добавляем PATH в .bashrc если отсутствует
    if ! grep -q 'export PATH=\$PATH:/sbin:/usr/sbin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH=$PATH:/sbin:/usr/sbin' >> "$HOME/.bashrc"
    fi
    
    # Включаем tcp_timestamps если отключен
    if [ "$(sysctl -n net.ipv4.tcp_timestamps 2>/dev/null)" = "0" ]; then
      echo "net.ipv4.tcp_timestamps = 1" | $ELEVATE_CMD tee /etc/sysctl.d/90-zapret-tcp-timestamps.conf >/dev/null
      $ELEVATE_CMD sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null
    fi
    
    /opt/zapret/install_bin.sh
    $ELEVATE_CMD cp /opt/zapret/init.d/systemd/*.service /etc/systemd/system/ 2>/dev/null || true
    $ELEVATE_CMD systemctl enable zapret
    $ELEVATE_CMD systemctl start zapret
    echo "Служба zapret настроена и запущена для ALT Linux."
  fi

  # Проверка на Bazzite и настройка systemd
  if [ -f "/etc/os-release" ] && grep -qi "bazzite" /etc/os-release; then
    echo "Настройка службы zapret для Bazzite..."
    $ELEVATE_CMD cp /opt/zapret/init.d/systemd/*.service /etc/systemd/system/ 2>/dev/null || true
    $ELEVATE_CMD systemctl enable zapret
    $ELEVATE_CMD systemctl start zapret
    echo "Служба zapret настроена и запущена для Bazzite."
  fi

  # Проверка на Fedora Silverblue и настройка systemd
  if [ -f "/etc/os-release" ] && grep -q "VARIANT_ID=silverblue" /etc/os-release; then
    echo "Настройка службы zapret для Fedora Silverblue..."
    $ELEVATE_CMD cp /opt/zapret/init.d/systemd/*.service /etc/systemd/system/ 2>/dev/null || true
    $ELEVATE_CMD systemctl enable zapret
    $ELEVATE_CMD systemctl start zapret
    echo "Служба zapret настроена и запущена для Fedora Silverblue."
  fi

  # Определение системы инициализации для остальных дистрибутивов
  INIT_SYSTEM=$(ps -p 1 -o comm= 2>/dev/null)

  # Специальная обработка для Artix Linux - установка iptables с суффиксом init
  if [ -f "/etc/os-release" ] && grep -qi "artix" /etc/os-release; then
    echo "Обнаружен Artix Linux. Проверка iptables для $INIT_SYSTEM..."
    
    declare -A iptables_map=(
      ["dinit"]="iptables-dinit"
      ["s6-svscan"]="iptables-s6"
      ["runit-init"]="iptables-runit"
      ["runit"]="iptables-runit"
    )
    
    pkg="${iptables_map[$INIT_SYSTEM]:-iptables-openrc}"
    
    if ! pacman -Q "$pkg" >/dev/null 2>&1; then
      echo "Установка $pkg..."
      $ELEVATE_CMD pacman -S --noconfirm "$pkg"
    fi
  fi

  # Настройка для dinit
  if [ "$INIT_SYSTEM" = "dinit" ]; then
    echo "Настройка службы zapret для dinit..."
       
    # Создание директории для dinit скриптов
    mkdir -p /opt/zapret/init.d/dinit/
    
    # URL для скачивания файлов из форка
    DINIT_COMMIT="0f9f0bd74e1dca5f6a3def00bf88d7bf177cab2a"
    DINIT_BASE_URL="https://raw.githubusercontent.com/Lintech-1/zapret/$DINIT_COMMIT/init.d/dinit"
    
    # Скачивание файлов dinit
    echo "Скачивание файлов dinit из репозитория..."
    curl -fsSL "$DINIT_BASE_URL/zapret-start.sh" -o /opt/zapret/init.d/dinit/zapret-start.sh
    curl -fsSL "$DINIT_BASE_URL/zapret-stop.sh" -o /opt/zapret/init.d/dinit/zapret-stop.sh
    curl -fsSL "$DINIT_BASE_URL/zapret" -o /opt/zapret/init.d/dinit/zapret
    
    # Создание симлинка на файл сервиса
    $ELEVATE_CMD ln -sf /opt/zapret/init.d/dinit/zapret /etc/dinit.d/zapret
    
    # Включение и запуск сервиса
    $ELEVATE_CMD dinitctl enable zapret
    $ELEVATE_CMD dinitctl start zapret
    
    echo "Служба zapret настроена и запущена для dinit."
  fi

  # Настройка для s6
  if [ "$INIT_SYSTEM" = "s6-svscan" ]; then
    echo "Настройка службы zapret для s6..."
    $ELEVATE_CMD cp -r /opt/zapret/init.d/s6/zapret/ /etc/s6/adminsv/
    $ELEVATE_CMD touch /etc/s6/adminsv/default/contents.d/zapret
    $ELEVATE_CMD s6-db-reload
    $ELEVATE_CMD s6-rc -u change zapret
    echo "Служба zapret настроена и запущена для s6."
  fi

  # Настройка для runit (кроме Void Linux и AntiX)
  if [ "$INIT_SYSTEM" = "runit-init" ] || [ "$INIT_SYSTEM" = "runit" ]; then
    if ! ([ -f "/etc/os-release" ] && grep -q "PRETTY_NAME=\"Void Linux\"" /etc/os-release) && [ ! -f "/usr/local/bin/antix" ]; then
      echo "Настройка службы zapret для runit..."
      $ELEVATE_CMD cp -r /opt/zapret/init.d/runit/zapret/ /etc/sv/
      if [ -d "/var/service" ]; then
        $ELEVATE_CMD ln -s /etc/sv/zapret /var/service/
      elif [ -d "/etc/service" ]; then
        $ELEVATE_CMD ln -s /etc/sv/zapret /etc/service/
      fi
      $ELEVATE_CMD sv up zapret
      echo "Служба zapret настроена и запущена для runit."
    fi
  fi

  # Настройка для sysvinit (кроме Slackware и AntiX)
  if [ "$INIT_SYSTEM" = "init" ]; then
    if ! ([ -f "/etc/os-release" ] && grep -q "^NAME=Slackware$" /etc/os-release) && [ ! -f "/usr/local/bin/antix" ]; then
      echo "Настройка службы zapret для sysvinit..."
      $ELEVATE_CMD ln -s /opt/zapret/init.d/sysv/zapret /etc/init.d/zapret
      if command -v update-rc.d >/dev/null 2>&1; then
        $ELEVATE_CMD update-rc.d zapret defaults
      elif command -v chkconfig >/dev/null 2>&1; then
        $ELEVATE_CMD chkconfig --add zapret
        $ELEVATE_CMD chkconfig zapret on
      fi
      $ELEVATE_CMD service zapret start
      echo "Служба zapret настроена и запущена для sysvinit."
    fi
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