{
  lib,
  zapret-flowseal,

  stdenv,
  fetchurl,
  makeWrapper,
  nix-update-script,
  writeText,
  bash,
  coreutils,
  curl,
  findutils,
  gawk,
  gnugrep,
  gnused,
  ipset,
  iptables,
  kmod,
  procps,
  util-linux,
  wget,

  strategyName ? "general",
  gameFilter ? null,
  listGeneral ? [ ],
  listExclude ? [ ],
  ipsetAll ? [ ],
  ipsetExclude ? [ ],
  extraHostlists ? { },
  nfqwsAppend ? [ ],
  extraStrategies ? { },
  extraFixes ? { },
  enabledFixes ? [ ],
  derivedStrategies ? { },
}:

let
  # Конфиги переименованы к единообразным именам (general-alt вместо
  # general(ALT), general-simple-fake вместо general (SIMPLE FAKE) и т.д.).
  # Таблица ниже принимает старые имена, чтобы у пользователей с уже
  # написанным configName = "general(ALT)" ничего не сломалось при обновлении
  # flake. Будет удалена через два релиза — тогда же, что и шимы.
  legacyStrategyNames = {
    "general(ALT)" = "general-alt";
    "general(ALT2)" = "general-alt-2";
    "general(ALT3)" = "general-alt-3";
    "general(ALT4)" = "general-alt-4";
    "general(ALT5)" = "general-alt-5";
    "general(ALT6)" = "general-alt-6";
    "general(ALT7)" = "general-alt-7";
    "general(ALT8)" = "general-alt-8";
    "general(ALT9)" = "general-alt-9";
    "general(ALT10)" = "general-alt-10";
    "general(ALT11)" = "general-alt-11";
    "general (ALT12)" = "general-alt-12";
    "general (FAKE_TLS_AUTO)" = "general-fake-tls-auto";
    "general (FAKE_TLS_AUTO_ALT)" = "general-fake-tls-auto-alt";
    "general (FAKE_TLS_AUTO_ALT2)" = "general-fake-tls-auto-alt-2";
    "general (FAKE_TLS_AUTO_ALT3)" = "general-fake-tls-auto-alt-3";
    "general (SIMPLE FAKE)" = "general-simple-fake";
    "general (SIMPLE FAKE ALT)" = "general-simple-fake-alt";
    "general (SIMPLE_FAKE_ALT2)" = "general-simple-fake-alt-2";
    "general (EXP)" = "general-exp";
  };

  resolveStrategyName =
    name:
    let
      resolved = legacyStrategyNames.${name} or name;
    in
    lib.warnIf (resolved != name)
      "zapret-discord-youtube: имя стратегии '${name}' устарело, используйте '${resolved}'"
      resolved;

  resolvedStrategyName = resolveStrategyName strategyName;

  tls_4pda = toString (zapret-flowseal + "/bin/tls_clienthello_4pda_to.bin");
  tls_max_ru = toString (zapret-flowseal + "/bin/tls_clienthello_max_ru.bin");
  stun = toString (zapret-flowseal + "/bin/stun.bin");
  stun2 = toString (zapret-flowseal + "/bin/stun2.bin");
  quic_initial_dbankcloud_ru = toString (zapret-flowseal + "/bin/quic_initial_dbankcloud_ru.bin");
  quic_initial_steamcommunity_com = toString (zapret-flowseal + "/bin/quic_initial_steamcommunity_com.bin");
  quic_initial_tencent_com = toString (zapret-flowseal + "/bin/quic_initial_tencent_com.bin");
  active_discord_udp = toString (zapret-flowseal + "/bin/ACTIVE_DISCORD_UDP.bin");
  active_game_udp = toString (zapret-flowseal + "/bin/ACTIVE_GAME_UDP.bin");
  # nfqwsAppend в новой схеме — это обычный fix. Раньше правила приходилось
  # вживлять в середину NFQWS_OPT awk-скриптом; теперь загрузчик сам склеивает
  # фрагменты, и вся та машинерия не нужна.
  nfqwsAppendFix = writeText "zapret-fix-nix-append" ''
    FIX_NFQWS_OPT="
    ${lib.concatStringsSep "\n" nfqwsAppend}
    "
  '';

  safeStoreName =
    name:
    lib.replaceStrings
      [
        " "
        "("
        ")"
        "["
        "]"
        ":"
        "/"
        "\\"
      ]
      [
        "-"
        ""
        ""
        ""
        ""
        "-"
        "-"
        "-"
      ]
      name;

  extraHostlistCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: domains:
      let
        content = writeText "zapret-hostlist-${safeStoreName name}" (
          lib.concatStringsSep "\n" domains + "\n"
        );
      in
      ''
        echo "Создание hostlist: ${name}"
        cp ${content} "$out/opt/zapret/hostlists/${name}"
      ''
    ) extraHostlists
  );

  extraStrategyCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: contentText:
      let
        content = writeText "zapret-strategy-${safeStoreName name}" contentText;
      in
      ''
        echo "Создание стратегии: ${name}"
        cp ${content} "$out/opt/zapret/strategies/${name}"
      ''
    ) extraStrategies
  );

  extraFixCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: contentText:
      let
        content = writeText "zapret-fix-${safeStoreName name}" contentText;
      in
      ''
        echo "Создание фикса: ${name}"
        cp ${content} "$out/opt/zapret/fixes/${name}"
      ''
    ) extraFixes
  );

  # Производная стратегия просто подключает базовую и дописывает свои правила.
  # Фрагмент сорсится загрузчиком, у которого уже выставлен ZAPRET_BASE.
  derivedStrategyCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: derived:
      let
        base = resolveStrategyName derived.base;
        content = writeText "zapret-strategy-${safeStoreName name}" ''
          . "$ZAPRET_BASE/strategies/${base}"
          NFQWS_STRATEGY_OPT="$NFQWS_STRATEGY_OPT
          ${lib.concatStringsSep "\n" derived.nfqwsAppend}
          "
        '';
      in
      ''
        echo "Создание производной стратегии: ${name} <- ${base}"
        if [ ! -f "$out/opt/zapret/strategies/${base}" ]; then
          echo "Ошибка: базовая стратегия '${base}' не найдена"
          ls -la "$out/opt/zapret/strategies/" || true
          exit 1
        fi
        cp ${content} "$out/opt/zapret/strategies/${name}"
      ''
    ) derivedStrategies
  );

  allEnabledFixes = enabledFixes ++ lib.optional (nfqwsAppend != [ ]) "nix-append";

