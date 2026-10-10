# luci-app-overlaybackup

**Русский** · [English](#english)

Плагин для LuCI (OpenWrt): резервное копирование и восстановление раздела
`/overlay` прямо из веб-интерфейса роутера.

Страница появляется в меню **Система → Бэкап и восстановление overlay**
(`admin/system/overlaybackup`) и следует языку, выбранному в LuCI: русский и
английский.

Проверялось на Netis NX30 v2 / GL.iNet Flint 2 с ванильной OpenWrt 25.12.5.

## Возможности

* **Скачивание бэкапа** — всё содержимое overlay (установленные пакеты,
  конфигурация, изменённые и добавленные файлы) упаковывается и сразу
  отдаётся в браузер под именем
  `overlay-backup-<имя устройства>-<версия OpenWrt>-<ГГГГ-ММ-ДД>.tar.gz`.
  На роутере ничего не сохраняется, поэтому размер overlay не упирается
  в свободную оперативную память.
* **Восстановление** из ранее сохранённого архива. Новый слой распаковывается
  рядом с живым, а подменяется на ранней загрузке — так, как это безопасно
  для overlayfs.
* **Откат**: слой, заменённый прошлым восстановлением, сохраняется.
* Ошибки показываются на странице вместе с выводом `tar`.

## Установка

### Вариант 1: установка с GitHub прямо на роутере

Ни `git`, ни компьютер посередине не нужны — на роутере:

```sh
apk update
apk add luci-compat luci-lua-runtime luci-lib-nixio tar

cd /tmp
wget -O overlaybackup.tar.gz https://github.com/p0sixxx/luci-app-overlaybackup/archive/refs/heads/main.tar.gz
tar -xzf overlaybackup.tar.gz
sh luci-app-overlaybackup-main/deploy/install.sh
```

Обновление — те же команды: `install.sh` перезаписывает файлы поверх.

Если `wget` ругается на HTTPS — в образе нет SSL-библиотеки для
`uclient-fetch`: `apk add libustream-mbedtls` и повторить.

`/tmp` очищается при перезагрузке, так что для удаления плагина архив
придётся скачать заново и запустить `deploy/uninstall.sh`.

#### С компьютера через scp

```sh
scp -O -r luci-app-overlaybackup root@<IP роутера>:/tmp/
ssh root@<IP роутера> 'sh /tmp/luci-app-overlaybackup/deploy/install.sh'
```

`-O` обязателен: современный OpenSSH по умолчанию копирует через SFTP, а в
OpenWrt `sftp-server` нет — без ключа получите `sftp-server: not found`.

`deploy/install.sh` разложит файлы по путям из `deploy/MANIFEST`, удалит
файлы прежних версий плагина, сбросит кэш LuCI и перезапустит `uhttpd`.
Удаление — `sh deploy/uninstall.sh`. Если файлы переносятся вручную,
перечитать их заставит `sh deploy/restart.sh`.

Всё содержимое `runtime/` повторяет раскладку файловой системы роутера,
поэтому при желании можно скопировать файлы и поштучно:

```sh
scp -O runtime/etc/init.d/overlaybackup-restore             root@<IP роутера>:/etc/init.d/overlaybackup-restore
scp -O runtime/usr/lib/lua/luci/controller/overlaybackup.lua root@<IP роутера>:/usr/lib/lua/luci/controller/overlaybackup.lua
scp -O runtime/usr/lib/lua/luci/view/overlaybackup.htm       root@<IP роутера>:/usr/lib/lua/luci/view/overlaybackup.htm
scp -O runtime/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo    root@<IP роутера>:/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo
```

После поштучного копирования init-скрипт нужно сделать исполняемым и
включить — без него подготовленное восстановление никогда не применится:

```sh
chmod 0755 /etc/init.d/overlaybackup-restore
/etc/init.d/overlaybackup-restore enable
rm -f /tmp/luci-indexcache*
rm -rf /tmp/luci-modulecache
/etc/init.d/uhttpd restart
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
раскладки нет, используется `/overlay` целиком, и тогда из архива исключаются
служебный каталог `work` и рабочий каталог плагина `.overlaybackup`.

### Почему важен GNU tar

Overlayfs хранит следы удалений двумя способами. Удалённый файл отмечается
whiteout-записью — символьным устройством `0:0`, и её сохраняет любой tar.
А вот каталог, перекрывающий нижний слой, отмечается расширенным атрибутом
`trusted.overlay.opaque`, и **BusyBox tar про расширенные атрибуты не знает
вообще**. Архив при этом выглядит целым, но после восстановления удалённые
каталоги возвращаются из образа прошивки.

Поэтому плагин ищет GNU tar (`/usr/bin/tar`) и, найдя его, добавляет
`--xattrs --xattrs-include='trusted.overlay.*' --numeric-owner`. Без GNU tar
всё работает, но страница показывает предупреждение. Ставится он обычным
`apk add tar`.

Там же при создании архива используется `--hard-dereference`: жёсткие ссылки
записываются обычными файлами. Прежние версии плагина добивались того же,
разрывая ссылки прямо в живом overlay через `cp -p` + `mv` — то есть правили
систему, которую копируют. Больше этого не происходит.

### Скачивание

Имя архива собирается из трёх частей: имя устройства
(`/proc/sys/kernel/hostname`), версия прошивки (`DISTRIB_RELEASE` из
`/etc/openwrt_release`, с откатом на `VERSION_ID` из `/etc/os-release`) и дата.
Недопустимые для имени файла символы в первых двух заменяются на `_`. Если
версию определить не удалось, поле просто выпадает — лучше короткое имя, чем
слово-заглушка в нём.

Промежуточного файла нет: `tar` пишет в конвейер, а контроллер перекладывает
его блоками по 64 КБ прямо в HTTP-ответ. Раньше архив собирался в `/tmp`, а это
tmpfs, то есть оперативная память, — overlay на сотни мегабайт туда просто не
помещался, и `tar` обрывался на полпути.

Обратная сторона: заголовок `Content-Length` выставить нельзя, размер заранее
неизвестен. Если передача прервётся, файл окажется коротким, а серверной копии
для проверки не останется — после скачивания стоит убедиться, что архив
открывается.

### Восстановление

Распаковывать архив прямо в смонтированный `/overlay/upper` **нельзя**. Правка
слоёв смонтированного overlayfs ядром не поддерживается: открытые файлы уезжают
на подменённые inode, и обращения к ним начинают падать с `Stale file handle` —
вплоть до того, что перестаёт записываться база пакетов. Прежние версии плагина
делали именно так.

Теперь это разнесено на два шага.

**Шаг 1, из LuCI.** Загружаемый архив принимается потоково и пишется в
`/overlay/.overlaybackup/upload.tar.gz` — на файловую систему overlay, а не
в `/tmp`, по той же причине с памятью. Затем он проверяется (`tar -tzf`) и
распаковывается в `/overlay/.overlaybackup/staging` — каталог **рядом** с
`upper`, вне смонтированного объединения, так что живую систему это не трогает.
Если в распакованном нет каталога `etc`, подмена отменяется: остаться без `etc`
значит остаться без загрузки. После этого ставится флаг и устройство уходит
в перезагрузку.

**Шаг 2, на загрузке.** Скрипт `/etc/init.d/overlaybackup-restore` со
`START=01` видит флаг и выполняет подмену двумя `mv` в пределах одной файловой
системы: текущий слой уезжает в `previous`, подготовленный встаёт на его место.
Если второй `mv` не удался, прежний слой возвращается обратно. Сразу после
этого — `reboot -f`, чтобы ядро увидело новый слой с нуля; `-f` намеренно,
потому что скрипты завершения работы читали бы файлы слоя, которого на его
месте уже нет.

Флаг снимается до подмены, так что неудача не превращается в цикл перезагрузок.

Итого устройство перезагружается дважды: первый раз — чтобы применить,
второй — чтобы подняться на восстановленной системе.

### Откат

`/overlay/.overlaybackup/previous` — это слой, который был заменён. Он
удаляется при подготовке следующего восстановления, когда система уже
загружена и слой ничем не занят. Если восстановленная система не устраивает,
вернуться можно, поменяв каталоги обратно (из failsafe или по SSH):

```sh
mv /overlay/upper /overlay/.overlaybackup/staging
mv /overlay/.overlaybackup/previous /overlay/upper
sync && reboot -f
```

## Структура репозитория

```
runtime/                              раскладка файлов от корня ФС роутера
  etc/init.d/overlaybackup-restore   подмена слоя на загрузке
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

* **Download a backup** — the entire overlay content (installed packages,
  configuration, modified and added files) is packed and streamed straight to
  the browser as
  `overlay-backup-<hostname>-<OpenWrt version>-<YYYY-MM-DD>.tar.gz`. Nothing is
  written to the router, so the size of the overlay is not limited by free RAM.
* **Restore** from a previously saved archive. The new layer is unpacked next
  to the live one and swapped in early during boot - the way overlayfs allows.
* **Rollback**: the layer replaced by the last restore is kept.
* Failures are reported on the page along with the `tar` output.

## Installation

### Option 1: installing from GitHub right on the router

Neither `git` nor a computer in between is needed - on the router:

```sh
apk update
apk add luci-compat luci-lua-runtime luci-lib-nixio tar

cd /tmp
wget -O overlaybackup.tar.gz https://github.com/p0sixxx/luci-app-overlaybackup/archive/refs/heads/main.tar.gz
tar -xzf overlaybackup.tar.gz
sh luci-app-overlaybackup-main/deploy/install.sh
```

Updating is the same commands: `install.sh` overwrites the files in place.

If `wget` complains about HTTPS, the image lacks the SSL library for
`uclient-fetch`: `apk add libustream-mbedtls` and try again.

`/tmp` is wiped on reboot, so to remove the plugin you will need to download
the archive again and run `deploy/uninstall.sh`.

#### From a computer over scp

```sh
scp -O -r luci-app-overlaybackup root@<router IP>:/tmp/
ssh root@<router IP> 'sh /tmp/luci-app-overlaybackup/deploy/install.sh'
```

`-O` is required: modern OpenSSH copies over SFTP by default, and OpenWrt ships
no `sftp-server` - without the flag you get `sftp-server: not found`.

`deploy/install.sh` lays the files out along the paths in `deploy/MANIFEST`,
removes the files of earlier versions of the plugin, drops the LuCI cache and
restarts `uhttpd`. To remove it, use `sh deploy/uninstall.sh`; after copying
files by hand, `sh deploy/restart.sh` makes LuCI pick them up.

Everything under `runtime/` mirrors the router's filesystem layout, so the
files can just as well be copied one by one:

```sh
scp -O runtime/etc/init.d/overlaybackup-restore             root@<router IP>:/etc/init.d/overlaybackup-restore
scp -O runtime/usr/lib/lua/luci/controller/overlaybackup.lua root@<router IP>:/usr/lib/lua/luci/controller/overlaybackup.lua
scp -O runtime/usr/lib/lua/luci/view/overlaybackup.htm       root@<router IP>:/usr/lib/lua/luci/view/overlaybackup.htm
scp -O runtime/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo    root@<router IP>:/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo
```

After copying file by file, the init script has to be made executable and
enabled - without it a prepared restore is never applied:

```sh
chmod 0755 /etc/init.d/overlaybackup-restore
/etc/init.d/overlaybackup-restore enable
rm -f /tmp/luci-indexcache*
rm -rf /tmp/luci-modulecache
/etc/init.d/uhttpd restart
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

`/overlay/upper` is archived - the layer holding the actual changes. If that
layout is missing, the whole `/overlay` is used instead, and then the internal
`work` directory and the plugin's own `.overlaybackup` are excluded.

### Why GNU tar matters

Overlayfs records deletions in two different ways. A deleted file is marked by
a whiteout entry - a `0:0` character device - and any tar preserves that. A
directory that masks the one below it, however, is marked by the extended
attribute `trusted.overlay.opaque`, and **BusyBox tar knows nothing about
extended attributes at all**. The archive still looks complete, but after a
restore those deleted directories come back from the firmware image.

So the plugin looks for GNU tar (`/usr/bin/tar`) and, when it finds it, adds
`--xattrs --xattrs-include='trusted.overlay.*' --numeric-owner`. Everything
works without GNU tar, but the page shows a warning. Install it with a plain
`apk add tar`.

Creating the archive also passes `--hard-dereference`, so hard links are stored
as ordinary files. Earlier versions of the plugin achieved the same by breaking
the links in the live overlay with `cp -p` + `mv` - that is, by editing the very
system they were copying. That no longer happens.

### Downloading

The archive name is built from three parts: the device hostname
(`/proc/sys/kernel/hostname`), the firmware version (`DISTRIB_RELEASE` from
`/etc/openwrt_release`, falling back to `VERSION_ID` from `/etc/os-release`) and
the date. Characters unsafe for a file name are replaced by `_` in the first two.
If the version cannot be determined the field is simply left out - a shorter name
beats a placeholder word inside it.

There is no intermediate file: `tar` writes into a pipe and the controller
forwards it to the HTTP response in 64 KiB blocks. The archive used to be built
in `/tmp`, which is tmpfs - RAM - so an overlay of a few hundred megabytes
simply did not fit and `tar` was cut off halfway.

The trade-off: `Content-Length` cannot be set, because the size is not known in
advance. If the transfer breaks the file ends up short, and there is no copy on
the server left to check it against - so do confirm the downloaded archive
opens.

### Restoring

Unpacking an archive straight into the mounted `/overlay/upper` is **not
allowed**. The kernel does not support modifying the layers of a mounted
overlayfs: open files end up on replaced inodes and accesses to them start
failing with `Stale file handle` - to the point where the package database can
no longer be written. Earlier versions of the plugin did exactly that.

It is now split in two.

**Step 1, from LuCI.** The uploaded archive is streamed to
`/overlay/.overlaybackup/upload.tar.gz` - onto the overlay filesystem rather
than `/tmp`, for the same reason of memory. It is then validated (`tar -tzf`)
and unpacked into `/overlay/.overlaybackup/staging`, a directory **next to**
`upper` and outside the mounted union, so the live system is left alone. If the
unpacked tree has no `etc` directory the swap is called off: a device without
`etc` is a device that does not boot. A flag is then set and the device reboots.

**Step 2, during boot.** `/etc/init.d/overlaybackup-restore` with `START=01`
sees the flag and performs the swap with two renames within one filesystem: the
current layer moves aside to `previous`, the prepared one takes its place. If
the second rename fails, the old layer is put back. Immediately after comes
`reboot -f`, so the kernel sees the new layer from scratch; `-f` is deliberate,
because shutdown scripts would read files of a layer that is no longer where it
was.

The flag is cleared before the swap, so a failure does not turn into a reboot
loop.

All in all the device reboots twice: once to apply the restore, once to come up
on the restored system.

### Rolling back

`/overlay/.overlaybackup/previous` is the layer that was replaced. It is removed
when the next restore is prepared, by which time the system is up and the layer
is not in use by anything. If the restored system is not what you wanted, swap
the directories back (from failsafe or over SSH):

```sh
mv /overlay/upper /overlay/.overlaybackup/staging
mv /overlay/.overlaybackup/previous /overlay/upper
sync && reboot -f
```

## Repository layout

```
runtime/                              files laid out from the router's FS root
  etc/init.d/overlaybackup-restore   boot-time layer swap
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
