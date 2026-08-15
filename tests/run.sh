#!/usr/bin/env bash
#
# Тесты библиотечного слоя. Запуск: tests/run.sh
#
# Реальная система не трогается: /opt/zapret, /etc/hosts, /proc и внешние
# команды подменяются временными каталогами и заглушками в PATH.

set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$(cd -- "$TESTS_DIR/.." && pwd -P)"

# shellcheck source=harness.sh
. "$TESTS_DIR/harness.sh"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/zdy-tests.XXXXXX")"
trap 'rm -rf -- "$SANDBOX"' EXIT

export HOME="$SANDBOX/home"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export ZAPRET_DIR="$SANDBOX/opt/zapret"
export ZDY_HOSTS_FILE="$SANDBOX/etc/hosts"
export ZDY_PROC="$SANDBOX/proc"
export ZDY_OS_RELEASE="$SANDBOX/etc/os-release"
export ZDY_ASSUME_YES=1
export ZDY_SYSTEMD_UNIT_DIR="$SANDBOX/etc/systemd/system"
export ZDY_CRON_DIR="$SANDBOX/etc/cron.d"
export ZDY_HELPER_DIR="$SANDBOX/usr/local/lib/zapret"
export ZDY_AUTORESTART_LOG="$SANDBOX/var/log/zapret-autorestart.log"
export NO_COLOR=1

mkdir -p "$HOME" "$SANDBOX/etc" "$ZAPRET_DIR/hostlists" "$SANDBOX/proc/1" "$SANDBOX/bin" \
  "$SANDBOX/etc/systemd/system" "$SANDBOX/etc/cron.d" "$SANDBOX/var/log"
export PATH="$SANDBOX/bin:$PATH"

# Заглушка sudo: пишет факт вызова в лог и выполняет команду как есть.
cat >"$SANDBOX/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'SUDO-CALLED %s\n' "$*" >>"$SUDO_LOG"
exec "$@"
EOF
chmod +x "$SANDBOX/bin/sudo"
export SUDO_LOG="$SANDBOX/sudo.log"
: >"$SUDO_LOG"

# shellcheck source=../lib/paths.sh
. "$REPO_DIR/lib/paths.sh"
# shellcheck source=../lib/common.sh
. "$REPO_DIR/lib/common.sh"
# shellcheck source=../lib/compat.sh
. "$REPO_DIR/lib/compat.sh"
# shellcheck source=../lib/nfqws.sh
. "$REPO_DIR/lib/nfqws.sh"
# shellcheck source=../lib/service.sh
. "$REPO_DIR/lib/service.sh"
# shellcheck source=../lib/lists.sh
. "$REPO_DIR/lib/lists.sh"
# shellcheck source=../lib/update.sh
. "$REPO_DIR/lib/update.sh"
# shellcheck source=../lib/diag.sh
. "$REPO_DIR/lib/diag.sh"
# shellcheck source=../lib/lock.sh
. "$REPO_DIR/lib/lock.sh"
# shellcheck source=../lib/strategy.sh
. "$REPO_DIR/lib/strategy.sh"
# shellcheck source=../lib/autorestart.sh
. "$REPO_DIR/lib/autorestart.sh"
# shellcheck source=../lib/incident.sh
. "$REPO_DIR/lib/incident.sh"

# ============================================================== compat ======

t_section "compat: procfs вместо ps"

printf 'systemd\n' >"$SANDBOX/proc/1/comm"
assert_eq "systemd" "$(init_system_name)" "init_system_name читает /proc/1/comm"

printf 'dinit\n' >"$SANDBOX/proc/1/comm"
assert_eq "dinit" "$(init_system_name)" "init_system_name видит смену init-системы"

rm -f "$SANDBOX/proc/1/comm"
assert_fails "init_system_name честно падает без procfs" init_system_name
printf 'systemd\n' >"$SANDBOX/proc/1/comm"

t_section "compat: os-release"

cat >"$ZDY_OS_RELEASE" <<'EOF'
NAME="Alpine Linux"
ID=alpine
VERSION_ID=3.20.0
EOF
assert_eq "alpine" "$(os_release_id)" "os_release_id снимает кавычки и возвращает ID"
assert_ok "os_is находит точное совпадение ID" os_is alpine
assert_fails "os_is не срабатывает на чужом ID" os_is fedora

cat >"$ZDY_OS_RELEASE" <<'EOF'
NAME="Bazzite"
ID=bazzite
ID_LIKE="fedora rhel"
VARIANT_ID=silverblue
EOF
assert_ok "os_is учитывает ID_LIKE" os_is fedora
assert_ok "os_release_mentions ищет по всему файлу" os_release_mentions silverblue

t_section "compat: хеши и деревья"

printf 'hello\n' >"$SANDBOX/a.txt"
assert_eq "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03" \
  "$(sha256_file "$SANDBOX/a.txt")" "sha256_file prints the hash only"

mkdir -p "$SANDBOX/tree-a/sub" "$SANDBOX/tree-b/sub" "$SANDBOX/tree-a/.git"
printf 'x\n' >"$SANDBOX/tree-a/sub/f"
printf 'x\n' >"$SANDBOX/tree-b/sub/f"
printf 'junk\n' >"$SANDBOX/tree-a/.git/HEAD"
assert_ok "trees_match игнорирует исключённый .git" trees_match "$SANDBOX/tree-a" "$SANDBOX/tree-b" ".git"
printf 'y\n' >"$SANDBOX/tree-b/sub/f"
assert_fails "trees_match видит различие в содержимом" trees_match "$SANDBOX/tree-a" "$SANDBOX/tree-b" ".git"

# ============================================================== common ======

t_section "common: повышение привилегий"

# Регрессия на исходный баг: exit 1 внутри $(...) не останавливал скрипт,
# и в ELEVATE_CMD оказывался текст ошибки.
(
  # zdy_is_root переопределяется, чтобы тест работал и от root (в CI-контейнере
  # это обычный случай).
  # shellcheck disable=SC2329  # вызывается косвенно из detect_elevation
  zdy_is_root() { return 1; }
  ZDY_ELEVATE_DETECTED=0
  ZDY_ELEVATE=""
  ZDY_ELEVATE_PREFERENCE="no-such-command"
  if detect_elevation; then exit 1; fi
  [ -z "$ZDY_ELEVATE" ] || exit 1
)
assert_eq "0" "$?" "detect_elevation возвращает ошибку и не пишет мусор в переменную"

