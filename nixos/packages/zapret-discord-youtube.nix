{ lib
, stdenv
, fetchurl
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
, gzip
, configName ? "general"
}:

let
  targetArch = 
    if stdenv.isx86_64 then "linux-x86_64"
    else if stdenv.isAarch64 then "linux-aarch64" 
    else throw "Unsupported architecture: ${stdenv.hostPlatform.system}";

in stdenv.mkDerivation rec {
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
    gzip
  ];

  dontBuild = true;
  dontConfigure = true;

  patchPhase = ''
    runHook prePatch
    
    echo "Patching shebangs..."
    patchShebangs .
    
    echo "Patching utilities for NixOS..."
    
    # Список утилит для замены
    utilities=(
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
      'gunzip:${gzip}/bin/gunzip'
      'gzip:${gzip}/bin/gzip'
    )

    # Патчим файлы с безопасным разделителем
    for file in $(find . -type f \( -name "*.sh" -o -name "zapret" -o -name "functions" -o -name "*.config" -o -name "*.conf" \) -print); do
      if [[ ! -f "$file" ]]; then
        continue
      fi
      
      echo "Patching utilities in: $file"
      
      # Создаем временный файл для безопасного патчинга
      temp_file="''${file}.tmp"
      cp "$file" "$temp_file"
      
      for utility_pair in "''${utilities[@]}"; do
        util="''${utility_pair%%:*}"
        path="''${utility_pair##*:}"
        
        # Используем # как разделитель вместо |, чтобы избежать конфликтов
        # Замена: ^util -> /path/util
        ${gnused}/bin/sed -i "s#^\([[:space:]]*\)$util\([[:space:]]\)#\1$path\2#g" "$temp_file"
        
        # Замена: | util | -> | /path/util |
        ${gnused}/bin/sed -i "s#\([[:space:]]\)$util\([[:space:]]\)#\1$path\2#g" "$temp_file"
      done
      
      # АГРЕССИВНАЯ замена путей /opt/zapret - ВСЕ вхождения
      ${gnused}/bin/sed -i "s#/opt/zapret#$out/opt/zapret#g" "$temp_file"
      
      # Замена путей /var/run на /run/zapret
      ${gnused}/bin/sed -i "s#/var/run/#/run/zapret/#g" "$temp_file"
      
      # Настройка для NixOS
      ${gnused}/bin/sed -i "s#^\([[:space:]]*\)WS_USER=.*#\1WS_USER=root#g" "$temp_file"
      ${gnused}/bin/sed -i "s#--user=tpws##g" "$temp_file"
      ${gnused}/bin/sed -i "s#--user=root##g" "$temp_file"
      
      # Заменяем оригинальный файл
      mv "$temp_file" "$file"
    done
    
    # ДОПОЛНИТЕЛЬНО: патчим ВСЕ файлы на предмет оставшихся путей /opt/zapret
    echo "Aggressive path patching..."
    find . -type f -exec ${gnused}/bin/sed -i "s#/opt/zapret#$out/opt/zapret#g" {} \;
    find . -type f -exec ${gnused}/bin/sed -i "s#/var/run/#/run/zapret/#g" {} \;
    
    # Дополнительные патчи для функций с безопасным разделителем
    if [ -f "./init.d/sysv/functions" ]; then
      ${gnused}/bin/sed -i \
        -e 's#USEROPT="--user=\$WS_USER"#USEROPT=""#g' \
        -e 's#USEROPT="--uid \$WS_USER:\$WS_USER"#USEROPT=""#g' \
        -e 's#TPWS_OPT_BASE="\$USEROPT"#TPWS_OPT_BASE=""#g' \
        -e 's#NFQWS_OPT_BASE="\$USEROPT #NFQWS_OPT_BASE=" #g' \
        "./init.d/sysv/functions"
    fi
    
    # Исправляем скрипт create_ipset.sh - КОМПЛЕКСНОЕ исправление MemTotal
    if [ -f "./ipset/create_ipset.sh" ]; then
      echo "Fixing create_ipset.sh completely..."
      ${gnused}/bin/sed -i \
        -e 's#^[[:space:]]*ram=.*#ram=1024#g' \
        -e 's#MemTotal=#echo "Using fixed RAM value" #g' \
        -e 's#if \[ $ram -lt#if false \&\& [ $ram -lt#g' \
        "./ipset/create_ipset.sh"
    fi
    
    runHook postPatch
  '';

  installPhase = ''
    runHook preInstall
    
    # Создаем структуру каталогов
    mkdir -p $out/opt/zapret
    mkdir -p $out/bin
    
    # Копируем ВСЕ исходные файлы (включая files/fake)
    echo "Copying ALL zapret files..."
    cp -r ./* $out/opt/zapret/
    
    # Копируем hostlists
    echo "Copying hostlists..."
    mkdir -p $out/opt/zapret/hostlists
    cp -v ${configsSrc}/hostlists/* $out/opt/zapret/hostlists/ 2>/dev/null || true
    
    # Копируем конфигурации
    echo "Copying configurations..."
    mkdir -p $out/opt/zapret/configs
    cp -r ${configsSrc}/configs/* $out/opt/zapret/configs/ 2>/dev/null || true
    
    # Выбор конфигурации
    echo "Selecting configuration: ${configName}"
    config_file="$out/opt/zapret/configs/${configName}"
    if [ ! -f "$config_file" ]; then
      echo "Error: Configuration '${configName}' not found!"
      echo "Available configurations:"
      ls -1 "$out/opt/zapret/configs/" 2>/dev/null || true
      exit 1
    fi
    
    cp "$config_file" "$out/opt/zapret/config"
    echo "Configuration '${configName}' installed"
    
    # ФИНАЛЬНАЯ проверка путей в конфигурационном файле
    echo "Final path verification in config file..."
    ${gnused}/bin/sed -i "s#/opt/zapret#$out/opt/zapret#g" "$out/opt/zapret/config"
    
    # Проверяем что пути в конфиге правильные
    echo "Checking paths in final config:"
    grep -n "zapret" "$out/opt/zapret/config" | head -10 || true
    
    # Симлинки для совместимости
    mkdir -p $out/opt/zapret/nfq
    mkdir -p $out/opt/zapret/tpws
    
    if [ -d "$out/opt/zapret/binaries/${targetArch}" ]; then
      ln -sf "$out/opt/zapret/binaries/${targetArch}/nfqws" "$out/opt/zapret/nfq/nfqws" 2>/dev/null || true
      ln -sf "$out/opt/zapret/binaries/${targetArch}/tpws" "$out/opt/zapret/tpws/tpws" 2>/dev/null || true
    fi
    
    # Проверяем что fake-файлы существуют и доступны
    echo "Checking fake files accessibility..."
    if [ -f "$out/opt/zapret/files/fake/quic_initial_www_google_com.bin" ]; then
      echo "✓ Fake file exists: $out/opt/zapret/files/fake/quic_initial_www_google_com.bin"
    else
      echo "✗ Fake file missing: $out/opt/zapret/files/fake/quic_initial_www_google_com.bin"
      ls -la "$out/opt/zapret/files/fake/" 2>/dev/null || echo "Fake directory not found"
    fi
    
    # Обертки
    if [ -f "$out/opt/zapret/binaries/${targetArch}/nfqws" ]; then
      makeWrapper "$out/opt/zapret/binaries/${targetArch}/nfqws" "$out/bin/nfqws" \
        --prefix PATH : "${lib.makeBinPath buildInputs}"
    fi
    
    if [ -f "$out/opt/zapret/binaries/${targetArch}/tpws" ]; then
      makeWrapper "$out/opt/zapret/binaries/${targetArch}/tpws" "$out/bin/tpws" \
        --prefix PATH : "${lib.makeBinPath buildInputs}"
    fi
    
    # Основная обертка
    makeWrapper "$out/opt/zapret/init.d/sysv/zapret" "$out/bin/zapret" \
      --prefix PATH : "${lib.makeBinPath buildInputs}" \
      --set ZAPRET_BASE "$out/opt/zapret"
    
    # Права исполнения
    find "$out/opt/zapret" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    find "$out/opt/zapret/init.d" -type f -exec chmod +x {} \; 2>/dev/null || true
    find "$out/opt/zapret/binaries" -type f -exec chmod +x {} \; 2>/dev/null || true
    chmod +x "$out/opt/zapret/init.d/sysv/zapret" 2>/dev/null || true
    
    runHook postInstall
  '';

  meta = with lib; {
    description = "DPI bypass tool with Discord and YouTube configurations";
    homepage = "https://github.com/kartavkun/zapret-discord-youtube";
    license = licenses.mit;
    maintainers = [ maintainers."@kartavkun" ];
    platforms = platforms.linux;
    mainProgram = "zapret";
  };
}
