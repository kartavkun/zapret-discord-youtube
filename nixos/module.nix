inputs:
{
  pkgs,
  lib,
  config,
  ...
}:

let
  cfg = config.services.zapret-discord-youtube;
  validGeneratedName =
    name:
    ! (lib.hasInfix "/" name)
    && ! (lib.hasInfix "\"" name)
    && ! (lib.hasInfix "$" name)
    && ! (lib.hasInfix "`" name)
    && ! (lib.hasInfix "\\" name)
    && ! (lib.hasInfix "\n" name);

  zapretPackage = pkgs.callPackage ./package.nix {
    inherit (inputs) zapret-flowseal;
    inherit (cfg)
      configName
      gameFilter
      listGeneral
      listExclude
      ipsetAll
      ipsetExclude
      extraHostlists
      nfqwsAppend
      extraConfigs
      derivedConfigs
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

  testWrapper = pkgs.writeShellScriptBin "zapret-test-strategies" ''
    set -euo pipefail

    if [ "$(${lib.getExe' pkgs.coreutils "id"} -u)" -ne 0 ]; then
      echo "Run as root: sudo zapret-test-strategies"
      exit 1
    fi

    state_root="''${ZAPRET_TEST_STATE_DIR:-/run/zapret-discord-youtube-test}"
    runtime_zapret="$state_root/zapret"
    store_zapret="${zapretPackage}/opt/zapret"
    log_dir="''${ZAPRET_TEST_LOG_DIR:-/var/log/zapret-discord-youtube-test}"
    main_was_active=0

    export PATH="${lib.makeBinPath (runtimeDeps ++ [
      pkgs.iputils
      pkgs.lua5_4
      pkgs.systemd
      pkgs.which
    ])}:$PATH"

    cleanup() {
      if [ -x "$runtime_zapret/init.d/sysv/zapret" ]; then
        "$runtime_zapret/init.d/sysv/zapret" stop >/dev/null 2>&1 || true
      fi

      if [ "$main_was_active" -eq 1 ]; then
        ${lib.getExe' pkgs.systemd "systemctl"} start zapret-discord-youtube.service >/dev/null 2>&1 || true
      fi
    }
    trap cleanup EXIT

    if ${lib.getExe' pkgs.systemd "systemctl"} is-active --quiet zapret-discord-youtube.service; then
      main_was_active=1
      ${lib.getExe' pkgs.systemd "systemctl"} stop zapret-discord-youtube.service
    fi

    ${lib.getExe' pkgs.coreutils "rm"} -rf -- "$state_root"
    ${lib.getExe' pkgs.coreutils "mkdir"} -p "$state_root" "$log_dir"
    ${lib.getExe' pkgs.coreutils "cp"} -a "$store_zapret" "$runtime_zapret"
    ${lib.getExe' pkgs.coreutils "chmod"} -R u+rwX "$runtime_zapret"

    path_list="$state_root/store-path-files"
    if ${lib.getExe pkgs.gnugrep} -rlZ -- "$store_zapret" "$runtime_zapret" > "$path_list"; then
      ${lib.getExe' pkgs.findutils "xargs"} -0 -r ${lib.getExe pkgs.gnused} -i "s|$store_zapret|$runtime_zapret|g" < "$path_list"
    fi
    ${lib.getExe' pkgs.coreutils "rm"} -f -- "$path_list"

    export ZAPRET_TEST_LOG_DIR="$log_dir"
    export ZAPRET_TEST_CONFIGS_DIR="${zapretPackage}/opt/zapret/configs"
    export ZAPRET_TEST_TARGETS_FILE="${../utils/targets.txt}"
    export ZAPRET_TEST_CONFIG="$runtime_zapret/config"
    export ZAPRET_TEST_IPSET_FILE="$runtime_zapret/hostlists/ipset-all.txt"
    export ZAPRET_TEST_RESTART_CMD="$runtime_zapret/init.d/sysv/zapret restart"
    export ZAPRET_TEST_RESTART_TIMEOUT="30"
    export ZAPRET_TEST_RESTART_LOG="$log_dir/restart.log"

    ${lib.getExe pkgs.lua5_4} ${../utils/test-zapret.lua}
    echo "Logs: $log_dir"
  '';
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

    extraHostlists = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "Additional hostlist files to create in hostlists directory";
      example = {
        "list-github.txt" = [
          "github.com"
          "raw.githubusercontent.com"
        ];
      };
    };

    extraConfigs = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = { };
      description = "Full custom zapret config files to create in configs directory";
      example = {
        "my-custom-config" = ''
          NFQWS_ENABLE=1
          NFQWS_OPT="
          --filter-tcp=443 --hostlist="/opt/zapret/hostlists/list-github.txt" --dpi-desync=multisplit --dpi-desync-split-pos=2
          "
        '';
      };
    };

    nfqwsAppend = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "NFQWS_OPT rules to append to the selected configName";
      example = [
        ''--filter-tcp=443 --hostlist="/opt/zapret/hostlists/list-github.txt" --dpi-desync=multisplit --dpi-desync-split-pos=2''
      ];
    };

    derivedConfigs = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            base = lib.mkOption {
              type = lib.types.str;
              description = "Existing config name to copy before appending NFQWS rules";
              example = "general(ALT)";
            };

            nfqwsAppend = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "NFQWS_OPT rules to append to the copied config";
              example = [
                ''--filter-tcp=443 --hostlist="/opt/zapret/hostlists/list-github.txt" --dpi-desync=multisplit --dpi-desync-split-pos=2''
              ];
            };
          };
        }
      );
      default = { };
      description = "Configs derived from existing configs with extra NFQWS_OPT rules appended";
      example = {
        "general(ALT)-github" = {
          base = "general(ALT)";
          nfqwsAppend = [
            ''--filter-tcp=443 --hostlist="/opt/zapret/hostlists/list-github.txt" --dpi-desync=multisplit --dpi-desync-split-pos=2''
          ];
        };
      };
    };

    testTools.enable = lib.mkEnableOption "strategy testing tools for writable NixOS runtime";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          lib.all validGeneratedName (
            lib.attrNames cfg.extraHostlists ++ lib.attrNames cfg.extraConfigs ++ lib.attrNames cfg.derivedConfigs
          );
        message = "zapret-discord-youtube generated config and hostlist names must not contain '/', quotes, '$', backticks, backslashes, or newlines";
      }
      {
        assertion = lib.all (entry: validGeneratedName entry.base) (lib.attrValues cfg.derivedConfigs);
        message = "zapret-discord-youtube derivedConfigs.*.base must not contain '/', quotes, '$', backticks, backslashes, or newlines";
      }
    ];

    environment.systemPackages = [ zapretPackage ] ++ lib.optional cfg.testTools.enable testWrapper;

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
