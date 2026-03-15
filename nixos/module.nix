inputs:
{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.services.zapret-discord-youtube;

  zapretPackage = pkgs.callPackage ./package.nix {
    inherit (inputs) zapret-flowseal;
    inherit (cfg)
      configName
      gameFilter
      listGeneral
      listExclude
      ipsetAll
      ipsetExclude
      ;
  };

  runtimeDeps = lib.attrValues {
    inherit (pkgs)
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
      ;
  };
in

{
  imports = [
    (lib.mkRenamedOptionModule
      [ "services" "zapret-discord-youtube" "config" ]
      [ "services" "zapret-discord-youtube" "configName" ]
    )
  ];

  options.services.zapret-discord-youtube = {
    enable = lib.mkEnableOption "zapret DPI bypass for Discord and YouTube";

    configName = lib.mkOption {
      type = lib.types.str;
      default = "general";
      description = "Configuration name to use from configs directory";
    };

    gameFilter = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "all" "tcp" "udp" "null" ]);
      default = null;
      description = "Game filter mode (null or 'null' = disabled, 'all' = TCP+UDP, 'tcp' = TCP only, 'udp' = UDP only)";
      example = "all";
    };

    listGeneral = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional domains to add to list-general.txt";
      example = [
        "example.com"
        "test.org"
        "mysite.net"
      ];
    };

    listExclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional domains to add to list-exclude.txt";
      example = [
        "ubisoft.com"
        "origin.com"
      ];
    };

    ipsetAll = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional IP addresses/subnets to add to ipset-all.txt";
      example = [
        "192.168.1.0/24"
        "10.0.0.1"
      ];
    };

    ipsetExclude = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional IP addresses/subnets to add to ipset-exclude.txt";
      example = [ "203.0.113.0/24" ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ zapretPackage ];

    users.users.tpws = {
      isSystemUser = true;
      group = "tpws";
      description = "Zapret TPWS service user";
    };

    users.groups.tpws = { };

    systemd.services.zapret-discord-youtube = {
      description = "Zapret DPI bypass for Discord and YouTube";
      after = [
        "network-online.target"
        "nss-lookup.target"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = runtimeDeps;

      preStart =
        let
          zapretInit = "${zapretPackage}/opt/zapret/init.d/sysv/zapret";
        in
        ''
          ${zapretInit} stop || true

          ${lib.getExe' pkgs.kmod "modprobe"} xt_NFQUEUE 2>/dev/null || true
          ${lib.getExe' pkgs.kmod "modprobe"} xt_connbytes 2>/dev/null || true
          ${lib.getExe' pkgs.kmod "modprobe"} xt_multiport 2>/dev/null || true

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

        Environment = [
          "ZAPRET_BASE=${zapretPackage}/opt/zapret"
          "PATH=${lib.makeBinPath runtimeDeps}"
        ];

        User = "root";
        Group = "root";

        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
          "CAP_SYS_MODULE"
        ];
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
          "CAP_SYS_MODULE"
        ];

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [
          "/proc"
          "/sys"
          "/run"
        ];

        PrivateNetwork = false;
        ProtectKernelTunables = false;
        ProtectKernelModules = false;
        ProtectControlGroups = false;
      };

      unitConfig = {
        StartLimitInterval = "60s";
        StartLimitBurst = 3;
      };
    };

    boot.kernelModules = [
      "xt_NFQUEUE"
      "xt_connbytes"
      "xt_multiport"
    ];

    networking.firewall.extraCommands = ''
      if ! ${lib.getExe pkgs.ipset} list nozapret >/dev/null 2>&1; then
        ${lib.getExe pkgs.ipset} create nozapret hash:net
      fi
    '';
  };
}