(
  # shellcheck disable=SC2329  # вызывается косвенно из detect_elevation
  zdy_is_root() { return 1; }
  ZDY_ELEVATE_DETECTED=0
  ZDY_ELEVATE=""
  ZDY_ELEVATE_PREFERENCE="no-such-command doas sudo"
  detect_elevation || exit 1
  [ "$ZDY_ELEVATE" = "sudo" ] || exit 1
)
assert_eq "0" "$?" "detect_elevation выбирает первую доступную утилиту из списка"

t_section "common: запись по факту писабельности"

: >"$SUDO_LOG"

writable_target="$SANDBOX/writable.txt"
printf 'data\n' | write_out "$writable_target"
assert_eq "data" "$(cat "$writable_target")" "write_out пишет напрямую в писабельный путь"
assert_eq "" "$(cat "$SUDO_LOG")" "write_out не зовёт sudo там, где он не нужен"

if [ "$(id -u)" -ne 0 ]; then
  mkdir -p "$SANDBOX/locked"
  chmod 500 "$SANDBOX/locked"
  ZDY_ELEVATE_DETECTED=1 ZDY_ELEVATE="sudo" \
    bash -c ". '$REPO_DIR/lib/paths.sh'; . '$REPO_DIR/lib/common.sh'; \
             ZDY_ELEVATE_DETECTED=1; ZDY_ELEVATE=sudo; \
             printf 'x\n' | write_out '$SANDBOX/locked/f'" >/dev/null 2>&1
  assert_contains "$(cat "$SUDO_LOG")" "SUDO-CALLED" "write_out поднимает права для защищённого пути"
  chmod 700 "$SANDBOX/locked"
else
  t_begin "write_out под root - проверка пропущена"
  t_pass
fi

# ============================================================== nfqws ======

t_section "фрагменты: разбор стратегий и фиксов"

assert_eq "9" "$(nfqws_extract_rules "$REPO_DIR/strategies/general" | grep -c .)" \
  "в general девять правил"
assert_eq "1" "$(nfqws_extract_rules "$REPO_DIR/fixes/hypixel" | grep -c .)" \
  "в фиксе hypixel одно правило"
assert_contains "$(nfqws_referenced_paths "$REPO_DIR/strategies/general")" \
  "hostlists/list-general.txt" "среди ссылок фрагмента есть hostlist"
assert_contains "$(nfqws_referenced_paths "$REPO_DIR/strategies/general")" \
  "files/fake/" "среди ссылок фрагмента есть бинарник фейка"

bad_syntax=0
bad_parse=0
for cfg in "$REPO_DIR"/strategies/*; do
  [ -f "$cfg" ] || continue
  case "${cfg##*/}" in
    legacy-names.map) continue ;;
  esac
  sh -n "$cfg" 2>/dev/null || bad_syntax=$((bad_syntax + 1))
  nfqws_validate "$cfg" 2>/dev/null || bad_parse=$((bad_parse + 1))
done
assert_eq "0" "$bad_syntax" "все стратегии проходят sh -n"
assert_eq "0" "$bad_parse" "во всех стратегиях разбирается блок правил"

t_section "загрузчик: выбор стратегии"

export ZAPRET_STRATEGIES="$ZAPRET_DIR/strategies"
export ZAPRET_FIXES="$ZAPRET_DIR/fixes"
mkdir -p "$ZAPRET_STRATEGIES" "$ZAPRET_FIXES"
cp "$REPO_DIR"/strategies/general "$REPO_DIR"/strategies/general-alt "$ZAPRET_STRATEGIES/"
cp "$REPO_DIR"/fixes/hypixel "$ZAPRET_FIXES/"

assert_eq "general" "$(strategy_current)" "по умолчанию выбрана general"
assert_ok "general проходит валидацию" strategy_is_valid general
assert_fails "несуществующая стратегия отклоняется" strategy_is_valid does-not-exist
assert_fails "имя с путём отклоняется" strategy_is_valid "../etc/passwd"

strategy_apply general-alt >/dev/null
assert_eq "general-alt" "$(strategy_current)" "стратегия переключилась"
assert_fails "неизвестная стратегия не применяется" strategy_apply nonexistent
assert_eq "general-alt" "$(strategy_current)" "после отказа прежняя стратегия цела"

t_section "загрузчик: таблица старых имён"

assert_eq "general-alt-11" "$(strategy_resolve_name 'general(ALT11)' 2>/dev/null)" \
  "старое имя со скобками резолвится"
assert_eq "general-simple-fake" "$(strategy_resolve_name 'general (SIMPLE FAKE)' 2>/dev/null)" \
  "старое имя с пробелами резолвится"
# Промежуточные имена (general-alt2) существовали только в черновиках и
# никогда не выпускались - в таблице синонимов им не место.
assert_eq "general-alt2" "$(strategy_resolve_name 'general-alt2' 2>/dev/null)" \
  "невыпускавшееся имя не резолвится, возвращается как есть"
assert_eq "general" "$(strategy_resolve_name general 2>/dev/null)" \
  "актуальное имя не меняется"

t_section "загрузчик: фиксы"

assert_eq "нет" "$(fix_enabled_text)" "по умолчанию фиксов нет"
assert_fails "фикс выключен" fix_is_enabled hypixel
fix_enable hypixel >/dev/null
assert_ok "фикс включён" fix_is_enabled hypixel
assert_eq "hypixel" "$(fix_enabled_text)" "включённый фикс виден в шапке"
fix_enable hypixel >/dev/null
assert_eq "1" "$(fix_enabled_list | wc -l)" "повторное включение не дублирует запись"
fix_disable hypixel >/dev/null
assert_fails "фикс выключен обратно" fix_is_enabled hypixel
assert_fails "несуществующий фикс не включается" fix_enable no-such-fix

t_section "lists: нормализация доменов"

