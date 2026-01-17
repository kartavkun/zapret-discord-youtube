{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.zapret-discord-youtube;
  zapretPackage = pkgs.callPackage ../packages/zapret-discord-youtube.nix {
    configName = cfg.config;
    listGeneral = cfg.listGeneral;
    listExclude = cfg.listExclude;
    ipsetAll = cfg.ipsetAll;
    ipsetExclude = cfg.ipsetExclude;
  };
  
  # Путь к основным утилитам
  runtimeDeps = with pkgs; [
    iptables
    ipset
    coreutils
    gawk
    curl
    wget
    bash
    kmod
    findutils
    gnused
    gnugrep
    procps
    util-linux
  ];
  
in {
  options.services.zapret-discord-youtube = {
    enable = mkEnableOption "zapret DPI bypass for Discord and YouTube";
    
    config = mkOption {
      type = types.str;
      default = "general";
      description = "Configuration name to use from configs directory";
    };
    
    listGeneral = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional domains to add to list-general.txt";
      example = [ "example.com" "test.org" "mysite.net" ];
    };
    
    listExclude = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional domains to add to list-exclude.txt";
      example = [ "ubisoft.com" "origin.com" ];
    };
    
    ipsetAll = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional IP addresses/subnets to add to ipset-all.txt";
      example = [ "192.168.1.0/24" "10.0.0.1" ];
    };
    
    ipsetExclude = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional IP addresses/subnets to add to ipset-exclude.txt";
      example = [ "203.0.113.0/24" ];
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ zapretPackage ];
    
    # Создаем пользователя tpws для совместимости (хотя используем root)
    users.users.tpws = {
      isSystemUser = true;
      group = "tpws";
      description = "Zapret TPWS service user";
    };
    
    users.groups.tpws = {};
    
    # Используем готовый systemd файл от zapret
    systemd.services.zapret-discord-youtube = {
      description = "Zapret DPI bypass for Discord and YouTube";
      after = [ "network-online.target" "nss-lookup.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      
      path = runtimeDeps;
      
      preStart = let
        zapretInit = "${zapretPackage}/opt/zapret/init.d/sysv/zapret";
      in ''
        # Останавливаем службу если уже запущена
        ${zapretInit} stop || true
        
        # Загружаем необходимые модули ядра
        ${pkgs.kmod}/bin/modprobe xt_NFQUEUE 2>/dev/null || true
        ${pkgs.kmod}/bin/modprobe xt_connbytes 2>/dev/null || true
        ${pkgs.kmod}/bin/modprobe xt_multiport 2>/dev/null || true
        
        # Создаем необходимые ipset если их нет
        if ! ${pkgs.ipset}/bin/ipset list nozapret >/dev/null 2>&1; then
          ${pkgs.ipset}/bin/ipset create nozapret hash:net
        fi
      '';
      
      serviceConfig = {
        Type = "forking";
        ExecStart = "${zapretPackage}/opt/zapret/init.d/sysv/zapret start";
        ExecStop = "${zapretPackage}/opt/zapret/init.d/sysv/zapret stop";
        ExecReload = "${zapretPackage}/opt/zapret/init.d/sysv/zapret restart";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutSec = 30;
        
        # Переменные окружения
        Environment = [
          "ZAPRET_BASE=${zapretPackage}/opt/zapret"
          "PATH=${lib.makeBinPath runtimeDeps}"
        ];
        
        # Запускаем от root для управления сетью
        User = "root";
        Group = "root";
        
        # Расширенные возможности для работы с сетью
        AmbientCapabilities = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_SYS_MODULE" ];
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" "CAP_NET_RAW" "CAP_SYS_MODULE" ];
        
        # Настройки безопасности
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/proc" "/sys" "/run" ];
        
        # Разрешаем доступ к сетевой подсистеме
        PrivateNetwork = false;
        ProtectKernelTunables = false;
        ProtectKernelModules = false;
        ProtectControlGroups = false;
      };
      
      # Настройки перезапуска
      unitConfig = {
        StartLimitInterval = "60s";
        StartLimitBurst = 3;
      };
    };
    
    # Добавляем необходимые модули ядра
    boot.kernelModules = [ "xt_NFQUEUE" "xt_connbytes" "xt_multiport" ];
    
    # Предоставляем доступ к ipset для firewall
    networking.firewall.extraCommands = ''
      # Создаем ipset для zapret если его нет
      if ! ${pkgs.ipset}/bin/ipset list nozapret >/dev/null 2>&1; then
        ${pkgs.ipset}/bin/ipset create nozapret hash:net
      fi
    '';
  };
}
