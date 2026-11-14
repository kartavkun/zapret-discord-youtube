# 🚀 Zapret - Обход блокировок Discord и YouTube

> Зеркало: https://codeberg.org/Lintech/zapret-discord-youtube

> [!NOTE]
> **Внимание**: Этот репозиторий - **некоммерческая** *User-Friendly* сборка [оригинального проекта zapret](https://github.com/bol-van/zapret).
>
> 📡 **Ветка OpenWrt**: Адаптация для роутеров со штатной службой zapret. Используется [bol-van/zapret](https://github.com/bol-van/zapret) (nfqws).
>
> ⭐ **Поддержка проекта**: Буду очень рад [поставленной звездочке](https://github.com/kartavkun/zapret-discord-youtube/stargazers) в правом верхнем углу! 🙂

## 📄 Лицензия

Этот проект распространяется на условиях лицензии MIT.
Полный текст лицензии можно найти в файле [LICENSE](./LICENSE.txt).

## ⚡ Быстрая установка

### 📡 Для пользователей OpenWrt

**Скопируйте содержимое ветки `openwrt` на роутер** в папку `/root/zapret-configs`, подключитесь к нему по SSH и выполните:

```sh
cd /root/zapret-configs
sh setup.sh
```

> [!NOTE]
> **Заранее устанавливать пакеты не нужно.** Скрипт сам определит `opkg` или `apk`, обновит индексы и установит `curl` и `ca-bundle`. Нужны права **root** и доступ роутера в Интернет.

**Что делает скрипт установки:**

- 📦 Устанавливает зависимости через пакетный менеджер OpenWrt
- ⬇️ Скачивает релиз zapret из официального репозитория
- 🛠️ Запускает штатный `install_easy.sh` для выбора бинарников и настройки firewall
- 🎯 Применяет конфигурацию `general`
- ✅ Включает автозапуск службы `/etc/init.d/zapret`

> [!IMPORTANT]
> В официальном установщике выберите **nfqws** и подходящий firewall: для **firewall4** — **nftables**. Скрипты запускаются через `/bin/sh`; Bash, sudo и git на роутере не нужны.

> [!TIP]
> Если zapret уже установлен, скрипт пропустит скачивание и переустановку и применит `general`. Существующая папка `/opt/zapret` не удаляется.

**Установка с USB-накопителя:**

Если в оперативной памяти мало места, заранее распакуйте официальный релиз zapret на USB-накопитель и передайте путь к нему:

```sh
sh setup.sh /mnt/usb/zapret-ВАША_ВЕРСИЯ
```

Этот аргумент используется при первой установке. Для `/opt/zapret`, списков и дополнительных пакетов нужно свободное место на overlay или внешнем накопителе. Полный архив релиза требует существенно больше места, чем установленный zapret.

> [!NOTE]
> Пока ветка существует только локально, перенесите файлы на роутер вручную. Для скачивания ветки с GitHub её сначала нужно опубликовать. Запускайте `setup.sh` из папки проекта: ему нужны соседние файлы.

## 🎮 Использование

### 🔧 Выбор конфигурации

**Посмотреть доступные конфигурации:**

```sh
cd /root/zapret-configs
sh install.sh --list
```

**Применить выбранную конфигурацию:**

```sh
sh install.sh 'general (SIMPLE FAKE)'
```

**Доступные конфигурации:**

- `general` — базовая конфигурация
- `general(ALT)` и варианты — альтернативные стратегии
- `general (FAKE_TLS_AUTO)` и варианты — с автогенерацией TLS
- `general (SIMPLE FAKE)` и варианты — стратегии SIMPLE FAKE

Каждый актуальный файл в `configs/` содержит блок `NFQWS_OPT`. Общие параметры находятся в `configs/config.base`. Архивные полные Linux-конфиги из `configs/old configs` в этой ветке не применяются.

> [!TIP]
> Названия с пробелами и скобками указывайте в кавычках. Дополнительные fake-файлы выбранной стратегии скачиваются из репозитория Flowseal, если их ещё нет в установленном zapret.

### 🛡️ Проверка и резервная копия

Перед заменой `/opt/zapret/config` скрипт проверяет параметры через `nfqws --dry-run`. Предыдущая конфигурация сохраняется в `/opt/zapret/config.backup`. При ошибке команды перезапуска она восстанавливается.

**Вернуть предыдущую конфигурацию вручную:**

```sh
sh utils-zapret.sh restore
```

> [!NOTE]
> Проверка параметров не проверяет доступность сайтов. После применения откройте YouTube и Discord на устройстве, подключённом к роутеру. Списки и скачанные fake-файлы вместе с config не откатываются.

## 🗒️ Добавление адресов прочих ресурсов

Списки установленного zapret находятся в `/opt/zapret/hostlists/`:

- **`list-general-user.txt`** — дополнительные домены для обхода
- **`list-exclude-user.txt`** — исключения доменов
- **`ipset-exclude-user.txt`** — исключения IP-адресов и подсетей

**Пример добавления домена:**

```sh
printf '%s\n' 'example.com' >> /opt/zapret/hostlists/list-general-user.txt
/etc/init.d/zapret restart
```

Пользовательские файлы `*-user.txt` и состояние игрового фильтра сохраняются при переключении конфигурации. Остальные списки обновляются из локальной копии проекта.

## 🎛️ Управление и тестирование

### 🔄 Управление режимами

**Доступные команды:**

| Команда | Описание |
|---------|----------|
| `sh utils-zapret.sh list` | Показать конфигурации |
| `sh utils-zapret.sh switch 'general(ALT)'` | Переключить конфигурацию |
| `sh utils-zapret.sh status` | Проверить состояние службы |
| `sh utils-zapret.sh restart` | Перезапустить zapret |
| `sh utils-zapret.sh log` | Показать журнал zapret |
| `sh utils-zapret.sh restore` | Восстановить предыдущий config |

**GameFilter:**

| Команда | Режим |
|---------|-------|
| `sh utils-zapret.sh game off` | Выключен (по умолчанию) |
| `sh utils-zapret.sh game tcp` | Игровые порты TCP |
| `sh utils-zapret.sh game udp` | Игровые порты UDP |
| `sh utils-zapret.sh game all` | Игровые порты TCP и UDP |

> [!WARNING]
> GameFilter обрабатывает порты **1024–65535** выбранных протоколов и увеличивает нагрузку на роутер.

### 🔄 Обновление репозитория

Обновите файлы в `/root/zapret-configs` из ветки **`openwrt`**, затем повторно примените нужную конфигурацию через `install.sh`.

> [!IMPORTANT]
> Используйте именно ветку **`openwrt`**. Скрипты ветки `main` предназначены для настольных Linux-систем. Автоматическое обновление проекта в этой версии не предусмотрено.

## 🛠️ Управление службой

**Штатные команды OpenWrt:**

```sh
/etc/init.d/zapret start
/etc/init.d/zapret stop
/etc/init.d/zapret restart
/etc/init.d/zapret status
/etc/init.d/zapret enable
/etc/init.d/zapret disable
```

**Если хотите удалить zapret:**

```sh
sh /opt/zapret/uninstall_easy.sh
```

### 🌐 Настройка сети роутера

По умолчанию firewall определяется средствами zapret, IPv6 разрешён, а лимиты ipset и число потоков DNS уменьшены для роутеров.

Для своих сетей создайте файл **`/opt/zapret/config.router`**, например:

```sh
OPENWRT_LAN="lan guest"
# При необходимости укажите логические интерфейсы OpenWrt:
# OPENWRT_WAN4="wan"
# OPENWRT_WAN6="wan6"
# DISABLE_IPV6=1
# FLOWOFFLOAD=software
```

После изменения файла повторно примените выбранную конфигурацию:

```sh
cd /root/zapret-configs
sh install.sh general
```

> [!IMPORTANT]
> Если у вас уже настроен zapret, перед первым применением перенесите индивидуальные параметры сети из `/opt/zapret/config` в `config.router`. Этот файл добавляется после общей части конфигурации и сохраняется при переключении стратегий.

> [!NOTE]
> По умолчанию используется `FLOWOFFLOAD=none`: zapret отключает flow offloading, чтобы трафик не обходил NFQUEUE. Это может снизить скорость маршрутизации.

## ✅ Протестировано на

| Среда | Статус | Примечания |
|-------|--------|------------|
| Локальные проверки | ✅ Пройдены | Генерация актуальных конфигураций, сохранение списков, откат и установка зависимостей с заглушками |
| Роутер с OpenWrt | 🧪 Ожидает проверки | На реальном устройстве пока не проверено |

## ❓ Решение проблем

**Частые проблемы:**

1. **Права доступа** — запускайте скрипты от **root**.
2. **Не устанавливаются зависимости** — проверьте доступ роутера в Интернет и доступность репозиториев `opkg` или `apk`.
3. **Не хватает памяти при скачивании** — используйте распакованный релиз на USB-накопителе.
4. **Ошибка проверки конфигурации** — проверьте сообщение `nfqws`: возможны неподдерживаемые параметры или отсутствующие файлы. Прежний config при такой ошибке сохраняется.
5. **Обход не работает** — попробуйте другую конфигурацию и проверьте журнал командой `sh utils-zapret.sh log`.

> [!IMPORTANT]
> **Стратегии зависят от провайдера и могут переставать работать.** Попробуйте альтернативные варианты из `configs/`. Если ни один не помогает, потребуется подобрать параметры под ваше подключение.

**Для сложных случаев:**

- 📖 [Официальная документация zapret](https://github.com/bol-van/zapret/blob/master/docs/readme.md)
- 🛠️ [Официальный установщик](https://github.com/bol-van/zapret/blob/master/install_easy.sh)
- 🐛 [Вопросы по оригинальному zapret](https://github.com/bol-van/zapret/issues)

## 💝 Поддержка проекта

- ⭐ **Поставить звездочку** репозиторию (вверху страницы)
- 💰 **[Поддержать разработчика](https://t.me/kartavslinks/8)**
- 🐛 **Сообщить о багах** и предложить улучшения

**Поддержите оригинального разработчика zapret:**
https://github.com/bol-van/zapret/issues/590

## 📈 История звезд

<a href="https://star-history.dera.page/#kartavkun/zapret-discord-youtube&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://star-history.dera.page/svg?repos=kartavkun/zapret-discord-youtube&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://star-history.dera.page/svg?repos=kartavkun/zapret-discord-youtube&type=Date" />
    <img alt="Star History Chart" src="https://star-history.dera.page/svg?repos=kartavkun/zapret-discord-youtube&type=Date" />
  </picture>
</a>

## 🙏 Благодарности

- **[@bol-van](https://github.com/bol-van/)** - создатель оригинального [zapret](https://github.com/bol-van/zapret/)
- **[@Flowseal](https://github.com/Flowseal)** - за конфигурации для Windows и Linux
- **Сообществу** - за тестирование и обратную связь

### 🩷 Контрибьюторы

[![Contributors](https://contrib.rocks/image?repo=kartavkun/zapret-discord-youtube)](https://github.com/kartavkun/zapret-discord-youtube/graphs/contributors)

---

**🚀 Наслаждайтесь свободным интернетом!**
