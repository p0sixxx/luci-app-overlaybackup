#!/bin/sh
# luci-app-overlaybackup - install.sh
#
# The one installer, for installing and for updating. Run ON the router,
# as root, either straight from GitHub:
#
#   wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/install.sh | sh
#
# or from an unpacked copy of the project:
#
#   sh install.sh
#
# Options (after "sh -s --" when piped):
#
#   --no-deps   do not touch the package manager, only check that the
#               dependencies are present (for routers without internet)
#
# Read from a pipe, the script has no project files next to it: it then
# downloads the main branch as an archive and runs the install.sh inside it.
# From an unpacked copy it installs right away:
#
#   1. checks the dependencies and installs whatever is missing through apk
#      (25.12 and newer) or opkg (up to 24.10);
#   2. copies the files listed in MANIFEST and keeps a copy of MANIFEST and
#      uninstall.sh in /usr/share/luci-app-overlaybackup for removal;
#   3. enables the boot-time layer swap, raises uhttpd's script_timeout,
#      drops the LuCI caches and restarts uhttpd.

set -e

REPO=p0sixxx/luci-app-overlaybackup
BRANCH=main
SHARE=/usr/share/luci-app-overlaybackup

INSTALL_DEPS=1
for arg in "$@"; do
	case "$arg" in
		--no-deps) INSTALL_DEPS=0 ;;
		*) echo "Unknown option: $arg" >&2; exit 1 ;;
	esac
done

echo "== luci-app-overlaybackup installer =="

if [ "$(id -u)" != "0" ]; then
	echo "ERROR: this must be run as root on the router." >&2
	exit 1
fi

if [ ! -f /etc/openwrt_release ]; then
	echo "ERROR: /etc/openwrt_release not found - this does not look like an OpenWrt system." >&2
	exit 1
fi

# ------------------------------------------------------------------
# where the project files are
# ------------------------------------------------------------------

# Empty when the script is read from a pipe ($0 is then the shell itself).
SELF_DIR=""
case "$0" in
	install.sh|*/install.sh)
		[ -f "$0" ] && SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
		;;
esac

if [ -z "$SELF_DIR" ] || [ ! -f "$SELF_DIR/runtime/usr/lib/lua/luci/controller/overlaybackup.lua" ]; then
	# Guard against a loop if the downloaded copy turns out incomplete.
	if [ -n "$OVERLAYBACKUP_FETCHED" ]; then
		echo "ERROR: the downloaded project is incomplete - no runtime/ next to install.sh." >&2
		exit 1
	fi

	URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
	WORK=/tmp/luci-app-overlaybackup-install
	echo "Downloading $URL"

	rm -rf /tmp/luci-app-overlaybackup-install
	mkdir -p "$WORK"

	if ! wget -q -O "$WORK/src.tar.gz" "$URL"; then
		echo "ERROR: download failed - is the router online?" >&2
		exit 1
	fi
	tar -xzf "$WORK/src.tar.gz" -C "$WORK"

	# stdin is the pipe this script is being read from: keep the real
	# installer off it, or anything reading stdin would eat the script.
	export OVERLAYBACKUP_FETCHED=1
	exec sh "$WORK/luci-app-overlaybackup-$BRANCH/install.sh" "$@" </dev/null
fi

RUNTIME_DIR="$SELF_DIR/runtime"
MANIFEST="$SELF_DIR/MANIFEST"

# shellcheck disable=SC1091
. /etc/openwrt_release
echo "Target system: ${DISTRIB_ID:-OpenWrt} ${DISTRIB_RELEASE:-unknown}"

if [ ! -f "$MANIFEST" ]; then
	echo "ERROR: manifest not found at $MANIFEST" >&2
	exit 1
fi

# ------------------------------------------------------------------
# dependencies - before anything else, since the checks below rely on them
# ------------------------------------------------------------------

