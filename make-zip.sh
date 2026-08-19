#!/bin/sh
#
# Сборка zip-архива с раскладкой файлов от корня файловой системы роутера,
# такого же, как использовался при ручной установке через scp/WinSCP.
#
set -e

cd "$(dirname "$0")"

NAME="luci-app-overlaybackup"
OUT="$NAME.zip"

rm -f "$OUT"
zip -r "$OUT" luasrc po install.sh uninstall.sh README.md -x '*.DS_Store' >/dev/null

echo "Собрано: $OUT"
