# luci-app-overlaybackup

**Русский** · [English](#english)

Плагин для LuCI (OpenWrt): резервное копирование и восстановление раздела
`/overlay` прямо из веб-интерфейса роутера.

Страница появляется в меню **Система → Бэкап и восстановление overlay**
(`admin/system/overlaybackup`) и следует языку, выбранному в LuCI: русский и
английский.

Проверялось на Netis NX30 v2 / GL.iNet Flint 2 с ванильной OpenWrt 25.12.5.

## Возможности

* **Создание бэкапа** — всё содержимое overlay (установленные пакеты,
  конфигурация, изменённые и добавленные файлы) упаковывается в
  `/tmp/overlay-backup-<имя устройства>-<ГГГГ-ММ-ДД>.tar.gz`.
* **Скачивание** готового архива для хранения вне устройства — под тем же
  именем, под каким он лежит в `/tmp`.
* **Удаление** архива из `/tmp`, чтобы не занимать оперативную память.
* **Восстановление** из ранее сохранённого архива с автоматической
  перезагрузкой устройства после распаковки.
* Вывод `tar` показывается на странице, если операция завершилась ошибкой.

## Установка

### Вариант 1: копирование файлов (без пересборки прошивки)

Скопируйте каталог проекта на роутер и запустите установщик там:

```sh
scp -r luci-app-overlaybackup root@<IP роутера>:/tmp/
ssh root@<IP роутера> 'sh /tmp/luci-app-overlaybackup/deploy/install.sh'
```

`deploy/install.sh` разложит файлы по путям из `deploy/MANIFEST`, удалит
файлы прежних версий плагина, сбросит кэш LuCI и перезапустит `uhttpd`.
Удаление — `sh deploy/uninstall.sh`. Если файлы переносятся вручную,
перечитать их заставит `sh deploy/restart.sh`.

Всё содержимое `runtime/` повторяет раскладку файловой системы роутера,
поэтому при желании можно скопировать файлы и поштучно:

```sh
scp runtime/usr/lib/lua/luci/controller/overlaybackup.lua root@<IP роутера>:/usr/lib/lua/luci/controller/overlaybackup.lua
scp runtime/usr/lib/lua/luci/view/overlaybackup.htm       root@<IP роутера>:/usr/lib/lua/luci/view/overlaybackup.htm
scp runtime/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo    root@<IP роутера>:/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo
```

### Вариант 2: сборка пакета `.apk` в OpenWrt SDK

Начиная с 25.12 OpenWrt использует менеджер пакетов **apk** вместо opkg, и
сборка даёт `.apk`. Сам `Makefile` от менеджера пакетов не зависит — формат
выбирает buildroot, так что ничего специально настраивать не нужно.

Возьмите SDK ровно под свою версию и платформу — со страницы
`https://downloads.openwrt.org/releases/25.12.5/targets/<target>/<subtarget>/`,
файл `openwrt-sdk-*.tar.zst`. Распакуйте его и из каталога SDK:

```sh
./scripts/feeds update -a
./scripts/feeds install -a
git clone https://github.com/p0sixxx/luci-app-overlaybackup.git package/luci-app-overlaybackup
make defconfig
make package/luci-app-overlaybackup/compile V=s
```

Готовый пакет появится в `bin/packages/<архитектура>/base/`:

```sh
ls bin/packages/*/base/luci-app-overlaybackup-*.apk
```

Установка на роутер:

```sh
scp bin/packages/*/base/luci-app-overlaybackup-*.apk root@<IP роутера>:/tmp/
ssh root@<IP роутера> 'apk add --allow-untrusted /tmp/luci-app-overlaybackup-*.apk'
```

`--allow-untrusted` здесь обязателен: пакет собран локально и не подписан
ключом, которому доверяет роутер.

Обновление той же командой поверх установленного пакета; удаление —
`apk del luci-app-overlaybackup`.

#### Выпуски до 24.10 включительно

Там ещё opkg, и тот же `Makefile` без изменений даёт `.ipk`:

```sh
make package/luci-app-overlaybackup/compile V=s
ls bin/packages/*/base/luci-app-overlaybackup_*.ipk
opkg install ./luci-app-overlaybackup_*.ipk    # на роутере
```

### Язык интерфейса

Переводы идут через обычный для LuCI механизм gettext: исходные строки в коде
английские, перевод лежит в `po/ru/overlaybackup.po`, а страница получает его
из скомпилированного каталога `/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo`.

Язык следует общей настройке в **System → System → Language**, то есть
переключается вместе со всем остальным интерфейсом LuCI.

Собранный каталог **закоммичен** в `runtime/usr/lib/lua/luci/i18n/` и
устанавливается наравне с остальными файлами: проект разворачивается
копированием на роутер, где нет ни компилятора, ни сборочных утилит LuCI.
Подробности — правка строк, пересборка `.lmo`, добавление языков и разбор
того, почему msgid не должны совпадать со строками `luci-base`, — в
[`po/README.md`](po/README.md).

### Зависимости

Страница написана на Lua (старый API LuCI), поэтому на современных сборках
OpenWrt нужны пакеты `luci-compat`, `luci-lua-runtime` и `luci-lib-nixio`.

На 25.12 и новее:

```sh
apk update && apk add luci-compat luci-lua-runtime luci-lib-nixio
```

На выпусках до 24.10 включительно:

```sh
opkg update && opkg install luci-compat luci-lua-runtime luci-lib-nixio
```

При установке пакетом эти зависимости подтянутся сами — команды нужны только
для установки копированием файлов.

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

Имя архива собирается из имени устройства (`/proc/sys/kernel/hostname`,
недопустимые для имени файла символы заменяются на `_`) и даты, и одинаково
в `/tmp` и при скачивании. Фиксированного пути поэтому нет: архив ищется по
маске `/tmp/overlay-backup-*.tar.gz`, а при создании нового прежние удаляются,
чтобы копии за разные дни не занимали оперативную память.

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
runtime/                              раскладка файлов от корня ФС роутера
  usr/lib/lua/luci/controller/…lua    контроллер (маршруты и логика)
  usr/lib/lua/luci/view/…htm          шаблон страницы
  usr/lib/lua/luci/i18n/…ru.lmo       собранный русский каталог
deploy/MANIFEST                       список файлов и путей установки
deploy/install.sh, uninstall.sh       установка и удаление, запускать на роутере
deploy/restart.sh                     перечитать файлы после ручного копирования
po/                                   исходники переводов и инструменты к ним
Makefile                              необязательная сборка ipk для OpenWrt
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

The page shows up under **System → Overlay backup and restore**
(`admin/system/overlaybackup`) and follows the language selected in LuCI:
English and Russian.

Tested on Netis NX30 v2 / GL.iNet Flint 2 running vanilla OpenWrt 25.12.5.

## Features

* **Create a backup** — the entire overlay content (installed packages,
  configuration, modified and added files) is packed into
  `/tmp/overlay-backup-<hostname>-<YYYY-MM-DD>.tar.gz`.
* **Download** the resulting archive to keep it off the device, under the very
  same name it has in `/tmp`.
* **Delete** the archive from `/tmp` so it stops using up RAM.
* **Restore** from a previously saved archive, with the device
  rebooting automatically once the archive is unpacked.
* The `tar` output is shown on the page whenever an operation fails.

## Installation

### Option 1: copying the files (no firmware rebuild)

Copy the project directory to the router and run the installer there:

```sh
scp -r luci-app-overlaybackup root@<router IP>:/tmp/
ssh root@<router IP> 'sh /tmp/luci-app-overlaybackup/deploy/install.sh'
```

`deploy/install.sh` lays the files out along the paths in `deploy/MANIFEST`,
removes the files of earlier versions of the plugin, drops the LuCI cache and
restarts `uhttpd`. To remove it, use `sh deploy/uninstall.sh`; after copying
files by hand, `sh deploy/restart.sh` makes LuCI pick them up.

Everything under `runtime/` mirrors the router's filesystem layout, so the
files can just as well be copied one by one:

```sh
scp runtime/usr/lib/lua/luci/controller/overlaybackup.lua root@<router IP>:/usr/lib/lua/luci/controller/overlaybackup.lua
scp runtime/usr/lib/lua/luci/view/overlaybackup.htm       root@<router IP>:/usr/lib/lua/luci/view/overlaybackup.htm
scp runtime/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo    root@<router IP>:/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo
```

### Option 2: building an `.apk` package with the OpenWrt SDK

As of 25.12 OpenWrt uses the **apk** package manager instead of opkg, and a
build produces an `.apk`. The `Makefile` itself does not depend on the package
manager — the format is chosen by buildroot, so there is nothing to configure.

Grab the SDK for exactly your version and platform from
`https://downloads.openwrt.org/releases/25.12.5/targets/<target>/<subtarget>/`,
the `openwrt-sdk-*.tar.zst` file. Unpack it, then from the SDK directory:

```sh
./scripts/feeds update -a
./scripts/feeds install -a
git clone https://github.com/p0sixxx/luci-app-overlaybackup.git package/luci-app-overlaybackup
make defconfig
make package/luci-app-overlaybackup/compile V=s
```

The package lands in `bin/packages/<architecture>/base/`:

```sh
ls bin/packages/*/base/luci-app-overlaybackup-*.apk
```

Installing it on the router:

```sh
scp bin/packages/*/base/luci-app-overlaybackup-*.apk root@<router IP>:/tmp/
ssh root@<router IP> 'apk add --allow-untrusted /tmp/luci-app-overlaybackup-*.apk'
```

`--allow-untrusted` is required here: the package was built locally and is not
signed by a key the router trusts.

Upgrading is the same command over the installed package; removal is
`apk del luci-app-overlaybackup`.

#### Releases up to and including 24.10

Those still use opkg, and the very same `Makefile` produces an `.ipk`:

```sh
make package/luci-app-overlaybackup/compile V=s
ls bin/packages/*/base/luci-app-overlaybackup_*.ipk
opkg install ./luci-app-overlaybackup_*.ipk    # on the router
```

### Interface language

Translations go through LuCI's ordinary gettext machinery: the source strings
in the code are English, the Russian translation lives in
`po/ru/overlaybackup.po`, and the page picks it up from the compiled catalog at
`/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo`.

The language follows the global setting under **System → System → Language**,
so it switches along with the rest of the LuCI interface.

The compiled catalog is **committed** under `runtime/usr/lib/lua/luci/i18n/`
and installed like any other file: this project is deployed by copying onto a
router, which has neither a compiler nor the LuCI build host tools. Editing
strings, rebuilding the `.lmo`, adding languages and why msgids must not
collide with `luci-base` are all covered in [`po/README.md`](po/README.md).

### Dependencies

The page is written in Lua (the old LuCI API), so on current OpenWrt builds it
needs the `luci-compat`, `luci-lua-runtime` and `luci-lib-nixio` packages.

On 25.12 and newer:

```sh
apk update && apk add luci-compat luci-lua-runtime luci-lib-nixio
```

On releases up to and including 24.10:

```sh
opkg update && opkg install luci-compat luci-lua-runtime luci-lib-nixio
```

Installing the package pulls these in on its own — the commands are only needed
when installing by copying the files.

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

The archive name is built from the device hostname (`/proc/sys/kernel/hostname`,
with characters unsafe for a file name replaced by `_`) and the date, and is the
same in `/tmp` as it is when downloaded. There is therefore no fixed path: the
archive is looked up by the `/tmp/overlay-backup-*.tar.gz` pattern, and creating a
new one removes the previous archives so that copies from different days do not eat
up RAM.

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
runtime/                              files laid out from the router's FS root
  usr/lib/lua/luci/controller/…lua    controller (routes and logic)
  usr/lib/lua/luci/view/…htm          page template
  usr/lib/lua/luci/i18n/…ru.lmo       compiled Russian catalog
deploy/MANIFEST                       file list and install paths
deploy/install.sh, uninstall.sh       install and removal, run on the router
deploy/restart.sh                     reload after copying files by hand
po/                                   translation sources and their tooling
Makefile                              optional ipk build for OpenWrt
```

## Warning

Restoring overwrites the current overlay content and reboots the device. If the
archive was taken from a different device or a different firmware version, the
router may fail to boot — the only way out then is a factory reset
(failsafe / reset).

## License

GPL-2.0-or-later.