# What the plugin needs on top of a stock image:
#   luci-compat, luci-lua-runtime - the page is a Lua controller and template,
#                                   and 24.10/25.12 ship LuCI without a Lua runtime
#   luci-lib-nixio                - file system access from the controller
#   tar                           - GNU tar: only it keeps the overlayfs markers
#                                   (trusted.overlay.* xattrs); BusyBox tar
#                                   silently drops them
DEPS="luci-compat luci-lua-runtime luci-lib-nixio tar"

# 25.12 and newer use apk, earlier releases opkg.
if command -v apk >/dev/null 2>&1; then
	PM=apk
elif command -v opkg >/dev/null 2>&1; then
	PM=opkg
else
	PM=""
fi

# Queries only the database of installed packages, so it needs no network.
# apk 3: "info -e" exits non-zero for every name that is not installed.
pkg_installed() {
	case "$PM" in
		apk)  apk info -e "$1" >/dev/null 2>&1 ;;
		# opkg: "Status: <want> <flags> <state>"; the state must be exactly
		# "installed", not "not-installed" or "half-installed".
		opkg) opkg status "$1" 2>/dev/null | grep -q '^Status: .* installed$' ;;
		*)    return 1 ;;
	esac
}

missing_deps() {
	out=""
	for pkg in $DEPS; do
		pkg_installed "$pkg" || out="$out $pkg"
	done
	echo "$out"
}

echo "Checking dependencies..."
if [ -z "$PM" ]; then
	echo "WARNING: neither apk nor opkg found, cannot check packages." >&2
else
	TODO=$(missing_deps)
	if [ -z "$TODO" ]; then
		echo "  all present: $DEPS"
	elif [ "$INSTALL_DEPS" = "0" ]; then
		echo "ERROR: missing packages:$TODO" >&2
		echo "       install them, or run without --no-deps to let this script do it." >&2
		exit 1
	else
		echo "  installing:$TODO"
		# The package index lives in /tmp and is gone after every reboot,
		# so it is refreshed only when something actually has to be installed.
		case "$PM" in
			apk)
				apk update >/dev/null || {
					echo "ERROR: 'apk update' failed - is the router online?" >&2
					exit 1
				}
				# shellcheck disable=SC2086
				apk add $TODO
				;;
			opkg)
				opkg update >/dev/null || {
					echo "ERROR: 'opkg update' failed - is the router online?" >&2
					exit 1
				}
				# shellcheck disable=SC2086
				opkg install $TODO
				;;
		esac

		TODO=$(missing_deps)
		if [ -n "$TODO" ]; then
			echo "ERROR: still missing after installation:$TODO" >&2
			exit 1
		fi
		echo "  OK"
	fi
fi

# GNU tar is a soft requirement: everything works without it, but the
# overlayfs markers are lost on backup and restore.
# The tar package installs GNU tar as /usr/libexec/tar-gnu and points /bin/tar
# at it through alternatives, on 24.10 and 25.12 alike.
GNU_TAR=0
for candidate in /usr/libexec/tar-gnu /bin/tar /usr/bin/tar /usr/sbin/tar; do
	[ -x "$candidate" ] || continue
	if "$candidate" --version 2>/dev/null | grep -q 'GNU tar'; then
		GNU_TAR=1
		break
	fi
done
if [ "$GNU_TAR" = "0" ]; then
	echo "WARNING: GNU tar is not available - only BusyBox tar. Backups will lose" >&2
	echo "         the overlayfs markers of deleted files and directories." >&2
fi

# ------------------------------------------------------------------
# environment
# ------------------------------------------------------------------

MISSING=0
[ -d /usr/lib/lua/luci ] || { echo "ERROR: /usr/lib/lua/luci not found - LuCI with Lua support is not installed." >&2; MISSING=1; }
[ -x /etc/init.d/uhttpd ] || { echo "ERROR: /etc/init.d/uhttpd not found." >&2; MISSING=1; }
command -v tar >/dev/null 2>&1 || { echo "ERROR: tar not found." >&2; MISSING=1; }
[ "$MISSING" = "1" ] && exit 1

