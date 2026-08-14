# shellcheck shell=bash
#
# Все пути проекта в одном месте.
#
# Корень проекта определяется от расположения самого этого файла, а не от
# XDG: иначе сломалась бы работа из git-клона и из временной распаковки,
# которую делает бутстрап. XDG используется только для того, чтобы понять,
# куда проект должен быть установлен, и где лежат состояние и кеш.

[ -n "${ZDY_PATHS_SOURCED:-}" ] && return 0
ZDY_PATHS_SOURCED=1

# lib/paths.sh -> lib -> корень проекта
ZDY_LIB="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ZDY_ROOT="$(cd -- "$ZDY_LIB/.." && pwd -P)"
ZDY_BIN="$ZDY_ROOT/bin"

zdy_xdg_dir() {
  local var="$1" fallback="$2" value="${!1:-}"
  # Спека требует игнорировать значение, если путь не абсолютный.
  case "$value" in
    /*) printf '%s\n' "$value" ;;
    *) printf '%s\n' "$fallback" ;;
  esac
}

ZDY_APP_NAME="zapret-discord-youtube"

ZDY_DATA_HOME="$(zdy_xdg_dir XDG_DATA_HOME "$HOME/.local/share")"
ZDY_STATE_HOME="$(zdy_xdg_dir XDG_STATE_HOME "$HOME/.local/state")"
ZDY_CACHE_HOME="$(zdy_xdg_dir XDG_CACHE_HOME "$HOME/.cache")"

# Единый оверрайд для тех, кто хочет держать проект в другом месте,
# и для упаковщиков.
ZDY_INSTALL_DIR="${ZAPRET_DY_HOME:-$ZDY_DATA_HOME/$ZDY_APP_NAME}"
ZDY_STATE_DIR="$ZDY_STATE_HOME/$ZDY_APP_NAME"
ZDY_CACHE_DIR="$ZDY_CACHE_HOME/$ZDY_APP_NAME"
ZDY_USER_BIN="$HOME/.local/bin"

ZDY_BACKUP_DIR="$ZDY_STATE_DIR/backups"
ZDY_LOG_DIR="$ZDY_STATE_DIR/log"
ZDY_SCHEMA_FILE="$ZDY_STATE_DIR/schema"
ZDY_COMMIT_FILE="$ZDY_STATE_DIR/current-commit"

# Куда старые версии клали всё сразу: и код, и бэкапы, и логи.
ZDY_LEGACY_DIR="$HOME/zapret-configs"

# Текущая версия схемы состояния. Поднимается при несовместимых изменениях
# раскладки файлов; миграции живут в bin/zapret-setup.
ZDY_SCHEMA_VERSION=2

# Режим запуска:
#   installed - из $ZDY_INSTALL_DIR
#   legacy    - из старого ~/zapret-configs (нужен перенос)
#   dev       - из git-клона разработчика
#   temp      - из временной распаковки бутстрапом
zdy_mode() {
  case "$ZDY_ROOT" in
    "$ZDY_INSTALL_DIR") printf 'installed\n'; return ;;
    "$ZDY_LEGACY_DIR") printf 'legacy\n'; return ;;
  esac
  if [ -d "$ZDY_ROOT/.git" ]; then
    printf 'dev\n'
  else
    printf 'temp\n'
  fi
}

# ----------------------------------------------- содержимое проекта ---------

ZDY_STRATEGIES_SRC="$ZDY_ROOT/strategies"
ZDY_FIXES_SRC="$ZDY_ROOT/fixes"
ZDY_CONFIG_SRC="$ZDY_ROOT/config"
ZDY_HOSTLISTS_SRC="$ZDY_ROOT/hostlists"
ZDY_MODULE_DIR="$ZDY_ROOT/module"
ZDY_UTILS_DIR="$ZDY_ROOT/utils"
ZDY_TEST_SCRIPT="$ZDY_UTILS_DIR/test-zapret.lua"

# ------------------------------------------------- установленный zapret -----
#
# ZAPRET_DIR переопределяется в тестах и при нестандартной установке.

ZAPRET_DIR="${ZAPRET_DIR:-/opt/zapret}"
ZAPRET_CONFIG="$ZAPRET_DIR/config"
ZAPRET_HOSTLISTS="$ZAPRET_DIR/hostlists"
ZAPRET_FAKE_DIR="$ZAPRET_DIR/files/fake"

ZAPRET_STRATEGIES="$ZAPRET_DIR/strategies"
ZAPRET_FIXES="$ZAPRET_DIR/fixes"

# Состояния загрузчика: имя выбранной стратегии и список включённых фиксов.
ZDY_STRATEGY_STATE="$ZAPRET_DIR/zapret.strategy"
ZDY_FIXES_STATE="$ZAPRET_DIR/zapret.fixes"

# Контрольная сумма config на момент установки. По ней видно, правил ли
# пользователь файл руками.
ZDY_CONFIG_BASELINE="$ZDY_STATE_DIR/config.sha256"

ZDY_IPSET_FILE="$ZAPRET_HOSTLISTS/ipset-all.txt"
ZDY_IPSET_BACKUP="$ZDY_IPSET_FILE.backup"
ZDY_GAME_FILE="$ZAPRET_HOSTLISTS/.game_filter.enabled"
ZDY_LIST_GENERAL="$ZAPRET_HOSTLISTS/list-general-user.txt"
ZDY_LIST_EXCLUDE="$ZAPRET_HOSTLISTS/list-exclude-user.txt"

ZDY_HOSTS_FILE="${ZDY_HOSTS_FILE:-/etc/hosts}"

# Заглушка для режима ipset "none": документационная сеть из RFC 5737.
ZDY_IPSET_STUB_IP="203.0.113.113/32"

ZDY_SERVICE_NAME="zapret"

# ---------------------------------------------------- внешние источники -----

# Все внешние адреса переопределяются переменными окружения - это нужно,
# чтобы гонять установку и обновление против форка, а не против оригинала.
# Достаточно задать ZDY_REPO_SLUG и ZDY_BRANCH, остальное соберётся само.
ZDY_REPO_SLUG="${ZDY_REPO_SLUG:-kartavkun/zapret-discord-youtube}"
ZDY_BRANCH="${ZDY_BRANCH:-main}"
ZDY_ARCHIVE_URL="${ZDY_ARCHIVE_URL:-https://codeload.github.com/$ZDY_REPO_SLUG/tar.gz/refs/heads/$ZDY_BRANCH}"
ZDY_API_BRANCH_URL="${ZDY_API_BRANCH_URL:-https://api.github.com/repos/$ZDY_REPO_SLUG/commits/$ZDY_BRANCH}"

# Источник списков и .bin-файлов. Меняется отдельно: форк проекта не означает
# форк Flowseal.
ZDY_FLOWSEAL_SLUG="${ZDY_FLOWSEAL_SLUG:-Flowseal/zapret-discord-youtube}"
ZDY_FLOWSEAL_IPSET_URL="${ZDY_FLOWSEAL_IPSET_URL:-https://raw.githubusercontent.com/$ZDY_FLOWSEAL_SLUG/main/lists/ipset-all.txt.backup}"
ZDY_FLOWSEAL_HOSTS_URL="${ZDY_FLOWSEAL_HOSTS_URL:-https://raw.githubusercontent.com/$ZDY_FLOWSEAL_SLUG/refs/heads/main/.service/hosts}"
