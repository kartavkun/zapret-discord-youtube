#!/bin/bash

# Функция для определения доступной утилиты повышения привилегий
detect_privilege_escalation() {
  if [ "$(id -u)" -eq 0 ]; then
    echo ""
  elif command -v doas &>/dev/null; then
    echo "doas"
  elif command -v sudo-rs &>/dev/null; then
    echo "sudo-rs"
  elif command -v sudo &>/dev/null; then
    echo "sudo"
  elif command -v run0 &>/dev/null; then
    echo "run0"
  else
    return 1
  fi
}

# Определяем доступную утилиту повышения привилегий
if ! ELEVATE_CMD=$(detect_privilege_escalation); then
  echo "Ошибка: не найдены утилиты sudo, sudo-rs, doas или run0 для повышения привилегий."
  echo "Установите одну из этих утилит для продолжения."
  exit 1
fi

choose_gentoo_emerge_mode() {
  if [ -n "$GENTOO_EMERGE_MODE" ]; then
    return 0
  fi

  while true; do
    echo "Обнаружен Portage/emerge. Выберите способ установки пакетов:"
    echo "1. Сборка из исходников (обычный Gentoo способ)"
    echo "2. Бинарные пакеты через --getbinpkg (если доступны)"
    read -rp "Введите номер [1/2]: " emerge_choice

    case "$emerge_choice" in
      1)
        GENTOO_EMERGE_MODE="source"
        export GENTOO_EMERGE_MODE
        break ;;
      2)
        GENTOO_EMERGE_MODE="binary"
        export GENTOO_EMERGE_MODE
        break ;;
      *)
        echo "Неверный выбор. Введите 1 или 2." ;;
    esac
  done
}

emerge_install() {
  choose_gentoo_emerge_mode

  if [ "$GENTOO_EMERGE_MODE" = "binary" ]; then
    $ELEVATE_CMD emerge --ask=n --getbinpkg --noreplace --oneshot "$@"
  else
    $ELEVATE_CMD emerge --ask=n --noreplace --oneshot "$@"
  fi
}

# Функция установки пакетов с разными пакетными менеджерами
install_packages() {
  local artix_iptables_package="iptables"

  if [ -f /etc/os-release ] && grep -qi '^ID="?artix"?$' /etc/os-release; then
    case "$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')" in
      dinit) artix_iptables_package="iptables-dinit" ;;
      s6-svscan) artix_iptables_package="iptables-s6" ;;
      runit|runit-init) artix_iptables_package="iptables-runit" ;;
      *) artix_iptables_package="iptables-openrc" ;;
    esac
  fi

  case "$1" in
    epm)
      $ELEVATE_CMD epm -i curl wget git tar iptables ipset ;;
    apt)
      $ELEVATE_CMD apt update && $ELEVATE_CMD apt install -y --no-install-recommends curl wget git tar iptables ipset ;;
    apt-get)
      $ELEVATE_CMD apt-get update && $ELEVATE_CMD apt-get install -y --no-install-recommends curl wget git tar iptables ipset ;;
    nala)
      $ELEVATE_CMD nala update && $ELEVATE_CMD nala install -y curl wget git tar iptables ipset ;;
    yum)
      $ELEVATE_CMD yum install -y curl wget git tar iptables ipset ;;
    dnf)
      $ELEVATE_CMD dnf install -y curl wget git tar iptables ipset ;;
    pacman)
      $ELEVATE_CMD pacman -Sy --noconfirm curl wget git tar "$artix_iptables_package" ipset ;;
    zypper)
      $ELEVATE_CMD zypper install -y curl wget git tar iptables ipset ;;
    xbps-install)
      $ELEVATE_CMD xbps-install -Sy curl wget git tar ipset iptables cronie ;;
    slapt-get)
      $ELEVATE_CMD slapt-get -i --no-prompt curl wget git tar iptables ipset ;;
    apk)
      $ELEVATE_CMD apk add curl wget git tar iptables ip6tables ipset ;;
    emerge)
      emerge_install net-misc/curl net-misc/wget dev-vcs/git app-arch/tar net-firewall/iptables net-firewall/ipset ;;
    eopkg)
      $ELEVATE_CMD eopkg update-repo && $ELEVATE_CMD eopkg install curl wget git tar iptables ipset ;;
    rpm-ostree)
      echo "ВНИМАНИЕ: rpm-ostree требует перезагрузку после установки пакетов."
      echo "Установка зависимостей через rpm-ostree..."
      $ELEVATE_CMD rpm-ostree install curl wget git tar iptables ipset
      echo "Пожалуйста, перезагрузите систему и запустите скрипт снова."
      exit 0 ;;
    *)
      echo "Неизвестный пакетный менеджер: $1"
      return 1 ;;
  esac
}

