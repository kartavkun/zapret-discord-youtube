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

  configName ? "general",
  gameFilter ? null,
  listGeneral ? [ ],
  listExclude ? [ ],
  ipsetAll ? [ ],
  ipsetExclude ? [ ],
  extraHostlists ? { },
  nfqwsAppend ? [ ],
  extraConfigs ? { },
  derivedConfigs ? { },
}:

let
  tls_4pda = toString (zapret-flowseal + "/bin/tls_clienthello_4pda_to.bin");
  tls_max_ru = toString (zapret-flowseal + "/bin/tls_clienthello_max_ru.bin");
  stun = toString (zapret-flowseal + "/bin/stun.bin");
  quic_initial_dbankcloud_ru = toString (zapret-flowseal + "/bin/quic_initial_dbankcloud_ru.bin");
  selectedNfqwsAppendFile = writeText "zapret-nfqws-append-selected" (
    lib.concatStringsSep "\n" nfqwsAppend + "\n"
  );

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

  extraConfigCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: contentText:
      let
        content = writeText "zapret-config-${safeStoreName name}" contentText;
      in
      ''
        echo "Создание конфигурации: ${name}"
        cp ${content} "$out/opt/zapret/configs/${name}"
      ''
    ) extraConfigs
  );

  derivedConfigCommands = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (
      name: derived:
      let
        appendFile = writeText "zapret-nfqws-append-${safeStoreName name}" (
          lib.concatStringsSep "\n" derived.nfqwsAppend + "\n"
        );
      in
      ''
        echo "Создание производной конфигурации: ${name} <- ${derived.base}"
        if [ ! -f "$out/opt/zapret/configs/${derived.base}" ]; then
          echo "Ошибка: базовая конфигурация '${derived.base}' не найдена"
          ls -la "$out/opt/zapret/configs/" || true
          exit 1
        fi
        cp "$out/opt/zapret/configs/${derived.base}" "$out/opt/zapret/configs/${name}"
        ${lib.optionalString (derived.nfqwsAppend != [ ]) ''
        append_nfqws_rules "$out/opt/zapret/configs/${name}" ${appendFile}
        ''}
      ''
    ) derivedConfigs
  );
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
    cp ${quic_initial_dbankcloud_ru} $sourceRoot/files/fake/quic_initial_dbankcloud_ru.bin
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

    echo "Копирование конфигураций..."
    mkdir -p $out/opt/zapret/configs
    cp -r ${configsSrc}/configs/* $out/opt/zapret/configs/
    ${extraConfigCommands}

    append_nfqws_rules() {
      local target="$1"
      local append_file="$2"

      if [ ! -s "$append_file" ]; then
        return 0
      fi

      if ! ${gnugrep}/bin/grep -q '^NFQWS_OPT="$' "$target"; then
        echo "Ошибка: NFQWS_OPT блок не найден в $target"
        exit 1
      fi

      ${gawk}/bin/awk -v append_file="$append_file" '
        function load_append() {
          while ((getline line < append_file) > 0) {
            append[++append_count] = line
          }
          close(append_file)
        }

        BEGIN {
          load_append()
          in_nfqws = 0
          last = ""
        }

        {
          if (in_nfqws) {
            if ($0 == "\"") {
              if (last != "") {
                if (last !~ /(^|[[:space:]])--new([[:space:]]|$)/) {
                  last = last " --new"
                }
                print last
                last = ""
              }

              for (idx = 1; idx <= append_count; idx++) {
                if (append[idx] != "") {
                  print append[idx]
                }
              }

              print
              in_nfqws = 0
              next
            }

            if (last != "") {
              print last
            }
            last = $0
            next
          }

          print
          if ($0 == "NFQWS_OPT=\"") {
            in_nfqws = 1
          }
        }
      ' "$target" > "$target.tmp"
      mv "$target.tmp" "$target"
    }

    ${derivedConfigCommands}

    ${lib.optionalString (nfqwsAppend != [ ]) ''
      echo "Дополнение NFQWS_OPT для выбранной конфигурации: ${configName}"
      if [ ! -f "$out/opt/zapret/configs/${configName}" ]; then
        echo "Ошибка: конфигурация '${configName}' не найдена для nfqwsAppend"
        ls -la "$out/opt/zapret/configs/" || true
        exit 1
      fi
      append_nfqws_rules "$out/opt/zapret/configs/${configName}" ${selectedNfqwsAppendFile}
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

    find $out/opt/zapret/configs -type f -exec ${gnused}/bin/sed -i \
      -e 's|^#\?WS_USER=.*|WS_USER=root|g' \
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

    echo "Выбор конфигурации: ${configName}"
    if [ -f "$out/opt/zapret/configs/${configName}" ]; then
      cp "$out/opt/zapret/configs/${configName}" "$out/opt/zapret/config"
      echo "Конфигурация '${configName}' установлена"
    else
      echo "Ошибка: конфигурация '${configName}' не найдена"
      ls -la "$out/opt/zapret/configs/" || true
      exit 1
    fi

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
