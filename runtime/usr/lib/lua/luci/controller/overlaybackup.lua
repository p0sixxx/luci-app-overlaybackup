module("luci.controller.overlaybackup", package.seeall)

local i18n = require "luci.i18n"

-- Переводы подхватываются сами: диспетчер luci-lua-runtime на каждом запросе
-- вызывает i18n.setlanguage(), а тот загружает ВСЕ файлы *.<язык>.lmo из
-- /usr/lib/lua/luci/i18n, включая наш overlaybackup.<язык>.lmo. Загружать
-- каталог поштучно не нужно, и функции для этого в рантайме нет.
-- Если каталога нет, LuCI показывает исходные английские строки.

function index()
    -- Каталог здесь намеренно НЕ загружается. Дерево диспетчера кэшируется
    -- в /tmp/luci-indexcache независимо от языка, поэтому в него должен
    -- попасть исходный английский заголовок: тему LuCI переводит пункт меню
    -- при отрисовке, и тогда он следует текущему языку. Переведи мы заголовок
    -- здесь - в кэше осел бы русский текст, и после переключения языка меню
    -- осталось бы русским до сброса кэша.
    entry({"admin", "system", "overlaybackup"}, firstchild(), _("Overlay backup and restore"), 60).dependent = false
    entry({"admin", "system", "overlaybackup", "backup"}, call("action_backup_page"), _("Overlay backup and restore"), 10)
    entry({"admin", "system", "overlaybackup", "create_backup"}, call("create_backup"), nil)
    entry({"admin", "system", "overlaybackup", "delete_backup"}, call("delete_backup"), nil)
    entry({"admin", "system", "overlaybackup", "download"}, call("download_backup"), nil)
    entry({"admin", "system", "overlaybackup", "restore"}, call("restore_backup"), nil)
end

-- Архив в /tmp называется так же, как его получает браузер:
-- overlay-backup-<имя устройства>-<ГГГГ-ММ-ДД>.tar.gz
-- Поэтому фиксированного пути нет, и архив ищется по маске.
local BACKUP_GLOB = "/tmp/overlay-backup-*.tar.gz"

local function backup_filename()
    local fs = require "nixio.fs"

    local hostname = fs.readfile("/proc/sys/kernel/hostname") or ""
    hostname = hostname:gsub("%s", "")
    -- Оставляем только безопасные для имени файла символы: имя хоста
    -- задаёт пользователь, и кавычка или слэш сломали бы заголовок
    -- Content-Disposition.
    hostname = hostname:gsub("[^%w%-_.]", "_")
    if hostname == "" then
        hostname = "openwrt"
    end

    return string.format("overlay-backup-%s-%s.tar.gz", hostname, os.date("%Y-%m-%d"))
end

-- Путь к самому свежему архиву в /tmp или nil, если архива нет.
local function find_backup()
    local p = io.popen("ls -1t " .. BACKUP_GLOB .. " 2>/dev/null")
    if not p then
        return nil
    end
    local path = p:read("*l")
    p:close()

    if path and path:match("%S") then
        return path
    end
    return nil
end

-- Имя файла без каталога - его показываем на странице и отдаём браузеру.
local function backup_basename(path)
    return path and path:match("([^/]+)$") or nil
end

-- Удаляем все архивы разом: имя зависит от даты, поэтому за несколько
-- дней их может накопиться несколько. Заодно подчищаем overlay.tar.gz -
-- так архив назывался в прежних версиях плагина, и после обновления он
-- иначе остался бы висеть в /tmp незамеченным.
local function remove_backups()
    os.execute("rm -f " .. BACKUP_GLOB .. " /tmp/overlay.tar.gz >/dev/null 2>&1")
end