# Проверяем инструменты, необходимые для загрузки, firewall и NFQUEUE.
MISSING_COMMANDS=()
for REQUIRED_COMMAND in curl wget git tar iptables ip6tables ipset; do
  command -v "$REQUIRED_COMMAND" >/dev/null 2>&1 || MISSING_COMMANDS+=("$REQUIRED_COMMAND")
done

if [ "${#MISSING_COMMANDS[@]}" -eq 0 ]; then
  echo "Необходимые зависимости уже установлены, продолжаем..."
else
  if [ -f /etc/os-release ] &&
      grep -qi '^ID="?chimera"?$' /etc/os-release &&
      command -v apk >/dev/null 2>&1 &&
      ! apk info -e chimera-repo-user >/dev/null 2>&1; then
    echo "Подключение user-репозитория Chimera Linux..."
    $ELEVATE_CMD apk add chimera-repo-user
    $ELEVATE_CMD apk update
  fi

  PACKAGE_MANAGERS=(
    nala
    epm
    apt
    apt-get
    rpm-ostree
    yum
    dnf
    pacman
    zypper
    xbps-install
    slapt-get
    apk
    emerge
    eopkg
  )

  DETECTED_PM=""
  for pm in "${PACKAGE_MANAGERS[@]}"; do
    if command -v "$pm" &>/dev/null; then
      DETECTED_PM="$pm"
      break
    fi
  done

  if [ -n "$DETECTED_PM" ]; then
    echo "Не найдены команды: ${MISSING_COMMANDS[*]}"
    echo "Обнаружен $DETECTED_PM, устанавливаем зависимости..."
    install_packages "$DETECTED_PM"
  else
    echo "Не удалось определить пакетный менеджер."
    echo "Необходимо установить вручную: ${MISSING_COMMANDS[*]}"
    exit 1
  fi
fi

MISSING_COMMANDS=()
for REQUIRED_COMMAND in curl wget git tar iptables ip6tables ipset; do
  command -v "$REQUIRED_COMMAND" >/dev/null 2>&1 || MISSING_COMMANDS+=("$REQUIRED_COMMAND")
done
if [ "${#MISSING_COMMANDS[@]}" -gt 0 ]; then
  echo "Ошибка: после установки всё ещё отсутствуют команды: ${MISSING_COMMANDS[*]}"
  exit 1
fi

