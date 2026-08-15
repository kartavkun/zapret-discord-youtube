# ❄️ NixOS

Установка через Flake. Для остальных дистрибутивов см. [README](../README.md).


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

## Стратегии и фиксы в конфигурации

```nix
services.zapret-discord-youtube = {
  enable = true;
  strategyName = "general-alt";
  enabledFixes = [ "hypixel" ];

  # Свой фикс прямо в конфигурации
  extraFixes."my-game" = ''
    FIX_TCP_PORTS="27015"
    FIX_NFQWS_OPT="
    --filter-tcp=27015 --dpi-desync=multisplit --dpi-desync-split-pos=1
    "
  '';

  # Своя стратегия целиком
  extraStrategies."my-strategy" = ''
    NFQWS_STRATEGY_OPT="
    --filter-tcp=443 --dpi-desync=multisplit --dpi-desync-split-pos=1
    "
  '';
};
```

`nfqwsAppend` по-прежнему работает: правила из него собираются в отдельный
фикс `nix-append`, который включается автоматически.

> [!NOTE]
> Опция `configName` переименована в `strategyName`, `extraConfigs` — в
> `extraStrategies`. Старые имена работают через `mkRenamedOptionModule`,
> ломаться ничего не должно.

> [!WARNING]
> Поддержка NixOS помечена экспериментальной не просто так: она собирается,
> но проверена заметно меньше, чем обычный путь установки.
