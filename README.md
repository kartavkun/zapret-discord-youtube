# 🚀 Zapret - Обход блокировок Discord и YouTube

> Зеркало: https://codeberg.org/Lintech/zapret-discord-youtube

> [!NOTE]
> **Внимание**: Этот репозиторий — **некоммерческая** *User-Friendly* сборка [оригинального проекта zapret](https://github.com/bol-van/zapret).
>
> 🔒 **Безопасность**: Используются оригинальные бинарники с проверяемыми хэшами. Так как zapret — open-source, вы всегда можете самостоятельно собрать бинарники из исходного кода.
>
> ⭐ **Поддержка проекта**: Буду очень рад [поставленной звездочке](https://github.com/kartavkun/zapret-discord-youtube/stargazers) в правом верхнем углу! 🙂

## 📄 Лицензия

Этот проект распространяется на условиях лицензии MIT.
Полный текст лицензии можно найти в файле [LICENSE](./LICENSE.txt).

## ⚡ Быстрая установка

### 🐧 Для пользователей Linux

**Автоматическая установка одной командой:**

```bash
bash <(curl -s https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/setup.sh)
```

> [!TIP]
> Если команда выше не работает, попробуйте альтернативный вариант:
> ```bash
> bash <(curl -s https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/setup.sh | psub)
> ```

**Что делает скрипт установки:**
- ✅ Автоматически определяет ваш дистрибутив Linux
- 📦 Устанавливает необходимые зависимости (wget, git)
- ⬇️ Скачивает последнюю версию zapret с официального репозитория
- 🛠️ Настраивает систему для работы zapret
- 🎯 Предлагает интерактивный выбор конфигурации

## ❄️ Для пользователей NixOS

> [!IMPORTANT]
> Каждая конфигурация NixOS уникальна, поэтому пример ниже нужно адаптировать под вашу систему. Используйте его только как ориентир.

> [!NOTE]
> Для поддержки Flake в NixOS добавьте следующую строку в файл `/etc/nixos/configuration.nix` (см. подробнее [Flakes](https://wiki.nixos.org/wiki/Flakes/ru))

**Включите поддержку Flakes в вашем конфиге:**
```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

**Пример интеграции в ваш `flake.nix` (можете его поместить в `/etc/nixos/flake.nix`):**
```nix
{
  description = "NixOS configuration with zapret-discord-youtube";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"; # Укажите свою версию NixOS, но не ниже 25.11.
    zapret-discord-youtube.url = "github:kartavkun/zapret-discord-youtube";
  };

  outputs = { self, nixpkgs, zapret-discord-youtube }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix

        zapret-discord-youtube.nixosModules.withTestTools
        {
          services.zapret-discord-youtube = {
            enable = true;
            strategyName = "general-alt";  # Любое имя из strategies: general, general-alt … general-alt-12,
                                         # general-fake-tls-auto*, general-simple-fake*, general-exp

            # Game Filter: "null" (отключен), "all" (TCP+UDP), "tcp" (только TCP), "udp" (только UDP)
            gameFilter = "null";  # или "all", "tcp", "udp"

            # Добавляем кастомные домены в list-general-user.txt
            listGeneral = [ "example.com" "test.org" "mysite.net" ];

            # Добавляем домены в list-exclude-user.txt (исключения)
            listExclude = [ "ubisoft.com" "origin.com" ];

            # Добавляем IP адреса в ipset-all.txt
            ipsetAll = [ "192.168.1.0/24" "10.0.0.1" ];

            # Добавляем IP адреса в ipset-exclude-user.txt (исключения)
            ipsetExclude = [ "203.0.113.0/24" ];

            # Необязательно: пользовательские hostlists и конфиги.
            # extraHostlists может содержать несколько файлов.
            # Если нужен пример для GitHub, раскомментируйте блок ниже
            # и оставьте в configName выбранный вами готовый конфиг.
            #
            # extraHostlists."list-github.txt" = [
            #   "github.com"
            #   "api.github.com"
            #   "raw.githubusercontent.com"
            #   "objects.githubusercontent.com"
            #   "githubusercontent.com"
            #   "githubassets.com"
            # ];
            #
            # extraHostlists."list-custom.txt" = [
            #   "example.com"
            #   "example.org"
            # ];
            #
            # nfqwsAppend = [
            #   ''--filter-tcp=443 --hostlist="/opt/zapret/hostlists/list-github.txt" --dpi-desync=multisplit --dpi-desync-split-pos=2''
            # ];
            #
            # Для полностью ручного конфига можно создать отдельный файл:
            # extraConfigs."my-custom-config" = ''
            #   NFQWS_ENABLE=1
            #   NFQWS_OPT="
            #   --filter-tcp=443 --hostlist="/opt/zapret/hostlists/list-github.txt" --dpi-desync=multisplit --dpi-desync-split-pos=2
            #   "
            # '';
          };
        }
      ];
    };
  };
}
```

> [!TIP]
> Применение Zapret в сочетании с [Encrypted DNS](https://nixos.wiki/wiki/Encrypted_DNS) или [DNScrypt-proxy](https://github.com/DNSCrypt/dnscrypt-proxy) также может помочь вам получить доступ к сайтам.

**Тестирование стратегий на NixOS:**

Так как `/nix/store` доступен только для чтения, подключите модуль с тестовыми инструментами:

```nix
zapret-discord-youtube.nixosModules.withTestTools
```

После `nixos-rebuild switch` запустите:

```bash
sudo zapret-test-strategies
```

Утилита создаёт временную writable-копию zapret в `/run/zapret-discord-youtube-test`, пишет логи в `/var/log/zapret-discord-youtube-test` и после теста возвращает основной сервис. Основные результаты сохраняются в файлах `test-zapret-*.txt`, а вывод перезапуска zapret — в `restart.log`.

Если тестовые инструменты не нужны, используйте обычный модуль:

```nix
zapret-discord-youtube.nixosModules.default
```

## 🎮 Использование

### 🔧 Выбор конфигурации

После установки запустите меню выбора конфигурации:

```bash
zapret-config
```

Или если вы устанавливали alias:
```bash
zapret-config
```

**Доступные стратегии:**
- `general` — базовая конфигурация
- `general-alt` … `general-alt-12` — альтернативные варианты
- `general-fake-tls-auto`, `-alt`, `-alt-2`, `-alt-3` — с автогенерацией TLS
- `general-simple-fake`, `-alt`, `-alt-2` — оптимизировано для МГТС
- `general-exp` — экспериментальная

Полный список: `zapret-config --list`

> [!NOTE]
> Имена приведены к единому виду. Старые (`general(ALT)`, `general (SIMPLE FAKE)`)
> пока принимаются и в `zapret-config`, и в `strategyName` для NixOS, но выводят
> предупреждение и будут удалены через два релиза.

### Как это устроено

Стратегия больше не подменяет `/opt/zapret/config`. Общий `config` — это
загрузчик: при старте службы он читает имя стратегии из
`/opt/zapret/zapret.strategy`, список включённых фиксов из
`/opt/zapret/zapret.fixes`, и собирает `NFQWS_OPT` сам. Поэтому фрагмент
стратегии — это 11 строк, а не 168, и общие параметры правятся в одном месте.

Файл `/opt/zapret/config` можно править руками: обновление увидит, что он
отличается от версии в проекте, оставит ваш вариант и положит рядом
`config.new`.

### Фиксы

Фикс — это набор правил, который добавляется к любой стратегии независимо от
того, какая выбрана. В комплекте идёт `hypixel` (Minecraft на порту 25565).
Включаются в `zapret-manager` → «Стратегия и фиксы».

Свой фикс — файл в `/opt/zapret/fixes/`:

```sh
FIX_TCP_PORTS="25565"

