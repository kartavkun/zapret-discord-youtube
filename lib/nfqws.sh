# shellcheck shell=bash
#
# Модуль подключается из bin/*, а не сам по себе: общие функции и пути
# приходят из lib/common.sh, lib/compat.sh и lib/paths.sh, подключённых
# вызывающим скриптом раньше. Отсюда директивы source ниже - без них
# shellcheck считает эти имена неопределёнными.
# shellcheck source=common.sh
#
# Разбор фрагментов стратегий и фиксов.
#
# Изначально здесь жила машинерия для "склейки" стратегий: сигнатуры правил,
# слоты, пересборка конфига из кусков. После перехода на загрузчик она стала
# не нужна - правила больше не вырезают из одного файла и не вставляют в
# другой, а добавляют отдельным фрагментом из fixes/. Осталось то, что
# действительно используется: вытащить правила из фрагмента, чтобы проверить
# ссылки на файлы, и убедиться, что фрагмент вообще разбирается.

[ -n "${ZDY_NFQWS_SOURCED:-}" ] && return 0
ZDY_NFQWS_SOURCED=1

# Открывающие строки блоков, которые нас интересуют.
ZDY_NFQWS_OPENERS=(
  'NFQWS_STRATEGY_OPT="'
  'FIX_NFQWS_OPT="'
  'NFQWS_OPT="'
)

# Печатает правила блока по одному на строку.
nfqws_extract_rules() {
  local file="$1" line inside=0 opener
  [ -r "$file" ] || return 1

  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$inside" = "1" ]; then
      if [ "$line" = '"' ]; then
        inside=0
        continue
      fi
      [ -n "${line//[[:space:]]/}" ] && printf '%s\n' "$line"
      continue
    fi
    for opener in "${ZDY_NFQWS_OPENERS[@]}"; do
      if [ "$line" = "$opener" ]; then
        inside=1
        break
      fi
    done
  done <"$file"
}

# Печатает пути, на которые ссылается фрагмент: hostlists, ipset, .bin.
#
# Единственная реализация на весь проект: раньше этот же case по --hostlist=*
# был скопирован ещё в bin/zapret-config и lib/diag.sh.
nfqws_referenced_paths() {
  local file="$1" rule word path

  while IFS= read -r rule; do
    for word in $rule; do
      case "$word" in
        --hostlist=* | --hostlist-exclude=* | --ipset=* | --ipset-exclude=* | *-pattern=* | *fake-*=*)
          path="${word#*=}"
          path="${path//\"/}"
          case "$path" in
            /*) printf '%s\n' "$path" ;;
          esac
          ;;
      esac
    done
  done < <(nfqws_extract_rules "$file")
}

# Фрагмент пригоден, если из него извлекается хотя бы одно правило.
nfqws_validate() {
  local count
  count=$(nfqws_extract_rules "$1" | grep -c .) || return 1
  [ "$count" -gt 0 ]
}

# Печатает отсутствующие пути; код возврата 0, если всё на месте.
nfqws_missing_paths() {
  local path missing=0
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if [ ! -e "$path" ]; then
      printf '%s\n' "$path"
      missing=1
    fi
  done < <(nfqws_referenced_paths "$1" | LC_ALL=C sort -u)
  [ "$missing" -eq 0 ]
}

# То же самое, но с предупреждениями в stderr - для интерактивных сценариев.
#
# Отсутствующий hostlist или .bin zapret ошибкой не считает: он просто молча
# не отфильтрует часть трафика. Это ровно тот класс симптомов, который потом
# ищут неделями.
nfqws_warn_missing_paths() {
  local out path
  out=$(nfqws_missing_paths "$1") && return 0
  while IFS= read -r path; do
    [ -n "$path" ] && warn "Файл отсутствует: $path"
  done <<<"$out"
  return 1
}
