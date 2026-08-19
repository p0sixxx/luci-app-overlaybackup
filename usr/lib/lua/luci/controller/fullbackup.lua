module("luci.controller.fullbackup", package.seeall)

function index()
    entry({"admin", "system", "fullbackup"}, firstchild(), _("Полный бэкап"), 60).dependent = false
    entry({"admin", "system", "fullbackup", "backup"}, template("fullbackup"), _("Backup"), 10)
    entry({"admin", "system", "fullbackup", "create_backup"}, call("create_backup"), nil)
    entry({"admin", "system", "fullbackup", "delete_backup"}, call("delete_backup"), nil)
    entry({"admin", "system", "fullbackup", "download"}, call("download_backup"), nil)
end

function create_backup()
    local backup_file = "/tmp/overlay.tar.gz"
    os.execute("tar -czf " .. backup_file .. " /overlay/")
    luci.http.redirect(luci.dispatcher.build_url("admin/system/fullbackup/backup"))
end

function download_backup()
    local backup_file = "/tmp/overlay.tar.gz"
    local fs = require "nixio.fs"
    if fs.access(backup_file) then
        luci.http.header('Content-Disposition', 'attachment; filename="overlay.tar.gz"')
        luci.http.prepare_content("application/x-tar-gz")
        local f = io.open(backup_file, "rb")
        luci.http.write(f:read("*a"))
        f:close()
    else
        luci.http.status(404, "Backup file not found")
    end
end

function delete_backup()
    local backup_file = "/tmp/overlay.tar.gz"
    if nixio.fs.access(backup_file) then
        os.remove(backup_file)
    end
    luci.http.redirect(luci.dispatcher.build_url("admin/system/fullbackup/backup"))
end