FIX_NFQWS_OPT="
--filter-tcp=25565 --dpi-desync=multisplit --dpi-desync-split-pos=1
"
```

`FIX_TCP_PORTS` и `FIX_UDP_PORTS` нужны, только если фикс работает на портах,
которых нет в базовом списке — загрузчик добавит их сам. Файлы, положенные
напрямую в `/opt/zapret/fixes/`, обновление проекта не удаляет.

> [!IMPORTANT]
> После выбора конфигурации скрипт запустит `install_easy.sh`, который будет запрашивать подтверждение - **просто нажимайте ENTER для принятия значений по умолчанию.**

> [!TIP]
> В некоторых экзотических дистрибутивах может быть такое сообщение:
>
> ```bash
> * checking readonly system
> !!! READONLY SYSTEM DETECTED !!!
> !!! WILL NOT BE ABLE TO CONFIGURE STARTUP !!!
> !!! MANUAL STARTUP CONFIGURATION IS REQUIRED !!!
> do you want to continue (default: N) (Y/N)?
> ```
> Выбирайте **Y** чтобы установить zapret

## 📁 Где что лежит

| Что | Путь |
|---|---|
| Копия проекта | `~/.local/share/zapret-discord-youtube` |
| Состояние, бэкапы, логи, снимки | `~/.local/state/zapret-discord-youtube` |
| Загрузки | `~/.cache/zapret-discord-youtube` |
| Команды | `~/.local/bin/zapret-{config,manager,restart}` |
| Сам zapret | `/opt/zapret` (владелец root) |

Перенести проект в другое место: переменная `ZAPRET_DY_HOME`.

> [!NOTE]
> Раньше всё лежало в `~/zapret-configs`. При первом запуске новой версии
> `zapret-setup` перенесёт файлы сам и уберёт устаревшие алиасы из конфига
> оболочки.

## 🔁 Если Discord отвалился

Самое быстрое — перезапустить службу:

```bash
zapret-manager restart
```

Перед перезапуском автоматически сохраняется снимок состояния в
`~/.local/state/zapret-discord-youtube/incidents/`. Он нужен, чтобы однажды
найти причину: перезапуск лечит симптом и одновременно стирает улики.

Если это происходит регулярно, можно включить плановый перезапуск:

```bash
zapret-manager autorestart on 12    # раз в 12 часов
zapret-manager autorestart off
```

> [!WARNING]
> Это обходная мера, а не исправление. Перезапуск рвёт активные соединения,
> поэтому рано или поздно попадёт в момент разговора. Требуется systemd.
> Прежде чем включать, стоит обновить список IPSet — устаревшие адреса
> Discord дают ровно такой же симптом.

## 🧩 Как устроены стратегии

Раньше каждая стратегия была самостоятельным конфигом на 168 строк, из которых
160 совпадали. Теперь есть один общий загрузчик `/opt/zapret/config` и
фрагменты по 11 строк в `strategies/`. Загрузчик при старте службы читает имя
стратегии из `/opt/zapret/zapret.strategy`, список включённых фиксов из
`/opt/zapret/zapret.fixes` и собирает `NFQWS_OPT` сам.

Смена стратегии — это запись одной строки и перезапуск службы, а не подмена
файла конфигурации.

### Фиксы

`fixes/` — независимые дополнения поверх любой стратегии. Например, `hypixel`
добавляет обработку порта 25565 для Minecraft. Включаются в
`zapret-manager` → «Фиксы».

Свой фикс — это файл в `/opt/zapret/fixes/` вида:

```sh
FIX_TCP_PORTS="25565"