in

stdenv.mkDerivation rec {
  pname = "zapret-discord-youtube";
  version = "72.12";

  src = fetchurl {
    url = "https://github.com/bol-van/zapret/releases/download/v${version}/zapret-v${version}.tar.gz";
    hash = "sha256-WkYcTN24e7ip8d5eIi40I/jw1lanUg9SnPH2bY1YWmg=";
  };

  configsSrc = ./..;

  nativeBuildInputs = [ makeWrapper ];

  buildInputs = [
    iptables
    ipset
    coreutils
    bash
    gawk
    curl
    wget
    kmod
    findutils
    gnused
    gnugrep
    procps
    util-linux
  ];

  dontBuild = true;
  dontConfigure = true;

  postUnpack = ''
    echo "Копирование бинарников TLS..."
    mkdir -p $sourceRoot/files/fake
    cp ${tls_4pda} $sourceRoot/files/fake/tls_clienthello_4pda_to.bin
    cp ${tls_max_ru} $sourceRoot/files/fake/tls_clienthello_max_ru.bin
    cp ${stun} $sourceRoot/files/fake/stun.bin
    cp ${stun2} $sourceRoot/files/fake/stun2.bin
    cp ${quic_initial_dbankcloud_ru} $sourceRoot/files/fake/quic_initial_dbankcloud_ru.bin
    cp ${quic_initial_steamcommunity_com} $sourceRoot/files/fake/quic_initial_steamcommunity_com.bin
    cp ${quic_initial_tencent_com} $sourceRoot/files/fake/quic_initial_tencent_com.bin
    cp ${active_discord_udp} $sourceRoot/files/fake/ACTIVE_DISCORD_UDP.bin
    cp ${active_game_udp} $sourceRoot/files/fake/ACTIVE_GAME_UDP.bin
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt/zapret $out/bin
    cp -r * $out/opt/zapret/

    echo "Копирование hostlists..."
    mkdir -p $out/opt/zapret/hostlists
    cp -v ${configsSrc}/hostlists/* $out/opt/zapret/hostlists/
    ${extraHostlistCommands}

    ${lib.optionalString (listGeneral != [ ]) ''
            cat ${configsSrc}/hostlists/list-general-user.txt > $out/opt/zapret/hostlists/list-general-user.txt.tmp
            ${gnused}/bin/sed -i -e '$a\' $out/opt/zapret/hostlists/list-general-user.txt.tmp
            cat >> $out/opt/zapret/hostlists/list-general-user.txt.tmp <<'EOF'
      ${lib.concatStringsSep "\n" listGeneral}
      EOF
            mv $out/opt/zapret/hostlists/list-general-user.txt.tmp $out/opt/zapret/hostlists/list-general-user.txt
    ''}

    ${lib.optionalString (listExclude != [ ]) ''
            cat ${configsSrc}/hostlists/list-exclude-user.txt > $out/opt/zapret/hostlists/list-exclude-user.txt.tmp
            ${gnused}/bin/sed -i -e '$a\' $out/opt/zapret/hostlists/list-exclude-user.txt.tmp
            cat >> $out/opt/zapret/hostlists/list-exclude-user.txt.tmp <<'EOF'
      ${lib.concatStringsSep "\n" listExclude}
      EOF
            mv $out/opt/zapret/hostlists/list-exclude-user.txt.tmp $out/opt/zapret/hostlists/list-exclude-user.txt
    ''}

    ${lib.optionalString (ipsetAll != [ ]) ''
            cat ${configsSrc}/hostlists/ipset-all.txt > $out/opt/zapret/hostlists/ipset-all.txt.tmp
            ${gnused}/bin/sed -i -e '$a\' $out/opt/zapret/hostlists/ipset-all.txt.tmp
            cat >> $out/opt/zapret/hostlists/ipset-all.txt.tmp <<'EOF'
      ${lib.concatStringsSep "\n" ipsetAll}
      EOF
            mv $out/opt/zapret/hostlists/ipset-all.txt.tmp $out/opt/zapret/hostlists/ipset-all.txt
    ''}

    ${lib.optionalString (ipsetExclude != [ ]) ''
            cat ${configsSrc}/hostlists/ipset-exclude-user.txt > $out/opt/zapret/hostlists/ipset-exclude-user.txt.tmp
            ${gnused}/bin/sed -i -e '$a\' $out/opt/zapret/hostlists/ipset-exclude-user.txt.tmp
            cat >> $out/opt/zapret/hostlists/ipset-exclude-user.txt.tmp <<'EOF'
      ${lib.concatStringsSep "\n" ipsetExclude}
      EOF
            mv $out/opt/zapret/hostlists/ipset-exclude-user.txt.tmp $out/opt/zapret/hostlists/ipset-exclude-user.txt
    ''}

    echo "Копирование стратегий и фиксов..."
    mkdir -p $out/opt/zapret/strategies $out/opt/zapret/fixes
    cp -r ${configsSrc}/strategies/* $out/opt/zapret/strategies/
    cp -r ${configsSrc}/fixes/* $out/opt/zapret/fixes/
    ${extraStrategyCommands}
    ${extraFixCommands}
    ${derivedStrategyCommands}
    ${lib.optionalString (nfqwsAppend != [ ]) ''
      echo "Создание фикса nix-append из nfqwsAppend"
      cp ${nfqwsAppendFix} "$out/opt/zapret/fixes/nix-append"
    ''}

    echo "Патчинг файлов для NixOS..."

    local utilities=(
      'iptables:${iptables}/bin/iptables'
      'ip6tables:${iptables}/bin/ip6tables' 
      'ipset:${ipset}/bin/ipset'
      'awk:${gawk}/bin/awk'
      'curl:${curl}/bin/curl'
      'wget:${wget}/bin/wget'
      'modprobe:${kmod}/bin/modprobe'
      'xargs:${findutils}/bin/xargs'
      'find:${findutils}/bin/find'
      'sed:${gnused}/bin/sed'
      'grep:${gnugrep}/bin/grep'
      'wc:${coreutils}/bin/wc'
      'cat:${coreutils}/bin/cat'
      'mkdir:${coreutils}/bin/mkdir'
      'rm:${coreutils}/bin/rm'
      'cp:${coreutils}/bin/cp'
      'mv:${coreutils}/bin/mv'
      'ln:${coreutils}/bin/ln'
      'chmod:${coreutils}/bin/chmod'
      'chown:${coreutils}/bin/chown'
      'ps:${procps}/bin/ps'
      'pkill:${procps}/bin/pkill'
      'pgrep:${procps}/bin/pgrep'
      'flock:${util-linux}/bin/flock'
      'renice:${util-linux}/bin/renice'
      'killall:${procps}/bin/killall'
      'head:${coreutils}/bin/head'
      'tail:${coreutils}/bin/tail'
      'sort:${coreutils}/bin/sort'
      'uniq:${coreutils}/bin/uniq'
      'tr:${coreutils}/bin/tr'
      'cut:${coreutils}/bin/cut'
      'echo:${coreutils}/bin/echo'
      'test:${coreutils}/bin/test'
      'printf:${coreutils}/bin/printf'
      'sleep:${coreutils}/bin/sleep'
      'id:${coreutils}/bin/id'
      'basename:${coreutils}/bin/basename'
      'dirname:${coreutils}/bin/dirname'
      'which:${coreutils}/bin/which'
    )

    for utility_pair in "''${utilities[@]}"; do
      util="''${utility_pair%%:*}"
      path="''${utility_pair##*:}"
      
      find $out/opt/zapret -type f \( -name "*.sh" -o -name "zapret" -o -name "functions" \) \
        -exec ${gnused}/bin/sed -i \
          -e "s|^$util |$path |g" \
          -e "s|[[:space:]]$util[[:space:]]| $path |g" \
          -e "s|\"$util\"|\"$path\"|g" \
          -e "s|'$util'|'$path'|g" \
          -e "s|\`$util\`|\`$path\`|g" \
          {} \;
    done

    find $out/opt/zapret -type f -exec ${gnused}/bin/sed -i \
      -e 's|/opt/zapret|'"$out"'/opt/zapret|g' \
      {} \;

    if [ -f "$out/opt/zapret/common/def.sh" ]; then
      {
        echo "# NixOS environment setup"
        echo "export AWK='${gawk}/bin/awk'"
        echo "export GREP='${gnugrep}/bin/grep'"
        echo ""
        cat "$out/opt/zapret/common/def.sh"
      } > "$out/opt/zapret/common/def.sh.new"
      mv "$out/opt/zapret/common/def.sh.new" "$out/opt/zapret/common/def.sh"
    fi

    find $out/opt/zapret -type f \( -name "*.sh" -o -name "create_ipset" -o -name "functions" \) -exec ${gnused}/bin/sed -i \
      -e 's|''$GREP|${gnugrep}/bin/grep|g' \
      -e 's|''$AWK|${gawk}/bin/awk|g' \
      {} \;


    if [ -f "$out/opt/zapret/init.d/sysv/functions" ]; then
      ${gnused}/bin/sed -i \
        -e 's|USEROPT="--user=\$WS_USER"|USEROPT=""|g' \
        -e 's|USEROPT="--uid \$WS_USER:\$WS_USER"|USEROPT=""|g' \
        -e 's|TPWS_OPT_BASE="\$USEROPT"|TPWS_OPT_BASE=""|g' \
        -e 's|NFQWS_OPT_BASE="\$USEROPT |NFQWS_OPT_BASE="|g' \
        "$out/opt/zapret/init.d/sysv/functions"
    fi

    find $out/opt/zapret -type f -exec ${gnused}/bin/sed -i \
      -e 's|--user=tpws||g' \
      -e 's|--user=root||g' \
      {} \;

    echo "Выбор стратегии: ${resolvedStrategyName}"
    if [ ! -f "$out/opt/zapret/strategies/${resolvedStrategyName}" ]; then
      echo "Ошибка: стратегия '${resolvedStrategyName}' не найдена"
      ls -la "$out/opt/zapret/strategies/" || true
      exit 1
    fi

    # Загрузчик читает имя стратегии и список фиксов из состояния, а не из
    # самого config, поэтому конфигурация задаётся двумя текстовыми файлами.
    cp ${configsSrc}/config "$out/opt/zapret/config"

    # Патч применяется после копирования: раньше он выполнялся над каталогом
    # configs, которого больше не существует, и его результат всё равно был бы
    # затёрт этим cp.
    ${gnused}/bin/sed -i \
      -e 's|^#\?WS_USER=.*|WS_USER=root|g' \
      "$out/opt/zapret/config"
    echo "${resolvedStrategyName}" > "$out/opt/zapret/zapret.strategy"
    ${lib.optionalString (allEnabledFixes != [ ]) ''
      printf '%s\n' ${lib.escapeShellArgs allEnabledFixes} > "$out/opt/zapret/zapret.fixes"
      echo "Включённые фиксы: ${lib.concatStringsSep ", " allEnabledFixes}"
    ''}
    echo "Стратегия '${resolvedStrategyName}' установлена"

    ${lib.optionalString (gameFilter != null && gameFilter != "null") ''
      echo "Установка Game Filter: ${gameFilter}"
      mkdir -p $out/opt/zapret/hostlists
      echo "${gameFilter}" > $out/opt/zapret/hostlists/.game_filter.enabled
    ''}

    makeWrapper "$out/opt/zapret/binaries/linux-x86_64/nfqws" "$out/bin/nfqws" \
      --prefix PATH : "${
        lib.makeBinPath [
          iptables
          ipset
          coreutils
          procps
        ]
      }"

    makeWrapper "$out/opt/zapret/binaries/linux-x86_64/tpws" "$out/bin/tpws" \
      --prefix PATH : "${
        lib.makeBinPath [
          iptables
          ipset
          coreutils
          procps
        ]
      }"

    makeWrapper "$out/opt/zapret/init.d/sysv/zapret" "$out/bin/zapret-service" \
      --prefix PATH : "${lib.makeBinPath buildInputs}"

    ln -sf "$out/opt/zapret/binaries/linux-x86_64/nfqws" "$out/opt/zapret/nfq/nfqws"
    ln -sf "$out/opt/zapret/binaries/linux-x86_64/tpws" "$out/opt/zapret/tpws/tpws"

    find "$out/opt/zapret" -name "*.sh" -exec chmod +x {} \;
    chmod +x "$out/opt/zapret/init.d/sysv/zapret"
    chmod +x "$out/opt/zapret/init.d/sysv/functions"
    chmod +x "$out/opt/zapret/binaries/linux-x86_64/"*

    runHook postInstall
  '';

  passthru.updateScript = nix-update-script { };

  meta = with lib; {
    description = "DPI bypass tool with Discord and YouTube configurations";
    homepage = "https://github.com/bol-van/zapret";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