assert_eq "github.com" "$(domain_normalize 'https://github.com/user/repo')" "домен извлекается из URL"
assert_eq "github.com" "$(domain_normalize '  WWW.GitHub.com  ')" "регистр, пробелы и www"
assert_eq "sub.example.co.uk" "$(domain_normalize 'sub.example.co.uk')" "многоуровневый домен"
assert_eq "example.com" "$(domain_normalize 'example.com:8443')" "порт отбрасывается"
assert_status "2" "мусор не проходит валидацию" domain_normalize 'не домен'
assert_status "2" "голый хост без зоны отклоняется" domain_normalize 'localhost'
assert_status "1" "пустая строка отклоняется" domain_normalize '   '

t_section "lists: добавление домена"

list="$ZAPRET_HOSTLISTS/list-general-user.txt"
: >"$list"
domain_add "example.com" "$list" >/dev/null
assert_eq "example.com" "$(cat "$list")" "домен добавлен"
assert_fails "повторное добавление того же домена отклоняется" domain_add "example.com" "$list"

printf 'first.com' >"$list" # no trailing newline
domain_add "second.com" "$list" >/dev/null
assert_eq "first.com
second.com" "$(cat "$list")" "lines are not glued together when the file lacks a trailing newline"

t_section "lists: состояние ipset"

rm -f "$ZDY_IPSET_FILE"
assert_eq "any" "$(ipset_state)" "нет файла - режим any"
: >"$ZDY_IPSET_FILE"
assert_eq "any" "$(ipset_state)" "пустой файл - режим any"
printf '%s\n' "$ZDY_IPSET_STUB_IP" >"$ZDY_IPSET_FILE"
assert_eq "none" "$(ipset_state)" "одна заглушка - режим none"
printf '1.2.3.4\n5.6.7.8\n' >"$ZDY_IPSET_FILE"
assert_eq "loaded" "$(ipset_state)" "реальные адреса - режим loaded"

t_section "lists: game filter"

rm -f "$ZDY_GAME_FILE"
assert_eq "off" "$(game_filter_mode)" "нет файла - фильтр выключен"
printf 'tcp\n' >"$ZDY_GAME_FILE"
assert_eq "tcp" "$(game_filter_mode)" "режим читается из файла"
printf 'мусор\n' >"$ZDY_GAME_FILE"
assert_eq "unknown" "$(game_filter_mode)" "неизвестное значение не выдаётся за режим"
rm -f "$ZDY_GAME_FILE"

t_section "lists: блок в /etc/hosts"

cat >"$ZDY_HOSTS_FILE" <<'EOF'
127.0.0.1 localhost
::1 localhost
EOF
original_hosts=$(cat "$ZDY_HOSTS_FILE")

assert_fails "блок ещё не установлен" hosts_has_block

{
  cat "$ZDY_HOSTS_FILE"
  printf '%s\n' "$ZDY_HOSTS_BEGIN"
  printf '1.2.3.4 discord.gg\n'
  printf '%s\n' "$ZDY_HOSTS_END"
} >"$SANDBOX/hosts.new"
cp "$SANDBOX/hosts.new" "$ZDY_HOSTS_FILE"

assert_ok "блок распознаётся по маркеру" hosts_has_block
assert_eq "$original_hosts" "$(hosts_without_block)" "удаление блока восстанавливает исходный hosts"

# Повторная установка не должна накапливать записи - прежний код дописывал
# содержимое в конец при каждом изменении апстрима.
{
  hosts_without_block
  printf '%s\n' "$ZDY_HOSTS_BEGIN"
  printf '5.6.7.8 discord.gg\n'
  printf '%s\n' "$ZDY_HOSTS_END"
} >"$SANDBOX/hosts.second"
cp "$SANDBOX/hosts.second" "$ZDY_HOSTS_FILE"
assert_eq "1" "$(grep -c 'discord.gg' "$ZDY_HOSTS_FILE")" "повторное применение не дублирует записи"
assert_eq "$original_hosts" "$(hosts_without_block)" "пользовательские строки hosts не пострадали"

# ============================================================= service ======

t_section "service: определение менеджера служб"

cat >"$SANDBOX/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  list-unit-files) printf 'zapret.service enabled\n' ;;
  is-active) exit "${FAKE_ACTIVE:-0}" ;;
  is-enabled) exit "${FAKE_ENABLED:-0}" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$SANDBOX/bin/systemctl"

ZDY_SERVICE_MANAGER_CACHE=""
assert_eq "systemd" "$(detect_service_manager)" "systemd определяется по list-unit-files"

FAKE_ACTIVE=0 assert_ok "служба видна как запущенная" service_is_active systemd
FAKE_ACTIVE=3 assert_fails "служба видна как остановленная" env FAKE_ACTIVE=3 service_is_active systemd

rm -f "$SANDBOX/bin/systemctl"
hash -r   # bash caches command paths; without a reset the stub stays 'found'
ZDY_SERVICE_MANAGER_CACHE=""
assert_fails "detect_service_manager падает без известных менеджеров" detect_service_manager

# ============================================================== update ======

t_section "update: валидация архива обновления"

fake_src="$SANDBOX/fake-update"
mkdir -p "$fake_src"
assert_fails "пустой архив отклоняется" validate_update_source "$fake_src"

mkdir -p "$fake_src/bin" "$fake_src/lib" "$fake_src/configs" "$fake_src/hostlists" "$fake_src/utils"
touch "$fake_src/setup.sh" "$fake_src/bin/zapret-setup" \
  "$fake_src/bin/zapret-config" "$fake_src/bin/zapret-manager"
assert_ok "полный архив проходит валидацию" validate_update_source "$fake_src"

t_section "update: состояние"

assert_eq "0" "$(state_schema)" "схема по умолчанию - 0"
state_set_schema 2
assert_eq "2" "$(state_schema)" "схема сохраняется"
state_set_commit "0123456789abcdef0123456789abcdef01234567"
assert_eq "0123456789abcdef0123456789abcdef01234567" "$(state_commit)" "коммит сохраняется"
assert_contains "$ZDY_STATE_DIR" ".local/state/zapret-discord-youtube" \
  "state lives in XDG_STATE_HOME, not inside the project"

# ========================================================= autorestart ======

t_section "autorestart: валидация интервала"

