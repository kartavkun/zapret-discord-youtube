# shellcheck shell=bash
#
# Слой совместимости с урезанными userland'ами: busybox (Alpine) и
# chimerautils/BSD (Chimera Linux). Правило для всего остального кода:
# если утилита или её флаг есть не везде - обёртка живёт здесь.
#
# Запрещено во всём остальном коде (проверяется tools/lint-portability.sh):
#   ps -p / ps -o     нет в busybox ps        -> init_system_name, proc_comm
#   sed -i            требует суффикс в BSD   -> запись через временный файл
#   readlink -f       нет в старых BSD        -> abs_path
#   diff -qr -x       -x есть не везде        -> tree_manifest
#   find ... -exec +  нет в старых busybox    -> -exec ... \;
#   pgrep -f          есть не во всех сборках -> proc_pgrep
#   find -printf      расширение GNU               -> path_owner
#   date -d "-N days" относительные даты - GNU     -> days_since_epoch

[ -n "${ZDY_COMPAT_SOURCED:-}" ] && return 0
ZDY_COMPAT_SOURCED=1

# Переопределяется в тестах, чтобы подсунуть поддельный /proc.
ZDY_PROC="${ZDY_PROC:-/proc}"

# ------------------------------------------------------------- процессы -----

# Имя процесса по pid. Читает procfs напрямую: busybox ps не понимает -p/-o,
# из-за чего старый install.sh на Alpine получал пустую строку и молча
# пропускал настройку init-системы.
proc_comm() {
  local pid="$1"
  [ -r "$ZDY_PROC/$pid/comm" ] || return 1
  local comm
  IFS= read -r comm <"$ZDY_PROC/$pid/comm" || return 1
  printf '%s\n' "$comm"
}

init_system_name() { proc_comm 1; }

# Не используется прямо сейчас; оставлено как часть слоя procfs
# рядом с proc_comm и proc_pgrep.
# shellcheck disable=SC2329
proc_is_running() { [ -d "$ZDY_PROC/$1" ]; }

# Замена pgrep -f: ищет подстроку в cmdline всех процессов.
proc_pgrep() {
  local pattern="$1" dir pid cmdline
  for dir in "$ZDY_PROC"/[0-9]*; do
    [ -r "$dir/cmdline" ] || continue
    pid="${dir##*/}"
    cmdline=$(tr '\0' ' ' <"$dir/cmdline" 2>/dev/null) || continue
    case "$cmdline" in
      *"$pattern"*)
        printf '%s\n' "$pid"
        ;;
    esac
  done
}

# ------------------------------------------------------------------ пути ----

# Замена readlink -f: работает и там, где readlink без -f.
abs_path() {
  local path="$1" dir base
  if [ -d "$path" ]; then
    (cd -- "$path" 2>/dev/null && pwd -P)
    return
  fi
  dir="${path%/*}"
  base="${path##*/}"
  [ "$dir" = "$path" ] && dir="."
  dir=$(cd -- "$dir" 2>/dev/null && pwd -P) || return 1
  printf '%s/%s\n' "${dir%/}" "$base"
}

# --------------------------------------------------------------- хеши -------

ZDY_SHA256_CMD=""

sha256_cmd() {
  if [ -n "$ZDY_SHA256_CMD" ]; then
    printf '%s\n' "$ZDY_SHA256_CMD"
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    ZDY_SHA256_CMD="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    ZDY_SHA256_CMD="shasum -a 256"
  elif command -v openssl >/dev/null 2>&1; then
    ZDY_SHA256_CMD="openssl-dgst"
  else
    return 1
  fi
  printf '%s\n' "$ZDY_SHA256_CMD"
}

# Печатает только хеш, без имени файла.
sha256_file() {
  local file="$1" cmd out
  cmd=$(sha256_cmd) || return 1
  case "$cmd" in
    openssl-dgst) out=$(openssl dgst -sha256 "$file") || return 1
                  printf '%s\n' "${out##* }" ;;
    sha256sum)    out=$(sha256sum "$file") || return 1
                  printf '%s\n' "${out%% *}" ;;
    *)            out=$(shasum -a 256 "$file") || return 1
                  printf '%s\n' "${out%% *}" ;;
  esac
}

verify_sha256() {
  local file="$1" expected="$2" actual
  actual=$(sha256_file "$file") || return 2
  [ "$actual" = "$expected" ]
}

# ------------------------------------------------------------- загрузка -----

# Скачивание с фоллбэком: curl -> wget. Раньше setup.sh требовал обе утилиты
# сразу, хотя каждой по отдельности достаточно.
fetch_url() {
  local url="$1" dest="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 -o "$dest" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$dest" "$url"
  else
    return 127
  fi
}

fetch_stdout() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --retry 2 "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O - "$url"
  else
    return 127
  fi
}

# --------------------------------------------------------------- деревья ----

