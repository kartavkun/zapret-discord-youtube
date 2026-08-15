#!/usr/bin/env bash
#
# Проверка на конструкции, которых нет в busybox (Alpine) и в BSD-userland
# (Chimera Linux). shellcheck такое не ловит: синтаксис верный, отсутствует
# сам флаг у утилиты в конкретном дистрибутиве.
#
# Всё, что перечислено ниже, должно вызываться через обёртки из lib/compat.sh.
# Сам compat.sh из проверки исключён - он и есть место, где это можно.

set -uo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$REPO_DIR" || exit 1

# шаблон<TAB>объяснение<TAB>чем заменить
RULES=$(
  cat <<'EOF'
ps -p	busybox ps does not support -p/-o	proc_comm / init_system_name from lib/compat.sh
ps -o	busybox ps does not support -p/-o	proc_comm / init_system_name from lib/compat.sh
sed -i	BSD sed requires a suffix for -i	write to a temp file and mv
readlink -f	-f is missing on older BSD	abs_path from lib/compat.sh
diff -qr	-x is missing in some busybox builds	tree_manifest / trees_match from lib/compat.sh
pgrep -f	pgrep is missing in some busybox builds	proc_pgrep from lib/compat.sh
-exec .*\{\}[[:space:]]*\+	-exec ... + is missing in older busybox find	-exec ... \;
EOF
)

TARGETS=()
while IFS= read -r file; do
  TARGETS+=("$file")
done < <(
  {
    printf '%s\n' setup.sh
    find bin lib tools tests -type f -print 2>/dev/null
  } | LC_ALL=C sort -u
)

failed=0

for target in "${TARGETS[@]}"; do
  [ -f "$target" ] || continue
  case "$target" in
    lib/compat.sh | tools/lint-portability.sh) continue ;;
  esac

  while IFS=$'\t' read -r pattern reason replacement; do
    [ -n "$pattern" ] || continue
    while IFS= read -r hit; do
      # Строки-комментарии не считаем: в них конструкции упоминаются
      # именно как запрещённые.
      case "${hit#*:}" in
        [[:space:]]*'#'* | '#'*) continue ;;
      esac
      # Осознанное исключение: строка сама проверяет отсутствие конструкции.
      case "$hit" in
        *"lint-ok:"*) continue ;;
      esac
      printf '[ - ] %s\n' "$target:$hit"
      printf '      запрещено: %s - %s\n' "$pattern" "$reason"
      printf '      замена:    %s\n\n' "$replacement"
      failed=1
    done < <(grep -nE -- "$pattern" "$target" 2>/dev/null)
  done <<<"$RULES"
done

if [ "$failed" -eq 0 ]; then
  printf '[ + ] проверка переносимости пройдена (файлов: %d).\n' "${#TARGETS[@]}"
else
  printf '[ - ] проверка переносимости провалена.\n' >&2
fi

exit "$failed"
