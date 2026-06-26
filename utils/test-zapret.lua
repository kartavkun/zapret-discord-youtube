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

local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
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

local function print_info(msg)
    print(colorize("[INFO] " .. msg, colors.cyan))
end

local function print_warn(msg)
    print(colorize("[WARN] " .. msg, colors.yellow))
end

local function print_gray(msg)
    print(colorize(msg, colors.darkgray))
end

local function init_log(log_dir, test_type)
    if not file_exists(log_dir) then
        os.execute("mkdir -p " .. shell_quote(log_dir))
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

local function os_execute_code(cmd)
    local ok, _, code = os.execute(cmd)
    if ok == true then return 0 end
    return tonumber(code) or 1
end

local function spawn_background(command, output_file)
    local spawn_cmd = string.format(
        "sh -c %s",
        shell_quote("(" .. command .. ") > " .. shell_quote(output_file) .. " 2>&1 & echo $!")
    )
    local output = execute_cmd(spawn_cmd)
    if not output then return nil end
    return tonumber(output:match("(%d+)"))
end

local function pid_is_running(pid)
    return os_execute_code(string.format("kill -0 %d >/dev/null 2>&1", pid)) == 0
end

local interrupt_terminal_state = nil

local function enable_interrupt_polling()
    if os_execute_code("[ -t 0 ] >/dev/null 2>&1") ~= 0 then
        return false
    end

    local state = execute_cmd("stty -g 2>/dev/null")
    if not state or state == "" then
        return false
    end

    interrupt_terminal_state = state:gsub("%s+$", "")
    return os_execute_code("stty -icanon -echo -isig min 0 time 0 2>/dev/null") == 0
end

local function restore_interrupt_polling()
    if interrupt_terminal_state and interrupt_terminal_state ~= "" then
        os_execute_code("stty " .. shell_quote(interrupt_terminal_state) .. " 2>/dev/null")
        interrupt_terminal_state = nil
    end
end

local function user_requested_interrupt()
    if not interrupt_terminal_state then
        return false
    end

    local output = execute_cmd("dd bs=1 count=1 2>/dev/null | od -An -t u1")
    return output and output:match("%f[%d]3%f[%D]") ~= nil
end

local function terminate_task(task)
    if not task or not task.pid then
        return
    end

    os_execute_code(string.format("pkill -TERM -P %d >/dev/null 2>&1", task.pid))
    os_execute_code(string.format("kill %d >/dev/null 2>&1", task.pid))
    os.execute("sleep 0.1")
    os_execute_code(string.format("pkill -KILL -P %d >/dev/null 2>&1", task.pid))
    os_execute_code(string.format("kill -9 %d >/dev/null 2>&1", task.pid))
end