FIX_NFQWS_OPT="
--filter-tcp=25565 --dpi-desync=multisplit --dpi-desync-split-pos=1 --new
"
```

Загрузчик сам добавит порты к общему списку и склеит правила со стратегией.
Имя файла — только буквы, цифры, точка, дефис и подчёркивание. Фиксы,
положенные напрямую в `/opt/zapret/fixes/`, обновление проекта не удаляет.

### Свой config

`/opt/zapret/config` можно править руками. При обновлении проверяется
контрольная сумма: если файл не трогали, он обновится сам; если правили,
останется ваш, а рядом появится `config.new` для сравнения.

## 🗑️ Удаление

```bash
zapret-setup --uninstall           # всё, кроме состояния и снимков
zapret-setup --uninstall --purge   # вместе с состоянием
```

Перед удалением выводится полный список того, что будет удалено.

## 🩺 Диагностика

```bash
zapret-manager doctor    # модули ядра, счётчики nfqueue, давность списков
zapret-manager report    # то же самое плюс последний снимок - одним файлом
```

`report` создаёт файл, который можно приложить к issue. Проверьте его перед
отправкой: там есть адреса из conntrack.

## 🗒️ Добавление адресов прочих ресурсов

Список адресов для обхода можно расширить, добавляя их в:
- **`hostlists/list-general-user.txt`** — для доменов (поддомены автоматически учитываются)
- **`hostlists/list-exclude-user.txt`** — для исключения доменов (если IP сети указан в `ipset-all.txt`, но конкретный домен не надо фильтровать)
- **`hostlists/ipset-exclude-user.txt`** — для исключения IP адресов и подсетей

**Быстрое добавление доменов через меню:**

Используйте встроенное меню для добавления доменов:

```bash
zapret-manager
```

Выберите пункт **"5. Добавить домен в список"** и следуйте подсказкам. Вы можете добавлять:
- Отдельные домены: `example.com`
- URL: `https://github.com/user/repo` (будет извлечён `github.com`)
- Поддомены: `sub.example.com`


