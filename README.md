# 🚀 Zapret - Обход блокировок Discord и YouTube

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

**Автоматическая установка одним командой:**

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
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zapret-discord-youtube.url = "github:kartavkun/zapret-discord-youtube";
  };

  outputs = { self, nixpkgs, zapret-discord-youtube }: {
    nixosConfigurations.your-hostname = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix

        zapret-discord-youtube.nixosModules.default
        {
          services.zapret-discord-youtube = {
            enable = true;
            config = "general(ALT)";  # Или любой конфиг из папки configs (general, general(ALT), general (SIMPLE FAKE) и т.д.)
            
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
          };
        }
      ];
    };
  };
}
```

> [!TIP]
> Применение Zapret в сочетании с [Encrypted DNS](https://nixos.wiki/wiki/Encrypted_DNS) или [DNScrypt-proxy](https://github.com/DNSCrypt/dnscrypt-proxy) также может помочь вам получить доступ к сайтам.

## 🎮 Использование

### 🔧 Выбор конфигурации

После установки запустите меню выбора конфигурации:

```bash
$HOME/zapret-configs/install.sh
```

Или если вы устанавливали alias:
```bash
zapret-config
```

**Доступные конфигурации:**
- `general` — базовая конфигурация
- `general(ALT)` до `general(ALT11)` — альтернативные варианты
- `general (FAKE_TLS_AUTO)` и варианты — с автогенерацией TLS
- `general (SIMPLE FAKE)` — оптимизировано для МГТС

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

## 🗒️ Добавление адресов прочих ресурсов

Список адресов для обхода можно расширить, добавляя их в:
- **`hostlists/list-general-user.txt`** — для доменов (поддомены автоматически учитываются)
- **`hostlists/list-exclude-user.txt`** — для исключения доменов (если IP сети указан в `ipset-all.txt`, но конкретный домен не надо фильтровать)
- **`hostlists/ipset-exclude-user.txt`** — для исключения IP адресов и подсетей

**Быстрое добавление доменов через меню:**

Используйте встроенное меню для добавления доменов:

```bash
$HOME/zapret-configs/utils-zapret.sh
```

Выберите пункт **"5. Добавить домен в список"** и следуйте подсказкам. Вы можете добавлять:
- Отдельные домены: `example.com`
- URL: `https://github.com/user/repo` (будет извлечён `github.com`)
- Поддомены: `sub.example.com`


## 🎛️ Управление и тестирование

### 🔄 Управление режимами

Для удобного переключения режимов ipset, GameFilter и управления конфигурациями используйте:

```bash
$HOME/zapret-configs/utils-zapret.sh
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
$HOME/zapret-configs/utils-zapret.sh
```

Выберите пункт **"6. Запустить тесты"** и следуйте подсказкам.

**Тестер проверяет:**
- Доступность целевых сайтов (HTTP, TLS 1.2, TLS 1.3)
- Обход DPI блокировок на различных провайдерах
- Результаты сохраняются в `$HOME/zapret-configs/utils/log/`

### 🔄 Обновление репозитория

```bash
cd $HOME/zapret-configs && git pull --rebase
```

> [!WARNING]
> Если текущая конфигурация работает идеально, обновляйтесь только если текущая конфигурация перестала работать или вы хотите попробовать новые конфигурации.

**Откат на предыдущую версию:**
```bash
cd $HOME/zapret-configs && git reset --hard HEAD~1
```

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
2. **Бесконечное "подключение" к Discord** — запустите `utils-zapret.sh` → пункт 4 (обновить hosts)
3. **Обход не работает / перестал работать** — попробуйте следующие шаги:
   - Сначала попробуйте альтернативные конфигурации (ALT, FAKE и т.д.) через `$HOME/zapret-configs/install.sh`
   - Обновите IPSet через `utils-zapret.sh` → пункт 3 (обновить IPSet)
   - Проверьте режим IPSet через `utils-zapret.sh` → пункт 1 (переключить режим IPSet на `loaded`)
   - Запустите тесты через `utils-zapret.sh` → пункт 6 (запустить тесты) для диагностики
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

## 🙏 Благодарности

- **[@bol-van](https://github.com/bol-van/)** — создатель оригинального [zapret](https://github.com/bol-van/zapret/)
- **[@Flowseal](https://github.com/Flowseal)** — за конфигурации для Windows и Linux
- **Сообществу** — за тестирование и обратную связь

### 🩷 Контрибьюторы

[![Contributors](https://contrib.rocks/image?repo=kartavkun/zapret-discord-youtube)](https://github.com/kartavkun/zapret-discord-youtube/graphs/contributors)

---

**🚀 Наслаждайтесь свободным интернетом!**