local function run_parallel_tasks(tasks, max_parallel, options)
    options = options or {}
    max_parallel = tonumber(max_parallel) or 1
    if max_parallel < 1 then max_parallel = 1 end

    local running = {}
    local next_task = 1
    local completed = 0
    local cancelled = false
    local terminal_polling = false
    local last_progress = os.time()
    local progress_interval = tonumber(options.progress_interval) or 5

    if options.allow_interrupt then
        terminal_polling = enable_interrupt_polling()
        if terminal_polling and options.on_interrupt_ready then
            options.on_interrupt_ready()
        end
    end

    while next_task <= #tasks or #running > 0 do
        if terminal_polling and user_requested_interrupt() then
            cancelled = true
            if options.on_interrupt then
                options.on_interrupt()
            end
            for _, task in ipairs(running) do
                task.cancelled = true
                terminate_task(task)
            end
            running = {}
            break
        end

        while next_task <= #tasks and #running < max_parallel do
            local task = tasks[next_task]
            task.started_at = os.time()
            task.pid = spawn_background(task.command, task.output_file)
            if not task.pid then
                task.failed_to_start = true
                completed = completed + 1
                if options.on_finish then
                    options.on_finish(task, completed, #tasks)
                end
            else
                table.insert(running, task)
                if options.on_start then
                    options.on_start(task, next_task, #tasks)
                end
            end
            next_task = next_task + 1
        end

        for idx = #running, 1, -1 do
            local task = running[idx]
            local timeout = tonumber(task.timeout) or 30
            if not pid_is_running(task.pid) then
                task.finished = true
                table.remove(running, idx)
                completed = completed + 1
                if options.on_finish then
                    options.on_finish(task, completed, #tasks)
                end
            elseif os.time() - task.started_at > timeout then
                terminate_task(task)
                task.timed_out = true
                table.remove(running, idx)
                completed = completed + 1
                if options.on_timeout then
                    options.on_timeout(task, completed, #tasks)
                end
            end
        end

        if options.on_progress and #running > 0 and os.time() - last_progress >= progress_interval then
            options.on_progress(next_task - 1, completed, #tasks, #running)
            last_progress = os.time()
        end

        if #running > 0 then
            os.execute("sleep 0.1")
        end
    end

    if cancelled then
        for idx = next_task, #tasks do
            tasks[idx].cancelled = true
        end
    end

    if terminal_polling then
        restore_interrupt_polling()
    end

    tasks.cancelled = cancelled
    return tasks
end

local function detect_privilege_escalation()
    local doas_check = execute_cmd("command -v doas >/dev/null 2>&1 && echo 1 || echo 0")
    if doas_check and doas_check:match("1") then return "doas" end
    
    local sudo_check = execute_cmd("command -v sudo >/dev/null 2>&1 && echo 1 || echo 0")
    if sudo_check and sudo_check:match("1") then return "sudo" end
    
    return nil
end

local function restart_zapret(elevate_cmd)
    local restart_cmd = os.getenv("ZAPRET_TEST_RESTART_CMD")
    if restart_cmd and restart_cmd ~= "" then
        local timeout = tonumber(os.getenv("ZAPRET_TEST_RESTART_TIMEOUT") or "30") or 30
        local restart_log = os.getenv("ZAPRET_TEST_RESTART_LOG") or "/tmp/zapret-test-restart.log"
        local restart_tmp = restart_log .. ".tmp"
        log_info("Перезапуск zapret (custom)...")
        local code = os_execute_code(
            string.format(
                "timeout %d sh -c %s > %s 2>&1",
                timeout,
                shell_quote(restart_cmd),
                shell_quote(restart_tmp)
            )
        )
        local result = read_file(restart_tmp) or ""
        append_file(restart_log, "------------------------------------------------------------")
        append_file(restart_log, os.date("%Y-%m-%d %H:%M:%S") .. " | " .. restart_cmd)
        append_file(restart_log, result)
        os.remove(restart_tmp)
        if code == 0 then
            log_ok("Zapret перезапущен (custom)")
            return true
        end
        if code == 124 then
            log_warn("Custom restart command timed out after " .. timeout .. "s")
        end
        log_warn("Custom restart command failed: " .. (result or ""))
        return false
    end

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
            local cmd = "cp " .. shell_quote(ipset_file) .. " " .. shell_quote(backup_file)
            os.execute(cmd)
            log_info("Backup ipset создан: " .. backup_file)
        else
            os.execute("touch " .. shell_quote(backup_file))
            log_info("Backup файл создан (исходный не существовал)")
        end
        -- Очищаем файл ipset (режим "any" = пустой файл)
        write_file(ipset_file, "\n")
        log_info("IPSet очищен (режим 'any')")
    elseif mode == "restore" then
        if file_exists(backup_file) then
            local cmd = "mv " .. shell_quote(backup_file) .. " " .. shell_quote(ipset_file)
            os.execute(cmd)
            log_info("IPSet восстановлен из backup")
        else
            log_warn("Backup файл не найден для восстановления")
        end
    end
end

-- DPI checker defaults (override via MONITOR_* env vars like in monitor.ps1)
local dpiTimeoutSeconds = 5
local dpiRangeBytes = 65536
local dpiMaxParallel = 8
local dpiCustomHost = os.getenv("MONITOR_HOST") or os.getenv("MONITOR_URL")
if os.getenv("MONITOR_TIMEOUT") then dpiTimeoutSeconds = tonumber(os.getenv("MONITOR_TIMEOUT")) or dpiTimeoutSeconds end
if os.getenv("MONITOR_RANGE") then dpiRangeBytes = tonumber(os.getenv("MONITOR_RANGE")) or dpiRangeBytes end
if os.getenv("MONITOR_MAX_PARALLEL") then dpiMaxParallel = tonumber(os.getenv("MONITOR_MAX_PARALLEL")) or dpiMaxParallel end

-- DPI набор и цели
-- Набор тестов из https://github.com/hyperion-cs/dpi-checkers (Apache-2.0 license)
-- Авторские права оригинального репозитория dpi-checkers сохранены
-- Добавлено зеркало файла на github
local function get_dpi_suite()
    -- Possible sources of the suite
    local urls = {
        "https://hyperion-cs.github.io/dpi-checkers/ru/tcp-16-20/suite.v2.json",
        "https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/main/ru/tcp-16-20/suite.v2.json"
    }

    local output = nil
    local used_url = nil

    -- Try each mirror until one works
    for _, url in ipairs(urls) do
        local cmd = string.format("curl -s -L -m %d '%s' 2>/dev/null", dpiTimeoutSeconds, url)
        local result = execute_cmd(cmd)

        if result and result ~= "" and result:match("{") then
            output = result
            used_url = url
            break
        end
    end

    if not output then
        log_warn("Fetch dpi suite failed from all mirrors.")
        return {}
    end

    log_info("DPI suite loaded from: " .. used_url)

    -- Parse suite JSON (simple parser compatible with current v2 format)
    local suite = {}

    for id, provider, country, host in
        output:gmatch('"id"%s*:%s*"([^"]+)".-"provider"%s*:%s*"([^"]+)".-"country"%s*:%s*"([^"]+)".-"host"%s*:%s*"([^"]+)"')
    do
        table.insert(suite, {
            id = id,
            provider = provider,
            country = country,
            host = host
        })
    end

    if #suite == 0 then
        log_warn("Suite downloaded but no targets parsed.")
    else
        log_info("DPI suite entries loaded: " .. #suite)
    end

    return suite
end

local function build_dpi_targets(custom_host)
    local targets = {}

    if custom_host and custom_host ~= "" then
        custom_host = custom_host:gsub("^https?://", ""):gsub("/.*$", "")
        table.insert(targets, { id = "CUSTOM", provider = "Custom", country = "custom", host = custom_host })
    else
        local suite = get_dpi_suite()
        for _, entry in ipairs(suite) do
            table.insert(targets, {
                id = entry.id,
                provider = entry.provider,
                country = entry.country,
                host = entry.host
            })
        end
    end

    return targets
end

-- Функции тестирования
local function get_curl_args(test_label)
    local args = ""
    if test_label == "HTTP" then
        args = "--http1.1"
    elseif test_label == "TLS1.2" then
        args = "--tlsv1.2 --tls-max 1.2"
    elseif test_label == "TLS1.3" then
        args = "--tlsv1.3 --tls-max 1.3"
    end
    return args
end

local function classify_url_output(output, code)
    if not output then return "ERR", 0 end

    -- Проверка на SSL/сертификат ошибки
    if output:match("Could not resolve host") or 
       output:match("certificate") or 
       output:match("SSL certificate problem") or 
       output:match("self[- ]?signed") or 
       output:match("certificate verify failed") or 
       output:match("unable to get local issuer certificate") then
        return "SSL", 0
    end

    local http_code, size = output:match("(%d+)%s+(%d+)")
    if not http_code then
        if output:match("not supported") or
           output:match("does not support") or
           output:match("protocol%s+'.+'%s+not%s+supported") or
           output:match("protocol%s+.+%s+not%s+supported") or
           output:match("unsupported protocol") or
           output:match("unsupported option") or
           output:match("unsupported feature") or
           output:match("Unrecognized option") or
           output:match("Unknown option") or
           output:match("schannel") or
           code == 35 then
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

local function test_url(url, timeout, test_label)
    local args = get_curl_args(test_label)
    local cmd = string.format("curl -I -s -m %d -o /dev/null -w '%%{http_code} %%{size_download}' --show-error %s %s 2>&1", timeout, args, shell_quote(url))
    local output, code = execute_cmd(cmd)
    return classify_url_output(output, code)
end

local function extract_host(url)
    if url:match("^PING:") then
        return url:match("^PING:(.+)$")
    end
    return url:gsub("^https?://", ""):gsub("/.*$", ""):gsub(":.*$", "")
end

local function test_ping(host, count)
    local cmd = string.format("ping -c %d -W 2 %s 2>&1 | grep 'min/avg/max'", count, shell_quote(host))
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

local function pattern_escape(value)
    return (value:gsub("([^%w])", "%%%1"))
end

local function get_target_group(target)
    local name = target.name:lower()
    local host = extract_host(target.value):lower()

    if name:match("youtube") or name:match("google") or
       host:match("youtube") or host:match("youtu%.be") or
       host:match("ytimg") or host:match("google") or
       host:match("googlevideo") or host:match("gstatic") then
        return "google"
    end

    if name:match("discord") or host:match("discord") then
        return "discord"
    end

    if name:match("cloudflare") or host:match("cloudflare") or host:match("cdnjs") then
        return "cloudflare"
    end

    return "other"
end

local function make_url_target_command(target, timeout, tests)
    local command_parts = {}

    for _, test_label in ipairs(tests) do
        local args = get_curl_args(test_label)
        table.insert(command_parts, string.format(
            "printf 'TARGET\\t%s\\tBEGIN\\t%s\\n'; curl -I -s -m %d -o /dev/null -w '%%{http_code} %%{size_download}' --show-error %s %s; code=$?; printf '\\nTARGET\\t%s\\tEXIT\\t%s\\t%%s\\n' \"$code\"",
            target.name,
            test_label,
            timeout,
            args,
            shell_quote(target.value),
            target.name,
            test_label
        ))
    end

    return table.concat(command_parts, "; ")
end

local function parse_url_target_task_result(task, tests, timeout)
    local output = read_file(task.output_file) or ""
    local target_results = {}
    local escaped_target = pattern_escape(task.target.name)

    for _, test_label in ipairs(tests) do
        local escaped_label = pattern_escape(test_label)
        local block, code_text = output:match(
            "TARGET\t" .. escaped_target .. "\tBEGIN\t" .. escaped_label .. "\n(.-)\nTARGET\t" ..
            escaped_target .. "\tEXIT\t" .. escaped_label .. "\t(%d+)"
        )
        local status
        if task.timed_out then
            status = "ERR"
        else
            status = classify_url_output(block or "", tonumber(code_text) or 1)
        end
        table.insert(target_results, { label = test_label, status = status })
    end

    return {
        tests = target_results,
        timed_out = task.timed_out,
        failed_to_start = task.failed_to_start,
        cancelled = task.cancelled,
        group = task.group_name
    }
end

local function run_url_targets_grouped_parallel(targets, timeout, on_target_result, options)
    options = options or {}
    local tests = { "HTTP", "TLS1.2", "TLS1.3" }
    local group_order = { "discord", "google", "cloudflare", "other" }
    local tasks = {}
    local results_by_name = {}
    local emitted = {}

    for _, group_name in ipairs(group_order) do
        for _, target in ipairs(targets) do
            if not target.value:match("^PING:") and get_target_group(target) == group_name then
                table.insert(tasks, {
                    name = target.name,
                    group_name = group_name,
                    target = target,
                    output_file = os.tmpname(),
                    command = make_url_target_command(target, timeout, tests),
                    timeout = timeout * #tests + 5
                })
            end
        end
    end

    local function emit_task(task)
        if emitted[task.name] then
            return
        end

        local target_result = parse_url_target_task_result(task, tests, timeout)
        results_by_name[task.target.name] = target_result

        if on_target_result then
            on_target_result(task.target, target_result)
        end

        emitted[task.name] = true
    end

    run_parallel_tasks(tasks, math.min(#tasks, 2), {
        allow_interrupt = options.allow_interrupt,
        on_interrupt_ready = options.on_interrupt_ready,
        on_interrupt = options.on_interrupt,
        on_finish = function(task)
            emit_task(task)
        end,
        on_timeout = function(task)
            emit_task(task)
        end
    })

    for _, task in ipairs(tasks) do
        if task.pid or task.failed_to_start or task.timed_out or task.finished then
            emit_task(task)
        end
        os.remove(task.output_file)
    end

    results_by_name.cancelled = tasks.cancelled
    return results_by_name
end

local function create_payload_file(size_bytes)
    local path = os.tmpname()
    local code = os_execute_code(string.format("head -c %d /dev/urandom > %s", size_bytes, shell_quote(path)))
    if code ~= 0 then
        os.remove(path)
        return nil
    end
    return path
end

local function dpi_post_check(host, timeout, range_bytes, test_label, payload_file)
    local args = ""
    if test_label == "HTTP" then
        args = "--http1.1"
    elseif test_label == "TLS1.2" then
        args = "--tlsv1.2 --tls-max 1.2"
    elseif test_label == "TLS1.3" then
        args = "--tlsv1.3 --tls-max 1.3"
    end

    local url = "https://" .. host
    local cmd = string.format(
        "curl --range 0-%d -m %d -w '%%{http_code} %%{size_upload} %%{size_download} %%{time_total}' -o /dev/null -X POST --data-binary %s -s --show-error %s %s",
        range_bytes - 1,
        timeout,
        shell_quote("@" .. payload_file),
        args,
        shell_quote(url)
    )
    local output, code = execute_cmd(cmd)
    output = output or ""

    local http_code, size_upload, size_download, time_total = output:match("(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*$")
    if not http_code then
        return {
            status = "ERR",
            code = code or 1,
            http_code = "000",
            upload = 0,
            download = 0,
            time = 0,
            raw = output
        }
    end

    local upload = tonumber(size_upload) or 0
    local download = tonumber(size_download) or 0
    local elapsed = tonumber(time_total) or 0
    local likely_blocked = upload > 0 and download == 0 and elapsed >= timeout and (code or 0) ~= 0
    local status = "OK"

    if likely_blocked then
        status = "LIKELY_BLOCKED"
    elseif (code or 0) ~= 0 then
        status = "ERR"
    end

    return {
        status = status,
        code = code or 0,
        http_code = http_code,
        upload = upload,
        download = download,
        time = elapsed,
        raw = output
    }
end

local function classify_dpi_output(output, code, timeout)
    output = output or ""

    local http_code, size_upload, size_download, time_total = output:match("(%d+)%s+([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)%s*$")
    if not http_code then
        return {
            status = "ERR",
            code = code or 1,
            http_code = "000",
            upload = 0,
            download = 0,
            time = 0,
            raw = output
        }
    end

    local upload = tonumber(size_upload) or 0
    local download = tonumber(size_download) or 0
    local elapsed = tonumber(time_total) or 0
    local likely_blocked = upload > 0 and download == 0 and elapsed >= timeout and (code or 0) ~= 0
    local status = "OK"

    if likely_blocked then
        status = "LIKELY_BLOCKED"
    elseif (code or 0) ~= 0 then
        status = "ERR"
    end

    return {
        status = status,
        code = code or 0,
        http_code = http_code,
        upload = upload,
        download = download,
        time = elapsed,
        raw = output
    }
end

local function parse_dpi_task_result(task, tests, timeout)
    local output = read_file(task.output_file) or ""
    local target_results = {}

    for _, test_label in ipairs(tests) do
        local escaped_label = pattern_escape(test_label)
        local block, code_text = output:match("BEGIN\t" .. escaped_label .. "\n(.-)\nEXIT\t" .. escaped_label .. "\t(%d+)")
        local result
        if task.cancelled then
            result = {
                status = "CANCELLED",
                code = 130,
                http_code = "000",
                upload = 0,
                download = 0,
                time = 0,
                raw = "worker cancelled"
            }
        elseif task.timed_out then
            result = {
                status = "ERR",
                code = 124,
                http_code = "000",
                upload = 0,
                download = 0,
                time = timeout,
                raw = "worker timeout"
            }
        else
            result = classify_dpi_output(block or "", tonumber(code_text) or 1, timeout)
        end
        result.label = test_label
        table.insert(target_results, result)
    end

    return {
        tests = target_results,
        timed_out = task.timed_out,
        failed_to_start = task.failed_to_start,
        cancelled = task.cancelled
    }
end

local function run_dpi_targets_parallel(targets, timeout, range_bytes, payload_file, on_target_result)
    local tests = { "HTTP", "TLS1.2", "TLS1.3" }
    local tasks = {}
    local results_by_id = {}
    local emitted = {}

    for idx, target in ipairs(targets) do
        local output_file = os.tmpname()
        local command_parts = {}

        for _, test_label in ipairs(tests) do
            local args = get_curl_args(test_label)
            local url = "https://" .. target.host
            table.insert(command_parts, string.format(
                "printf 'BEGIN\\t%s\\n'; curl --range 0-%d -m %d -w '%%{http_code} %%{size_upload} %%{size_download} %%{time_total}' -o /dev/null -X POST --data-binary %s -s --show-error %s %s; code=$?; printf '\\nEXIT\\t%s\\t%%s\\n' \"$code\"",
                test_label,
                range_bytes - 1,
                timeout,
                shell_quote("@" .. payload_file),
                args,
                shell_quote(url),
                test_label
            ))
        end

        table.insert(tasks, {
            name = target.id,
            target = target,
            display_name = string.format("%s [%s/%s] %s", target.id, target.provider, target.country or "-", target.host),
            output_file = output_file,
            command = table.concat(command_parts, "; "),
            timeout = timeout * #tests + 5,
            order = idx
        })
    end

    local function emit_task(task)
        if emitted[task.name] then
            return
        end

        local parsed = parse_dpi_task_result(task, tests, timeout)
        results_by_id[task.name] = parsed
        emitted[task.name] = true

        if on_target_result then
            on_target_result(task.target, parsed)
        end
    end

    run_parallel_tasks(tasks, dpiMaxParallel, {
        allow_interrupt = true,
        on_interrupt_ready = function()
            print_info("Для досрочного завершения нажмите Ctrl+C")
        end,
        on_finish = function(task, completed, total)
            emit_task(task)
        end,
        on_timeout = function(task, completed, total)
            emit_task(task)
        end,
        on_interrupt = function()
            log_warn("Получен Ctrl+C, останавливаю DPI проверки...")
        end
    })

    for _, task in ipairs(tasks) do
        if task.pid or task.failed_to_start or task.timed_out or task.finished then
            emit_task(task)
        end
        os.remove(task.output_file)
    end

    results_by_id.cancelled = tasks.cancelled
    return results_by_id
end

local function default_targets()
    return {
        { name = "DiscordMain", value = "https://discord.com" },
        { name = "DiscordGateway", value = "https://gateway.discord.gg" },
        { name = "DiscordCDN", value = "https://cdn.discordapp.com" },
        { name = "DiscordUpdates", value = "https://updates.discord.com" },
        { name = "YouTubeWeb", value = "https://www.youtube.com" },
        { name = "YouTubeShort", value = "https://youtu.be" },
        { name = "YouTubeImage", value = "https://i.ytimg.com" },
        { name = "YouTubeVideoRedirect", value = "https://redirector.googlevideo.com" },
        { name = "GoogleMain", value = "https://www.google.com" },
        { name = "GoogleGstatic", value = "https://www.gstatic.com" },
        { name = "CloudflareWeb", value = "https://www.cloudflare.com" },
        { name = "CloudflareCDN", value = "https://cdnjs.cloudflare.com" },
        { name = "CloudflareDNS1111", value = "PING:1.1.1.1" },
        { name = "CloudflareDNS1001", value = "PING:1.0.0.1" },
        { name = "GoogleDNS8888", value = "PING:8.8.8.8" },
        { name = "GoogleDNS8844", value = "PING:8.8.4.4" },
        { name = "Quad9DNS9999", value = "PING:9.9.9.9" }
    }
end

local function load_targets(targets_file)
    local targets = {}

    if not file_exists(targets_file) then
        log_warn("targets.txt не найден, используются встроенные цели")
        return default_targets()
    end

    for line in io.lines(targets_file) do
        if not line:match("^%s*#") and line:match("=") then
            local name, value = line:match("^%s*(%w+)%s*=%s*\"(.+)\"%s*$")
            if name and value then
                table.insert(targets, { name = name, value = value })
            end
        end
    end

    if #targets == 0 then
        log_warn("targets.txt пустой, используются встроенные цели")
        return default_targets()
    end

    return targets
end

local function render_standard_target_result(target, timeout, profile, target_parallel, stats)
    local line = string.format("  %-30s ", target.name)
    io.write(line)

    if target.value:match("^PING:") then
        local host = target.value:match("^PING:(.+)$")
        local result = test_ping(host, 3)
        local output = colorize("Пинг: " .. result, colors.cyan)
        print(output)
        write_log(string.format("%-30s Пинг: %s", target.name, result))
        stats.total = stats.total + 1
        if result ~= "Timeout" then
            stats.ok = stats.ok + 1
            stats.ping_ok = stats.ping_ok + 1
        else
            stats.err = stats.err + 1
            stats.ping_fail = stats.ping_fail + 1
        end
        return
    end

    local results = {}
    local log_results = {}

    for _, test_label in ipairs({ "HTTP", "TLS1.2", "TLS1.3" }) do
        local status
        if profile == "fast" and target_parallel then
            for _, test_result in ipairs(target_parallel.tests or {}) do
                if test_result.label == test_label then
                    status = test_result.status
                    break
                end
            end
            status = status or "ERR"
        else
            status = test_url(target.value, timeout, test_label)
        end

        local color = colors.green
        if status == "SSL" then color = colors.red
        elseif status == "UNSUP" then color = colors.yellow
        elseif status == "ERR" then color = colors.red end
        table.insert(results, colorize(test_label .. ":" .. status, color))
        table.insert(log_results, test_label .. ":" .. status)
        stats.total = stats.total + 1
        if status == "OK" then
            stats.ok = stats.ok + 1
        elseif status == "SSL" then
            stats.ssl = stats.ssl + 1
            stats.err = stats.err + 1
        elseif status == "UNSUP" then
            stats.unsupported = stats.unsupported + 1
        else
            stats.err = stats.err + 1
        end
    end

    if profile == "fast" and target_parallel and target_parallel.timed_out then
        table.insert(log_results, "worker:TIMEOUT")
    elseif profile == "fast" and target_parallel and target_parallel.failed_to_start then
        table.insert(log_results, "worker:START_ERR")
    elseif profile == "fast" and target_parallel and target_parallel.cancelled then
        table.insert(log_results, "worker:CANCELLED")
    end

    local ping_host = extract_host(target.value)
    local ping_result = test_ping(ping_host, 3)
    if ping_result ~= "Timeout" then
        stats.ping_ok = stats.ping_ok + 1
    else
        stats.ping_fail = stats.ping_fail + 1
    end
    table.insert(results, colorize("Ping:" .. ping_result, colors.cyan))
    table.insert(log_results, "Ping:" .. ping_result)

    print(table.concat(results, " "))
    write_log(string.format("%-30s %s", target.name, table.concat(log_results, " ")))
end

local function run_standard_tests(config_name, targets, timeout, profile)
    profile = profile or "accurate"
    print(colorize("  > Запуск тестов...", colors.darkgray))
    write_log("> Запуск тестов...")

    local stats = {
        config = config_name,
        total = 0,
        ok = 0,
        err = 0,
        ssl = 0,
        unsupported = 0,
        ping_ok = 0,
        ping_fail = 0
    }

    if profile == "fast" then
        local pending_results = {}
        local next_index = 1

        local function flush_ready()
            while next_index <= #targets do
                local target = targets[next_index]

                if target.value:match("^PING:") then
                    render_standard_target_result(target, timeout, profile, nil, stats)
                    next_index = next_index + 1
                elseif pending_results[target.name] then
                    render_standard_target_result(target, timeout, profile, pending_results[target.name], stats)
                    pending_results[target.name] = nil
                    next_index = next_index + 1
                else
                    break
                end
            end
        end

        local parallel_results = run_url_targets_grouped_parallel(targets, timeout, function(target, target_parallel)
            pending_results[target.name] = target_parallel
            flush_ready()
        end, {
            allow_interrupt = true,
            on_interrupt_ready = function()
                print_info("Для досрочного завершения нажмите Ctrl+C")
            end,
            on_interrupt = function()
                log_warn("Получен Ctrl+C, останавливаю проверки стратегии...")
            end
        })

        flush_ready()
        stats.cancelled = parallel_results.cancelled == true
    else
        local terminal_polling = enable_interrupt_polling()
        if terminal_polling then
            print_info("Для досрочного завершения нажмите Ctrl+C")
        end

        for _, target in ipairs(targets) do
            if terminal_polling and user_requested_interrupt() then
                stats.cancelled = true
                log_warn("Получен Ctrl+C, останавливаю проверки стратегии...")
                break
            end

            render_standard_target_result(target, timeout, profile, nil, stats)
        end

        if terminal_polling then
            restore_interrupt_polling()
        end
    end

    local score = 0
    if stats.total > 0 then
        score = math.floor((stats.ok / stats.total) * 1000 + 0.5) / 10
    end
    stats.score = score
    log_info(string.format(
        "Итог %s: OK %d/%d (%.1f%%), ERR %d, SSL %d, UNSUP %d, ping OK %d, ping FAIL %d",
        config_name, stats.ok, stats.total, stats.score, stats.err, stats.ssl, stats.unsupported, stats.ping_ok, stats.ping_fail
    ))
    if stats.cancelled then
        log_warn("Проверки стратегии отменены пользователем.")
    end
    return stats
end

local function read_standard_profile_selection()
    local env_profile = os.getenv("ZAPRET_TEST_PROFILE")
    if env_profile then
        env_profile = env_profile:lower()
        if env_profile == "1" or env_profile == "accurate" then
            return "accurate"
        elseif env_profile == "2" or env_profile == "fast" or env_profile == "parallel" then
            return "fast"
        end
    end

    while true do
        print("")
        print(colorize("Выберите профиль стандартных тестов:", colors.cyan))
        print("  [1] Точный (последовательно, рекомендуется)")
        print("  [2] Быстрый (возможны ложные ERR)")
        io.write("Введите 1 или 2: ")
        local choice = io.read()

        if choice == "1" then
            return "accurate"
        elseif choice == "2" then
            return "fast"
        else
            print(colorize("Неверный ввод. Попробуйте снова.", colors.yellow))
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
        print("Введите номера конфигов (0 = все, можно 1,3,5 или 2-7):")
        io.write("> ")
        local input = io.read()
        
        local selected = {}
        local seen = {}

        local function add_config(num)
            if num >= 1 and num <= #all_configs and not seen[num] then
                table.insert(selected, all_configs[num])
                seen[num] = true
            end
        end

        if input:match("^%s*0%s*$") then
            for idx, config in ipairs(all_configs) do
                table.insert(selected, config)
                seen[idx] = true
            end
        else
            for token in input:gmatch("[^,%s]+") do
                local from_num, to_num = token:match("^(%d+)%-(%d+)$")
                if from_num and to_num then
                    from_num = tonumber(from_num)
                    to_num = tonumber(to_num)
                    if from_num > to_num then
                        from_num, to_num = to_num, from_num
                    end
                    for num = from_num, to_num do
                        add_config(num)
                    end
                else
                    local num = tonumber(token)
                    if num then
                        add_config(num)
                    end
                end
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

local function render_dpi_target_result(target, target_parallel, stats)
    print("")
    local header = string.format("=== %s [%s/%s] %s ===", target.id, target.provider, target.country or "-", target.host)
    print(colorize(header, colors.darkcyan))
    write_log(header)

    local target_blocked = false

    for _, result in ipairs(target_parallel and target_parallel.tests or {}) do
        stats.total = stats.total + 1

        local color = colors.green
        if result.status == "LIKELY_BLOCKED" then
            color = colors.yellow
            stats.blocked = stats.blocked + 1
            target_blocked = true
        elseif result.status == "CANCELLED" then
            color = colors.yellow
            stats.err = stats.err + 1
        elseif result.status == "ERR" then
            color = colors.red
            stats.err = stats.err + 1
        else
            stats.ok = stats.ok + 1
        end

        local msg = string.format(
            "  [%s][%s] http=%s exit=%s buf_up=%d buf_down=%d time=%.2fs status=%s",
            target.id,
            result.label,
            result.http_code,
            tostring(result.code),
            result.upload,
            result.download,
            result.time,
            result.status
        )
        print(colorize(msg, color))
        write_log(msg)
    end

    if not target_parallel then
        local msg = string.format("  [%s] worker result missing", target.id)
        print(colorize(msg, colors.red))
        write_log(msg)
        stats.err = stats.err + 3
        stats.total = stats.total + 3
    elseif target_parallel.timed_out then
        local msg = string.format("  [%s] worker timed out", target.id)
        print(colorize(msg, colors.red))
        write_log(msg)
    elseif target_parallel.failed_to_start then
        local msg = string.format("  [%s] worker failed to start", target.id)
        print(colorize(msg, colors.red))
        write_log(msg)
    elseif target_parallel.cancelled then
        local msg = string.format("  [%s] worker cancelled", target.id)
        print(colorize(msg, colors.yellow))
        write_log(msg)
    end

    if target_parallel and target_parallel.cancelled then
        local msg = "  Проверка цели отменена пользователем."
        print(colorize(msg, colors.yellow))
        write_log(msg)
    elseif target_blocked then
        local msg = "  Паттерн совпадает с TCP 16-20 freeze: upload есть, ответа нет до timeout."
        print(colorize(msg, colors.yellow))
        write_log(msg)
    else
        local msg = "  TCP 16-20 freeze не обнаружен для этой цели."
        print(colorize(msg, colors.green))
        write_log(msg)
    end
end

local function run_dpi_tests(targets, timeout, range_bytes)
    if #targets == 0 then
        log_error("Нет DPI целей для тестирования")
        return { total = 0, blocked = 0, ok = 0, err = 0 }
    end

    log_info(string.format(
        "Целей: %d. Диапазон upload: 0-%d байт; Таймаут: %d с",
        #targets, range_bytes - 1, timeout
    ))
    log_info(string.format(
        "Параллельные DPI проверки: до %d целей одновременно",
        dpiMaxParallel
    ))
    log_info("Запуск проверок DPI TCP 16-20 через POST upload...")
    log_info("Результаты DPI будут появляться по мере готовности целей")

    local payload_file = create_payload_file(range_bytes)
    if not payload_file then
        log_error("Не удалось создать временный payload для DPI теста")
        return { total = 0, blocked = 0, ok = 0, err = 0 }
    end

    local stats = { total = 0, blocked = 0, ok = 0, err = 0 }
    local parallel_results = run_dpi_targets_parallel(targets, timeout, range_bytes, payload_file, function(target, target_parallel)
        render_dpi_target_result(target, target_parallel, stats)
    end)
    local cancelled = parallel_results.cancelled == true

    os.remove(payload_file)

    print("")
    if cancelled then
        stats.cancelled = true
        log_warn("DPI проверки отменены пользователем.")
    elseif stats.blocked > 0 then
        log_error(string.format("DPI freeze найден: %d/%d проверок. Рассмотрите изменение стратегии/SNI/IP.", stats.blocked, stats.total))
    else
        log_ok("DPI freeze не найден.")
    end

    return stats
end

-- Основной скрипт
local function main()
    -- Определяем директорию utils, где лежит сам скрипт
    local utils_dir = arg[0]:match("(.*/)")
    if not utils_dir then
        utils_dir = "./"
    end
    
    -- Корневая директория проекта (родитель папки utils)
    local root_dir = utils_dir .. "../"
    
    local configs_dir = os.getenv("ZAPRET_TEST_CONFIGS_DIR") or (root_dir .. "configs")
    local targets_file = os.getenv("ZAPRET_TEST_TARGETS_FILE") or (utils_dir .. "targets.txt")
    local log_dir = os.getenv("ZAPRET_TEST_LOG_DIR") or (utils_dir .. "log")
    local zapret_config = os.getenv("ZAPRET_TEST_CONFIG") or "/opt/zapret/config"
    local zapret_config_backup = os.getenv("ZAPRET_TEST_CONFIG_BACKUP") or (zapret_config .. ".back")

    -- Проверка доступности curl
    local curl_check = execute_cmd("which curl")
    if not curl_check or curl_check == "" then
        print(colorize("[ERROR] curl не найден. Пожалуйста, установите curl.", colors.red))
        os.exit(1)
    end

    -- Определение повышения привилегий
    local elevate_cmd = detect_privilege_escalation()
    local custom_restart_cmd = os.getenv("ZAPRET_TEST_RESTART_CMD")
    if not elevate_cmd and (not custom_restart_cmd or custom_restart_cmd == "") then
        print(colorize("[ERROR] sudo или doas не найдены", colors.red))
        os.exit(1)
    end
    if elevate_cmd then
        print(colorize("[OK] Повышение привилегий: " .. elevate_cmd, colors.green))
    else
        print(colorize("[OK] Перезапуск: custom command", colors.green))
    end

    -- Поиск всех файлов конфигов (исключая старые конфиги)
    local configs = {}
    local handle = io.popen("ls -1 " .. shell_quote(configs_dir) .. " 2>/dev/null | grep -v '^\\.' | grep -v '^old' | sort")
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

    if test_type ~= "1" and test_type ~= "2" then
        print(colorize("[ERROR] Неверный выбор", colors.red))
        os.exit(1)
    end

    test_type = (test_type == "1") and "standard" or "dpi"

    local standard_profile = "accurate"
    if test_type == "standard" then
        standard_profile = read_standard_profile_selection()
    end

    -- Выбор режима тестирования (все или выбранные конфиги)
    local mode = read_mode_selection()
    if mode == "select" then
        configs = select_configs(configs)
    end

    -- Инициализация логирования после выбора типа теста
    if not init_log(log_dir, test_type) then
        print(colorize("[ERROR] Не удалось инициализировать файл лога", colors.red))
        os.exit(1)
    end

    log_info("Тест запущен из: " .. root_dir)
    if test_type == "standard" then
        log_info("Профиль стандартных тестов: " .. standard_profile)
        if standard_profile == "fast" then
            log_warn("Быстрый профиль: параллельные curl проверки могут давать ложные ERR")
        else
            log_info("Точный профиль: curl проверки выполняются последовательно")
        end
    end

    -- Загрузка целей для стандартных тестов
    local targets = {}
    if test_type == "standard" then
        targets = load_targets(targets_file)
    else
        targets = build_dpi_targets(dpiCustomHost)
    end

    -- Резервная копия текущего конфига
    if file_exists(zapret_config_backup) then
        log_warn("Резервная копия конфига уже существует, используется существующая")
    else
        if file_exists(zapret_config) then
            os.execute("cp " .. shell_quote(zapret_config) .. " " .. shell_quote(zapret_config_backup))
            log_ok("Текущий конфиг сохранён в " .. zapret_config_backup)
        end
    end

    -- Для DPI тестов переключаем ipset в режим "any"
    local ipset_file = os.getenv("ZAPRET_TEST_IPSET_FILE") or "/opt/zapret/hostlists/ipset-all.txt"
    local ipset_backup = ipset_file .. ".test-backup"
    local original_ipset_status = nil
    
    if test_type == "dpi" then
        original_ipset_status = get_ipset_status(ipset_file)
        if original_ipset_status ~= "any" then
            log_warn("Переключение ipset в режим 'any' для точных DPI тестов...")
            set_ipset_mode("any", ipset_file, ipset_backup)
            restart_zapret(elevate_cmd)
            os.execute("sleep 3")
        end
    end

    -- Запуск тестов для каждого конфига
    local summaries = {}
    local stop_requested = false
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

        os.execute("cp " .. shell_quote(source_config) .. " " .. shell_quote(zapret_config))
        log_info("Конфиг скопирован в " .. zapret_config)

        -- Перезапуск zapret
        restart_zapret(elevate_cmd)
        os.execute("sleep 3")

        if test_type == "standard" then
            local stats = run_standard_tests(config, targets, dpiTimeoutSeconds, standard_profile)
            table.insert(summaries, stats)
            if stats.cancelled then
                stop_requested = true
            end
        else
            local stats = run_dpi_tests(targets, dpiTimeoutSeconds, dpiRangeBytes)
            stats.config = config
            table.insert(summaries, stats)
            if stats.cancelled then
                stop_requested = true
            end
        end

        ::continue::
        if stop_requested then
            log_warn("Тестирование остановлено пользователем")
            break
        end
        if idx < #configs then
            os.execute("sleep 2")
        end
    end

    if #summaries > 0 then
        print("")
        log_info("Сводка по конфигам:")
        if stop_requested then
            log_warn("Сводка неполная: тестирование остановлено пользователем")
        end
        local best = nil
        for _, stats in ipairs(summaries) do
            if test_type == "standard" then
                local msg = string.format(
                    "  %-30s OK %d/%d (%.1f%%), ERR %d, SSL %d, UNSUP %d, ping OK %d, ping FAIL %d",
                    stats.config,
                    stats.ok,
                    stats.total,
                    stats.score or 0,
                    stats.err,
                    stats.ssl,
                    stats.unsupported,
                    stats.ping_ok,
                    stats.ping_fail
                )
                print(msg)
                write_log(msg)
                if not best or (stats.score or 0) > (best.score or 0) then
                    best = stats
                end
            else
                local clean = stats.total - stats.blocked - stats.err
                local msg = string.format(
                    "  %-30s clean %d/%d, blocked %d, err %d",
                    stats.config,
                    clean,
                    stats.total,
                    stats.blocked,
                    stats.err
                )
                print(msg)
                write_log(msg)
                if not best or stats.blocked < best.blocked or (stats.blocked == best.blocked and stats.err < best.err) then
                    best = stats
                end
            end
        end
        if best then
            if stop_requested then
                log_warn("Лучший конфиг не выбран: тестирование остановлено пользователем")
            elseif test_type == "standard" then
                log_ok(string.format("Лучший конфиг: %s (%.1f%% OK)", best.config, best.score or 0))
            else
                log_ok(string.format("Лучший конфиг: %s (blocked %d, err %d)", best.config, best.blocked, best.err))
            end
        end
    end

    -- Восстановление исходного конфига и ipset
    local need_restart = false
    
    if file_exists(zapret_config_backup) then
        os.execute("mv " .. shell_quote(zapret_config_backup) .. " " .. shell_quote(zapret_config))
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