# Создаем временную директорию, если она не существует
mkdir -p "$HOME/tmp"
# Удаление архива с запретом на всякий
rm -rf -- "$HOME/tmp"/*

# Бэкап запрета если есть
ZAPRET_BACKUP_CREATED=0
if [ -d "/opt/zapret" ]; then
  echo "Создание резервной копии существующего zapret..."
  TARGET_USER=$(logname 2>/dev/null || id -un 2>/dev/null || echo "$USER")
  TARGET_GROUP=$(id -gn "$TARGET_USER" 2>/dev/null || echo "$TARGET_USER")

  $ELEVATE_CMD rm -rf "/opt/zapret.bak"
  if ! $ELEVATE_CMD cp -a "/opt/zapret" "/opt/zapret.bak"; then
    echo "Ошибка: не удалось создать резервную копию /opt/zapret."
    exit 1
  fi
  ZAPRET_BACKUP_CREATED=1
  $ELEVATE_CMD chown -R "$TARGET_USER:$TARGET_GROUP" "/opt/zapret.bak"
  $ELEVATE_CMD chmod -R u+rwX,go+rX "/opt/zapret.bak"
  $ELEVATE_CMD find "/opt/zapret.bak" -type d -exec chmod g+s {} \;
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

# Проверяем, является ли система Solus/Chimera, если да, то создаём /opt/
if [ -f "/etc/os-release" ] && grep -Eq '^ID="?(solus|chimera)"?$' /etc/os-release; then
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
  rm -rf -- "$HOME/zapret-configs"
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
  "stun.bin"
  "stun2.bin"
  "quic_initial_dbankcloud_ru.bin"
  "quic_initial_steamcommunity_com.bin"
  "quic_initial_tencent_com.bin"
  "ACTIVE_DISCORD_UDP.bin"
  "ACTIVE_GAME_UDP.bin"
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

valid_fragment_name() {
  case "$1" in
    ""|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

extract_nfqws_assignment() {
  local config_file="$1"
  local output_file="$2"

  awk '
    /^[[:space:]]*NFQWS_OPT="/ { copying=1 }
    copying { print }
    copying && /^[[:space:]]*NFQWS_OPT=".*"[[:space:]]*$/ { exit }
    copying && /^[[:space:]]*"$/ { exit }
  ' "$config_file" > "$output_file"

  [ -s "$output_file" ] && sh -n "$output_file" >/dev/null 2>&1
}

find_matching_strategy() {
  local old_config="$1"
  local assignment_file
  local old_value_file
  local strategy_value_file
  local strategy_file
  local strategy_name

  assignment_file=$(mktemp "${TMPDIR:-/tmp}/zapret-old-strategy.XXXXXX") || return 1
  old_value_file=$(mktemp "${TMPDIR:-/tmp}/zapret-old-value.XXXXXX") || {
    rm -f "$assignment_file"
    return 1
  }
  strategy_value_file=$(mktemp "${TMPDIR:-/tmp}/zapret-new-value.XXXXXX") || {
    rm -f "$assignment_file" "$old_value_file"
    return 1
  }

  if ! extract_nfqws_assignment "$old_config" "$assignment_file" ||
      ! GAME_FILTER_TCP=1024-65535 GAME_FILTER_UDP=1024-65535 \
        sh -c '. "$1"; printf "%s" "$NFQWS_OPT"' sh "$assignment_file" > "$old_value_file" ||
      [ ! -s "$old_value_file" ]; then
    rm -f "$assignment_file" "$old_value_file" "$strategy_value_file"
    return 1
  fi

  for strategy_file in "$HOME/zapret-configs"/strategies/*; do
    [ -f "$strategy_file" ] || continue
    if GAME_FILTER_TCP=1024-65535 GAME_FILTER_UDP=1024-65535 \
        sh -c 'NFQWS_STRATEGY_OPT=; . "$1"; printf "%s" "$NFQWS_STRATEGY_OPT"' \
        sh "$strategy_file" > "$strategy_value_file" &&
        cmp -s "$old_value_file" "$strategy_value_file"; then
      strategy_name=$(basename "$strategy_file")
      rm -f "$assignment_file" "$old_value_file" "$strategy_value_file"
      printf '%s\n' "$strategy_name"
      return 0
    fi
  done

  sed '1s/NFQWS_OPT/NFQWS_STRATEGY_OPT/' "$assignment_file" > "$strategy_value_file"
  if [ -s "$strategy_value_file" ]; then
    if ! $ELEVATE_CMD cp "$strategy_value_file" /opt/zapret/strategies/migrated-custom ||
        ! $ELEVATE_CMD chmod 644 /opt/zapret/strategies/migrated-custom; then
      rm -f "$assignment_file" "$old_value_file" "$strategy_value_file"
      return 1
    fi
    rm -f "$assignment_file" "$old_value_file" "$strategy_value_file"
    printf '%s\n' migrated-custom
    return 0
  fi

  rm -f "$assignment_file" "$old_value_file" "$strategy_value_file"
  return 1
}

restore_fragment_state() {
  local backup_root="/nonexistent/zapret-backup"
  local selected_strategy=""
  local state_tmp
  local state_entry
  local old_fragment

  [ "$ZAPRET_BACKUP_CREATED" -eq 0 ] || backup_root="/opt/zapret.bak"

  if [ -d "$backup_root/strategies" ]; then
    for old_fragment in "$backup_root"/strategies/*; do
      [ -f "$old_fragment" ] || continue
      [ -e "/opt/zapret/strategies/$(basename "$old_fragment")" ] ||
        $ELEVATE_CMD cp "$old_fragment" /opt/zapret/strategies/
    done
  fi
  if [ -d "$backup_root/fixes" ]; then
    for old_fragment in "$backup_root"/fixes/*; do
      [ -f "$old_fragment" ] || continue
      [ -e "/opt/zapret/fixes/$(basename "$old_fragment")" ] ||
        $ELEVATE_CMD cp "$old_fragment" /opt/zapret/fixes/
    done
  fi

  if [ -f "$backup_root/zapret.strategy" ]; then
    selected_strategy=$(sed -n '1{s/\r$//;p;}' "$backup_root/zapret.strategy")
  fi
  if ! valid_fragment_name "$selected_strategy" ||
      [ ! -f "/opt/zapret/strategies/$selected_strategy" ]; then
    selected_strategy=""
  fi

  if [ -z "$selected_strategy" ] && [ -f "$backup_root/config" ]; then
    selected_strategy=$(find_matching_strategy "$backup_root/config" || true)
  fi
  if ! valid_fragment_name "$selected_strategy" ||
      [ ! -f "/opt/zapret/strategies/$selected_strategy" ]; then
    selected_strategy="general"
  fi
  printf '%s\n' "$selected_strategy" | $ELEVATE_CMD tee /opt/zapret/zapret.strategy >/dev/null

  state_tmp=$(mktemp "${TMPDIR:-/tmp}/zapret-fixes.XXXXXX") || return 1
  if [ -f "$backup_root/zapret.fixes" ]; then
    while IFS= read -r state_entry || [ -n "$state_entry" ]; do
      state_entry=$(printf '%s' "$state_entry" |
        sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      valid_fragment_name "$state_entry" || continue
      [ -f "/opt/zapret/fixes/$state_entry" ] || continue
      grep -Fqx -- "$state_entry" "$state_tmp" 2>/dev/null ||
        printf '%s\n' "$state_entry" >> "$state_tmp"
    done < "$backup_root/zapret.fixes"
  fi
  $ELEVATE_CMD cp "$state_tmp" /opt/zapret/zapret.fixes
  $ELEVATE_CMD chmod 644 /opt/zapret/zapret.strategy /opt/zapret/zapret.fixes
  rm -f "$state_tmp"
}

install_runtime_files() {
  local backup_root="/nonexistent/zapret-backup"
  local hostlist_name

  [ "$ZAPRET_BACKUP_CREATED" -eq 0 ] || backup_root="/opt/zapret.bak"

  echo "Установка общего конфига, стратегий, фиксов и hostlists..."
  $ELEVATE_CMD mkdir -p /opt/zapret/hostlists /opt/zapret/strategies /opt/zapret/fixes || return 1
  $ELEVATE_CMD cp -R "$HOME/zapret-configs/hostlists/." /opt/zapret/hostlists/ || return 1
  $ELEVATE_CMD cp -R "$HOME/zapret-configs/strategies/." /opt/zapret/strategies/ || return 1
  $ELEVATE_CMD cp -R "$HOME/zapret-configs/fixes/." /opt/zapret/fixes/ || return 1

  if [ -f "$backup_root/config" ] &&
      grep -q '^ZAPRET_CONFIG_VERSION=2$' "$backup_root/config"; then
    echo "Сохранён существующий общий config."
    $ELEVATE_CMD cp "$backup_root/config" /opt/zapret/config || return 1
  else
    if [ -f "$backup_root/config" ]; then
      echo "Старый config сохранён в $backup_root/config; устанавливается новая схема."
    fi
    $ELEVATE_CMD cp "$HOME/zapret-configs/config" /opt/zapret/config || return 1
  fi

  for hostlist_name in \
    list-general-user.txt \
    list-exclude-user.txt \
    ipset-exclude-user.txt \
    ipset-all.txt \
    ipset-all.txt.backup \
    .game_filter.enabled; do
    if [ -f "$backup_root/hostlists/$hostlist_name" ]; then
      $ELEVATE_CMD cp "$backup_root/hostlists/$hostlist_name" "/opt/zapret/hostlists/$hostlist_name"
    fi
  done

  restore_fragment_state || return 1
  $ELEVATE_CMD chmod 755 /opt/zapret/hostlists /opt/zapret/strategies /opt/zapret/fixes
  $ELEVATE_CMD find /opt/zapret/hostlists /opt/zapret/strategies /opt/zapret/fixes \
    -type f -exec chmod 644 {} \;
}

if ! install_runtime_files; then
  echo "Ошибка: не удалось установить config, стратегии, фиксы или hostlists."
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
  
  if ! grep -q "alias zapret-utils=" "$shell_config"; then
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