assert_ok "6 часов принимается" autorestart_interval_valid 6
assert_ok "нижняя граница 5 принимается" autorestart_interval_valid 5
assert_ok "верхняя граница 12 принимается" autorestart_interval_valid 12
assert_fails "4 часа отклоняются" autorestart_interval_valid 4
assert_fails "13 часов отклоняются" autorestart_interval_valid 13
assert_fails "нечисловое значение отклоняется" autorestart_interval_valid "eight"
assert_fails "пустое значение отклоняется" autorestart_interval_valid ""

t_section "autorestart: systemd"

cat >"$SANDBOX/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s
' "$*" >>"$SYSTEMCTL_LOG"
case "$1" in
  list-unit-files) printf 'zapret.service enabled
' ;;
  is-active | is-enabled) exit 0 ;;
esac
exit 0
EOF
chmod +x "$SANDBOX/bin/systemctl"
hash -r
export SYSTEMCTL_LOG="$SANDBOX/systemctl.log"
: >"$SYSTEMCTL_LOG"
ZDY_SERVICE_MANAGER_CACHE=""

assert_eq "off" "$(autorestart_status)" "автоперезапуск по умолчанию выключен"

autorestart_enable 8 >/dev/null 2>&1
assert_ok "unit таймера создан" test -f "$ZDY_AUTORESTART_TIMER"
assert_ok "unit службы создан" test -f "$ZDY_AUTORESTART_SERVICE"
assert_ok "helper создан" test -x "$ZDY_AUTORESTART_HELPER"
assert_eq "systemd:8" "$(autorestart_status)" "интервал читается обратно из unit-файла"
assert_eq "каждые 8 ч (systemd timer)" "$(autorestart_status_text)" "человекочитаемый статус"
assert_contains "$(cat "$SYSTEMCTL_LOG")" "daemon-reload" "systemd перечитал unit-файлы"
assert_contains "$(cat "$SYSTEMCTL_LOG")" "enable --now zapret-autorestart.timer" "таймер включён"

# Сгенерированный helper запускается системным планировщиком, где может не
# быть bash - проверяем, что он валиден именно для POSIX sh.
assert_ok "helper проходит sh -n" sh -n "$ZDY_AUTORESTART_HELPER"
assert_contains "$(cat "$ZDY_AUTORESTART_HELPER")" "systemctl restart zapret" \
  "the restart command is baked into the helper"
assert_fails "в helper нет непереносимого pgrep" grep -q "pgrep" "$ZDY_AUTORESTART_HELPER"
assert_fails "в helper нет непереносимого ps -o" grep -q "ps -o" "$ZDY_AUTORESTART_HELPER" # lint-ok: asserting absence

autorestart_enable 12 >/dev/null 2>&1
assert_eq "systemd:12" "$(autorestart_status)" "смена интервала переписывает таймер"

assert_fails "интервал вне диапазона не применяется" autorestart_enable 24
assert_eq "systemd:12" "$(autorestart_status)" "прежняя настройка переживает отклонённую смену"

autorestart_disable >/dev/null 2>&1
assert_eq "off" "$(autorestart_status)" "отключение убирает таймер"
assert_fails "unit таймера удалён" test -f "$ZDY_AUTORESTART_TIMER"

t_section "autorestart: подсчёт перезапусков"

cat >"$ZDY_AUTORESTART_LOG" <<EOF
$(date '+%Y-%m-%d %H:%M:%S') restart interval=8h nfqws_procs=1
$(date '+%Y-%m-%d %H:%M:%S') restart interval=8h nfqws_procs=1
2001-01-01 03:00:00 restart interval=8h nfqws_procs=1
EOF
assert_eq "2" "$(autorestart_log_count 7)" "старые записи не попадают в счётчик за 7 дней"

# ============================================================ incident ======

t_section "incident: снимок состояния"

printf 'systemd\n' >"$SANDBOX/proc/1/comm"
printf '12345.67 20000.00\n' >"$SANDBOX/proc/uptime"
cp "$REPO_DIR/config" "$ZAPRET_CONFIG"

snapshot_dir=$(incident_snapshot "test")
assert_ok "каталог снимка создан" test -d "$snapshot_dir"
assert_ok "сводка записана" test -s "$snapshot_dir/summary.txt"
assert_ok "процессы записаны" test -s "$snapshot_dir/processes.txt"
assert_ok "состояние списков записано" test -s "$snapshot_dir/lists.txt"
assert_ok "копия конфига сохранена" test -f "$snapshot_dir/config"
assert_contains "$(cat "$snapshot_dir/summary.txt")" "Стратегия:       general" "текущая стратегия попала в сводку"
assert_contains "$(cat "$snapshot_dir/summary.txt")" "Причина:         test" "причина попала в сводку"

t_section "incident: ротация снимков"

ZDY_INCIDENT_KEEP=3
for i in 1 2 3 4 5; do
  mkdir -p "$ZDY_INCIDENT_DIR/2020-01-0$i""_00-00-00"
done
incident_prune
assert_eq "3" "$(incident_count)" "лишние снимки удаляются, свежие остаются"
ZDY_INCIDENT_KEEP=30

t_section "фрагменты: ссылки на отсутствующие файлы"

refs=$(nfqws_referenced_paths "$ZAPRET_STRATEGIES/general")
assert_ne "0" "$(printf '%s\n' "$refs" | grep -c .)" "ссылки из фрагмента извлекаются"
assert_contains "$refs" "list-general.txt" "среди ссылок есть hostlist"
assert_contains "$refs" ".bin" "среди ссылок есть бинарник фейка"

missing=0
while IFS= read -r ref; do
  [ -e "$ref" ] || missing=$((missing + 1))
done <<<"$refs"
assert_ne "0" "$missing" "в песочнице этих файлов действительно нет"

# ============================================== имена конфигов и NixOS ======

t_section "конфиги: единообразные имена"

bad_names=0
for cfg in "$REPO_DIR"/strategies/*; do
  [ -f "$cfg" ] || continue
  name="${cfg##*/}"
  [ "$name" = "legacy-names.map" ] && continue
  [[ "$name" =~ ^[a-z0-9-]+$ ]] || {
    printf '        non-standard name: %s\n' "$name"
    bad_names=$((bad_names + 1))
  }
done
assert_eq "0" "$bad_names" "все имена конфигов из [a-z0-9-]"

