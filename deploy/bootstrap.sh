#!/bin/sh
# luci-app-overlaybackup - bootstrap.sh
#
# One-command install straight from GitHub. Run ON the router, as root:
#
#   wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/deploy/bootstrap.sh | sh
#
# Options for install.sh go after "sh -s --", for example:
#
#   wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/deploy/bootstrap.sh | sh -s -- --no-deps
#
# Downloads the main branch as an archive (no git needed), unpacks it into
# /tmp and runs deploy/install.sh from it. install.sh then installs the
# dependencies, the plugin files, and restarts what is needed.

set -e

REPO=p0sixxx/luci-app-overlaybackup
BRANCH=main
URL="https://github.com/$REPO/archive/refs/heads/$BRANCH.tar.gz"
WORK=/tmp/luci-app-overlaybackup-install
SRC="$WORK/luci-app-overlaybackup-$BRANCH"

echo "== luci-app-overlaybackup bootstrap =="
echo "Downloading $URL"

rm -rf /tmp/luci-app-overlaybackup-install
mkdir -p "$WORK"

if ! wget -q -O "$WORK/src.tar.gz" "$URL"; then
	echo "ERROR: download failed - is the router online?" >&2
	exit 1
fi

tar -xzf "$WORK/src.tar.gz" -C "$WORK"

if [ ! -f "$SRC/deploy/install.sh" ]; then
	echo "ERROR: the downloaded archive has no deploy/install.sh" >&2
	exit 1
fi

# This script is being read by sh from a pipe, and that pipe is the
# installer's stdin unless redirected: anything in it reading stdin would
# swallow the rest of this script.
sh "$SRC/deploy/install.sh" "$@" </dev/null
