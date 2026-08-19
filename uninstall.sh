#!/bin/sh
#
# Удаление luci-app-overlaybackup с роутера. Запускать НА РОУТЕРЕ:
#
#   sh uninstall.sh
#
set -e

# Текущие файлы плагина и файлы прежних версий (fullbackup, fullbackuprestore).
rm -f /usr/lib/lua/luci/i18n/overlaybackup.*.lmo \
      /usr/lib/lua/luci/controller/overlaybackup.lua \
      /usr/lib/lua/luci/controller/fullbackup.lua \
      /usr/lib/lua/luci/controller/fullbackuprestore.lua \
      /usr/lib/lua/luci/view/overlaybackup.htm \
      /usr/lib/lua/luci/view/fullbackup.htm \
      /usr/lib/lua/luci/view/fullbackuprestore.htm 2>/dev/null || true

# Временные файлы, которые плагин создаёт в /tmp.
rm -f /tmp/overlay-backup-*.tar.gz \
      /tmp/overlay.tar.gz \
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
