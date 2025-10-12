{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.zapret-discord-youtube;
  
  zapretPackage = pkgs.callPackage ../packages/zapret-discord-youtube.nix {
    configName = cfg.config;
  };
  
  runtimeDeps = with pkgs; [
    iptables
    ipset
    coreutils
    gawk
    curl
    wget
    kmod
    findutils
    gnused
    gnugrep
    procps
    util-linux
    gzip
  ];
  
in {
  options.services.zapret-discord-youtube = {
    enable = mkEnableOption "Zapret DPI bypass service";
    
    config = mkOption {
      type = types.str;
      default = "general";
      description = "Configuration name from configs directory";
    };

    autoUpdateLists = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically update block lists using systemd timer";
    };

    updateSchedule = mkOption {
      type = types.str;
      default = "daily";
      description = ''
        Systemd timer schedule for updating block lists.
        Can be in systemd calendar format or one of: hourly, daily, weekly, monthly
      '';
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ zapretPackage ];
    
    # Системный пользователь
    users.users.zapret = {
      isSystemUser = true;
      group = "zapret";
      description = "Zapret DPI bypass service";
    };
    
    users.groups.zapret = {};
    
    # Модули ядра
    boot.kernelModules = [ "xt_NFQUEUE" "xt_connbytes" "xt_multiport" ];
    
    # Systemd служба
    systemd.services.zapret-discord-youtube = {
      description = "Zapret DPI bypass service";
      
      after = [ "network-online.target" "network.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      path = runtimeDeps;
      
      preStart = ''
        # Создаем ipset если не существует
        if ! ${pkgs.ipset}/bin/ipset list nozapret >/dev/null 2>&1; then
          ${pkgs.ipset}/bin/ipset create nozapret hash:net
        fi
        
        # Загружаем модули ядра
        ${pkgs.kmod}/bin/modprobe xt_NFQUEUE 2>/dev/null || true
        ${pkgs.kmod}/bin/modprobe xt_connbytes 2>/dev/null || true
        ${pkgs.kmod}/bin/modprobe xt_multiport 2>/dev/null || true
        
        # Останавливаем если уже запущено
        ${zapretPackage}/bin/zapret stop || true
        sleep 2
      '';
      
      serviceConfig = {
        Type = "forking";
        ExecStart = "${zapretPackage}/bin/zapret start";
        ExecStop = "${zapretPackage}/bin/zapret stop";
        ExecReload = "${zapretPackage}/bin/zapret restart";
        
        # Создаем runtime directory для pid-файлов
        RuntimeDirectory = "zapret";
        RuntimeDirectoryMode = "0755";
        
        User = "zapret";
        Group = "zapret";
        
        # Необходимые capabilities
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_SYS_MODULE" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_SYS_MODULE" ];
        
        # Безопасность
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = false;
        ProtectKernelModules = false;
        PrivateNetwork = false;
        
        # Доступ к файловой системе
        ReadWritePaths = [ 
          "/proc" 
          "/sys" 
          "/run"
          "/var/lib/zapret"
        ];
        
        # Лимиты
        LimitNOFILE = 65536;
        
        # Перезапуск
        Restart = "on-failure";
        RestartSec = "5s";
        StartLimitInterval = "60s";
        StartLimitBurst = 3;
        
        # Переменные окружения
        Environment = [
          "ZAPRET_BASE=${zapretPackage}/opt/zapret"
          "PATH=${lib.makeBinPath runtimeDeps}"
        ];
        
        # Рабочий каталог
        WorkingDirectory = "${zapretPackage}/opt/zapret";
      };
    };

    # Служба для обновления списков блокировки
    systemd.services.zapret-list-update = mkIf cfg.autoUpdateLists {
      description = "Update zapret block lists";
      path = runtimeDeps;
      
      serviceConfig = {
        Type = "oneshot";
        User = "zapret";
        Group = "zapret";
        
        # Безопасность
        NoNewPrivileges = true;
        PrivateTmp = true;
        
        # Переменные окружения
        Environment = [
          "ZAPRET_BASE=${zapretPackage}/opt/zapret"
          "PATH=${lib.makeBinPath runtimeDeps}"
        ];
        
        ExecStart = "${zapretPackage}/opt/zapret/ipset/get_config.sh";
        
        # Доступ к файловой системе
        ReadWritePaths = [
          "${zapretPackage}/opt/zapret/ipset"
          "/var/lib/zapret"
        ];
      };
    };
    
    # Таймер для автоматического обновления списков
    systemd.timers.zapret-list-update = mkIf cfg.autoUpdateLists {
      description = "Timer for zapret list updates";
      wantedBy = [ "timers.target" ];
      timerConfig = 
        if cfg.updateSchedule == "hourly" then {
          OnCalendar = "hourly";
          RandomizedDelaySec = "300";
        } else if cfg.updateSchedule == "daily" then {
          OnCalendar = "daily";
          RandomizedDelaySec = "1800";
        } else if cfg.updateSchedule == "weekly" then {
          OnCalendar = "weekly";
          RandomizedDelaySec = "3600";
        } else if cfg.updateSchedule == "monthly" then {
          OnCalendar = "monthly";
          RandomizedDelaySec = "7200";
        } else {
          OnCalendar = cfg.updateSchedule;
          RandomizedDelaySec = "1800";
        };
    };
    
    # Каталог для данных
    systemd.tmpfiles.rules = [
      "d /var/lib/zapret 0755 zapret zapret - -"
      "d /run/zapret 0755 zapret zapret - -"
    ];
  };
}
