#!/bin/sh
# luci-app-overlaybackup - restart.sh
#
# Reloads what is needed to pick up updated files after a re-copy during
# development: LuCI's dispatch index cache and uhttpd, which holds the
# compiled Lua controller and page template in memory.
#
# Usage (run ON the router, as root):
#   sh restart.sh

set -e

if [ "$(id -u)" != "0" ]; then
	echo "ERROR: this must be run as root on the router." >&2
	exit 1
fi

CONTROLLER=/usr/lib/lua/luci/controller/overlaybackup.lua
LUA_BIN=""
for candidate in lua lua5.1; do
	command -v "$candidate" >/dev/null 2>&1 && { LUA_BIN="$candidate"; break; }
done

if [ -n "$LUA_BIN" ] && [ -f "$CONTROLLER" ]; then
	echo "Checking the controller syntax..."
	if ! "$LUA_BIN" -e 'assert(loadfile(arg[1]))' "$CONTROLLER" >/tmp/overlaybackup-lua-check.log 2>&1; then
		echo "ERROR: $CONTROLLER fails to parse, not restarting uhttpd:" >&2
		cat /tmp/overlaybackup-lua-check.log >&2
		rm -f /tmp/overlaybackup-lua-check.log
		exit 1
	fi
	rm -f /tmp/overlaybackup-lua-check.log
	echo "  OK"
fi

echo "Clearing LuCI caches..."
rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

echo "Restarting uhttpd..."
/etc/init.d/uhttpd restart

echo "Done. Reload the plugin page in your browser."