## 🎛️ Управление и тестирование

### 🔄 Управление режимами

Для удобного переключения режимов ipset, GameFilter и управления конфигурациями используйте:

```bash
zapret-manager
```

Или если вы установили alias:

```bash
zapret-utils
```

**Доступные функции:**

| Функция | Описание |
|---------|---------|
| **IPSet режимы** | Переключение между режимами фильтрации (any, none, loaded) |
| **GameFilter** | Включение/отключение обработки игровых портов с выбором режима (TCP, UDP, TCP+UDP) |
| **Обновление IPSet** | Загрузка актуального списка IP адресов из репозитория |
| **Обновление hosts** | Загрузка актуального файла hosts для корректной работы Discord |
| **Добавление доменов** | Быстрое добавление новых доменов в list-general-user.txt или list-exclude-user.txt |
| **Тестирование конфигов** | Проверка работоспособности конфигураций |

**Режимы IPSet:**
- `loaded` — использует полный список доменов и IP (рекомендуется)
- `none` — обходит только тестовый IP (минимальная нагрузка, для отладки)
- `any` — пустой список (zapret отключен)

**GameFilter:**
- `Отключен` — игровые порты не обрабатываются (только порт 12)
- `TCP и UDP` — обрабатывает игровые порты 1024-65535 для обоих протоколов
- `Только TCP` — обрабатывает игровые порты 1024-65535 только для TCP
- `Только UDP` — обрабатывает игровые порты 1024-65535 только для UDP

### 🧪 Тестирование конфигураций

Для проверки работоспособности конфигураций используйте меню управления:

```bash
zapret-manager
```

