# shellcheck shell=bash
#
# Модуль подключается из bin/*, а не сам по себе: общие функции и пути
# приходят из lib/common.sh, lib/compat.sh и lib/paths.sh, подключённых
# вызывающим скриптом раньше. Отсюда директивы source ниже - без них
# shellcheck считает эти имена неопределёнными.
# shellcheck source=common.sh
# shellcheck source=compat.sh
#
# Определение дистрибутива и установка пакетов.

[ -n "${ZDY_DISTRO_SOURCED:-}" ] && return 0
ZDY_DISTRO_SOURCED=1

ZDY_PACKAGE_MANAGERS=(
  nala epm apt apt-get rpm-ostree yum dnf pacman zypper
  xbps-install slapt-get apk emerge eopkg
)

detect_package_manager() {
  local pm
  for pm in "${ZDY_PACKAGE_MANAGERS[@]}"; do
    if have_cmd "$pm"; then
      printf '%s\n' "$pm"
      return 0
    fi
  done
  return 1
}

# Gentoo: сборка из исходников или бинарные пакеты. Спрашивается один раз
# за сеанс, ответ переиспользуется.
ZDY_GENTOO_MODE="${ZDY_GENTOO_MODE:-}"

gentoo_choose_mode() {
  [ -n "$ZDY_GENTOO_MODE" ] && return 0

  if [ "${ZDY_ASSUME_YES:-0}" = "1" ]; then
    ZDY_GENTOO_MODE="source"
    return 0
  fi

  local choice
  while true; do
    msg "Обнаружен Portage. Как ставить пакеты?"
    plain "  1. Сборка из исходников (обычный путь Gentoo)"
    plain "  2. Бинарные пакеты через --getbinpkg"
    ask_line "Введите номер [1/2]: " choice || return 1
    case "$choice" in
      1) ZDY_GENTOO_MODE="source"; return 0 ;;
      2) ZDY_GENTOO_MODE="binary"; return 0 ;;
      *) warn "Введите 1 или 2." ;;
    esac
  done
}

emerge_install() {
  gentoo_choose_mode || return 1
  if [ "$ZDY_GENTOO_MODE" = "binary" ]; then
    run_elevated emerge --ask=n --getbinpkg --noreplace --oneshot "$@"
  else
    run_elevated emerge --ask=n --noreplace --oneshot "$@"
  fi
}

# install_packages <менеджер> <пакеты...>
# Имена пакетов передаются как есть; для Gentoo вызывающий передаёт
# категорию (net-misc/wget).
install_packages() {
  local pm="$1"
  shift

  case "$pm" in
    epm) run_elevated epm -i "$@" ;;
    apt) run_elevated apt update && run_elevated apt install -y --no-install-recommends "$@" ;;
    apt-get) run_elevated apt-get update && run_elevated apt-get install -y --no-install-recommends "$@" ;;
    nala) run_elevated nala update && run_elevated nala install -y "$@" ;;
    yum) run_elevated yum install -y "$@" ;;
    dnf) run_elevated dnf install -y "$@" ;;
    pacman) run_elevated pacman -Sy --noconfirm "$@" ;;
    zypper) run_elevated zypper install -y "$@" ;;
    xbps-install) run_elevated xbps-install -Sy "$@" ;;
    slapt-get) run_elevated slapt-get -i --no-prompt "$@" ;;
    apk) run_elevated apk add "$@" ;;
    emerge) emerge_install "$@" ;;
    eopkg) run_elevated eopkg update-repo && run_elevated eopkg install "$@" ;;
    rpm-ostree)
      warn "rpm-ostree требует перезагрузку после установки пакетов."
      run_elevated rpm-ostree install "$@"
      msg "Перезагрузите систему и запустите установку снова."
      return 2
      ;;
    *)
      err "Неизвестный пакетный менеджер: $pm"
      return 1
      ;;
  esac
}

# Имя пакета отличается между менеджерами - здесь только те случаи,
# где расхождение реальное.
package_name_for() {
  local pm="$1" generic="$2"

  case "$generic:$pm" in
    wget:emerge) printf 'net-misc/wget\n' ;;
    git:emerge) printf 'dev-vcs/git\n' ;;
    iptables:emerge) printf 'net-firewall/iptables\n' ;;
    ipset:emerge) printf 'net-firewall/ipset\n' ;;
    *) printf '%s\n' "$generic" ;;
  esac
}

# Ставит только то, чего нет.
ensure_commands() {
  local pm missing=() cmd status

  for cmd in "$@"; do
    have_cmd "$cmd" || missing+=("$cmd")
  done

  [ "${#missing[@]}" -eq 0 ] && return 0

  pm=$(detect_package_manager) || {
    err "Не удалось определить пакетный менеджер."
    err "Установите вручную: ${missing[*]}"
    return 1
  }

  msg "Обнаружен $pm, устанавливаю: ${missing[*]}"

  local packages=()
  for cmd in "${missing[@]}"; do
    packages+=("$(package_name_for "$pm" "$cmd")")
  done

  install_packages "$pm" "${packages[@]}"
  status=$?
  [ "$status" -eq 2 ] && exit 0
  return "$status"
}

# --------------------------------------------------- особенности дистрибутивов

prepare_chimera() {
  os_is chimera || return 0
  have_cmd apk || return 0
  have_cmd ipset && return 0

  msg "Chimera Linux: подключаю user-репозиторий ради ipset..."
  apk info -e chimera-repo-user >/dev/null 2>&1 || run_elevated apk add chimera-repo-user
  run_elevated apk update
}

prepare_gentoo() {
  os_is gentoo || return 0
  have_cmd emerge || return 0

  local packages=()
  have_cmd iptables || packages+=("net-firewall/iptables")
  have_cmd ipset || packages+=("net-firewall/ipset")
  [ "${#packages[@]}" -gt 0 ] || return 0

  msg "Gentoo: для работы zapret нужны iptables и ipset."
  emerge_install "${packages[@]}"
}
