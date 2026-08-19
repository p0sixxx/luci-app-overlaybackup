# luci-app-overlaybackup

**Русский** · [English](#english)

Плагин для LuCI (OpenWrt): резервное копирование и восстановление раздела
`/overlay` прямо из веб-интерфейса роутера.

Страница появляется в меню **Система → Бэкап и восстановление overlay**
(`admin/system/overlaybackup`).

Проверялось на Netis NX30 v2 / GL.iNet Flint 2 с ванильной OpenWrt 25.12.5.

## Возможности

* **Создание бэкапа** — всё содержимое overlay (установленные пакеты,
  конфигурация, изменённые и добавленные файлы) упаковывается в
  `/tmp/overlay.tar.gz`.
* **Скачивание** готового архива для хранения вне устройства.
* **Удаление** архива из `/tmp`, чтобы не занимать оперативную память.
* **Восстановление** из ранее сохранённого `overlay.tar.gz` с автоматической
  перезагрузкой устройства после распаковки.
* Вывод `tar` показывается на странице, если операция завершилась ошибкой.

## Установка

### Вариант 1: копирование файлов (без пересборки прошивки)

С компьютера, где лежит распакованный проект:

```sh
scp usr/lib/lua/luci/controller/overlaybackup.lua root@<IP роутера>:/usr/lib/lua/luci/controller/overlaybackup.lua
scp usr/lib/lua/luci/view/overlaybackup.htm       root@<IP роутера>:/usr/lib/lua/luci/view/overlaybackup.htm
```

Затем на роутере сбросить кэш LuCI и перезапустить веб-сервер:

```sh
rm -f /tmp/luci-indexcache*
rm -rf /tmp/luci-modulecache
/etc/init.d/uhttpd restart
```

Если весь каталог проекта скопирован на роутер целиком, то же самое делает
скрипт `sh install.sh`, запущенный на роутере. Удаление — `sh uninstall.sh`.

### Вариант 2: сборка ipk в OpenWrt SDK

```sh
git clone https://github.com/p0sixxx/luci-app-overlaybackup.git package/luci-app-overlaybackup
make menuconfig      # LuCI -> 3. Applications -> luci-app-overlaybackup
make package/luci-app-overlaybackup/compile V=s
```

### Зависимости

Страница написана на Lua (старый API LuCI), поэтому на современных сборках
OpenWrt нужны пакеты `luci-compat`, `luci-lua-runtime` и `luci-lib-nixio`:

```sh
opkg update && opkg install luci-compat luci-lua-runtime luci-lib-nixio
```

## Как это устроено

### Что попадает в архив

Архивируется `/overlay/upper` — слой с реальными изменениями. Если такой
раскладки нет, используется `/overlay` целиком. Служебный каталог `work`
исключается: BusyBox tar не понимает длинную опцию `--exclude=`, поэтому
шаблоны исключения передаются файлом через `-X`.

Перед архивацией разрываются жёсткие ссылки (`find -links +1`, затем
`cp -p` + `mv`). Иначе tar сохранит их как hardlink-записи, а при
распаковке обратно на overlayfs создание жёсткой ссылки может завершиться
ошибкой `Operation not permitted`.

### Скачивание

Файл отдаётся блоками по 64 КБ и с заголовком `Content-Length`. Чтение
архива целиком в память (`f:read("*a")`) на устройствах с небольшим объёмом
RAM обрывало ответ, и браузер показывал **Bad Request** — именно это здесь и
исправлено.

### Восстановление

Загружаемый архив принимается потоково через `luci.http.setfilehandler` и
сразу пишется на диск, а не собирается в памяти.

Распаковка идёт **напрямую в `/overlay/upper`**, а не в `/`. При записи в
объединённый (merged) overlay ядро может отказывать в замене файлов,
унаследованных из read-only слоя, с ошибкой `Operation not permitted`; запись
в upper-слой эту union-механику обходит.

После успешной распаковки роутер уходит в перезагрузку фоном с задержкой в
3 секунды — чтобы HTTP-ответ успел дойти до браузера прежде, чем оборвётся
соединение.

## Структура репозитория

```
usr/lib/lua/luci/controller/overlaybackup.lua   контроллер (маршруты и логика)
usr/lib/lua/luci/view/overlaybackup.htm         шаблон страницы
Makefile                                        сборка пакета для OpenWrt
install.sh / uninstall.sh                       установка вручную, запускать на роутере
make-zip.sh                                     сборка zip с раскладкой от корня ФС
```

## Предупреждение

Восстановление перезаписывает текущее содержимое overlay и перезагружает
устройство. Если архив снят с другого устройства или с другой версии
прошивки, роутер может не загрузиться — в этом случае поможет только сброс
к заводским настройкам (failsafe / reset).

## Лицензия

GPL-2.0-or-later.

---

<a id="english"></a>

# luci-app-overlaybackup

[Русский](#luci-app-overlaybackup) · **English**

LuCI plugin for OpenWrt: backup and restore of the `/overlay` partition
straight from the router's web interface.

The page shows up under **System → Бэкап и восстановление overlay**
(`admin/system/overlaybackup`). The interface is in Russian.

Tested on Netis NX30 v2 / GL.iNet Flint 2 running vanilla OpenWrt 25.12.5.

## Features

* **Create a backup** — the entire overlay content (installed packages,
  configuration, modified and added files) is packed into
  `/tmp/overlay.tar.gz`.
* **Download** the resulting archive to keep it off the device.
* **Delete** the archive from `/tmp` so it stops using up RAM.
* **Restore** from a previously saved `overlay.tar.gz`, with the device
  rebooting automatically once the archive is unpacked.
* The `tar` output is shown on the page whenever an operation fails.

## Installation

### Option 1: copying the files (no firmware rebuild)

From the machine holding the unpacked project:

```sh
scp usr/lib/lua/luci/controller/overlaybackup.lua root@<router IP>:/usr/lib/lua/luci/controller/overlaybackup.lua
scp usr/lib/lua/luci/view/overlaybackup.htm       root@<router IP>:/usr/lib/lua/luci/view/overlaybackup.htm
```

Then drop the LuCI cache and restart the web server on the router:

```sh
rm -f /tmp/luci-indexcache*
rm -rf /tmp/luci-modulecache
/etc/init.d/uhttpd restart
```

If the whole project directory was copied to the router, `sh install.sh` run
on the router does the same thing. To remove it, use `sh uninstall.sh`.

### Option 2: building an ipk with the OpenWrt SDK

```sh
git clone https://github.com/p0sixxx/luci-app-overlaybackup.git package/luci-app-overlaybackup
make menuconfig      # LuCI -> 3. Applications -> luci-app-overlaybackup
make package/luci-app-overlaybackup/compile V=s
```

### Dependencies

The page is written in Lua (the old LuCI API), so on current OpenWrt builds it
needs the `luci-compat`, `luci-lua-runtime` and `luci-lib-nixio` packages:

```sh
opkg update && opkg install luci-compat luci-lua-runtime luci-lib-nixio
```

## How it works

### What goes into the archive

`/overlay/upper` is archived — the layer holding the actual changes. If that
layout is missing, the whole `/overlay` is used instead. The internal `work`
directory is excluded: BusyBox tar does not understand the long `--exclude=`
option, so the exclusion patterns are passed as a file via `-X`.

Hard links are broken before archiving (`find -links +1`, then `cp -p` + `mv`).
Otherwise tar stores them as hardlink entries, and recreating a hard link while
unpacking back onto overlayfs can fail with `Operation not permitted`.

### Downloading

The file is served in 64 KiB blocks and with a `Content-Length` header. Reading
the whole archive into memory (`f:read("*a")`) truncated the response on devices
with little RAM, and the browser showed **Bad Request** — that is exactly what
is fixed here.

### Restoring

The uploaded archive is streamed in through `luci.http.setfilehandler` and
written to disk as it arrives instead of being buffered in memory.

It is unpacked **directly into `/overlay/upper`**, not into `/`. When writing
into the merged overlay, the kernel can refuse to replace files inherited from
the read-only layer with `Operation not permitted`; writing into the upper layer
sidesteps that union behaviour.

Once unpacking succeeds, the router reboots in the background after a 3 second
delay, so that the HTTP response reaches the browser before the connection drops.

## Repository layout

```
usr/lib/lua/luci/controller/overlaybackup.lua   controller (routes and logic)
usr/lib/lua/luci/view/overlaybackup.htm         page template
Makefile                                        OpenWrt package build
install.sh / uninstall.sh                       manual install, run on the router
make-zip.sh                                     builds a zip laid out from the FS root
```

## Warning

Restoring overwrites the current overlay content and reboots the device. If the
archive was taken from a different device or a different firmware version, the
router may fail to boot — the only way out then is a factory reset
(failsafe / reset).

## License

GPL-2.0-or-later.
