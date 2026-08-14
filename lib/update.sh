# shellcheck shell=bash
#
# Обновление самого проекта, резервные копии и откат.
#
# Отличия от прежней реализации:
#   * состояние и бэкапы живут в $XDG_STATE_HOME, а не внутри копии проекта,
#     поэтому "очистить перед распаковкой" больше не требует исключений;
#   * сравнение деревьев идёт по sha256-манифесту, а не через diff -qr -x
#     (флага -x нет в части сборок busybox);
#   * коммит берётся из GitHub API. Прежний код пытался вытащить его из имени
#     каталога в архиве, но codeload для ветки распаковывается в repo-main,
#     поэтому сохранялась строка "main" вместо хеша;
#   * обновление не вызывает exit из середины меню: возвращает
#     ZDY_UPDATE_RESTART, а вызывающий делает exec на новую версию.

[ -n "${ZDY_UPDATE_SOURCED:-}" ] && return 0
ZDY_UPDATE_SOURCED=1

# Код возврата "обновление применено, перезапустите себя".
ZDY_UPDATE_RESTART=10

ZDY_UPDATE_REQUIRED_PATHS=(
  setup.sh
  bin/zapret-setup
  bin/zapret-config
  bin/zapret-manager
  lib
  configs
  hostlists
  utils
)

# ------------------------------------------------------------ состояние -----

state_dir_init() {
  mkdir -p "$ZDY_STATE_DIR" "$ZDY_BACKUP_DIR" || return 1
  # 700, а не 755: в снимках инцидентов лежат записи conntrack, то есть
  # адреса, к которым подключался пользователь. Намногопользовательской машине
  # это не должно читаться посторонними.
  chmod 700 "$ZDY_STATE_DIR" 2>/dev/null || true
}

state_schema() {
  if [ -r "$ZDY_SCHEMA_FILE" ]; then
    local v
    IFS= read -r v <"$ZDY_SCHEMA_FILE" || v=""
    printf '%s\n' "${v:-0}"
  else
    printf '0\n'
  fi
}

state_set_schema() {
  state_dir_init
  printf '%s\n' "$1" >"$ZDY_SCHEMA_FILE"
}

state_commit() {
  if [ -r "$ZDY_COMMIT_FILE" ]; then
    local v
    IFS= read -r v <"$ZDY_COMMIT_FILE" || v=""
    printf '%s\n' "${v:-unknown}"
    return
  fi
  if have_cmd git && [ -d "$ZDY_ROOT/.git" ]; then
    git -C "$ZDY_ROOT" rev-parse HEAD 2>/dev/null && return
  fi
  printf 'unknown\n'
}

state_set_commit() {
  state_dir_init
  printf '%s\n' "$1" >"$ZDY_COMMIT_FILE"
}

remote_commit() {
  local json sha
  json=$(fetch_stdout "$ZDY_API_BRANCH_URL" 2>/dev/null) || return 1
  # Первый 40-символьный hex в ответе /commits/<branch> - это sha самого коммита.
  sha=$(printf '%s' "$json" | grep -o '[0-9a-f]\{40\}' | head -n 1)
  [ -n "$sha" ] || return 1
  printf '%s\n' "$sha"
}

# ----------------------------------------------------------- резервные ------

backup_list() {
  [ -d "$ZDY_BACKUP_DIR" ] || return 0
  find "$ZDY_BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | LC_ALL=C sort
}

backup_latest() { backup_list | tail -n 1; }

backup_create() {
  local backup_dir="$1" from_commit="$2" to_commit="$3"

  mkdir -p "$backup_dir/files" || return 1
  # tar в оба конца, чтобы не зависеть от cp -a и его различий в BSD-userland.
  (cd "$ZDY_ROOT" && tar --exclude='./.git' -cf - .) | (cd "$backup_dir/files" && tar -xf -) || return 1

  {
    printf 'from_commit=%s\n' "$from_commit"
    printf 'to_commit=%s\n' "$to_commit"
    printf 'date=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  } >"$backup_dir/metadata"
}

backup_matches_project() {
  local backup_dir="$1"
  [ -n "$backup_dir" ] && [ -d "$backup_dir/files" ] || return 1
  trees_match "$ZDY_ROOT" "$backup_dir/files" ".git"
}

backup_metadata_field() {
  local backup_dir="$1" field="$2" line
  [ -r "$backup_dir/metadata" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      "$field"=*)
        printf '%s\n' "${line#*=}"
        return 0
        ;;
    esac
  done <"$backup_dir/metadata"
  return 1
}

# --------------------------------------------------------- применение -------

project_clear() {
  find "$ZDY_ROOT" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} \;
}

project_copy_from() {
  local source_dir="$1"
  (cd "$source_dir" && tar -cf - .) | (cd "$ZDY_ROOT" && tar -xf -)
}

