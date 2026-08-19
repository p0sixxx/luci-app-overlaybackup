#!/bin/sh
# luci-app-overlaybackup - uninstall.sh
#
# Removes every file listed in deploy/MANIFEST, plus the temporary files
# the plugin creates in /tmp, and reloads LuCI.
#
# Usage (run ON the router, as root):
#   sh uninstall.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="${SCRIPT_DIR}/MANIFEST"

if [ "$(id -u)" != "0" ]; then
	echo "ERROR: this must be run as root on the router." >&2
	exit 1
fi

if [ -f "$MANIFEST" ]; then
	while IFS= read -r line; do
		case "$line" in
			''|'#'*) continue ;;
		esac
		dst=$(echo "$line" | awk '{print $2}')
		[ -n "$dst" ] || continue
		[ -f "$dst" ] || continue
		rm -f "$dst"
		echo "  remove  $dst"
	done < "$MANIFEST"
else
	echo "WARNING: manifest not found at $MANIFEST, removing the known paths." >&2
	rm -f /usr/lib/lua/luci/controller/overlaybackup.lua \
	      /usr/lib/lua/luci/view/overlaybackup.htm \
	      /usr/lib/lua/luci/i18n/overlaybackup.*.lmo
fi

# Files of the earlier versions of this plugin.
rm -f /usr/lib/lua/luci/controller/fullbackup.lua \
      /usr/lib/lua/luci/controller/fullbackuprestore.lua \
      /usr/lib/lua/luci/view/fullbackup.htm \
      /usr/lib/lua/luci/view/fullbackuprestore.htm 2>/dev/null || true

# Temporary files the plugin creates in /tmp.
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

echo "luci-app-overlaybackup removed."