# Фрагменты стратегий не содержат заголовка с именем - имя задаётся файлом,
# а внутри только NFQWS_STRATEGY_OPT. Проверяем, что это действительно так.
no_opt=0
for cfg in "$REPO_DIR"/strategies/*; do
  [ -f "$cfg" ] || continue
  name="${cfg##*/}"
  [ "$name" = "legacy-names.map" ] && continue
  grep -q '^NFQWS_STRATEGY_OPT="' "$cfg" || no_opt=$((no_opt + 1))
done
assert_eq "0" "$no_opt" "каждый фрагмент задаёт NFQWS_STRATEGY_OPT"

# Списки имён продублированы в трёх местах: каталог configs, таблица
# синонимов и nixos/module.nix. Разъедутся - установка сломается уже у
# пользователя, поэтому сверяем здесь.
t_section "конфиги: синхронность с NixOS и таблицей синонимов"

map_targets_ok=1
while IFS=$'\t' read -r legacy modern; do
  [ -n "$legacy" ] || continue
  [ -f "$REPO_DIR/strategies/$modern" ] || {
    printf '        alias table maps %s -> %s, but the file is missing\n' "$legacy" "$modern"
    map_targets_ok=0
  }
done <"$REPO_DIR/strategies/legacy-names.map"
assert_eq "1" "$map_targets_ok" "все цели legacy-names.map существуют"

missing_in_nix=0
for cfg in "$REPO_DIR"/strategies/*; do
  [ -f "$cfg" ] || continue
  name="${cfg##*/}"
  [ "$name" = "legacy-names.map" ] && continue
  grep -q "\"$name\"" "$REPO_DIR/nixos/module.nix" || {
    printf '        missing from knownStrategyNames: %s\n' "$name"
    missing_in_nix=$((missing_in_nix + 1))
  }
done
assert_eq "0" "$missing_in_nix" "все конфиги перечислены в knownStrategyNames (module.nix)"

missing_legacy_in_nix=0
while IFS=$'\t' read -r legacy modern; do
  [ -n "$legacy" ] || continue
  grep -qF "\"$legacy\" = \"$modern\";" "$REPO_DIR/nixos/package.nix" || {
    printf '        missing from legacyConfigNames in package.nix: %s\n' "$legacy"
    missing_legacy_in_nix=$((missing_legacy_in_nix + 1))
  }
done <"$REPO_DIR/strategies/legacy-names.map"
assert_eq "0" "$missing_legacy_in_nix" "таблица синонимов совпадает с package.nix"

t_section "lock: разбор zapret.lock"

assert_eq "v72.12" "$(lock_get zapret_version)" "версия читается из zapret.lock"
assert_eq "unset" "$(lock_get bin_sha256 stun.bin)" "хеш бинарника читается по подключу"
assert_fails "несуществующий ключ не выдумывается" lock_get nonexistent_key

lock_probe="$SANDBOX/probe.bin"
printf 'test\n' >"$lock_probe"
assert_ok "незаданный хеш пропускается в мягком режиме" \
  lock_verify_file "$lock_probe" "unset" "probe"
assert_status "1" "незаданный хеш прерывает работу в строгом режиме" \
  env ZDY_STRICT_CHECKSUMS=1 bash -c \
  ". '$REPO_DIR/lib/paths.sh'; . '$REPO_DIR/lib/common.sh'; . '$REPO_DIR/lib/compat.sh'; \
   . '$REPO_DIR/lib/lock.sh'; ZDY_STRICT_CHECKSUMS=1; \
   lock_verify_file '$lock_probe' unset probe"
assert_ok "совпавший хеш проходит проверку" \
  lock_verify_file "$lock_probe" "$(sha256_file "$lock_probe")" "probe"
assert_fails "несовпавший хеш отклоняется" \
  lock_verify_file "$lock_probe" "0000000000000000000000000000000000000000000000000000000000000000" "probe"


# ================================================= регрессии под set -e =====

t_section "команды не падают под set -euo pipefail"

# shopt -p возвращает 1, когда опция выключена. Под set -e это роняло
# zapret-config --list молча, с пустым выводом и кодом 1.
assert_ok "zapret-config --list отрабатывает" \
  env HOME="$HOME" ZAPRET_DIR="$ZAPRET_DIR" NO_COLOR=1 bash "$REPO_DIR/bin/zapret-config" --list
# Отдельный несуществующий ZAPRET_DIR: иначе список берётся из установленного
# каталога, который к этому моменту наполнили предыдущие тесты.
assert_eq "21" "$(env HOME="$HOME" ZAPRET_DIR="$SANDBOX/no-such-zapret" NO_COLOR=1 bash "$REPO_DIR/bin/zapret-config" --list | grep -c .)" \
  "zapret-config --list печатает все стратегии из проекта"
assert_ok "zapret-manager status отрабатывает" \
  env HOME="$HOME" ZAPRET_DIR="$ZAPRET_DIR" NO_COLOR=1 bash "$REPO_DIR/bin/zapret-manager" status
assert_ok "zapret-manager help отрабатывает" \
  env HOME="$HOME" ZAPRET_DIR="$ZAPRET_DIR" NO_COLOR=1 bash "$REPO_DIR/bin/zapret-manager" help

t_section "вывод: только стандартные символы"

# Проверка на уровне байтов, без python: в CI на Alpine его нет.
#
# tr удаляет ASCII (\000-\177) и байты, из которых состоит кириллица в UTF-8:
# ведущие \320 и \321 плюс продолжающие \200-\277. Всё, что осталось, -
# это не-ASCII и не кириллица: длинное тире (\342...), ёлочки (\302...)
# и прочие символы, которые в терминале без нужных глифов превращаются
# в мусор.
check_only_standard_symbols() {
  local file rest bad=""
  for file in "$@"; do
    [ -f "$file" ] || continue
    rest=$(LC_ALL=C tr -d '\000-\177\320\321\200-\277' <"$file")
    [ -n "$rest" ] && bad="$bad ${file##*/}"
  done
  printf '%s\n' "${bad# }"
}

