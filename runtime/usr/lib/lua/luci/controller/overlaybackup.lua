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
    entry({"admin", "system", "overlaybackup", "download"}, call("download_backup"), nil)
    entry({"admin", "system", "overlaybackup", "restore"}, call("restore_backup"), nil)
    entry({"admin", "system", "overlaybackup", "cancel"}, call("cancel_restore"), nil)
end

-- Рабочий каталог лежит РЯДОМ с upper, на той же файловой системе и вне
-- смонтированного объединения. Это принципиально: распаковка идёт сюда,
-- а не в живой upper, и подменой слоя занимается init-скрипт на загрузке.
local STAGE_ROOT = "/overlay/.overlaybackup"
local UPLOAD     = STAGE_ROOT .. "/upload.tar.gz"
local STAGING    = STAGE_ROOT .. "/staging"
local PREVIOUS   = STAGE_ROOT .. "/previous"
local PENDING    = STAGE_ROOT .. "/pending"
local LOGFILE    = STAGE_ROOT .. "/restore.log"

local UPPER = "/overlay/upper"

-- ------------------------------------------------------------------
-- вспомогательное
-- ------------------------------------------------------------------

-- Оставляем только безопасные для имени файла символы: имя хоста задаёт
-- пользователь, а кавычка или слэш сломали бы заголовок Content-Disposition.
local function safe_part(value)
    value = (value or ""):gsub("%s", "")
    return (value:gsub("[^%w%-_.]", "_"))
end

-- Версия прошивки: DISTRIB_RELEASE из /etc/openwrt_release, с откатом на
-- VERSION_ID из /etc/os-release. На снапшотах это будет "SNAPSHOT", и это
-- ровно то, что нужно знать про такой архив.
local function openwrt_release()
    local fs = require "nixio.fs"

    local release = (fs.readfile("/etc/openwrt_release") or "")
        :match("DISTRIB_RELEASE=[\"\']?([^\"\'\n]+)")

    if not release then
        release = (fs.readfile("/etc/os-release") or "")
            :match("VERSION_ID=[\"\']?([^\"\'\n]+)")
    end

    return safe_part(release)
end

local function backup_filename()
    local fs = require "nixio.fs"

    local hostname = safe_part(fs.readfile("/proc/sys/kernel/hostname"))
    if hostname == "" then
        hostname = "openwrt"
    end

    -- Версия ставится отдельным полем между именем устройства и датой.
    -- Если определить её не удалось, поле просто выпадает: лучше короткое
    -- имя, чем слово-заглушка в нём.
    local release = openwrt_release()
    if release ~= "" then
        release = release .. "-"
    end

    return string.format("overlay-backup-%s-%s%s.tar.gz",
        hostname, release, os.date("%Y-%m-%d"))
end

-- Путь к GNU tar или nil, если его нет.
--
-- Это не придирка к вкусу: метки overlayfs живут в расширенных атрибутах
-- (trusted.overlay.opaque на каталоге, перекрывающем нижний слой), а
-- BusyBox tar про xattr не знает вообще и молча их теряет. Архив при этом
-- выглядит целым, но после восстановления удалённые каталоги возвращаются
-- из прошивки. Сохранить их умеет только GNU tar с --xattrs.
local function gnu_tar()
    local fs = require "nixio.fs"

    for _, path in ipairs({ "/usr/bin/tar", "/bin/tar", "/usr/sbin/tar" }) do
        if fs.access(path) then
            local p = io.popen(path .. " --version 2>/dev/null", "r")
            if p then
                local first = p:read("*l") or ""
                p:close()
                if first:match("GNU tar") then
                    return path
                end
            end
        end
    end

    return nil
end

-- Ключи сохранения метаданных для GNU tar. Глоб обязательно в кавычках:
-- иначе его раскрыл бы шелл. --hard-dereference только при создании - он
-- превращает хардлинки в обычные файлы, и живую систему для этого трогать
-- не надо (прежние версии плагина ради этого правили файлы в overlay).
local XATTR_BASE    = " --xattrs --xattrs-include='trusted.overlay.*' --numeric-owner"
local XATTR_CREATE  = XATTR_BASE .. " --hard-dereference"
local XATTR_EXTRACT = XATTR_BASE

-- os.execute возвращает код возврата в Lua 5.1 и true/false в 5.2+.
local function succeeded(rc)
    return rc == true or rc == 0
end

-- Что архивируем. На большинстве устройств изменения лежат в /overlay/upper;
-- если такой раскладки нет, забираем /overlay целиком.
local function source_dir()
    local fs = require "nixio.fs"
    if fs.stat(UPPER) then
        return UPPER
    end
    return "/overlay"
end

-- ------------------------------------------------------------------
-- страница
-- ------------------------------------------------------------------

function action_backup_page()
    local fs = require "nixio.fs"
    local tpl = require "luci.template"

    -- Результат прошлой попытки показываем один раз: прочитали - удалили,
    -- чтобы сообщение не висело при следующем открытии страницы.
    local message = nil
    if fs.access(LOGFILE) then
        message = fs.readfile(LOGFILE)
        os.remove(LOGFILE)
    end

    tpl.render("overlaybackup", {
        pending      = fs.access(PENDING) and (fs.readfile(PENDING) or "") or nil,
        previous     = fs.stat(PREVIOUS) and true or nil,
        has_gnu_tar  = gnu_tar() and true or false,
        error_log    = message
    })
end

-- ------------------------------------------------------------------
-- бэкап: архив отдаётся потоком, без промежуточного файла
-- ------------------------------------------------------------------

