#!/bin/bash

# Определяем пакетный менеджер
if command -v brew &>/dev/null; then
  echo "Обнаружен brew, устанавливаем wget..."
  brew install wget git
else
  clear
  echo "Не нашёл установленный Homebrew. Установите Homebrew, потом запускайте скрипт ещё раз."
  exit 1
fi

# Проверка успешной установки wget
if ! command -v wget &>/dev/null; then
  echo "Ошибка: wget не установлен. Установите его вручную."
  exit 1
fi

echo "wget успешно установлен!"

# Создаем временную директорию, если она не существует
mkdir -p "$HOME/tmp"
# Удаление архива с запретом на всякий
rm -rf "$HOME/tmp/*"

# Бэкап запрета если есть
sudo cp "/opt/zapret" "/opt/zapret.bak"
sudo rm -rf "/opt/zapret"

# Переменная для хранения версии zapret
ZAPRET_VERSION="v70.3"

# Закачка последнего релиза bol-van/zapret
echo "Скачивание последнего релиза zapret..."
if ! wget -O "$HOME/tmp/zapret-$ZAPRET_VERSION.tar.gz" "https://github.com/bol-van/zapret/releases/download/$ZAPRET_VERSION/zapret-$ZAPRET_VERSION.tar.gz" --no-check-certificate; then
  echo "Ошибка: не удалось скачать zapret."
  exit 1
fi

# Распаковка архива
echo "Распаковка zapret..."
if ! tar -xvf "$HOME/tmp/zapret-$ZAPRET_VERSION.tar.gz" -C "$HOME/tmp"; then
  echo "Ошибка: не удалось распаковать zapret."
  exit 1
fi

# Перемещение zapret в /opt/zapret
echo "Перемещение zapret в /opt/zapret..."
if ! sudo mv "$HOME/tmp/zapret-$ZAPRET_VERSION" /opt/zapret; then
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
if ! sudo cp -r "$HOME/zapret-configs/hostlists" /opt/zapret/hostlists; then
  echo "Ошибка: не удалось скопировать hostlists."
  exit 1
fi

# Запуск второго скрипта
echo "Запуск install.sh..."
if ! bash "$HOME/zapret-configs/install.sh"; then
  echo "Ошибка: не удалось запустить install.sh."
  exit 1
fi