function action_backup_page()
    local fs = require "nixio.fs"
    local tpl = require "luci.template"

    local backup_file = find_backup()
    local log_file = "/tmp/overlay-backup.log"
    local restore_ok_file = "/tmp/overlay-restore-success.log"
    local restore_err_file = "/tmp/overlay-restore-error.log"

    -- Показываем лог ошибки только один раз - сразу после неудачной
    -- попытки. Прочитали - тут же удаляем, чтобы при следующей
    -- перезагрузке страницы (без новой попытки) блок ошибки не висел.
    local error_log = nil
    if not backup_file and fs.access(log_file) then
        error_log = fs.readfile(log_file)
        os.remove(log_file)
    end

    -- Аналогично для результата восстановления - однократное сообщение.
    local restore_ok = nil
    local restore_log = nil
    if fs.access(restore_ok_file) then
        restore_ok = true
        restore_log = fs.readfile(restore_ok_file)
        os.remove(restore_ok_file)
    elseif fs.access(restore_err_file) then
        restore_ok = false
        restore_log = fs.readfile(restore_err_file)
        os.remove(restore_err_file)
    end

    tpl.render("overlaybackup", {
        backup_name = backup_basename(backup_file),
        error_log = error_log,
        restore_ok = restore_ok,
        restore_log = restore_log
    })
end

function create_backup()
    local backup_file = "/tmp/" .. backup_filename()
    local log_file = "/tmp/overlay-backup.log"
    local exclude_file = "/tmp/overlay-backup-exclude.list"
    local fs = require "nixio.fs"

    -- На большинстве устройств данные overlay лежат в /overlay/upper,
    -- служебная /overlay/work нам не нужна. Но если по какой-то причине
    -- такой раскладки нет - подстрахуемся и заберём /overlay целиком.
    local source_dir = "/overlay/upper"
    if not fs.stat(source_dir) then
        source_dir = "/overlay"
    end

    -- Разрываем хардлинки перед архивацией: если в overlay есть файлы
    -- с несколькими именами на один inode (например, дублирующиеся
    -- скрипты в /etc/uci-defaults), tar сохранит их как hardlink-записи,
    -- а при восстановлении на overlayfs создание hardlink может падать
    -- с "Operation not permitted". Превращаем такие файлы в независимые
    -- копии - на содержимое и работу системы это не влияет.
    os.execute(string.format(
        "find %s -xdev -type f -links +1 -exec sh -c 'cp -p \"$1\" \"$1.tmp_delink\" && mv \"$1.tmp_delink\" \"$1\"' _ {} \\; > %s 2>&1",
        source_dir, log_file
    ))

    -- BusyBox tar (используется в этой прошивке) не понимает длинную опцию
    -- --exclude=..., только -X FILE со списком шаблонов - поэтому пишем
    -- шаблоны исключения в отдельный файл.
    fs.writefile(exclude_file, "work\n./work\n")

    local cmd = string.format(
        "tar -czf %s -C %s -X %s . >> %s 2>&1",
        backup_file, source_dir, exclude_file, log_file
    )

    -- Прежние архивы убираем до создания нового: их имена отличаются
    -- датой, и иначе в /tmp копились бы копии за разные дни.
    remove_backups()
    local ok = os.execute(cmd)

    if ok == true or ok == 0 then
        -- успех - лог и файл исключений больше не нужны
        os.remove(log_file)
        os.remove(exclude_file)
    else
        -- tar создаёт файл даже когда падает на полпути. Недоделанный
        -- архив надо убрать: иначе страница сочтёт бэкап готовым и не
        -- покажет лог ошибки, а пользователь скачает битый файл.
        remove_backups()
        os.remove(exclude_file)
    end

    luci.http.redirect(luci.dispatcher.build_url("admin/system/overlaybackup/backup"))
end

