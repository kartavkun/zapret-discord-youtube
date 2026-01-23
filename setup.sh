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
    echo "Ошибка: не найдены утилиты sudo, sudo-rs, doas или run0 для повышения привилегий."
    echo "Установите одну из этих утилит для продолжения."
    exit 1
  fi
}

# Определяем доступную утилиту повышения привилегий
ELEVATE_CMD=$(detect_privilege_escalation)

# Функция установки пакетов с разными пакетными менеджерами
install_packages() {
  case "$1" in
    epm)
      $ELEVATE_CMD epm -i wget git ;;
    apt)
      $ELEVATE_CMD apt update && $ELEVATE_CMD apt install -y --no-install-recommends wget git ;;
    apt-get)
      $ELEVATE_CMD apt-get update && $ELEVATE_CMD apt-get install -y --no-install-recommends wget git ;;
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
  elif command -v epm &>/dev/null; then
    echo "Обнаружен epm, устанавливаем wget и git..."
    install_packages epm
  elif command -v apt &>/dev/null; then
    echo "Обнаружен apt, устанавливаем wget и git..."
    install_packages apt
  elif command -v apt-get &>/dev/null; then
    echo "Обнаружен apt-get, устанавливаем wget и git..."
    install_packages apt-get
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

  # Сохраняем права владельца и группы для бэкапа
  OLD_OWNER=$(stat -c '%U:%G' "/opt/zapret")
  $ELEVATE_CMD chown -R "$OLD_OWNER" "/opt/zapret.bak"
fi

# Удаляем старую директорию перед установкой новой версии
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

if [ -d "$HOME/tmp/zapret-$ZAPRET_DIR_VERSION" ]; then
  ZAPRET_EXTRACT_DIR="$HOME/tmp/zapret-$ZAPRET_DIR_VERSION"
elif [ -d "$HOME/tmp/zapret-$ZAPRET_VERSION" ]; then
  ZAPRET_EXTRACT_DIR="$HOME/tmp/zapret-$ZAPRET_VERSION"
else
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

# Передаём права пользователю
TARGET_USER=$(logname 2>/dev/null || id -un 2>/dev/null || echo "$USER")
TARGET_GROUP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")
$ELEVATE_CMD chown -R "$TARGET_USER:$TARGET_GROUP" /opt/zapret
$ELEVATE_CMD chmod -R u+rwX,go+rX /opt/zapret
$ELEVATE_CMD find /opt/zapret -type d -exec chmod g+s {} \;

# Клонирование репозитория с конфигами
echo "Клонирование репозитория с конфигами..."
if ! git clone https://github.com/kartavkun/zapret-discord-youtube.git "$HOME/zapret-configs"; then
  rm -rf $HOME/zapret-configs
  if ! git clone https://github.com/kartavkun/zapret-discord-youtube.git "$HOME/zapret-configs"; then
    echo "Ошибка: не удалось клонировать репозиторий с конфигами."
  exit 1
  fi
fi

# Скачиваем бинарники TLS в папку fake
FAKE_BIN_DIR="/opt/zapret/files/fake"
GITHUB_BIN_URL="https://github.com/Flowseal/zapret-discord-youtube/raw/refs/heads/main/bin"

# Массив бинарников для скачивания
declare -a BINARIES=(
  "tls_clienthello_4pda_to.bin"
  "tls_clienthello_max_ru.bin"
)

echo "Скачивание бинарников TLS..."
for BINARY in "${BINARIES[@]}"; do
  DEST="$FAKE_BIN_DIR/$BINARY"
  URL="$GITHUB_BIN_URL/$BINARY"
  
  if [ ! -f "$DEST" ]; then
    echo "Скачивание $BINARY..."
    if ! wget -q -O "$DEST" "$URL"; then
      echo "Ошибка: не удалось скачать $BINARY с $URL"
      exit 1
    fi
    echo "$BINARY успешно скачан"
  else
    echo "$BINARY уже существует, пропускаем"
  fi