validate_update_source() {
  local source_dir="$1" required
  for required in "${ZDY_UPDATE_REQUIRED_PATHS[@]}"; do
    if [ ! -e "$source_dir/$required" ]; then
      err "В архиве обновления нет $required"
      return 1
    fi
  done
}

# Скачивает и применяет обновление.
#   0                    - уже актуально, ничего не делали
#   ZDY_UPDATE_RESTART   - обновление применено, нужен перезапуск
#   1                    - ошибка или отказ пользователя
project_update() {
  local work_dir archive source_dir current_commit latest_commit backup_dir last_backup

  msg "Обновление файлов проекта."
  plain "      Изменится только этот каталог: $ZDY_ROOT"
  hint "Состояние и резервные копии: $ZDY_STATE_DIR"
  printf '\n'

  case "$(zdy_mode)" in
    dev)
      err "Каталог проекта - это git-клон. Обновляйтесь через git pull."
      return 1
      ;;
  esac

  ask_yes_no "Continue?" y || {
    msg "Обновление отменено"
    return 1
  }

  require_cmd tar
  state_dir_init

  work_dir=$(zdy_tempdir) || return 1
  archive="$work_dir/update.tar.gz"

  msg "Скачивание архива..."
  fetch_url "$ZDY_ARCHIVE_URL" "$archive" || {
    err "Не удалось скачать архив обновления"
    return 1
  }

  tar -xzf "$archive" -C "$work_dir" || {
    err "Не удалось распаковать архив обновления"
    return 1
  }

  source_dir=$(find "$work_dir" -mindepth 1 -maxdepth 1 -type d -print | head -n 1)
  [ -n "$source_dir" ] || {
    err "Архив обновления пуст"
    return 1
  }
  validate_update_source "$source_dir" || return 1

  if trees_match "$ZDY_ROOT" "$source_dir" ".git"; then
    ok "Файлы уже актуальны, обновление не требуется"
    return 0
  fi

  current_commit=$(state_commit)
  latest_commit=$(remote_commit) || latest_commit="unknown"

  last_backup=$(backup_latest)
  if backup_matches_project "$last_backup"; then
    backup_dir="$last_backup"
    warn "Резервная копия уже актуальна: $backup_dir"
  else
    backup_dir="$ZDY_BACKUP_DIR/$(date '+%Y-%m-%d_%H-%M-%S')"
    backup_create "$backup_dir" "$current_commit" "$latest_commit" || {
      err "Не удалось создать резервную копию"
      return 1
    }
    ok "Резервная копия создана: $backup_dir"
  fi

  project_clear || {
    err "Не удалось очистить каталог проекта. Резервная копия: $backup_dir"
    return 1
  }
  project_copy_from "$source_dir" || {
    err "Не удалось скопировать новые файлы. Резервная копия: $backup_dir"
    return 1
  }

  state_set_commit "$latest_commit"
  ok "Файлы успешно обновлены"
  return "$ZDY_UPDATE_RESTART"
}

project_rollback() {
  local backup_dir from_commit

  backup_dir=$(backup_select) || return 1
  [ -n "$backup_dir" ] && [ -d "$backup_dir/files" ] || {
    warn "Нет резервной копии для отката"
    return 1
  }

  msg "Откат файлов проекта."
  plain "      Резервная копия: $backup_dir"
  plain "      Изменится только этот каталог: $ZDY_ROOT"
  printf '\n'
  ask_yes_no "Continue?" y || {
    msg "Откат отменён"
    return 1
  }

  project_clear || return 1
  project_copy_from "$backup_dir/files" || return 1

  if from_commit=$(backup_metadata_field "$backup_dir" from_commit); then
    state_set_commit "$from_commit"
  fi

  if rm -rf -- "$backup_dir"; then
    ok "Использованная резервная копия удалена"
  else
    warn "Откат выполнен, но резервную копию удалить не удалось: $backup_dir"
  fi

  ok "Откат успешно выполнен"
  return "$ZDY_UPDATE_RESTART"
}

# Печатает выбранный каталог резервной копии в stdout.
backup_select() {
  local -a backups=()
  local choice index backup

  while IFS= read -r backup; do
    [ -n "$backup" ] && backups+=("$backup")
  done < <(backup_list)

  case "${#backups[@]}" in
    0)
      warn "Резервных копий нет"
      return 1
      ;;
    1)
      printf '%s\n' "${backups[0]}"
      return 0
      ;;
  esac

  {
    printf 'Доступные резервные копии:\n'
    index=1
    for backup in "${backups[@]}"; do
      printf '%3d. %s\n' "$index" "${backup##*/}"
      index=$((index + 1))
    done
    printf '  0. Назад\n\n'
  } >&2

  ask_line "Select a backup: " choice >&2 || return 1
  [ "$choice" = "0" ] && return 1

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#backups[@]}" ]; then
    err "Неверный выбор"
    return 1
  fi

  printf '%s\n' "${backups[$((choice - 1))]}"
}
