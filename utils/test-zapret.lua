#!/usr/bin/env lua

local os = require("os")
local io = require("io")
local string = require("string")
local table = require("table")
local math = require("math")

-- Коды цветов
local colors = {
    reset = "\27[0m",
    green = "\27[32m",
    yellow = "\27[33m",
    red = "\27[31m",
    cyan = "\27[36m",
    gray = "\27[90m",
    darkgray = "\27[2;37m",
    darkcyan = "\27[36;2m"
}

-- Глобальный дескриптор файла лога
local log_file = nil
local log_path = nil

-- Базовые операции с файлами (определены первыми)
local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return content
end

local function write_file(path, content)
    local f = io.open(path, "w")
    if not f then return false end
    f:write(content)
    f:close()
    return true
end

local function append_file(path, content)
    local f = io.open(path, "a")
    if not f then return false end
    f:write(content .. "\n")
    f:close()
    return true
end

-- Функции логирования
local function colorize(text, color)
    if not color then return text end
    return color .. text .. colors.reset
end

local function write_log(msg)
    if log_file then
        log_file:write(msg .. "\n")
        log_file:flush()
    end
end

local function log_separator()
    write_log("------------------------------------------------------------")
end

local function log_header(idx, total, config_name)
    log_separator()
    write_log(string.format("[%d/%d] %s", idx, total, config_name))
    log_separator()
end

local function log_info(msg)
    print(colorize("[INFO] " .. msg, colors.cyan))
    write_log("[INFO] " .. msg)
end

local function log_warn(msg)
    print(colorize("[WARN] " .. msg, colors.yellow))
    write_log("[WARN] " .. msg)
end

local function log_error(msg)
    print(colorize("[ERROR] " .. msg, colors.red))
    write_log("[ERROR] " .. msg)
end

local function log_ok(msg)
    print(colorize("[OK] " .. msg, colors.green))
    write_log("[OK] " .. msg)
end

local function log_gray(msg)
    print(colorize(msg, colors.darkgray))
    write_log(msg)
end

