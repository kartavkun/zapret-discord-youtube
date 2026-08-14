# 🚀 Zapret - Обход блокировок Discord и YouTube

> Зеркало: https://codeberg.org/Lintech/zapret-discord-youtube

> [!NOTE]
> Этот репозиторий — **некоммерческая** *User-Friendly* сборка [оригинального проекта zapret](https://github.com/bol-van/zapret).
>
> 🔒 **Безопасность**: используются оригинальные бинарники, версии и контрольные суммы зафиксированы в [`zapret.lock`](./zapret.lock). Так как zapret — open-source, вы всегда можете собрать бинарники из исходного кода сами.
>
> ⭐ **Поддержка проекта**: буду очень рад [поставленной звёздочке](https://github.com/kartavkun/zapret-discord-youtube/stargazers) в правом верхнем углу! 🙂

## ⚡ Установка

```bash
bash <(curl -s https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/setup.sh)
```

> [!TIP]
> Если команда выше не работает в fish, попробуйте:
> ```bash
> bash <(curl -s https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/setup.sh | psub)
> ```

Скрипт определит дистрибутив, поставит зависимости, скачает zapret, настроит
службу и предложит выбрать стратегию обхода.

**Пользователям NixOS** — отдельная инструкция: [docs/nixos.md](docs/nixos.md).

> [!IMPORTANT]
> В процессе запустится `install_easy.sh` от zapret — он задаёт вопросы,
> **просто нажимайте ENTER**. Если увидите `!!! READONLY SYSTEM DETECTED !!!`,
> отвечайте **Y**.

## 🎮 Три команды, которые нужны

```bash
zapret-config     # выбрать стратегию обхода
zapret-manager    # меню: режимы, фиксы, обновления, диагностика
zapret-restart    # быстро перезапустить службу, если что-то отвалилось
```

**Доступные стратегии:**

- `general` — базовая
- `general-alt` … `general-alt-12` — альтернативные варианты
- `general-fake-tls-auto`, `-alt`, `-alt-2`, `-alt-3` — с автогенерацией TLS
- `general-simple-fake`, `-alt`, `-alt-2` — для МГТС
- `general-exp` — экспериментальная

Полный список: `zapret-config --list`.

> [!IMPORTANT]
> **Стратегии со временем перестают работать** — это нормально. Провайдер
> учится их распознавать. Если обход сломался, первым делом попробуйте
> другую стратегию.

Подробнее о том, как устроены стратегии и фиксы, как добавить свои домены и
как тестировать конфигурации: [docs/usage.md](docs/usage.md).

## 🔁 Что-то перестало работать

```bash
zapret-manager restart   # чаще всего этого достаточно
zapret-manager doctor    # если не помогло - диагностика
```

Дальше по порядку: другая стратегия через `zapret-config`, обновление списка
IPSet и файла hosts через `zapret-manager`. Разбор частых случаев —
[docs/troubleshooting.md](docs/troubleshooting.md).

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

## 🗑️ Удаление

```bash
zapret-setup --uninstall           # всё, кроме состояния и снимков
zapret-setup --uninstall --purge   # вместе с состоянием
```

Перед удалением выводится полный список того, что будет удалено.

## 📚 Документация

| Документ | О чём |
|---|---|
| [docs/usage.md](docs/usage.md) | стратегии, фиксы, свои домены, режимы, тестирование |
| [docs/troubleshooting.md](docs/troubleshooting.md) | диагностика и частые проблемы |
| [docs/nixos.md](docs/nixos.md) | установка и настройка на NixOS |
| [docs/development.md](docs/development.md) | тесты, линтеры, проверка на форке |
| [CHANGELOG.md](CHANGELOG.md) | что изменилось между версиями |

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

## 📄 Лицензия

MIT, полный текст — в [LICENSE](./LICENSE.txt).

## 🙏 Благодарности

- **[@bol-van](https://github.com/bol-van/)** — создатель оригинального [zapret](https://github.com/bol-van/zapret/)
- **[@Flowseal](https://github.com/Flowseal)** — за конфигурации для Windows и Linux
- **Сообществу** — за тестирование и обратную связь

### 🩷 Контрибьюторы

[![Contributors](https://contrib.rocks/image?repo=kartavkun/zapret-discord-youtube)](https://github.com/kartavkun/zapret-discord-youtube/graphs/contributors)

---

**🚀 Наслаждайтесь свободным интернетом!**