Для работы тестов нужен установленный [lua](https://www.lua.org/). Выберите пункт **"9. Запустить тесты"** и следуйте подсказкам.

**Тестер проверяет:**
- Доступность целевых сайтов (HTTP, TLS 1.2, TLS 1.3)
- Обход DPI блокировок на различных провайдерах
- Результаты сохраняются в `~/.local/state/zapret-discord-youtube/log/`

### 🔄 Обновление репозитория

```bash
zapret-manager
```

Выберите пункт **"6. Обновить файлы проекта"**. Обновление меняет только файлы в `~/.local/share/zapret-discord-youtube`.

> [!WARNING]
> Если текущая конфигурация работает идеально, обновляйтесь только если текущая конфигурация перестала работать или вы хотите попробовать новые конфигурации.

**Откат на предыдущую версию:**
Запустите `zapret-manager` и выберите пункт **"7. Откатить последнее обновление"**.

## 🛠️ Управление службой

**Если хотите удалить zapret:**
```bash
sudo /opt/zapret/uninstall_easy.sh
```

## 💡 Расширение функциональности

Хотите добавить обход для других сайтов? Ознакомьтесь с [личным руководством от kartavkun](https://github.com/kartavkun/zapret-discord-youtube/discussions/2#discussion-7902158). Конструктивная критика и предложения приветствуются!

## ✅ Протестировано на

| Дистрибутив                                                                                           | Статус                | Примечания         |
|-------------------------------------------------------------------------------------------------------|-----------------------|--------------------|
| ![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?logo=arch-linux&logoColor=white)         | ✅ Полностью          | "I use Arch btw"   |
| ![Artix Linux](https://img.shields.io/badge/Artix_Linux-10A0CC?logo=artix-linux&logoColor=white)      | ✅ Полностью          | OpenRC/runit/s6/dinit |
| ![Chimera Linux](https://img.shields.io/badge/Chimera_Linux-EF2D5E?logo=linux&logoColor=white)        | ✅ Полностью          | dinit              |
| ![Void Linux](https://img.shields.io/badge/Void_Linux-478061?logo=void-linux&logoColor=white)         | ✅ Полностью          | runit              |
| ![Slackware](https://img.shields.io/badge/Slackware-4B0062?logo=slackware&logoColor=white)            | ✅ Полностью          | sysVinit           |
| ![Alpine Linux](https://img.shields.io/badge/Alpine_Linux-0D597F?logo=alpine-linux&logoColor=white)   | ✅ Полностью          | OpenRC             |
| ![Gentoo](https://img.shields.io/badge/Gentoo-54487A?logo=gentoo&logoColor=white)                     | ✅ Полностью          | OpenRC             |
| ![Solus](https://img.shields.io/badge/Solus-5294E2?logo=solus&logoColor=white)                        | ✅ Полностью          | Systemd            |
| ![ALT Linux](https://img.shields.io/badge/ALT_Linux-0066CC?logo=linux&logoColor=white)                | ✅ Полностью          | Systemd            |
| ![Ximper Linux](https://img.shields.io/badge/Ximper_Linux-FF6600?logo=linux&logoColor=white)          | ✅ Полностью          | Systemd            |
| ![AntiX Linux](https://img.shields.io/badge/AntiX_Linux-0078D7?logo=debian&logoColor=white)           | ✅ Полностью          | sysVinit / runit   |
| ![Pop!_OS](https://img.shields.io/badge/Pop!_OS-48B9C7?logo=popos&logoColor=white)                    | ✅ Полностью          | Systemd            |
| ![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)                     | ✅ 18.04+             | Systemd            |
| ![Kubuntu](https://img.shields.io/badge/Kubuntu-0079C1?logo=kubuntu&logoColor=white)                  | ✅ Полностью          | Systemd            |
| ![Fedora](https://img.shields.io/badge/Fedora-blue?logo=Fedora&logoColor=white)                       | ✅ Полностью          | Systemd            |
| ![Fedora Silverblue](https://img.shields.io/badge/Fedora_Silverblue-51A2DA?logo=Fedora&logoColor=white) | ✅ Полностью        | Systemd (immutable) |
| ![Secureblue](https://img.shields.io/badge/Secureblue-4B0082?logo=Fedora&logoColor=white)             | ✅ Полностью          | Systemd (immutable) |
| ![Bazzite](https://img.shields.io/badge/Bazzite-8A2BE2)                                               | ✅ Полностью          | Systemd            |
| ![OpenSUSE](https://img.shields.io/badge/openSUSE-73BA25?logo=opensuse&logoColor=white)               | ✅ Полностью          | Systemd            |
| ![NixOS](https://img.shields.io/badge/NixOS-5277C3?logo=nixos&logoColor=white)                        | 🧪 Экспериментально   | Через Flake        |

## ❓ Решение проблем

**Частые проблемы:**

1. **Права доступа** — запускайте скрипты с правами root
2. **Бесконечное "подключение" к Discord** — `zapret-manager` → пункт 5 (файл hosts)
3. **Обход не работает / перестал работать** — попробуйте следующие шаги:
   - Сначала попробуйте альтернативные конфигурации (ALT, FAKE и т.д.) через `zapret-config`
   - Обновите IPSet через `zapret-manager` → пункт 4 (обновить список IPSet)
   - Проверьте режим IPSet через `zapret-manager` → пункт 2 (режим `loaded`)
   - Запустите `zapret-manager doctor` — он проверит модули ядра, счётчики очереди,
     давность списков и наличие файлов, на которые ссылается стратегия
   - Запустите тесты стратегий через `zapret-manager` → пункт 9
   - Если ничего не помогает, попробуйте создать новую конфигурацию на основе одной из существующих

> [!IMPORTANT]
> **Стратегии со временем могут переставать работать.** Определенная стратегия может работать какое-то время, но со временем она может переставать работать из-за обнаружения. В репозитории представлены множество различных стратегий для обхода. Если ни одна из них вам не помогает, то вам необходимо создать новую, взяв за основу одну из представленных здесь и изменив её параметры.

**Для сложных случаев:**
- Вопросы по Linux: [оригинальный репозиторий zapret](https://github.com/bol-van/zapret/issues)
- Вопросы по Windows: [репозиторий Flowseal](https://github.com/Flowseal/zapret-discord-youtube/issues)

## 💝 Поддержка проекта

- ⭐ **Поставить звездочку** репозиторию (вверху страницы)
- 💰 **[Поддержать разработчика](https://t.me/kartavslinks/8)**
- 🐛 **Сообщить о багах** и предложить улучшения

**Поддержите оригинального разработчика zapret:**
https://github.com/bol-van/zapret/issues/590

## 📈 История звезд

<a href="https://star-history.com/#kartavkun/zapret-discord-youtube&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=kartavkun/zapret-discord-youtube&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=kartavkun/zapret-discord-youtube&type=Date" />
    <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=kartavkun/zapret-discord-youtube&type=Date" />
  </picture>
</a>

## 🖨️ Вывод

Весь вывод скриптов на английском и использует только ASCII — так он
одинаково выглядит в любом терминале и не ломается в шрифтах без нужных
глифов:

```
[ + ]  успешно
[ - ]  ошибка
[ ! ]  предупреждение
[ * ]  выполняется
[ i ]  подсказка
[ > ]  запрос ввода
[dry]  сухой режим, команда не выполняется
```

Комментарии в коде и эта документация остаются на русском.

## 🧰 Для разработчиков

```bash
bash tests/run.sh               # тесты, без внешних зависимостей
bash tools/lint-portability.sh  # запрещённые непереносимые конструкции
shellcheck bin/zapret-* lib/*.sh
```

Структура: `bin/` — команды, `lib/` — общие модули, `configs/` — стратегии,
`tools/` — мейнтейнерские скрипты, `tests/` — тесты.

### Проверка на своём форке

Все внешние адреса переопределяются переменными окружения, поэтому установку и
обновление можно гонять против форка:

```bash
export ZDY_REPO_SLUG="ваш-логин/zapret-discord-youtube"
export ZDY_BRANCH="test"
bash <(curl -fsSL "https://raw.githubusercontent.com/$ZDY_REPO_SLUG/$ZDY_BRANCH/setup.sh")
```

| Переменная | Что задаёт |
|---|---|
| `ZDY_REPO_SLUG` | репозиторий проекта |
| `ZDY_BRANCH` | ветка |
| `ZDY_ARCHIVE_URL` | прямой адрес архива, если нужен не GitHub |
| `ZDY_FLOWSEAL_SLUG` | источник списков и `.bin` |
| `ZDY_ZAPRET_URL` | прямой адрес релиза zapret |
| `ZAPRET_DY_HOME` | куда ставить копию проекта |
| `ZAPRET_DIR` | куда ставить сам zapret |

Контрольные суммы загружаемых файлов лежат в `zapret.lock` и обновляются
через `tools/update-lock.sh`. Пока они не заполнены, установка выводит
предупреждение; `zapret-setup --strict` превращает его в отказ.

## 🙏 Благодарности

- **[@bol-van](https://github.com/bol-van/)** — создатель оригинального [zapret](https://github.com/bol-van/zapret/)
- **[@Flowseal](https://github.com/Flowseal)** — за конфигурации для Windows и Linux
- **Сообществу** — за тестирование и обратную связь

### 🩷 Контрибьюторы

[![Contributors](https://contrib.rocks/image?repo=kartavkun/zapret-discord-youtube)](https://github.com/kartavkun/zapret-discord-youtube/graphs/contributors)

---

**🚀 Наслаждайтесь свободным интернетом!**
