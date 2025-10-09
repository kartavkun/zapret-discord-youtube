#!/bin/bash
set -e

# Определяем каталог, где лежит сам скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# Используем ту же команду повышения прав, что и в install.sh
ELEVATE_CMD="${ELEVATE_CMD:-sudo}"

# Компиляция и установка SELinux модуля
checkmodule -M -m -o ./zapret.mod ./zapret.te
semodule_package -o ./zapret.pp -m ./zapret.mod

$ELEVATE_CMD semodule -i ./zapret.pp
$ELEVATE_CMD semanage fcontext -a -t bin_t "/opt/zapret/init.d/sysv/zapret"
$ELEVATE_CMD restorecon -v "/opt/zapret/init.d/sysv/zapret"