nonascii=$(check_only_standard_symbols "$REPO_DIR"/bin/* "$REPO_DIR"/lib/*.sh)
assert_eq "" "$nonascii" "в bin/ и lib/ нет нестандартных символов"


# ============================================== удаление и отчёт ============

t_section "uninstall: план удаления"

# shellcheck source=../lib/uninstall.sh
ZDY_COMMANDS=(zapret-config zapret-manager zapret-restart)
. "$REPO_DIR/lib/uninstall.sh"

mkdir -p "$ZDY_USER_BIN"
ln -sfn "$REPO_DIR/bin/zapret-manager" "$ZDY_USER_BIN/zapret-manager"
mkdir -p "$ZAPRET_DIR/strategies"

plan=$(uninstall_plan)
assert_contains "$plan" "$ZAPRET_DIR" "в план попал каталог zapret"
assert_contains "$plan" "$ZDY_USER_BIN/zapret-manager" "в план попал симлинк команды"
assert_ok "план не содержит каталог состояния (он сохраняется)" \
  bash -c "! printf '%s' \"\$1\" | grep -q 'state/zapret-discord-youtube[[:space:]]'" _ "$plan"

t_section "diag: отчёт для issue"

report_path=$(ZDY_ASSUME_YES=1 diag_bundle "$SANDBOX/report.txt" | tail -n 1)
assert_eq "$SANDBOX/report.txt" "$report_path" "diag_bundle печатает путь к отчёту"
assert_ok "файл отчёта создан" test -s "$SANDBOX/report.txt"
assert_eq "600" "$(stat -c '%a' "$SANDBOX/report.txt")" "отчёт доступен только владельцу"
assert_contains "$(cat "$SANDBOX/report.txt")" "doctor" "в отчёте есть блок doctor"
assert_contains "$(cat "$SANDBOX/report.txt")" "выбранная стратегия" "в отчёте есть выбранная стратегия"

t_section "форк: внешние адреса переопределяются"

fork_urls=$(env ZDY_REPO_SLUG="someone/fork" ZDY_BRANCH="test" bash -c \
  ". '$REPO_DIR/lib/paths.sh'; printf '%s\n%s\n' \"\$ZDY_ARCHIVE_URL\" \"\$ZDY_API_BRANCH_URL\"")
assert_contains "$fork_urls" "someone/fork" "архив берётся из форка"
assert_contains "$fork_urls" "heads/test" "ветка берётся из переменной"
assert_ok "адрес Flowseal переопределяется отдельно" \
  bash -c "env ZDY_FLOWSEAL_SLUG=me/lists bash -c '. \"$REPO_DIR/lib/paths.sh\"; case \$ZDY_FLOWSEAL_IPSET_URL in *me/lists*) exit 0;; esac; exit 1'"


t_section "compat: владелец файла без find -printf"

owner_probe="$SANDBOX/owner-probe"
: >"$owner_probe"
assert_eq "$(id -un)" "$(path_owner "$owner_probe")" "path_owner возвращает владельца"
assert_fails "path_owner падает на несуществующем пути" path_owner "$SANDBOX/no-such-file"


# ====================================== ссылки фрагментов на реальные файлы ==

t_section "фрагменты: ссылки на существующие .bin и hostlists"

# Опечатка в имени файла не мешает ни bash -n, ни разбору фрагмента, но
# install_easy.sh отказывается стартовать, а служба остаётся без обхода.
# Так был найден ACTIVE_DISCORD_UDP.binn в general-alt-8.
known_bins="$SANDBOX/known-bins.txt"
grep -v '^#' "$REPO_DIR/tests/fake-binaries.txt" | grep -v '^[[:space:]]*$' |
  LC_ALL=C sort >"$known_bins"

bad_bin_refs=0
for frag in "$REPO_DIR"/strategies/general* "$REPO_DIR"/fixes/*; do
  [ -f "$frag" ] || continue
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if ! grep -Fqx -- "$ref" "$known_bins"; then
      printf '       %s ссылается на несуществующий %s\n' "${frag##*/}" "$ref"
      bad_bin_refs=$((bad_bin_refs + 1))
    fi
  done < <(tr ' ' '\n' <"$frag" | grep -oE 'files/fake/[A-Za-z0-9_.-]+' | sed 's|files/fake/||' | LC_ALL=C sort -u)
done
assert_eq "0" "$bad_bin_refs" "все ссылки на .bin ведут на существующие файлы"

bad_list_refs=0
for frag in "$REPO_DIR"/strategies/general* "$REPO_DIR"/fixes/*; do
  [ -f "$frag" ] || continue
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    if [ ! -f "$REPO_DIR/hostlists/$ref" ]; then
      printf '       %s ссылается на несуществующий hostlist %s\n' "${frag##*/}" "$ref"
      bad_list_refs=$((bad_list_refs + 1))
    fi
  done < <(tr ' ' '\n' <"$frag" | grep -oE 'hostlists/[A-Za-z0-9_.-]+' | sed 's|hostlists/||' | LC_ALL=C sort -u)
done
assert_eq "0" "$bad_list_refs" "все ссылки на hostlists ведут на существующие файлы"


t_section "меню: естественная сортировка и запуск через симлинк"

sorted=$(env HOME="$HOME" ZAPRET_DIR="$SANDBOX/no-such-zapret" NO_COLOR=1 \
  bash "$REPO_DIR/bin/zapret-config" --list | tr '\n' ' ')
assert_contains "$sorted" "general-alt-9 general-alt-10" \
  "general-alt-10 идёт после general-alt-9, а не после general-alt"

# Команды в ~/.local/bin - симлинки. pwd -P раскрывает только каталог, но не
# сам файл, поэтому без разрешения симлинка подключение ../lib/ падало.
mkdir -p "$SANDBOX/fakebin"
ln -sfn "$REPO_DIR/bin/zapret-manager" "$SANDBOX/fakebin/zapret-manager"
ln -sfn "$REPO_DIR/bin/zapret-config" "$SANDBOX/fakebin/zapret-config"
assert_ok "zapret-manager работает через симлинк" \
  env HOME="$HOME" ZAPRET_DIR="$ZAPRET_DIR" NO_COLOR=1 "$SANDBOX/fakebin/zapret-manager" status
assert_ok "zapret-config работает через симлинк" \
  env HOME="$HOME" ZAPRET_DIR="$ZAPRET_DIR" NO_COLOR=1 "$SANDBOX/fakebin/zapret-config" --list

t_section "склонение дней"

