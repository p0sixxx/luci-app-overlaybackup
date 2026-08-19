#!/bin/sh
#
# Установка luci-app-overlaybackup на роутер.
# Запускать НА РОУТЕРЕ из распакованного каталога проекта:
#
#   sh install.sh
#
set -e

SRC_DIR="$(dirname "$0")"

CTRL_SRC="$SRC_DIR/luasrc/controller/overlaybackup.lua"
VIEW_SRC="$SRC_DIR/luasrc/view/overlaybackup.htm"

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

# Файлы прежних версий плагина (fullbackup, fullbackuprestore). Если их не
# удалить, в меню останутся лишние пункты, ведущие на устаревшие страницы.
rm -f /usr/lib/lua/luci/controller/fullbackup.lua \
      /usr/lib/lua/luci/controller/fullbackuprestore.lua \
      /usr/lib/lua/luci/view/fullbackup.htm \
      /usr/lib/lua/luci/view/fullbackuprestore.htm 2>/dev/null || true

mkdir -p /usr/lib/lua/luci/controller /usr/lib/lua/luci/view

cp "$CTRL_SRC" /usr/lib/lua/luci/controller/overlaybackup.lua
cp "$VIEW_SRC" /usr/lib/lua/luci/view/overlaybackup.htm

# Каталоги переводов, если они собраны рядом (файлы *.lmo). Без них
# интерфейс показывает исходные английские строки - это штатное поведение
# LuCI, а не ошибка. Русский интерфейс даёт пакет luci-i18n-overlaybackup-ru.
for lmo in "$SRC_DIR"/po/*/*.lmo; do
	[ -f "$lmo" ] || continue
	mkdir -p /usr/lib/lua/luci/i18n
	cp "$lmo" /usr/lib/lua/luci/i18n/
done

# Сброс кэшей LuCI, иначе новая страница не появится в меню.
rm -f /tmp/luci-indexcache* 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

/etc/init.d/uhttpd restart

echo "Готово. Страница: LuCI -> Система -> Бэкап и восстановление overlay"
