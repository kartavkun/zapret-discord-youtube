#!/usr/bin/env bash
#
# УСТАРЕЛО. Будет удалён через два релиза после выхода версии с bin/.
#
# Оставлен по двум причинам:
#   1. алиас zapret-config у уже установленных пользователей указывает сюда;
#   2. апдейтер прежних версий отказывается ставить обновление, если не
#      находит в архиве install.sh, setup.sh и utils-zapret.sh - убрав их
#      сразу, мы навсегда лишили бы обновлений всех, кто ещё не перешёл.
#
# Актуальная команда: zapret-config
set -euo pipefail

SELF_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

printf '[ ! ] install.sh устарел, используйте команду zapret-config\n' >&2

exec "$SELF_DIR/bin/zapret-config" "$@"
