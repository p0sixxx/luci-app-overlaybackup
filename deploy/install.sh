#!/bin/sh
# luci-app-overlaybackup - install.sh
#
# Copies the files listed in deploy/MANIFEST onto a running OpenWrt router
# and reloads what is needed to pick them up: LuCI's dispatch index cache
# and uhttpd, which keeps the compiled Lua controller and page template in
# memory. No package manager involved - this is the manual-copy runtime.
#
# Usage (run ON the router, as root):
#   sh install.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$(cd "${SCRIPT_DIR}/../runtime" && pwd)"
MANIFEST="${SCRIPT_DIR}/MANIFEST"

echo "== luci-app-overlaybackup installer =="

if [ "$(id -u)" != "0" ]; then
	echo "ERROR: this must be run as root on the router." >&2
	exit 1
fi

if [ ! -f /etc/openwrt_release ]; then
	echo "ERROR: /etc/openwrt_release not found - this does not look like an OpenWrt system." >&2
	exit 1
fi
# shellcheck disable=SC1091
. /etc/openwrt_release
echo "Target system: ${DISTRIB_ID:-OpenWrt} ${DISTRIB_RELEASE:-unknown}"

if [ ! -f "$MANIFEST" ]; then
	echo "ERROR: manifest not found at $MANIFEST" >&2
	exit 1
fi

MISSING=0
[ -d /usr/lib/lua/luci ] || { echo "ERROR: /usr/lib/lua/luci not found - LuCI with Lua support is not installed." >&2; MISSING=1; }
[ -x /etc/init.d/uhttpd ] || { echo "ERROR: /etc/init.d/uhttpd not found." >&2; MISSING=1; }
command -v tar >/dev/null 2>&1 || { echo "ERROR: tar not found." >&2; MISSING=1; }
[ "$MISSING" = "1" ] && exit 1

if [ ! -f /usr/lib/lua/luci/dispatcher.lua ]; then
	echo "WARNING: LuCI's Lua dispatcher is missing - install 'luci-compat' and" >&2
	echo "         'luci-lua-runtime', or the page will not appear." >&2
fi
if [ ! -d /overlay ]; then
	echo "WARNING: /overlay does not exist - there is nothing to back up on this system." >&2
fi

echo "Checking the Lua controller parses..."
LUA_BIN=""
for candidate in lua lua5.1; do
	command -v "$candidate" >/dev/null 2>&1 && { LUA_BIN="$candidate"; break; }
done
if [ -n "$LUA_BIN" ]; then
	if ! "$LUA_BIN" -e 'assert(loadfile(arg[1]))' "${RUNTIME_DIR}/usr/lib/lua/luci/controller/overlaybackup.lua" >/tmp/overlaybackup-lua-check.log 2>&1; then
		echo "ERROR: the controller fails to parse - aborting before touching the live install:" >&2
		cat /tmp/overlaybackup-lua-check.log >&2
		rm -f /tmp/overlaybackup-lua-check.log
		exit 1
	fi
	rm -f /tmp/overlaybackup-lua-check.log
	echo "  OK"
else
	echo "  skipped (no Lua interpreter on this system)"
fi

# Files of the earlier versions of this plugin. Left in place they would
# show up as extra menu entries pointing at outdated pages.
for stale in \
	/usr/lib/lua/luci/controller/fullbackup.lua \
	/usr/lib/lua/luci/controller/fullbackuprestore.lua \
	/usr/lib/lua/luci/view/fullbackup.htm \
	/usr/lib/lua/luci/view/fullbackuprestore.htm
do
	[ -f "$stale" ] || continue
	rm -f "$stale"
	echo "  remove  $stale (file of an earlier version)"
done

echo "Installing files..."
while IFS= read -r line; do
	case "$line" in
		''|'#'*) continue ;;
	esac
	src=$(echo "$line" | awk '{print $1}')
	dst=$(echo "$line" | awk '{print $2}')
	[ -n "$src" ] && [ -n "$dst" ] || continue

	mkdir -p "$(dirname "$dst")"
	cp "${RUNTIME_DIR}/${src}" "$dst"
	chmod 0644 "$dst"
	echo "  install $dst"
done < "$MANIFEST"

echo "Clearing the LuCI caches and restarting uhttpd..."
rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/uhttpd restart

if [ -f /usr/lib/lua/luci/i18n/overlaybackup.ru.lmo ]; then
	echo "Russian translation installed."
	echo "  LuCI shows it when its language is Russian or set to auto with a"
	echo "  Russian browser: System -> System -> Language, or"
	echo "  uci set luci.main.lang=ru; uci commit luci"
	if [ ! -f /usr/lib/lua/luci/i18n/base.ru.lmo ]; then
		echo "WARNING: LuCI's own Russian catalog (base.ru.lmo) is not installed," >&2
		echo "         so most of the surrounding interface stays English." >&2
		echo "         Install 'luci-i18n-base-ru' for a fully Russian LuCI." >&2
	fi
fi

echo
echo "luci-app-overlaybackup installed successfully."
echo "Open LuCI -> System -> Overlay backup and restore in your browser."
echo "(If the menu entry is missing, log out and back in, or hard-refresh the page.)"
