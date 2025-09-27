#!/bin/bash

# Функция для определения доступной утилиты повышения привилегий
detect_privilege_escalation() {
  if command -v doas &>/dev/null; then
    echo "doas"
  elif command -v sudo &>/dev/null; then
    echo "sudo"
  else
    echo "Ошибка: не найдены утилиты sudo или doas для повышения привилегий."
    echo "Установите одну из этих утилит для продолжения."
    exit 1
  fi
}

# Определяем доступную утилиту повышения привилегий
ELEVATE_CMD=$(detect_privilege_escalation)

# Функция установки пакетов с разными пакетными менеджерами
install_packages() {
  case "$1" in
    apt)
      $ELEVATE_CMD apt update && $ELEVATE_CMD apt install -y wget git ;;
    nala)
      $ELEVATE_CMD nala update && $ELEVATE_CMD nala install -y wget git ;;
    yum)
      $ELEVATE_CMD yum install -y wget git ;;
    dnf)
      $ELEVATE_CMD dnf install -y wget git ;;
    pacman)
      $ELEVATE_CMD pacman -Sy --noconfirm wget git ;;
    zypper)
      $ELEVATE_CMD zypper install -y wget git ;;
    xbps-install)
      $ELEVATE_CMD xbps-install -Sy wget git ipset iptables nftables cronie ;;
    slapt-get)
      $ELEVATE_CMD slapt-get -i --no-prompt wget git ;;
    apk)
      $ELEVATE_CMD apk add wget git ;;
    eopkg)
      $ELEVATE_CMD eopkg update-repo && $ELEVATE_CMD eopkg install wget git ;;
    *)
      echo "Неизвестный пакетный менеджер: $1"
      return 1 ;;
  esac
}

# Проверяем, есть ли wget и git — если да, переходим к следующему коду
if command -v wget &>/dev/null && command -v git &>/dev/null; then
  echo "wget и git уже установлены, продолжаем..."
else
  # Определяем пакетный менеджер и выполняем установку
  if command -v nala &>/dev/null; then
    echo "Обнаружен nala, устанавливаем wget и git..."
    install_packages nala
  elif command -v apt &>/dev/null; then
    echo "Обнаружен apt, устанавливаем wget и git..."
    install_packages apt
  elif command -v yum &>/dev/null; then
    echo "Обнаружен yum, устанавливаем wget и git..."
    install_packages yum
  elif command -v dnf &>/dev/null; then
    echo "Обнаружен dnf, устанавливаем wget и git..."
    install_packages dnf
  elif command -v pacman &>/dev/null; then
    echo "Обнаружен pacman, устанавливаем wget и git..."
    install_packages pacman
  elif command -v zypper &>/dev/null; then
    echo "Обнаружен zypper, устанавливаем wget и git..."
    install_packages zypper
  elif command -v xbps-install &>/dev/null; then
    echo "Обнаружен xbps, устанавливаем wget и git..."
    install_packages xbps-install
  elif command -v slapt-get &>/dev/null; then
    echo "Обнаружен slapt-get, устанавливаем wget и git..."
    install_packages slapt-get
  elif command -v apk &>/dev/null; then
    echo "Обнаружен apk, устанавливаем wget и git..."
    install_packages apk
  elif command -v eopkg &>/dev/null; then
    echo "Обнаружен eopkg, устанавливаем wget и git..."
    install_packages eopkg
  else
    echo "Не удалось определить пакетный менеджер."
    echo "Необходимо установить wget и git вручную."
    exit 1
  fi
fi

# Создаем временную директорию, если она не существует
mkdir -p "$HOME/tmp"
# Удаление архива с запретом на всякий
rm -rf "$HOME/tmp/*"

# Бэкап запрета если есть
if [ -d "/opt/zapret" ]; then
  echo "Создание резервной копии существующего zapret..."
  $ELEVATE_CMD cp -r "/opt/zapret" "/opt/zapret.bak"
fi
$ELEVATE_CMD rm -rf "/opt/zapret"

# Получение последней версии zapret с GitHub API
echo "Определение последней версии zapret..."
ZAPRET_VERSION=$(curl -s "https://api.github.com/repos/bol-van/zapret/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$ZAPRET_VERSION" ]; then
  echo "Не удалось получить версию через GitHub API. Используем git ls-remote..."
  
  # Получить все теги, отсортировать их по версии и выбрать последний
  ZAPRET_VERSION=$(git ls-remote --tags https://github.com/bol-van/zapret.git | 
                  grep -v '\^{}' | # Исключаем аннотированные теги
                  awk -F/ '{print $NF}' | # Извлекаем только имя тега
                  sort -V | # Сортируем по версии
                  tail -n 1) # Берем последний тег
  
  if [ -z "$ZAPRET_VERSION" ]; then
    echo "Ошибка: не удалось определить последнюю версию zapret через git ls-remote."
    exit 1
  fi