if [ ! -f /usr/lib/lua/luci/dispatcher.lua ]; then
	echo "ERROR: LuCI's Lua dispatcher is missing even though the packages are" >&2
	echo "       installed - the page would not appear. Check 'luci-lua-runtime'." >&2
	exit 1
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
	# The path goes inside the code: in Lua 5.1 the arg table only exists
	# after -e has run, and a file named after -e would also be executed.
	if ! "$LUA_BIN" -e "assert(loadfile('${RUNTIME_DIR}/usr/lib/lua/luci/controller/overlaybackup.lua'))" >/tmp/overlaybackup-lua-check.log 2>&1; then
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

# ------------------------------------------------------------------
# files
# ------------------------------------------------------------------

# Files of earlier versions of this plugin. Left in place, the old
# controllers would show up as extra menu entries pointing at outdated pages.
for stale in \
	/usr/lib/lua/luci/controller/fullbackup.lua \
	/usr/lib/lua/luci/controller/fullbackuprestore.lua \
	/usr/lib/lua/luci/view/fullbackup.htm \
	/usr/lib/lua/luci/view/fullbackuprestore.htm \
	/usr/libexec/overlaybackup-stage
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
	# Scripts keep their exec bit, everything else is plain data.
	if [ -x "${RUNTIME_DIR}/${src}" ]; then
		chmod 0755 "$dst"
	else
		chmod 0644 "$dst"
	fi
	echo "  install $dst"
done < "$MANIFEST"

# A record of what was installed, and the uninstaller next to it, so that
# removal works offline and removes exactly these files.
mkdir -p "$SHARE"
cp "$MANIFEST" "$SHARE/MANIFEST"
chmod 0644 "$SHARE/MANIFEST"
cp "$SELF_DIR/uninstall.sh" "$SHARE/uninstall.sh"
chmod 0755 "$SHARE/uninstall.sh"
echo "  install $SHARE/MANIFEST, $SHARE/uninstall.sh"

# The init script carries out the layer swap on the next boot; it exits
# immediately when no restore is pending, so enabling it is harmless.
if [ -f /etc/init.d/overlaybackup-restore ]; then
	/etc/init.d/overlaybackup-restore enable 2>/dev/null || true
	echo "  enable  /etc/init.d/overlaybackup-restore"
fi

# ------------------------------------------------------------------
# uhttpd
# ------------------------------------------------------------------

# uhttpd kills any CGI request that runs longer than script_timeout seconds
# in total - 60 by default. The timer is armed when the process starts and is
# never extended by upload or download progress (uhttpd proc.c: set once in
# uh_create_process, cancelled only in proc_free). Streaming a backup of a
# large overlay, or uploading one for a restore, takes longer than that, and
# uhttpd would cut it off halfway. The original value is remembered so that
# uninstall.sh can put it back.
MIN_TIMEOUT=1800
if command -v uci >/dev/null 2>&1; then
	CUR_TIMEOUT=$(uci -q get uhttpd.main.script_timeout || true)
	if [ -z "$CUR_TIMEOUT" ] || [ "$CUR_TIMEOUT" -lt "$MIN_TIMEOUT" ] 2>/dev/null; then
		if [ -z "$(uci -q get uhttpd.main.overlaybackup_orig_timeout || true)" ]; then
			uci set uhttpd.main.overlaybackup_orig_timeout="${CUR_TIMEOUT:-60}"
		fi
		uci set uhttpd.main.script_timeout="$MIN_TIMEOUT"
		uci commit uhttpd
		echo "  uhttpd  script_timeout ${CUR_TIMEOUT:-60} -> $MIN_TIMEOUT (large backups need more than a minute)"
	fi
fi

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
echo "To remove it later: sh $SHARE/uninstall.sh"