assert_eq "сегодня" "$(plural_days 0)" "0 дней"
assert_eq "1 день назад" "$(plural_days 1)" "1 день"
assert_eq "2 дня назад" "$(plural_days 2)" "2 дня"
assert_eq "5 дней назад" "$(plural_days 5)" "5 дней"
assert_eq "11 дней назад" "$(plural_days 11)" "11 дней (исключение)"
assert_eq "21 день назад" "$(plural_days 21)" "21 день"


t_section "загрузка .bin: список синхронен с zapret.lock"

lock_names=$(lock_list_binaries | LC_ALL=C sort)
manifest_flowseal=$(sed -n '/докачивается из bin\/ репозитория Flowseal/,/поставляется с zapret/p' \
  "$REPO_DIR/tests/fake-binaries.txt" | grep -E '^[A-Za-z0-9_.-]+\.bin$' | LC_ALL=C sort)
assert_eq "$manifest_flowseal" "$lock_names" \
  "bin_sha256 в zapret.lock совпадает со списком в fake-binaries.txt"

# Каждый .bin, на который ссылаются фрагменты, должен либо приезжать от
# Flowseal, либо поставляться с zapret. Ровно эта проверка ловит и опечатку
# в имени, и файл, забытый в списке загрузки.
missing_source=0
for frag in "$REPO_DIR"/strategies/general* "$REPO_DIR"/fixes/*; do
  [ -f "$frag" ] || continue
  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    grep -Fqx -- "$ref" "$known_bins" || {
      printf '       %s: %s не приезжает ниоткуда\n' "${frag##*/}" "$ref"
      missing_source=$((missing_source + 1))
    }
  done < <(tr ' ' '\n' <"$frag" | grep -oE 'files/fake/[A-Za-z0-9_.-]+' | sed 's|files/fake/||' | LC_ALL=C sort -u)
done
assert_eq "0" "$missing_source" "у каждого .bin из фрагментов есть источник"


# ============================================ интеграция: сам загрузчик =====

t_section "загрузчик config: сборка NFQWS_OPT"

# Здесь проверяется не наша обвязка, а то, что реально выполняет служба при
# старте: config сорсится в отдельной оболочке с подставным ZAPRET_BASE.
loader_run() {
  local base="$1"
  env ZAPRET_BASE="$base" sh -c '
    . "$1" >/dev/null 2>&1
    printf "PORTS_TCP=%s\n" "$NFQWS_PORTS_TCP"
    printf "PORTS_UDP=%s\n" "$NFQWS_PORTS_UDP"
    printf "OPT<<\n%s\n>>OPT\n" "$NFQWS_OPT"
  ' sh "$REPO_DIR/config"
}

loader_base="$SANDBOX/loader"
mkdir -p "$loader_base/strategies" "$loader_base/fixes" "$loader_base/hostlists"
cp "$REPO_DIR"/strategies/general "$REPO_DIR"/strategies/general-alt-3 "$loader_base/strategies/"
cp "$REPO_DIR"/fixes/hypixel "$loader_base/fixes/"

printf 'general\n' >"$loader_base/zapret.strategy"
out=$(loader_run "$loader_base")
assert_contains "$out" "PORTS_TCP=80,443" "базовые TCP-порты без game filter и фиксов"
assert_contains "$out" "filter-l7=discord,stun" "правило discord попало в NFQWS_OPT"
assert_ok "правило google из general на месте" \
  bash -c "case \"\$1\" in *list-google.txt*) exit 0;; esac; exit 1" _ "$out"

printf 'general-alt-3\n' >"$loader_base/zapret.strategy"
out_alt=$(loader_run "$loader_base")
assert_ne "$out" "$out_alt" "смена zapret.strategy меняет собранный NFQWS_OPT"

t_section "загрузчик config: game filter и фиксы"

printf 'general\n' >"$loader_base/zapret.strategy"
printf 'all\n' >"$loader_base/hostlists/.game_filter.enabled"
out_game=$(loader_run "$loader_base")
assert_contains "$out_game" "1024-65535" "порты game filter добавились к базовым"

printf 'hypixel\n' >"$loader_base/zapret.fixes"
out_fix=$(loader_run "$loader_base")
assert_contains "$out_fix" "25565" "порт фикса добавился к списку портов"
assert_contains "$out_fix" "filter-tcp=25565" "правило фикса попало в NFQWS_OPT"

# Фиксы идут перед стратегией: в nfqws выигрывает первый подошедший профиль,
# то есть фикс должен иметь возможность перекрыть стратегию.
fix_pos=$(printf '%s' "$out_fix" | grep -n 'filter-tcp=25565' | head -n 1 | cut -d: -f1)
strategy_pos=$(printf '%s' "$out_fix" | grep -n 'filter-l7=discord' | head -n 1 | cut -d: -f1)
assert_ok "правила фикса идут раньше правил стратегии" \
  test "$fix_pos" -lt "$strategy_pos"

rm -f "$loader_base/zapret.fixes" "$loader_base/hostlists/.game_filter.enabled"

t_section "загрузчик config: устойчивость к мусору"

printf 'нет-такой-стратегии\n' >"$loader_base/zapret.strategy"
out_bad=$(loader_run "$loader_base")
assert_contains "$out_bad" "filter-l7=discord,stun" "неизвестная стратегия - откат на general"

printf '../../etc/passwd\n' >"$loader_base/zapret.strategy"
out_traversal=$(loader_run "$loader_base")
assert_contains "$out_traversal" "filter-l7=discord,stun" "путь с ../ отвергается, откат на general"

printf 'general\n' >"$loader_base/zapret.strategy"
printf 'нет-такого-фикса\n' >"$loader_base/zapret.fixes"
out_badfix=$(loader_run "$loader_base")
assert_contains "$out_badfix" "filter-l7=discord,stun" "неизвестный фикс не ломает сборку"
rm -f "$loader_base/zapret.fixes"

printf 'NFQWS_STRATEGY_OPT="\nunclosed\n' >"$loader_base/strategies/broken"
printf 'broken\n' >"$loader_base/zapret.strategy"
out_broken=$(loader_run "$loader_base")
assert_contains "$out_broken" "filter-l7=discord,stun" "стратегия с синтаксической ошибкой - откат на general"
rm -f "$loader_base/strategies/broken"


t_section "autorestart: слепок перед перезапуском"

