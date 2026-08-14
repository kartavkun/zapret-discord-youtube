#!/usr/bin/env bash
#
# Мейнтейнерский скрипт: пересчитывает контрольные суммы в zapret.lock.
# Требует сети. Пользователям запускать не нужно.
#
# Использование:
#   tools/update-lock.sh              # текущая версия zapret из lock-файла
#   tools/update-lock.sh v72.13       # конкретная версия
#   tools/update-lock.sh --latest     # последний релиз с GitHub
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../lib/paths.sh
. "$REPO_DIR/lib/paths.sh"
# shellcheck source=../lib/common.sh
. "$ZDY_LIB/common.sh"
# shellcheck source=../lib/compat.sh
. "$ZDY_LIB/compat.sh"
# shellcheck source=../lib/lock.sh
. "$ZDY_LIB/lock.sh"

BINARIES=(
  tls_clienthello_4pda_to.bin
  tls_clienthello_max_ru.bin
  stun.bin
  stun2.bin
  quic_initial_dbankcloud_ru.bin
  quic_initial_steamcommunity_com.bin
  quic_initial_tencent_com.bin
  ACTIVE_DISCORD_UDP.bin
  ACTIVE_GAME_UDP.bin
)

resolve_version() {
  case "${1:-}" in
    --latest)
      fetch_stdout "https://api.github.com/repos/bol-van/zapret/releases/latest" |
        grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' |
        head -n 1 |
        sed 's/.*"\([^"]*\)"$/\1/'
      ;;
    "") lock_get zapret_version ;;
    *) printf '%s\n' "$1" ;;
  esac
}

resolve_flowseal_commit() {
  fetch_stdout "https://api.github.com/repos/$ZDY_FLOWSEAL_SLUG/commits/main" |
    grep -o '[0-9a-f]\{40\}' |
    head -n 1
}

main() {
  require_cmd tar
  sha256_cmd >/dev/null || die "Нужен sha256sum, shasum или openssl"

  local work version commit url tmp
  work=$(zdy_tempdir)

  version=$(resolve_version "${1:-}")
  [ -n "$version" ] || die "Не удалось определить версию zapret"
  msg "Версия zapret: $version"

  commit=$(resolve_flowseal_commit)
  [ -n "$commit" ] || die "Не удалось определить коммит Flowseal"
  msg "Коммит Flowseal: $commit"

  url="https://github.com/bol-van/zapret/releases/download/$version/zapret-$version.tar.gz"
  tmp="$work/zapret.tar.gz"
  msg "Скачивание $url"
  fetch_url "$url" "$tmp" || die "Не удалось скачать релиз zapret"
  local zapret_hash
  zapret_hash=$(sha256_file "$tmp")

  {
    printf '# Пины версий и контрольные суммы загружаемых файлов.\n'
    printf '#\n'
    printf '# Сгенерировано tools/update-lock.sh %s\n' "$(date '+%Y-%m-%d')"
    printf '# Правьте через этот скрипт, а не руками.\n'
    printf '\n'
    printf 'zapret_version %s\n' "$version"
    printf 'zapret_sha256 %s\n' "$zapret_hash"
    printf '\n'
    printf 'flowseal_commit %s\n' "$commit"
    printf '\n'

    local binary bin_url bin_tmp bin_hash
    for binary in "${BINARIES[@]}"; do
      bin_url="https://raw.githubusercontent.com/$ZDY_FLOWSEAL_SLUG/$commit/bin/$binary"
      bin_tmp="$work/$binary"
      printf '[ * ] Скачивание %s\n' "$binary" >&2
      if ! fetch_url "$bin_url" "$bin_tmp"; then
        printf '# ВНИМАНИЕ: не удалось скачать %s\n' "$binary"
        printf 'bin_sha256 %s unset\n' "$binary"
        continue
      fi
      bin_hash=$(sha256_file "$bin_tmp")
      printf 'bin_sha256 %s %s\n' "$binary" "$bin_hash"
    done
  } >"$work/zapret.lock"

  cp "$work/zapret.lock" "$ZDY_LOCK_FILE"
  ok "zapret.lock обновлён"
  msg ""
  cat "$ZDY_LOCK_FILE"
}

main "$@"