local function init_log(log_dir, test_type)
    if not file_exists(log_dir) then
        os.execute("mkdir -p " .. log_dir)
    end
    
    local timestamp = os.date("%Y-%m-%d-%H:%M:%S")
    local type_suffix = (test_type == "standard") and "standard" or "dpi"
    log_path = log_dir .. "/test-zapret-" .. type_suffix .. "-" .. timestamp .. ".txt"
    log_file = io.open(log_path, "w")
    
    if log_file then
        local header = (test_type == "standard") and "=== ZAPRET CONFIG STANDARD TEST LOG ===" or "=== ZAPRET CONFIG DPI TEST LOG ==="
        log_file:write(header .. "\n")
        log_file:write("Начало: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        log_file:write("=================================\n\n")
        log_file:flush()
        return true
    end
    return false
end

local function close_log()
    if log_file then
        log_file:write("\n=================================\n")
        log_file:write("Завершено: " .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        log_file:close()
        log_file = nil
    end
end

-- Системные функции
local function execute_cmd(cmd)
    local handle = io.popen(cmd .. " 2>&1")
    if not handle then return nil, 1 end
    local output = handle:read("*a")
    local _, _, code = handle:close()
    return output, code or 0
end

local function detect_privilege_escalation()
    local doas_check = execute_cmd("command -v doas >/dev/null 2>&1 && echo 1 || echo 0")
    if doas_check and doas_check:match("1") then return "doas" end
    
    local sudo_check = execute_cmd("command -v sudo >/dev/null 2>&1 && echo 1 || echo 0")
    if sudo_check and sudo_check:match("1") then return "sudo" end
    
    return nil
end

local function restart_zapret(elevate_cmd)
    if not elevate_cmd then return false end
    
    -- Проверка systemd
    local output = execute_cmd("command -v systemctl >/dev/null 2>&1 && echo 1 || echo 0")
    if output and output:match("1") then
        local cmd = elevate_cmd .. " systemctl restart zapret"
        local result, code = execute_cmd(cmd)
        if code == 0 then
            log_ok("Zapret перезапущен (systemd)")
            return true
        end
    end
    
    -- Проверка OpenRC
    output = execute_cmd("command -v rc-service >/dev/null 2>&1 && echo 1 || echo 0")
    if output and output:match("1") then
        local cmd = elevate_cmd .. " rc-service zapret restart"
        local result, code = execute_cmd(cmd)
        if code == 0 then
            log_ok("Zapret перезапущен (OpenRC)")
            return true
        end
    end
    
    -- Проверка runit
    output = execute_cmd("[ -d /var/service/zapret ] || [ -d /etc/service/zapret ] && echo 1 || echo 0")
    if output and output:match("1") then
        local cmd = elevate_cmd .. " sv restart zapret"
        local result, code = execute_cmd(cmd)
        if code == 0 then
            log_ok("Zapret перезапущен (runit)")
            return true
        end
    end
    
    -- Проверка sysvinit
    output = execute_cmd("command -v service >/dev/null 2>&1 && echo 1 || echo 0")
    if output and output:match("1") then
        local cmd = elevate_cmd .. " service zapret restart"
        local result, code = execute_cmd(cmd)
        if code == 0 then
            log_ok("Zapret перезапущен (sysvinit)")
            return true
        end
    end
    
    log_warn("Не удалось перезапустить zapret - система инициализации не обнаружена")
    return false
end

-- Функции анализа файлов
local function get_line_count(path)
    if not file_exists(path) then return 0 end
    local count = 0
    for _ in io.lines(path) do
        count = count + 1
    end
    return count
end

local function file_contains_line(path, line)
    if not file_exists(path) then return false end
    for l in io.lines(path) do
        if l == line then return true end
    end
    return false
end

local function get_ipset_status(ipset_file)
    if not file_exists(ipset_file) then return "none" end
    local line_count = get_line_count(ipset_file)
    if line_count == 0 then return "any" end
    if file_contains_line(ipset_file, "203.0.113.113/32") then return "none" end
    return "loaded"
end

local function set_ipset_mode(mode, ipset_file, backup_file)
    if mode == "any" then
        if file_exists(ipset_file) then
            local cmd = "cp '" .. ipset_file .. "' '" .. backup_file .. "'"
            os.execute(cmd)
            log_info("Backup ipset создан: " .. backup_file)
        else
            os.execute("touch '" .. backup_file .. "'")
            log_info("Backup файл создан (исходный не существовал)")
        end
        -- Очищаем файл ipset (режим "any" = пустой файл)
        local cmd = "sh -c 'echo \"\" > \"" .. ipset_file .. "\"'"
        os.execute(cmd)
        log_info("IPSet очищен (режим 'any')")
    elseif mode == "restore" then
        if file_exists(backup_file) then
            local cmd = "mv '" .. backup_file .. "' '" .. ipset_file .. "'"
            os.execute(cmd)
            log_info("IPSet восстановлен из backup")
        else
            log_warn("Backup файл не найден для восстановления")
        end
    end
end

-- DPI набор и цели
-- Набор тестов из https://github.com/hyperion-cs/dpi-checkers (Apache-2.0 license)
-- Авторские права оригинального репозитория dpi-checkers сохранены
local function get_dpi_suite()
    return {
        { id = "US.CF-01", provider = "Cloudflare", url = "https://cdn.cookielaw.org/scripttemplates/202501.2.0/otBannerSdk.js", times = 1 },
        { id = "US.CF-02", provider = "Cloudflare", url = "https://genshin.jmp.blue/characters/all#", times = 1 },
        { id = "US.CF-03", provider = "Cloudflare", url = "https://api.frankfurter.dev/v1/2000-01-01..2002-12-31", times = 1 },
        { id = "US.DO-01", provider = "DigitalOcean", url = "https://genderize.io/", times = 2 },
        { id = "DE.HE-01", provider = "Hetzner", url = "https://j.dejure.org/jcg/doctrine/doctrine_banner.webp", times = 1 },
        { id = "FI.HE-01", provider = "Hetzner", url = "https://tcp1620-01.dubybot.live/1MB.bin", times = 1 },
        { id = "FI.HE-02", provider = "Hetzner", url = "https://tcp1620-02.dubybot.live/1MB.bin", times = 1 },
        { id = "FI.HE-03", provider = "Hetzner", url = "https://tcp1620-05.dubybot.live/1MB.bin", times = 1 },
        { id = "FI.HE-04", provider = "Hetzner", url = "https://tcp1620-06.dubybot.live/1MB.bin", times = 1 },
        { id = "FR.OVH-01", provider = "OVH", url = "https://eu.api.ovh.com/console/rapidoc-min.js", times = 1 },
        { id = "FR.OVH-02", provider = "OVH", url = "https://ovh.sfx.ovh/10M.bin", times = 1 },
        { id = "SE.OR-01", provider = "Oracle", url = "https://oracle.sfx.ovh/10M.bin", times = 1 },
        { id = "DE.AWS-01", provider = "AWS", url = "https://tms.delta.com/delta/dl_anderson/Bootstrap.js", times = 1 },
        { id = "US.AWS-01", provider = "AWS", url = "https://corp.kaltura.com/wp-content/cache/min/1/wp-content/themes/airfleet/dist/styles/theme.css", times = 1 },
        { id = "US.GC-01", provider = "Google Cloud", url = "https://api.usercentrics.eu/gvl/v3/en.json", times = 1 },
        { id = "US.FST-01", provider = "Fastly", url = "https://openoffice.apache.org/images/blog/rejected.png", times = 1 },
        { id = "US.FST-02", provider = "Fastly", url = "https://www.juniper.net/etc.clientlibs/juniper/clientlibs/clientlib-site/resources/fonts/lato/Lato-Regular.woff2", times = 1 },
        { id = "PL.AKM-01", provider = "Akamai", url = "https://www.lg.com/lg5-common-gp/library/jquery.min.js", times = 1 },
        { id = "PL.AKM-02", provider = "Akamai", url = "https://media-assets.stryker.com/is/image/stryker/gateway_1?$max_width_1410$", times = 1 },
        { id = "US.CDN77-01", provider = "CDN77", url = "https://cdn.eso.org/images/banner1920/eso2520a.jpg", times = 1 },
        { id = "DE.CNTB-01", provider = "Contabo", url = "https://cloudlets.io/wp-content/themes/Avada/includes/lib/assets/fonts/fontawesome/webfonts/fa-solid-900.woff2", times = 1 },
        { id = "FR.SW-01", provider = "Scaleway", url = "https://renklisigorta.com.tr/teklif-al", times = 1 },
        { id = "US.CNST-01", provider = "Constant", url = "https://cdn.xuansiwei.com/common/lib/font-awesome/4.7.0/fontawesome-webfont.woff2?v=4.7.0", times = 1 },
    }
end

local function build_dpi_targets(custom_url)
    local suite = get_dpi_suite()
    local targets = {}

    if custom_url then
        table.insert(targets, { id = "CUSTOM", provider = "Custom", url = custom_url })
    else
        for _, entry in ipairs(suite) do
            local repeat_count = entry.times or 1
            for i = 0, repeat_count - 1 do
                local suffix = ""
                if repeat_count > 1 then suffix = "@" .. i end
                table.insert(targets, {
                    id = entry.id .. suffix,
                    provider = entry.provider,
                    url = entry.url
                })
            end
        end
    end

    return targets
end

-- Функции тестирования
local function test_url(url, timeout, test_label)
    local args = ""
    if test_label == "HTTP" then
        args = "--http1.1"
    elseif test_label == "TLS1.2" then
        args = "--tlsv1.2 --tls-max 1.2"
    elseif test_label == "TLS1.3" then
        args = "--tlsv1.3 --tls-max 1.3"
    end

    local cmd = string.format("curl -I -s -m %d -o /dev/null -w '%%{http_code} %%{size_download}' %s '%s' 2>&1", timeout, args, url)
    local output, code = execute_cmd(cmd)

    if not output then return "ERR", 0 end

    local http_code, size = output:match("(%d+)%s+(%d+)")
    if not http_code then
        if output:match("not supported") or output:match("does not support") or output:match("unsupported") or code == 35 then
            return "UNSUP", 0
        end
        return "ERR", 0
    end

    if code == 0 then
        return "OK", tonumber(size) or 0
    else
        return "ERR", 0
    end
end

local function test_ping(host, count)
    local cmd = string.format("ping -c %d -W 2 '%s' 2>&1 | grep 'min/avg/max'", count, host)
    local output = execute_cmd(cmd)

    if not output or output == "" then
        return "Timeout"
    end

    local avg = output:match("min/avg/max[^=]*= [^/]*/([^/]+)/")
    if avg then
        return string.format("%.0f ms", tonumber(avg))
    end

    return "Timeout"
end

local function load_targets(targets_file)
    local targets = {}

    for line in io.lines(targets_file) do
        if not line:match("^%s*#") and line:match("=") then
            local name, value = line:match("^%s*(%w+)%s*=%s*\"(.+)\"%s*$")
            if name and value then
                table.insert(targets, { name = name, value = value })
            end
        end
    end

    return targets
end

local function run_standard_tests(config_name, targets, timeout)
    print(colorize("  > Запуск тестов...", colors.darkgray))
    write_log("> Запуск тестов...")

    for _, target in ipairs(targets) do
        local line = string.format("  %-30s ", target.name)
        io.write(line)

        if target.value:match("^PING:") then
            local host = target.value:match("^PING:(.+)$")
            local result = test_ping(host, 3)
            local output = colorize("Пинг: " .. result, colors.cyan)
            print(output)
            write_log(string.format("%-30s Пинг: %s", target.name, result))
        else
            local tests = { "HTTP", "TLS1.2", "TLS1.3" }
            local results = {}
            local log_results = {}

            for _, test_label in ipairs(tests) do
                local status, size = test_url(target.value, timeout, test_label)
                local color = colors.green
                if status == "UNSUP" then color = colors.yellow
                elseif status == "ERR" then color = colors.red end
                table.insert(results, colorize(test_label .. ":" .. status, color))
                table.insert(log_results, test_label .. ":" .. status)
            end

            print(table.concat(results, " "))
            write_log(string.format("%-30s %s", target.name, table.concat(log_results, " ")))
        end
    end
end

local function read_mode_selection()
    while true do
        print("")
        print(colorize("Выберите режим тестирования:", colors.cyan))
        print("  [1] Все конфиги")
        print("  [2] Выбранные конфиги")
        io.write("Введите 1 или 2: ")
        local choice = io.read()
        
        if choice == "1" then
            return "all"
        elseif choice == "2" then
            return "select"
        else
            print(colorize("Неверный ввод. Попробуйте снова.", colors.yellow))
        end
    end
end

local function select_configs(all_configs)
    while true do
        print("")
        print(colorize("Доступные конфиги:", colors.cyan))
        for idx, config in ipairs(all_configs) do
            print(string.format("  [%2d] %s", idx, config))
        end
        
        print("")
        print("Введите номера конфигов для тестирования (через запятую, например 1,3,5):")
        io.write("> ")
        local input = io.read()
        
        local selected = {}
        for num_str in input:gmatch("[^,]+") do
            local num = tonumber(num_str:match("%d+"))
            if num and num >= 1 and num <= #all_configs then
                table.insert(selected, all_configs[num])
            end
        end
        
        if #selected == 0 then
            print(colorize("[WARN] Некорректный ввод. Попробуйте снова.", colors.yellow))
        else
            print(colorize(string.format("[OK] Выбрано конфигов: %d", #selected), colors.green))
            return selected
        end
    end
end

local function run_dpi_tests(targets, timeout, range_bytes, warn_min_kb, warn_max_kb)
    log_info(string.format("Целей: %d. Диапазон: 0-%d байт; Таймаут: %d с; Окно предупреждения: %d-%d КБ", 
        #targets, range_bytes - 1, timeout, warn_min_kb, warn_max_kb))
    log_info("Запуск проверок DPI TCP 16-20...")

    local warn_detected = false

    for _, target in ipairs(targets) do
        print("")
        local header = "=== " .. target.id .. " [" .. target.provider .. "] ==="
        print(colorize(header, colors.darkcyan))
        write_log(header)

        local tests = { "HTTP", "TLS1.2", "TLS1.3" }
        local target_warned = false

        for _, test_label in ipairs(tests) do
            local status, size = test_url(target.url, timeout, test_label)
            local size_kb = math.floor(size / 1024 * 10) / 10
            local color = colors.green
            local msg_status = "OK"

            if status == "UNSUP" then
                color = colors.yellow
                msg_status = "НЕ_ПОДДЕРЖИВАЕТСЯ"
            elseif status == "ERR" then
                color = colors.red
                msg_status = "ОШИБКА"
            end

            if size_kb >= warn_min_kb and size_kb <= warn_max_kb and status == "ERR" then
                msg_status = "ВЕРОЯТНО_ЗАБЛОКИРОВАНО"
                color = colors.yellow
                target_warned = true
            end

            local msg = string.format("  [%s][%s] code=%s size=%d bytes (%.1f KB) status=%s", 
                target.id, test_label, status, size, size_kb, msg_status)
            print(colorize(msg, color))
            write_log(msg)
        end

        if not target_warned then
            local msg = "  Паттерн замораживания 16-20КБ не обнаружен для этой цели."
            print(colorize(msg, colors.green))
            write_log(msg)
        else
            local msg = "  Паттерн совпадает с замораживанием 16-20КБ; цензор вероятно блокирует эту стратегию."
            print(colorize(msg, colors.yellow))
            write_log(msg)
            warn_detected = true
        end
    end

    print("")
    if warn_detected then
        log_error("Обнаружена возможная блокировка DPI TCP 16-20 на одной или нескольких целях. Рассмотрите изменение стратегии/SNI/IP.")
    else
        log_ok("Паттерн замораживания 16-20КБ не обнаружен на всех целях.")
    end
end

-- Основной скрипт
local function main()
    -- Определяем директорию utils, где лежит сам скрипт
    local utils_dir = arg[0]:match("(.*/)")
    if not utils_dir then
        utils_dir = "./"
    end
    
    -- Корневая директория проекта (родитель папки utils)
    local root_dir = utils_dir:gsub("/$", ""):match("(.*/)")
    if not root_dir then
        root_dir = "../"
    end
    
    local configs_dir = root_dir .. "configs"
    local targets_file = utils_dir .. "targets.txt"
    local log_dir = utils_dir .. "log"
    local zapret_config = "/opt/zapret/config"
    local zapret_config_backup = "/opt/zapret/config.back"

    -- Проверка доступности curl
    local curl_check = execute_cmd("which curl")
    if not curl_check or curl_check == "" then
        print(colorize("[ERROR] curl не найден. Пожалуйста, установите curl.", colors.red))
        os.exit(1)
    end

    -- Определение повышения привилегий
    local elevate_cmd = detect_privilege_escalation()
    if not elevate_cmd then
        print(colorize("[ERROR] sudo или doas не найдены", colors.red))
        os.exit(1)
    end
    print(colorize("[OK] Повышение привилегий: " .. elevate_cmd, colors.green))

    -- Поиск всех файлов конфигов (исключая старые конфиги)
    local configs = {}
    local handle = io.popen("ls -1 " .. configs_dir .. " 2>/dev/null | grep -v '^\\.' | grep -v '^old' | sort")
    if handle then
        for line in handle:lines() do
            if line ~= "" and line ~= "old configs" then
                table.insert(configs, line)
            end
        end
        handle:close()
    end

    if #configs == 0 then
        print(colorize("[ERROR] Файлы конфигов не найдены в " .. configs_dir, colors.red))
        os.exit(1)
    end

    print(colorize("[OK] curl найден", colors.green))

    print("")
    print(colorize("============================================================", colors.cyan))
    print(colorize("                 ТЕСТЫ КОНФИГОВ ZAPRET", colors.cyan))
    print(colorize("                 Всего конфигов: " .. string.format("%2d", #configs), colors.cyan))
    print(colorize("============================================================", colors.cyan))

    -- Выбор типа теста
    print("")
    print("Выберите тип теста:")
    print("  [1] Стандартные тесты (HTTP/ping)")
    print("  [2] DPI checkers (TCP 16-20 freeze)")
    io.write("Введите 1 или 2: ")
    local test_type = io.read()

    -- Выбор режима тестирования (все или выбранные конфиги)
    local mode = read_mode_selection()
    if mode == "select" then
        configs = select_configs(configs)
    end

    if test_type ~= "1" and test_type ~= "2" then
        print(colorize("[ERROR] Неверный выбор", colors.red))
        os.exit(1)
    end

    test_type = (test_type == "1") and "standard" or "dpi"

    -- Инициализация логирования после выбора типа теста
    if not init_log(log_dir, test_type) then
        print(colorize("[ERROR] Не удалось инициализировать файл лога", colors.red))
        os.exit(1)
    end

    log_info("Тест запущен из: " .. root_dir)

    -- Загрузка целей для стандартных тестов
    local targets = {}
    if test_type == "standard" then
        if not file_exists(targets_file) then
            print(colorize("[ERROR] targets.txt не найден", colors.red))
            os.exit(1)
        end
        targets = load_targets(targets_file)
    else
        targets = build_dpi_targets(os.getenv("MONITOR_URL"))
    end

    -- Резервная копия текущего конфига
    if file_exists(zapret_config_backup) then
        log_warn("Резервная копия конфига уже существует, используется существующая")
    else
        if file_exists(zapret_config) then
            os.execute("cp '" .. zapret_config .. "' '" .. zapret_config_backup .. "'")
            log_ok("Текущий конфиг сохранён в " .. zapret_config_backup)
        end
    end

    -- Для DPI тестов переключаем ipset в режим "any"
    local ipset_file = "/opt/zapret/hostlists/ipset-all.txt"
    local ipset_backup = ipset_file .. ".test-backup"
    local original_ipset_status = nil
    
    if test_type == "dpi" then
        original_ipset_status = get_ipset_status(ipset_file)
        if original_ipset_status ~= "any" then
            log_warn("Переключение ipset в режим 'any' для точных DPI тестов...")
            set_ipset_mode("any", ipset_file, ipset_backup)
            restart_zapret(elevate_cmd)
            os.execute("sleep 2")
        end
    end

    -- Запуск тестов для каждого конфига
    local timeout = tonumber(os.getenv("MONITOR_TIMEOUT")) or 5
    local range_bytes = tonumber(os.getenv("MONITOR_RANGE")) or 262144
    local warn_min_kb = tonumber(os.getenv("MONITOR_WARN_MINKB")) or 14
    local warn_max_kb = tonumber(os.getenv("MONITOR_WARN_MAXKB")) or 22

    for idx, config in ipairs(configs) do
        print("")
        print(colorize("------------------------------------------------------------", colors.darkcyan))
        print(colorize(string.format("  [%d/%d] %s", idx, #configs, config), colors.yellow))
        print(colorize("------------------------------------------------------------", colors.darkcyan))

        log_header(idx, #configs, config)
        log_info("Тестирование конфига: " .. config)

        -- Копирование конфига в /opt/zapret/config
        local source_config = configs_dir .. "/" .. config
        if not file_exists(source_config) then
            log_error("Файл конфига не найден: " .. source_config)
            goto continue
        end

        os.execute("cp '" .. source_config .. "' '" .. zapret_config .. "'")
        log_info("Конфиг скопирован в " .. zapret_config)

        -- Перезапуск zapret
        restart_zapret(elevate_cmd)
        os.execute("sleep 3")

        if test_type == "standard" then
            run_standard_tests(config, targets, timeout)
        else
            run_dpi_tests(targets, timeout, range_bytes, warn_min_kb, warn_max_kb)
        end

        ::continue::
        if idx < #configs then
            os.execute("sleep 2")
        end
    end

    -- Восстановление исходного конфига и ipset
    local need_restart = false
    
    if file_exists(zapret_config_backup) then
        os.execute("mv '" .. zapret_config_backup .. "' '" .. zapret_config .. "'")
        log_ok("Исходный конфиг восстановлен")
        need_restart = true
    end

    -- Восстановление исходного ipset после DPI тестов
    if test_type == "dpi" and original_ipset_status and original_ipset_status ~= "any" then
        log_warn("Восстановление исходного режима ipset...")
        set_ipset_mode("restore", ipset_file, ipset_backup)
        log_ok("IPSet восстановлен в режим '" .. original_ipset_status .. "'")
        need_restart = true
    end
    
    -- Перезапуск zapret после восстановления исходных файлов
    if need_restart then
        restart_zapret(elevate_cmd)
    end

    print("")
    log_ok("Тесты завершены")
    log_info("Файл лога сохранён в: " .. log_path)
    close_log()
end

main()
