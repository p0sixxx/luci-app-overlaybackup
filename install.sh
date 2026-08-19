#!/bin/sh
#
# Установка плагина на роутер.
# Запускать НА РОУТЕРЕ из распакованного каталога проекта:
#
#   ./install.sh
#
set -e

SRC_DIR="$(dirname "$0")"

CTRL_SRC="$SRC_DIR/usr/lib/lua/luci/controller/fullbackuprestore.lua"
VIEW_SRC="$SRC_DIR/usr/lib/lua/luci/view/fullbackuprestore.htm"

for f in "$CTRL_SRC" "$VIEW_SRC"; do
	if [ ! -f "$f" ]; then
		echo "Не найден файл: $f" >&2
		echo "Запускайте скрипт из каталога проекта." >&2
		exit 1
	fi
done

if [ ! -d /usr/lib/lua/luci ]; then
	echo "Каталог /usr/lib/lua/luci отсутствует." >&2
	echo "Похоже, LuCI с поддержкой Lua не установлен (нужны luci-compat и luci-lua-runtime)." >&2
	exit 1
fi

mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/view

cp "$CTRL_SRC" /usr/lib/lua/luci/controller/fullbackuprestore.lua
cp "$VIEW_SRC" /usr/lib/lua/luci/view/fullbackuprestore.htm

# Сброс кэшей LuCI, иначе новая страница не появится в меню.
rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

/etc/init.d/uhttpd restart

echo "Готово. Страница: LuCI -> Система -> Бэкап и восстановление overlay"