done

# Копирование hostlists
echo "Копирование hostlists..."
if ! cp -r "$HOME/zapret-configs/hostlists" /opt/zapret/hostlists; then
  echo "Ошибка: не удалось скопировать hostlists."
  exit 1
fi

# функция добавления alias в shell
setup_shell_shortcuts() {
  echo
  local response
  
  # Цикл повторяет вопрос, пока не получит правильный ответ
  while true; do
    echo "Добавить быстрые команды zapret-config и zapret-switch? [Y/n]"
    read -rp "> " response
    
    # Нормализуем ответ (учитываем русскую раскладку и регистр)
    case "${response,,}" in
      y|yes|д|да|"") break ;;
      n|no|н|нет) return 0 ;;
      *) echo "⚠ Неверный ввод. Ответьте Y/N (или Д/Н)"; echo ;;
    esac
  done
  
  # Определяем текущий shell и его конфиг
  local current_shell=$(basename "$SHELL")
  local shell_config
  
  declare -A shell_configs=(
    [bash]="$HOME/.bashrc"
    [zsh]="$HOME/.zshrc"
    [fish]="$HOME/.config/fish/config.fish"
    [ksh]="$HOME/.kshrc"
    [mksh]="$HOME/.kshrc"
    [tcsh]="$HOME/.tcshrc"
    [csh]="$HOME/.tcshrc"
  )
  
  shell_config="${shell_configs[$current_shell]}"
  
  if [ -z "$shell_config" ]; then
    echo "⚠ Неизвестный shell: $current_shell"
    echo "Добавьте alias вручную в ваш конфиг-файл shell"
    return 0
  fi
  
  if [ ! -f "$shell_config" ]; then
    echo "Создание $shell_config..."
    touch "$shell_config"
  fi
  
  # Добавляем alias если их ещё нет
  local alias_config_added=0
  local alias_switch_added=0
  
  # Проверяем, есть ли уже секция zapret
  if ! grep -q "# быстрые команды для управления zapret" "$shell_config"; then
    # Добавляем секцию с комментарием
    {
      echo ""
      echo "# быстрые команды для управления zapret"
    } >> "$shell_config"
  fi
  
  if ! grep -q "alias zapret-config=" "$shell_config"; then
    echo "alias zapret-config='\$HOME/zapret-configs/install.sh'" >> "$shell_config"
    alias_config_added=1
  fi
  
  if ! grep -q "alias utils-zapret=" "$shell_config"; then
    echo "alias zapret-utils='\$HOME/zapret-configs/utils-zapret.sh'" >> "$shell_config"
    alias_switch_added=1
  fi
  

  # вывод сообщений в терминал
  if [ $alias_config_added -eq 1 ] || [ $alias_switch_added -eq 1 ]; then
    echo "Alias добавлены в $shell_config"
    echo "Активирую alias..."
    source "$shell_config"
    echo "Готово! Теперь доступны команды:"
    echo "zapret-config - конфигуратор стратегий"
    echo "zapret-utils - управлением zapret"
  else
    echo "Alias уже добавлены в $shell_config"
    source "$shell_config"
  fi
}

# Вызываем функцию настройки
setup_shell_shortcuts

# Определяем текущую оболочку (рабочий процесс)
CURRENT_SHELL=$(ps -p $$ -o comm= 2>/dev/null || echo "")

# Если текущая оболочка fish -> используем интерактивный bash, чтобы fish-окружение не ломало ввод
if [[ "$CURRENT_SHELL" == *fish* ]]; then
  exec bash --login -i -c "exec $HOME/zapret-configs/install.sh < /dev/tty > /dev/tty 2>&1"
else
  # Для bash/zsh/sh - обычный запуск в том же TTY (без перенаправлений)
  bash "$HOME/zapret-configs/install.sh"
fi