function download_backup()
    local dir = source_dir()
    local tar = gnu_tar()
    local cmd

    if tar then
        -- Исключения нужны только когда архивируем /overlay целиком:
        -- work - служебный каталог overlayfs, .overlaybackup - наш.
        local exclude = ""
        if dir ~= UPPER then
            exclude = " --exclude=./work --exclude=./.overlaybackup"
        end
        cmd = string.format("%s%s%s -czf - -C %s . 2>/dev/null",
            tar, XATTR_CREATE, exclude, dir)
    else
        -- BusyBox tar не понимает длинную опцию --exclude, только -X FILE
        -- со списком шаблонов.
        local exclude = ""
        if dir ~= UPPER then
            local list = "/tmp/overlay-backup-exclude.list"
            require("nixio.fs").writefile(list, "work\n./work\n.overlaybackup\n./.overlaybackup\n")
            exclude = " -X " .. list
        end
        cmd = string.format("tar%s -czf - -C %s . 2>/dev/null", exclude, dir)
    end

    luci.http.header('Content-Disposition',
        'attachment; filename="' .. backup_filename() .. '"')
    luci.http.prepare_content("application/x-tar-gz")

    -- Архив нигде не складывается: tar пишет в конвейер, мы перекладываем
    -- блоками прямо в ответ. Промежуточный файл в /tmp (это ОЗУ) упирался
    -- в свободную память и на больших overlay обрывался на полпути.
    local p = io.popen(cmd, "r")
    if not p then
        luci.http.status(500, "Unable to start tar")
        return
    end

    local block = 65536
    local chunk = p:read(block)
    while chunk do
        luci.http.write(chunk)
        chunk = p:read(block)
    end
    p:close()
end

-- ------------------------------------------------------------------
-- восстановление: распаковка рядом с upper, подмена - на загрузке
-- ------------------------------------------------------------------

local function fail(text)
    require("nixio.fs").writefile(LOGFILE, text .. "\n")
    luci.http.redirect(luci.dispatcher.build_url("admin/system/overlaybackup/backup"))
end

function restore_backup()
    local fs = require "nixio.fs"

    if not fs.stat(UPPER) then
        return fail(i18n.translate(
            "This device does not use an /overlay/upper layer, so a staged restore is not possible."))
    end

    -- Прошлые следы убираем до приёма файла: система сейчас загружена
    -- нормально, и ничто из них не используется.
    os.execute("rm -rf " .. STAGING .. " " .. PREVIOUS .. " " .. UPLOAD ..
               " " .. PENDING .. " >/dev/null 2>&1")
    os.execute("mkdir -p " .. STAGE_ROOT .. " >/dev/null 2>&1")

    -- Принимаем загружаемый файл потоково, сразу на диск. Пишем на
    -- файловую систему overlay, а не в /tmp: /tmp - это ОЗУ, и архив
    -- на сотни мегабайт туда просто не поместится.
    local fd
    luci.http.setfilehandler(function(meta, chunk, eof)
        if not fd then
            fd = io.open(UPLOAD, "wb")
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

    if not fs.access(UPLOAD) then
        return fail(i18n.translate(
            "The archive file was not received. Make sure you selected a file before pressing the button."))
    end

    if not succeeded(os.execute("tar -tzf " .. UPLOAD .. " >/dev/null 2>&1")) then
        os.execute("rm -f " .. UPLOAD)
        return fail(i18n.translate(
            "The uploaded file is not a valid .tar.gz archive."))
    end

    local tar = gnu_tar()
    local unpack_log = STAGE_ROOT .. "/unpack.log"
    local cmd
    if tar then
        cmd = string.format("%s%s -xzf %s -C %s > %s 2>&1",
            tar, XATTR_EXTRACT, UPLOAD, STAGING, unpack_log)
    else
        cmd = string.format("tar -xzf %s -C %s > %s 2>&1",
            UPLOAD, STAGING, unpack_log)
    end

    os.execute("mkdir -p " .. STAGING)
    -- Через os.execute, а не io.popen: в Lua 5.1 popen:close() код возврата
    -- не отдаёт, и провал распаковки прошёл бы незамеченным.
    local ok = succeeded(os.execute(cmd))
    local output = fs.readfile(unpack_log) or ""
    os.remove(unpack_log)

    os.execute("rm -f " .. UPLOAD)

    if not ok then
        os.execute("rm -rf " .. STAGING)
        return fail(i18n.translate("Unpacking the archive failed.") .. "\n" .. output)
    end

    -- Проверка вменяемости перед тем, как ставить подмену слоя в очередь.
    -- Подсунутый архив не того содержания оставил бы устройство без etc,
    -- то есть незагружаемым, а это чинится только сбросом к заводским.
    if not fs.stat(STAGING .. "/etc") then
        os.execute("rm -rf " .. STAGING)
        return fail(i18n.translate(
            "The archive does not look like an overlay backup: it has no etc directory. Nothing was changed."))
    end

    fs.writefile(PENDING, os.date("%Y-%m-%d %H:%M:%S") .. "\n")
    os.execute("sync")

    -- Скрипт сработает на следующей загрузке, пока системой ещё никто
    -- не пользуется, подменит слой и сразу перезагрузится ещё раз.
    os.execute("/etc/init.d/overlaybackup-restore enable >/dev/null 2>&1")
    os.execute("(sleep 3 && reboot) >/dev/null 2>&1 &")

    luci.http.redirect(luci.dispatcher.build_url("admin/system/overlaybackup/backup"))
end

function cancel_restore()
    os.execute("rm -rf " .. STAGING .. " " .. UPLOAD .. " " .. PENDING .. " >/dev/null 2>&1")
    luci.http.redirect(luci.dispatcher.build_url("admin/system/overlaybackup/backup"))
end
