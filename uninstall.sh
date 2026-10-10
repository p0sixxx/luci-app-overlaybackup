#!/bin/sh
# luci-app-overlaybackup - uninstall.sh
#
# The one uninstaller. Run ON the router, as root - it needs no project
# files, so any of these works:
#
#   sh /usr/share/luci-app-overlaybackup/uninstall.sh
#   wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/uninstall.sh | sh
#   sh uninstall.sh                          (from an unpacked copy)
#
# Options (after "sh -s --" when piped):
#
#   --purge   also remove /overlay/.overlaybackup/previous - the overlay layer
#             that the last restore replaced, kept as a way back. Without
#             this option it is left alone: it is your data, not ours.
#
# Removes the files listed in the record install.sh keeps on the router, plus
# the known files of this and earlier versions, the boot hook, transient
# restore files and the backup passport; puts uhttpd's script_timeout back.
# The dependency packages stay installed: other software may use them.

set -e

SHARE=/usr/share/luci-app-overlaybackup
STAGE_ROOT=/overlay/.overlaybackup

PURGE=0
for arg in "$@"; do
	case "$arg" in
		--purge) PURGE=1 ;;
		*) echo "Unknown option: $arg" >&2; exit 1 ;;
	esac
done

echo "== luci-app-overlaybackup uninstaller =="

if [ "$(id -u)" != "0" ]; then
	echo "ERROR: this must be run as root on the router." >&2
	exit 1
fi

# The boot hook first, while its init script is still there to disable it.
if [ -x /etc/init.d/overlaybackup-restore ]; then
	/etc/init.d/overlaybackup-restore disable 2>/dev/null || true
fi
rm -f /etc/rc.d/S*overlaybackup-restore 2>/dev/null || true

# Exactly what the installed version put on the router.
if [ -f "$SHARE/MANIFEST" ]; then
	while IFS= read -r line; do
		case "$line" in
			''|'#'*) continue ;;
		esac
		dst=$(echo "$line" | awk '{print $2}')
		[ -n "$dst" ] && [ -f "$dst" ] || continue
		rm -f "$dst"
		echo "  remove  $dst"
	done < "$SHARE/MANIFEST"
fi

# Known files, for installs made before the record existed and for files of
# earlier versions of this plugin.
for f in \
	/etc/init.d/overlaybackup-restore \
	/usr/libexec/overlaybackup \
	/usr/libexec/overlaybackup-stage \
	/usr/lib/lua/luci/controller/overlaybackup.lua \
	/usr/lib/lua/luci/view/overlaybackup.htm \
	/usr/lib/lua/luci/controller/fullbackup.lua \
	/usr/lib/lua/luci/controller/fullbackuprestore.lua \
	/usr/lib/lua/luci/view/fullbackup.htm \
	/usr/lib/lua/luci/view/fullbackuprestore.htm \
	/etc/overlaybackup.meta
do
	[ -f "$f" ] || continue
	rm -f "$f"
	echo "  remove  $f"
done
for f in /usr/lib/lua/luci/i18n/overlaybackup.*.lmo; do
	[ -f "$f" ] || continue
	rm -f "$f"
	echo "  remove  $f"
done

# Restore work area: a prepared but not yet applied restore is dropped -
# without the boot hook it would never be applied anyway.
rm -rf /overlay/.overlaybackup/staging
rm -f "$STAGE_ROOT/upload.tar.gz" "$STAGE_ROOT/pending" "$STAGE_ROOT/working" \
      "$STAGE_ROOT/restore.log" "$STAGE_ROOT/unpack.log"
if [ -d "$STAGE_ROOT/previous" ]; then
	if [ "$PURGE" = "1" ]; then
		rm -rf /overlay/.overlaybackup
		echo "  remove  $STAGE_ROOT (including the rollback layer)"
	else
		echo "  keep    $STAGE_ROOT/previous - the layer replaced by the last restore."
		echo "          Run with --purge to remove it as well."
	fi
elif [ -d "$STAGE_ROOT" ]; then
	rmdir "$STAGE_ROOT" 2>/dev/null || true
fi

# Temporary files of earlier versions of this plugin.
rm -f /tmp/overlay-backup-*.tar.gz \
      /tmp/overlay.tar.gz \
      /tmp/overlay-backup.log \
      /tmp/overlay-backup-exclude.list \
      /tmp/overlay-restore-upload.tar.gz \
      /tmp/overlay-restore.log \
      /tmp/overlay-restore-success.log \
      /tmp/overlay-restore-error.log 2>/dev/null || true

# Put uhttpd's script_timeout back to what it was before install.sh raised it.
if command -v uci >/dev/null 2>&1; then
	ORIG_TIMEOUT=$(uci -q get uhttpd.main.overlaybackup_orig_timeout || true)
	if [ -n "$ORIG_TIMEOUT" ]; then
		uci set uhttpd.main.script_timeout="$ORIG_TIMEOUT"
		uci -q delete uhttpd.main.overlaybackup_orig_timeout || true
		uci commit uhttpd
		echo "  uhttpd  script_timeout restored to $ORIG_TIMEOUT"
	fi
fi

# The record and this very script, if it runs from there: the shell already
# has the file open, so removing it does not cut the run short.
rm -rf /usr/share/luci-app-overlaybackup

echo "Clearing the LuCI caches and restarting uhttpd..."
rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/uhttpd restart

echo
echo "luci-app-overlaybackup removed."
echo "The dependencies (luci-compat, luci-lua-runtime, luci-lib-nixio, tar) were"
echo "left installed - other packages may need them."