helper_env="$SANDBOX/ar"
mkdir -p "$helper_env/systemd"
(
  export ZDY_HELPER_DIR="$helper_env/helper"
  export ZDY_SYSTEMD_UNIT_DIR="$helper_env/systemd"
  export ZDY_AUTORESTART_LOG="$helper_env/autorestart.log"
  export ZDY_AUTORESTART_SNAPSHOT_DIR="$helper_env/snap"
  # переменные читает уже загруженный модуль, поэтому пересчитываем пути
  ZDY_AUTORESTART_HELPER="$ZDY_HELPER_DIR/autorestart.sh"
  autorestart_write_helper 12 >/dev/null 2>&1
  # перезапуск подменяем, чтобы не трогать систему
  sed 's|^systemctl restart |echo RESTART |' "$ZDY_AUTORESTART_HELPER" >"$helper_env/run.sh"
  sh "$helper_env/run.sh" >/dev/null 2>&1
)
assert_ok "helper проходит sh -n" sh -n "$helper_env/helper/autorestart.sh"
assert_ok "лог перезапусков создан" test -s "$helper_env/autorestart.log"
assert_ok "слепок перед перезапуском создан" \
  bash -c 'ls "$1"/*-timer.txt >/dev/null 2>&1' _ "$helper_env/snap"
snap_file=$(ls "$helper_env"/snap/*-timer.txt 2>/dev/null | head -n 1)
assert_contains "$(cat "$snap_file" 2>/dev/null)" "nfqueue" "в слепке есть счётчики nfqueue"
assert_contains "$(cat "$snap_file" 2>/dev/null)" "reason=timer" "в слепке указана причина"
assert_eq "600" "$(stat -c '%a' "$snap_file" 2>/dev/null)" "слепок доступен только владельцу"


t_section "даты: арифметика без GNU date"

assert_eq "2440588" "$(date_string_to_days 1970-01-01)" "эпоха Unix = JDN 2440588"
assert_eq "2451605" "$(date_string_to_days 2000-03-01)" "високосный год посчитан верно"
assert_eq "1" "$(( $(date_string_to_days 2024-03-01) - $(date_string_to_days 2024-02-29) ))" \
  "29 февраля учтено"
assert_eq "365" "$(( $(date_string_to_days 2023-01-01) - $(date_string_to_days 2022-01-01) ))" \
  "обычный год - 365 дней"
assert_fails "мусор вместо даты отвергается" date_string_to_days "не-дата"
assert_eq "$(today_days)" "$(( $(date '+%s') / 86400 + 2440588 ))" \
  "today_days сходится с эпохой"

t_section "autorestart: счётчик за 7 дней"

count_log="$SANDBOX/count.log"
old_day=$(( $(date '+%s') - 10 * 86400 ))
recent_day=$(( $(date '+%s') - 2 * 86400 ))
{
  printf '%s restart interval=12h nfqws_procs=1\n' "$(date -d "@$old_day" '+%Y-%m-%d %H:%M:%S' 2>/dev/null ||
    date -r "$old_day" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  printf '%s restart interval=12h nfqws_procs=1\n' "$(date -d "@$recent_day" '+%Y-%m-%d %H:%M:%S' 2>/dev/null ||
    date -r "$recent_day" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
  printf '%s restart interval=12h nfqws_procs=1\n' "$(date '+%Y-%m-%d %H:%M:%S')"
} >"$count_log"

# Регрессия: date -d "-7 days" - расширение GNU. В busybox cutoff получался
# пустым, срабатывал запасной путь, и считались все строки лога.
assert_eq "2" "$(ZDY_AUTORESTART_LOG="$count_log" autorestart_log_count 7)" \
  "запись десятидневной давности не попала в счётчик"
assert_eq "3" "$(ZDY_AUTORESTART_LOG="$count_log" autorestart_log_count 30)" \
  "за 30 дней считаются все три"


# ================================== реестр устаревшего не разъезжается ======

t_section "DEPRECATIONS.md: реестр совпадает с кодом"

# Смысл проверки: если код удалён, а запись осталась (или наоборот), реестр
# перестаёт быть источником правды и превращается в ещё один устаревший файл.
deprecations="$REPO_DIR/DEPRECATIONS.md"
assert_ok "реестр на месте" test -f "$deprecations"

assert_ok "шим install.sh существует, пока он в реестре" test -f "$REPO_DIR/install.sh"
assert_ok "шим utils-zapret.sh существует, пока он в реестре" test -f "$REPO_DIR/utils-zapret.sh"
assert_ok "таблица старых имён существует, пока она в реестре" \
  test -f "$REPO_DIR/strategies/legacy-names.map"
# Апдейтер прежних версий требует каталог configs в архиве обновления.
assert_ok "заглушка configs/ существует, пока она в реестре" \
  test -f "$REPO_DIR/configs/README.md"
assert_ok "возврат владельца /opt/zapret на месте" \
  grep -q 'fix_legacy_ownership' "$REPO_DIR/bin/zapret-setup"
assert_ok "перенос со старой раскладки на месте" \
  grep -q 'migrate_legacy_layout' "$REPO_DIR/bin/zapret-setup"
assert_ok "разрешение старых имён на месте" \
  grep -q 'strategy_resolve_name' "$REPO_DIR/lib/strategy.sh"
assert_ok "legacyStrategyNames в package.nix на месте" \
  grep -q 'legacyStrategyNames' "$REPO_DIR/nixos/package.nix"

# Каждый упомянутый в реестре файл должен существовать.
missing_dep=0
for dep in install.sh utils-zapret.sh strategies/legacy-names.map \
  nixos/package.nix lib/strategy.sh bin/zapret-setup lib/autorestart.sh; do
  grep -Fq "$dep" "$deprecations" || continue
  [ -e "$REPO_DIR/$dep" ] || {
    printf '       в реестре есть %s, а файла нет\n' "$dep"
    missing_dep=$((missing_dep + 1))
  }
done
assert_eq "0" "$missing_dep" "все файлы из реестра существуют"

# Шимы обязаны предупреждать, иначе их никто не заметит.
assert_ok "install.sh печатает предупреждение" \
  grep -q 'устарел' "$REPO_DIR/install.sh"
assert_ok "utils-zapret.sh печатает предупреждение" \
  grep -q 'устарел' "$REPO_DIR/utils-zapret.sh"

t_summary
