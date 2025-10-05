{ lib
, stdenv
, fetchurl
, fetchFromGitHub
, makeWrapper
, iptables
, ipset
, coreutils
, bash
, gawk
, curl
, wget
, kmod
, findutils
, gnused
, gnugrep
, procps
, util-linux
, configName ? "general"
}:

stdenv.mkDerivation rec {
  pname = "zapret-discord-youtube";
  version = "71.4";

  src = fetchurl {
    url = "https://github.com/bol-van/zapret/releases/download/v${version}/zapret-v${version}.tar.gz";
    hash = "sha256-qzeK8SldPCcMyHqMK/EQhyLEGq73dwPAcIrdVzpTjfI=";
  };

  configsSrc = ./../..;

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

  installPhase = ''
    runHook preInstall
    
    mkdir -p $out/opt/zapret
    mkdir -p $out/bin
    
    cp -r ./* $out/opt/zapret/
    
    echo "Копирование hostlists..."
    mkdir -p $out/opt/zapret/hostlists
    cp -v ${configsSrc}/hostlists/* $out/opt/zapret/hostlists/
    
    echo "Копирование конфигураций..."
    mkdir -p $out/opt/zapret/configs
    cp -r ${configsSrc}/configs/* $out/opt/zapret/configs/
    
    echo "Патчинг файлов для NixOS..."
    
    # Полный список утилит для замены
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
    
    # Заменяем все утилиты в скриптах
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
    
    # Заменяем пути /opt/zapret
    find $out/opt/zapret -type f -exec ${gnused}/bin/sed -i \
      -e 's|/opt/zapret|'"$out"'/opt/zapret|g' \
      {} \;
    
    # Настройка пользователя для NixOS
    find $out/opt/zapret/configs -type f -exec ${gnused}/bin/sed -i \
      -e 's|^#\?WS_USER=.*|WS_USER=root|g' \
      {} \;
    
    # Отключаем переключение пользователя в функциях
    if [ -f "$out/opt/zapret/init.d/sysv/functions" ]; then
      ${gnused}/bin/sed -i \
        -e 's|USEROPT="--user=\$WS_USER"|USEROPT=""|g' \
        -e 's|USEROPT="--uid \$WS_USER:\$WS_USER"|USEROPT=""|g' \
        -e 's|TPWS_OPT_BASE="\$USEROPT"|TPWS_OPT_BASE=""|g' \
        -e 's|NFQWS_OPT_BASE="\$USEROPT |NFQWS_OPT_BASE="|g' \
        "$out/opt/zapret/init.d/sysv/functions"
    fi
    
    # Убираем параметры --user
    find $out/opt/zapret -type f -exec ${gnused}/bin/sed -i \
      -e 's|--user=tpws||g' \
      -e 's|--user=root||g' \
      {} \;
    
    # Создаем основной конфигурационный файл
    echo "Выбор конфигурации: ${configName}"
    if [ -f "$out/opt/zapret/configs/${configName}" ]; then
      cp "$out/opt/zapret/configs/${configName}" "$out/opt/zapret/config"
      echo "Конфигурация '${configName}' установлена"
    else
      echo "Ошибка: конфигурация '${configName}' не найдена"
      ls -la "$out/opt/zapret/configs/" || true
      exit 1
    fi
    
    # Создаем обертки с полным PATH
    makeWrapper "$out/opt/zapret/binaries/linux-x86_64/nfqws" "$out/bin/nfqws" \
      --prefix PATH : "${lib.makeBinPath [ iptables ipset coreutils procps ]}"
    
    makeWrapper "$out/opt/zapret/binaries/linux-x86_64/tpws" "$out/bin/tpws" \
      --prefix PATH : "${lib.makeBinPath [ iptables ipset coreutils procps ]}"
    
    # Создаем обертку для основного скрипта
    makeWrapper "$out/opt/zapret/init.d/sysv/zapret" "$out/bin/zapret-service" \
      --prefix PATH : "${lib.makeBinPath (buildInputs)}"
    
    # Симлинки для совместимости
    ln -sf "$out/opt/zapret/binaries/linux-x86_64/nfqws" "$out/opt/zapret/nfq/nfqws"
    ln -sf "$out/opt/zapret/binaries/linux-x86_64/tpws" "$out/opt/zapret/tpws/tpws"
    
    # Исполняемые права
    find "$out/opt/zapret" -name "*.sh" -exec chmod +x {} \;
    chmod +x "$out/opt/zapret/init.d/sysv/zapret"
    chmod +x "$out/opt/zapret/init.d/sysv/functions"
    chmod +x "$out/opt/zapret/binaries/linux-x86_64/"*
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "DPI bypass tool with Discord and YouTube configurations";
    homepage = "https://github.com/bol-van/zapret";
    license = licenses.mit;
    maintainers = [ ];
    platforms = platforms.linux;
  };
}
