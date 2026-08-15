#!/usr/bin/env bash
#
# Точка входа для установки одной командой:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/setup.sh)
#
# Этот файл намеренно остаётся самодостаточным и коротким: он запускается
# в момент, когда репозитория на машине ещё нет, поэтому подключить lib/
# неоткуда. Его единственная задача - скачать проект во временный каталог
# и передать управление bin/zapret-setup, где уже доступны все библиотеки.
#
# Такая схема заодно решает проблему переноса со старой раскладки каталогов:
# перенос выполняется из временной копии, а не из каталога, который сам же
# и перемещается.
set -euo pipefail

REPO_SLUG="${ZDY_REPO_SLUG:-kartavkun/zapret-discord-youtube}"
BRANCH="${ZDY_BRANCH:-main}"
ARCHIVE_URL="${ZDY_ARCHIVE_URL:-https://codeload.github.com/$REPO_SLUG/tar.gz/refs/heads/$BRANCH}"

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

if [ -z "${BASH_VERSINFO:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  die "[ - ] нужен bash 4.0 или новее. Установите пакет bash и повторите."
fi

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 -o "$2" "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$2" "$1"
  else
    die "[ - ] нужен curl или wget."
  fi
}

command -v tar >/dev/null 2>&1 || die "[ - ] нужен tar."

WORK=$(mktemp -d "${TMPDIR:-/tmp}/zapret-setup.XXXXXX")
trap 'rm -rf -- "$WORK"' EXIT

printf '[ * ] Загрузка zapret-discord-youtube...\n'
fetch "$ARCHIVE_URL" "$WORK/repo.tar.gz" || die "[ - ] не удалось скачать проект."
tar -xzf "$WORK/repo.tar.gz" -C "$WORK" || die "[ - ] не удалось распаковать архив."

SOURCE=$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -print | head -n 1)
[ -n "$SOURCE" ] || die "[ - ] архив пуст."
[ -x "$SOURCE/bin/zapret-setup" ] || chmod +x "$SOURCE/bin/zapret-setup" 2>/dev/null || true
[ -f "$SOURCE/bin/zapret-setup" ] || die "[ - ] в архиве нет bin/zapret-setup."

# Установщику нужен настоящий терминал: он задаёт вопросы, а stdin у
# конструкции bash <(curl ...) может быть занят.
if [ ! -t 0 ] && [ -e /dev/tty ]; then
  exec bash "$SOURCE/bin/zapret-setup" "$@" </dev/tty
fi

exec bash "$SOURCE/bin/zapret-setup" "$@"