# Манифест дерева: "sha256__относительный/путь", отсортированный.
# Замена diff -qr -x, у которого -x есть не во всех сборках busybox.
tree_manifest() {
  local dir="$1"
  shift
  local excludes=("$@") file rel skip pattern

  while IFS= read -r file; do
    rel="${file#"$dir"/}"
    skip=0
    for pattern in "${excludes[@]:-}"; do
      [ -n "$pattern" ] || continue
      case "$rel" in
        "$pattern" | "$pattern"/*) skip=1; break ;;
      esac
    done
    [ "$skip" = "1" ] && continue
    printf '%s  %s\n' "$(sha256_file "$file")" "$rel"
  done < <(find "$dir" -type f -print | LC_ALL=C sort)
}

trees_match() {
  local a="$1" b="$2"
  shift 2
  [ -d "$a" ] && [ -d "$b" ] || return 1
  [ "$(tree_manifest "$a" "$@")" = "$(tree_manifest "$b" "$@")" ]
}

# --------------------------------------------------------- os-release -------

ZDY_OS_RELEASE="${ZDY_OS_RELEASE:-/etc/os-release}"

os_release_field() {
  local field="$1" line value
  [ -r "$ZDY_OS_RELEASE" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      "$field"=*)
        value="${line#*=}"
        value="${value%\"}"
        value="${value#\"}"
        printf '%s\n' "$value"
        return 0
        ;;
    esac
  done <"$ZDY_OS_RELEASE"
  return 1
}

os_release_id() { os_release_field ID; }

# Совпадение по ID или ID_LIKE, без регистра.
os_is() {
  local want="${1,,}" id like
  id=$(os_release_field ID 2>/dev/null) || id=""
  like=$(os_release_field ID_LIKE 2>/dev/null) || like=""
  [ "${id,,}" = "$want" ] && return 0
  case " ${like,,} " in
    *" $want "*) return 0 ;;
  esac
  return 1
}

# Свободный поиск подстроки по всему os-release (для Secureblue, Bazzite и
# прочих, которые не всегда кладут себя в ID).
os_release_mentions() {
  [ -r "$ZDY_OS_RELEASE" ] || return 1
  local needle="${1,,}" content
  content=$(<"$ZDY_OS_RELEASE") || return 1
  content="${content,,}"
  case "$content" in
    *"$needle"*) return 0 ;;
  esac
  return 1
}

# Владелец файла. find -printf есть только в GNU find, поэтому stat с двумя
# синтаксисами: GNU/busybox и BSD.
path_owner() {
  local path="$1" owner
  [ -e "$path" ] || return 1
  owner=$(stat -c '%U' "$path" 2>/dev/null) && [ -n "$owner" ] && {
    printf '%s\n' "$owner"
    return 0
  }
  owner=$(stat -f '%Su' "$path" 2>/dev/null) && [ -n "$owner" ] && {
    printf '%s\n' "$owner"
    return 0
  }
  return 1
}

# Время изменения файла в секундах эпохи.
#
# date -r в GNU и busybox принимает файл, а в BSD - число секунд, поэтому
# сначала пробуем stat в двух его синтаксисах.
path_mtime() {
  local path="$1" value
  [ -e "$path" ] || return 1

  value=$(stat -c '%Y' "$path" 2>/dev/null) && [ -n "$value" ] && {
    printf '%s\n' "$value"
    return 0
  }
  value=$(stat -f '%m' "$path" 2>/dev/null) && [ -n "$value" ] && {
    printf '%s\n' "$value"
    return 0
  }
  value=$(date -r "$path" '+%s' 2>/dev/null) && [ -n "$value" ] && {
    printf '%s\n' "$value"
    return 0
  }
  return 1
}

# Номер дня по григорианскому календарю (Julian Day Number).
#
# Нужен, потому что арифметика дат в date - расширение GNU: busybox не знает
# ни date -d "-7 days", ни date -d @epoch. Формула целочисленная, работает
# в любом shell.
date_to_days() {
  local y="$1" m="$2" d="$3" a

  case "$y$m$d" in
    "" | *[!0-9]*) return 1 ;;
  esac

  # Ведущие нули означали бы восьмеричную систему в $(( )).
  y=$((10#$y))
  m=$((10#$m))
  d=$((10#$d))

  a=$(((m - 14) / 12))
  printf '%s\n' "$(((1461 * (y + 4800 + a)) / 4 + (367 * (m - 2 - 12 * a)) / 12 - (3 * ((y + 4900 + a) / 100)) / 4 + d - 32075))"
}

# Номер сегодняшнего дня.
today_days() {
  local y m d
  read -r y m d <<EOF
$(date '+%Y %m %d')
EOF
  date_to_days "$y" "$m" "$d"
}

# Номер дня для строки вида YYYY-MM-DD (лишнее в конце игнорируется).
date_string_to_days() {
  local value="${1:-}" y m rest d
  y="${value%%-*}"
  rest="${value#*-}"
  m="${rest%%-*}"
  d="${rest#*-}"
  d="${d%%[!0-9]*}"
  [ -n "$y" ] && [ -n "$m" ] && [ -n "$d" ] || return 1
  date_to_days "$y" "$m" "$d"
}
