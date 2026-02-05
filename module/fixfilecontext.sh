#!/bin/bash
set -e

# Определяем каталог, где лежит сам скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

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
    echo "sudo"
  fi
}

# Используем ту же команду повышения прав, что и в install.sh
ELEVATE_CMD="${ELEVATE_CMD:-$(detect_privilege_escalation)}"

# Выбираем нужный модуль в зависимости от системы
if [ -f "/etc/os-release" ] && grep -qi "bazzite" /etc/os-release; then
  echo "Обнаружена система Bazzite. Используем специализированный SELinux модуль..."
  MODULE_FILE="./zapret-bazzite.te"
  OUTPUT_MOD="./zapret_bazzite.mod"
  OUTPUT_PP="./zapret_bazzite.pp"
elif [ -f "/etc/os-release" ] && grep -qi "Fedora" /etc/os-release; then
  echo "Обнаружена система Fedora. Используем специализированный SELinux модуль (от Bazzite)..."
  MODULE_FILE="./zapret-bazzite.te"
  OUTPUT_MOD="./zapret_bazzite.mod"
  OUTPUT_PP="./zapret_bazzite.pp"
else
  echo "Используем стандартный SELinux модуль..."
  MODULE_FILE="./zapret.te"
  OUTPUT_MOD="./zapret.mod"
  OUTPUT_PP="./zapret.pp"
fi

echo "Компиляция SELinux модуля для zapret..."
checkmodule -M -m -o "$OUTPUT_MOD" "$MODULE_FILE"
semodule_package -o "$OUTPUT_PP" -m "$OUTPUT_MOD"

echo "Установка SELinux модуля..."
$ELEVATE_CMD semodule -i "$OUTPUT_PP"

echo "Установка контекстов файлов..."
# Для стандартного пути
$ELEVATE_CMD semanage fcontext -a -t bin_t "/opt/zapret/init.d/sysv/zapret" 2>/dev/null || true

# Для всей папки /opt/zapret (важно для Bazzite)
$ELEVATE_CMD semanage fcontext -a -t bin_t "/opt/zapret(/.*)?" 2>/dev/null || true

echo "Применение контекстов..."
$ELEVATE_CMD restorecon -R -v /opt/zapret

echo "✓ SELinux модуль успешно установлен"