fi

echo "Последняя версия zapret: $ZAPRET_VERSION"

# Закачка последнего релиза bol-van/zapret
echo "Скачивание последнего релиза zapret..."
if ! wget -O "$HOME/tmp/zapret-$ZAPRET_VERSION.tar.gz" "https://github.com/bol-van/zapret/releases/download/$ZAPRET_VERSION/zapret-$ZAPRET_VERSION.tar.gz"; then
  echo "Ошибка: не удалось скачать zapret."
  exit 1
fi

# Распаковка архива
echo "Распаковка zapret..."
if ! tar -xvf "$HOME/tmp/zapret-$ZAPRET_VERSION.tar.gz" -C "$HOME/tmp"; then
  echo "Ошибка: не удалось распаковать zapret."
  exit 1
fi

# Версия без 'v' в начале для работы с директорией
ZAPRET_DIR_VERSION=$(echo $ZAPRET_VERSION | sed 's/^v//')
echo "Определение пути распакованного архива..."

# Проверяем наличие директорий с разными вариантами именования
if [ -d "$HOME/tmp/zapret-$ZAPRET_DIR_VERSION" ]; then
  ZAPRET_EXTRACT_DIR="$HOME/tmp/zapret-$ZAPRET_DIR_VERSION"
elif [ -d "$HOME/tmp/zapret-$ZAPRET_VERSION" ]; then
  ZAPRET_EXTRACT_DIR="$HOME/tmp/zapret-$ZAPRET_VERSION"
else
  # Если не нашли конкретные варианты, ищем любую папку zapret-*
  ZAPRET_EXTRACT_DIR=$(find "$HOME/tmp" -type d -name "zapret-*" | head -n 1)
  if [ -z "$ZAPRET_EXTRACT_DIR" ]; then
    echo "Ошибка: не удалось найти распакованную директорию zapret."
    echo "Содержимое $HOME/tmp:"
    ls -la "$HOME/tmp"
    exit 1
  fi
fi

echo "Найден распакованный каталог: $ZAPRET_EXTRACT_DIR"

# Проверяем, является ли система Solus, если да, то создаём /opt/
if [ -f "/etc/os-release" ] && grep -q "^ID=solus" /etc/os-release; then
    echo "Директория /opt/ не существует, создаём..."
    $ELEVATE_CMD mkdir -p /opt/
fi

# Перемещение zapret в /opt/zapret
echo "Перемещение zapret в /opt/zapret..."
if ! $ELEVATE_CMD mv "$ZAPRET_EXTRACT_DIR" /opt/zapret; then
  echo "Ошибка: не удалось переместить zapret в /opt/zapret."
  exit 1
fi

# Клонирование репозитория с конфигами
echo "Клонирование репозитория с конфигами..."
if ! git clone https://github.com/kartavkun/zapret-discord-youtube.git "$HOME/zapret-configs"; then
  rm -rf $HOME/zapret-configs
  if ! git clone https://github.com/kartavkun/zapret-discord-youtube.git "$HOME/zapret-configs"; then
    echo "Ошибка: не удалось клонировать репозиторий с конфигами."
  exit 1
  fi
fi

# Копирование hostlists
echo "Копирование hostlists..."
if ! cp -r "$HOME/zapret-configs/hostlists" /opt/zapret/hostlists; then
  echo "Ошибка: не удалось скопировать hostlists."
  exit 1
fi

# Настройка IP forwarding для WireGuard
echo "Проверка и настройка IP forwarding для WireGuard..."
if [ ! -f "/etc/sysctl.d/99-sysctl.conf" ]; then
  echo "Создание конфигурационного файла /etc/sysctl.d/99-sysctl.conf..."
  echo "# Конфигурация для zapret" | $ELEVATE_CMD tee /etc/sysctl.d/99-sysctl.conf > /dev/null
  echo "net.ipv4.ip_forward=1" | $ELEVATE_CMD tee -a /etc/sysctl.d/99-sysctl.conf > /dev/null
else
  # Проверяем, содержит ли файл уже параметр ip_forward
  if ! grep -q "net.ipv4.ip_forward=1" /etc/sysctl.d/99-sysctl.conf; then
    echo "Добавление параметра net.ipv4.ip_forward=1 в /etc/sysctl.d/99-sysctl.conf..."
    echo "net.ipv4.ip_forward=1" | $ELEVATE_CMD tee -a /etc/sysctl.d/99-sysctl.conf > /dev/null
  else
    echo "Параметр net.ipv4.ip_forward=1 уже установлен"
  fi
fi

# Применяем настройки без перезагрузки
$ELEVATE_CMD sysctl -p /etc/sysctl.d/99-sysctl.conf

# Запуск второго скрипта
echo "Запуск install.sh..."
if ! bash "$HOME/zapret-configs/install.sh"; then
  echo "Ошибка: не удалось запустить install.sh."
  exit 1
fi
