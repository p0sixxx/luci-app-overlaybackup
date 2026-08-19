#!/bin/sh
#
# Удаление плагина с роутера. Запускать НА РОУТЕРЕ.
#
set -e

rm -f /usr/lib/lua/luci/controller/fullbackuprestore.lua
rm -f /usr/lib/lua/luci/view/fullbackuprestore.htm

# Временные файлы, которые плагин создаёт в /tmp.
rm -f /tmp/overlay.tar.gz \
      /tmp/overlay-backup.log \
      /tmp/overlay-backup-exclude.list \
      /tmp/overlay-restore-upload.tar.gz \
      /tmp/overlay-restore.log \
      /tmp/overlay-restore-success.log \
      /tmp/overlay-restore-error.log 2>/dev/null || true

rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

/etc/init.d/uhttpd restart

echo "Плагин удалён."