function download_backup()
    local backup_file = find_backup()
    local fs = require "nixio.fs"
    if backup_file and fs.access(backup_file) then
        local stat = fs.stat(backup_file)
        local name = backup_basename(backup_file)

        luci.http.header('Content-Disposition', 'attachment; filename="' .. name .. '"')
        if stat and stat.size then
            luci.http.header('Content-Length', tostring(stat.size))
        end
        luci.http.prepare_content("application/x-tar-gz")

        -- Читаем и отдаём файл блоками, а не целиком в память -
        -- иначе на устройствах с малым объёмом RAM процесс может
        -- падать на больших архивах, обрывая ответ (видно в браузере
        -- как "Bad Request").
        local f = io.open(backup_file, "rb")
        if f then
            local block = 65536
            local chunk = f:read(block)
            while chunk do
                luci.http.write(chunk)
                chunk = f:read(block)
            end
            f:close()
        else
            luci.http.status(500, "Unable to open backup file")
        end
    else
        luci.http.status(404, "Backup file not found")
    end
end

function restore_backup()
    local fs = require "nixio.fs"

    local upload_path = "/tmp/overlay-restore-upload.tar.gz"
    local ok_file = "/tmp/overlay-restore-success.log"
    local err_file = "/tmp/overlay-restore-error.log"

    os.remove(ok_file)
    os.remove(err_file)
    os.remove(upload_path)

    -- Принимаем загружаемый файл потоково (пишем чанки на диск сразу),
    -- а не собираем всё в памяти - архив может быть довольно большим.
    local fd
    luci.http.setfilehandler(function(meta, chunk, eof)
        if not fd then
            fd = io.open(upload_path, "wb")
        end
        if chunk and fd then
            fd:write(chunk)
        end
        if eof and fd then
            fd:close()
            fd = nil
        end
    end)

    -- Сам вызов formvalue() запускает разбор multipart-тела запроса,
    -- в процессе которого сработает обработчик выше.
    luci.http.formvalue("archive")

    if not fs.access(upload_path) then
        fs.writefile(err_file, i18n.translate(
            "The archive file was not received. Make sure you selected a file before pressing the button.") .. "\n")
        luci.http.redirect(luci.dispatcher.build_url("admin/system/overlaybackup/backup"))
        return
    end

    -- Куда именно распаковывать: та же логика, что и при создании
    -- бэкапа. Важно: пишем прямо в /overlay/upper, а НЕ в "/" -
    -- при распаковке в объединённый (merged) overlay ядро может
    -- отказывать в замене файлов, унаследованных из read-only слоя
    -- (симлинки, хардлинки) с ошибкой "Operation not permitted".
    -- Запись напрямую в upper-слой минует эту union-механику.
    local target_dir = "/overlay/upper"
    if not fs.stat(target_dir) then
        target_dir = "/overlay"
    end

    local log_file = "/tmp/overlay-restore.log"
    local cmd = string.format(
        "tar -xzf %s -C %s > %s 2>&1",
        upload_path, target_dir, log_file
    )
    local ok = os.execute(cmd)
    local tar_output = fs.readfile(log_file) or ""

    os.remove(upload_path)
    os.remove(log_file)

    if ok == true or ok == 0 then
        -- В лог кладём только реальный вывод tar (обычно он пустой при
        -- успехе) - текст про успех и перезагрузку уже показан в плашке
        -- выше, дублировать его в блоке лога не нужно.
        fs.writefile(ok_file, tar_output)

        -- Перезагрузка с небольшой задержкой и в фоне - чтобы этот HTTP-ответ
        -- (редирект + отрисовка страницы с сообщением) успел дойти до браузера
        -- прежде, чем соединение оборвётся из-за ребута.
        os.execute("(sleep 3 && reboot) >/dev/null 2>&1 &")
    else
        fs.writefile(err_file, tar_output)
    end

    luci.http.redirect(luci.dispatcher.build_url("admin/system/overlaybackup/backup"))
end

function delete_backup()
    local log_file = "/tmp/overlay-backup.log"
    local exclude_file = "/tmp/overlay-backup-exclude.list"
    remove_backups()
    if nixio.fs.access(log_file) then
        os.remove(log_file)
    end
    if nixio.fs.access(exclude_file) then
        os.remove(exclude_file)
    end
    luci.http.redirect(luci.dispatcher.build_url("admin/system/overlaybackup/backup"))
end
