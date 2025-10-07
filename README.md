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
            config = "general(ALT)";  # или любой конфиг из папки configs (general, general(ALT), general (SIMPLE FAKE) и т.д.)
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

**Доступные конфигурации:**
- `general` — базовая конфигурация для обхода блокировок
- `general_ALT`, `general_ALT2` — альтернативные варианты
- `general (SIMPLE FAKE)`, `general (SIMPLE FAKE ALT)` — оптимизировано для провайдера МГТС

> [!IMPORTANT]
> После выбора конфигурации **просто нажимайте ENTER до появления командной строки в терминале**!

## 🛠️ Управление службой

**Остановить zapret:**
```bash
sudo /opt/zapret/uninstall_easy.sh
```

**Перезапустить с другим конфигом:**
```bash
$HOME/zapret-configs/install.sh
```

## 💡 Расширение функциональности

Хотите добавить обход для других сайтов? Ознакомьтесь с [личным руководством от kartavkun](https://github.com/kartavkun/zapret-discord-youtube/discussions/2#discussion-7902158). Конструктивная критика и предложения приветствуются!

## ✅ Протестировано на

| Дистрибутив                                                                                          | Статус                | Примечания                   |
|------------------------------------------------------------------------------------------------------|-----------------------|------------------------------|
| ![Arch Linux](https://img.shields.io/badge/Arch_Linux-1793D1?logo=arch-linux&logoColor=white)        | ✅ Полностью          | "I use Arch btw"             |
| ![Void Linux](https://img.shields.io/badge/Void_Linux-478061?logo=void-linux&logoColor=white)        | ✅ Полностью          | Поддержка runit              |
| ![Slackware](https://img.shields.io/badge/Slackware-4B0062?logo=slackware&logoColor=white)           | ✅ Полностью          | sysVinit                     |
| ![Alpine Linux](https://img.shields.io/badge/Alpine_Linux-0D597F?logo=alpine-linux&logoColor=white)  | ✅ Полностью          | OpenRC                       |
| ![Solus](https://img.shields.io/badge/Solus-5294E2?logo=solus&logoColor=white)                       | ✅ Полностью          | Systemd                      |
| ![AntiX Linux](https://img.shields.io/badge/AntiX_Linux-0078D7?logo=debian&logoColor=white)          | ✅ Полностью          | Поддержка sysVinit / runit   |
| ![Pop!_OS](https://img.shields.io/badge/Pop!_OS-48B9C7?logo=pop-os&logoColor=white)                  | ✅ Полностью          | Systemd                      |
| ![Ubuntu](https://img.shields.io/badge/Ubuntu-E95420?logo=ubuntu&logoColor=white)                    | ✅ 18.04+             | Systemd                      |
| ![Kubuntu](https://img.shields.io/badge/Kubuntu-0079C1?logo=kubuntu&logoColor=white)                 | ✅ Полностью          | Systemd                      |
| ![NixOS](https://img.shields.io/badge/NixOS-5277C3?logo=nixos&logoColor=white)                       | 🧪 Экспериментально   | Через Flake                  |

## ❓ Решение проблем

**Частые проблемы и решения:**

1. **Права доступа** — убедитесь, что скрипт запускается с правами root/sudo
2. **Обход не работает** — попробуйте альтернативную конфигурацию
3. **Зависимости** — установите curl вручную через пакетный менеджер

**Для сложных случаев:**
- Вопросы по Linux: [оригинальный репозиторий zapret](https://github.com/bol-van/zapret/issues) (приложите конфиг из `/opt/zapret/config`)
- Вопросы по Windows: [репозиторий Flowseal](https://github.com/Flowseal/zapret-discord-youtube)

## 💝 Поддержка проекта

Этот проект развивается благодаря сообществу! Вы можете помочь:

- ⭐ **Поставьте звезду** репозиторию (вверху страницы)
- 💰 **[Поддержите разработчика](https://t.me/kartavslinks/8)**
- 🐛 **Сообщайте о багах** и предлагайте улучшения
- 📚 **Помогать с документацией**

**Также поддержите оригинального разработчика zapret:**  
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
- **[@Flowseal](https://github.com/Flowseal)** — за конфигурации, адаптированные в этом репозитории
- **Сообществу** — за тестирование, багрепорты и предложения с исправлениями

---

**🚀 Наслаждайтесь свободным интернетом!**
