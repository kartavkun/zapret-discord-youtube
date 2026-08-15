# shellcheck shell=bash
#
# Микро-харнесс для тестов. Намеренно без bats: лишняя зависимость ради
# нескольких десятков проверок не окупается, а так тесты запускаются везде,
# где есть bash.

ZDY_TESTS_PASSED=0
ZDY_TESTS_FAILED=0
ZDY_CURRENT_TEST=""

t_begin() {
  ZDY_CURRENT_TEST="$1"
}

t_pass() {
  ZDY_TESTS_PASSED=$((ZDY_TESTS_PASSED + 1))
  printf '  [ + ] %s\n' "$ZDY_CURRENT_TEST"
}

t_fail() {
  ZDY_TESTS_FAILED=$((ZDY_TESTS_FAILED + 1))
  printf '  [ - ] %s\n' "$ZDY_CURRENT_TEST"
  printf '        %s\n' "$1"
}

assert_eq() {
  t_begin "$3"
  if [ "$1" = "$2" ]; then
    t_pass
  else
    t_fail "ожидалось [$1], получено [$2]"
  fi
}

assert_ne() {
  t_begin "$3"
  if [ "$1" != "$2" ]; then
    t_pass
  else
    t_fail "значения совпали, а не должны были: [$1]"
  fi
}

assert_ok() {
  local desc="$1"
  shift
  t_begin "$desc"
  if "$@" >/dev/null 2>&1; then
    t_pass
  else
    t_fail "команда завершилась с кодом $?: $*"
  fi
}

assert_fails() {
  local desc="$1"
  shift
  t_begin "$desc"
  if "$@" >/dev/null 2>&1; then
    t_fail "команда неожиданно завершилась успешно: $*"
  else
    t_pass
  fi
}

assert_status() {
  local expected="$1" desc="$2"
  shift 2
  local actual=0
  t_begin "$desc"
  "$@" >/dev/null 2>&1 || actual=$?
  if [ "$actual" = "$expected" ]; then
    t_pass
  else
    t_fail "expected exit code $expected, got $actual"
  fi
}

assert_contains() {
  t_begin "$3"
  case "$1" in
    *"$2"*) t_pass ;;
    *) t_fail "в выводе нет [$2]: $1" ;;
  esac
}

t_section() { printf '\n%s\n' "$1"; }

t_summary() {
  printf '\n----------------------------------------\n'
  printf 'Пройдено: %d, провалено: %d\n' "$ZDY_TESTS_PASSED" "$ZDY_TESTS_FAILED"
  [ "$ZDY_TESTS_FAILED" -eq 0 ]
}
