# luci-app-overlaybackup

**Русский** · [English](#english)

Плагин для LuCI (OpenWrt): резервное копирование и восстановление раздела
`/overlay` прямо из веб-интерфейса роутера.

Страница появляется в меню **Система → Бэкап и восстановление overlay**
(`admin/system/overlaybackup`) и следует языку, выбранному в LuCI: русский и
английский.

Поддерживаются OpenWrt **24.10.x** (менеджер пакетов opkg) и **25.12.x** (apk):
установщик сам определяет, какой из них на роутере.
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
* **Проверка модели и версии**: архив с другого устройства или другой версии
  OpenWrt не будет восстановлен — это проверяется до каких-либо изменений.
* **Откат**: слой, заменённый прошлым восстановлением, сохраняется.
* Ошибки показываются на странице вместе с выводом `tar`.
* Установка, обновление и удаление — одной командой, на 24.10 и 25.12.

## Установка

### Вариант 1: одной командой с GitHub

Установка и обновление — на роутере:

```sh
wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/install.sh | sh
```

Удаление:

```sh
sh /usr/share/luci-app-overlaybackup/uninstall.sh
```

Больше ничего не нужно — ни `git`, ни компьютера посередине, ни ручной
установки пакетов. `install.sh` один и тот же для всех случаев: прочитанный
из конвейера, он сам скачивает ветку `main` архивом и запускается уже из неё,
а затем:

1. проверяет зависимости (`luci-compat`, `luci-lua-runtime`, `luci-lib-nixio`,
   `tar`) и доставляет недостающие через `apk` на 25.12 или `opkg` на 24.10.
   Если всё уже стоит, в сеть он не обращается вовсе;
2. раскладывает файлы по путям из `MANIFEST` и оставляет на роутере, в
   `/usr/share/luci-app-overlaybackup/`, копию манифеста и `uninstall.sh` —
   поэтому удаление работает и без интернета, и после перезагрузки, и
   убирает ровно то, что было поставлено;
3. включает init-скрипт подмены слоя, поднимает `script_timeout` у `uhttpd`,
   сбрасывает кэши LuCI и перезапускает `uhttpd`.

`uninstall.sh` тоже можно запустить прямо с GitHub, файлы проекта ему не
нужны: `wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/uninstall.sh | sh`. Он оставляет на месте
`/overlay/.overlaybackup/previous` — слой, заменённый последним
восстановлением, — потому что это ваши данные; убрать и его: `--purge`.
Пакеты-зависимости тоже остаются: ими могут пользоваться другие программы.

Ключи передаются после `sh -s --`. Для роутера без интернета поставьте
зависимости заранее и запустите с `--no-deps` — тогда установщик только
проверит, что пакеты на месте:

```sh
wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/install.sh | sh -s -- --no-deps
```

#### С компьютера через scp

```sh
scp -O -r luci-app-overlaybackup root@<IP роутера>:/tmp/
ssh root@<IP роутера> 'sh /tmp/luci-app-overlaybackup/install.sh'
```

`-O` обязателен: современный OpenSSH по умолчанию копирует через SFTP, а в
OpenWrt `sftp-server` нет — без ключа получите `sftp-server: not found`.

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

`install.sh` ставит их сам; при установке пакетом они тоже
подтягиваются сами. Команды выше нужны только для `--no-deps`.

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

Поэтому плагин ищет GNU tar — пакет `tar` и в 24.10, и в 25.12 ставит его в
`/usr/libexec/tar-gnu` и переключает на него `/bin/tar` через alternatives — и,
найдя его, добавляет
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

Поток упирается в другое ограничение — время. `uhttpd` убивает любой
CGI-запрос, который длится дольше `script_timeout` секунд **в сумме**
(по умолчанию 60): таймер взводится при запуске процесса и не продлевается
ни отдачей данных, ни приёмом. Сжатие overlay на сотни мегабайт на процессоре
роутера дольше минуты, и поток оборвался бы на середине. Поэтому
`install.sh` поднимает `uhttpd.main.script_timeout` до 1800, запоминая
прежнее значение, а `uninstall.sh` его возвращает.

Обратная сторона потока: заголовок `Content-Length` выставить нельзя, размер заранее
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
в `/tmp`, по той же причине с памятью. На этом запрос и заканчивается.

Распаковка внутри запроса невозможна по той же причине, что и выше: на
большом архиве она занимает минуты, и `uhttpd` убил бы процесс посреди
работы — в браузере это выглядит как `Bad Gateway: The process did not
produce any response`. Поэтому распаковку делает отдельный фоновый процесс
`/usr/libexec/overlaybackup stage`, а страница показывает, что она идёт, и
обновляется сама.

Распаковка идёт в `/overlay/.overlaybackup/staging` — каталог **рядом** с
`upper`, вне смонтированного объединения, так что живую систему это не трогает.
Битый архив проваливает распаковку, и ничего не меняется. Если в распакованном
нет каталога `etc`, подмена тоже отменяется: остаться без `etc` значит
остаться без загрузки. После этого ставится флаг и устройство уходит
в перезагрузку.

Если фоновый процесс умрёт, не закончив (например, пропало питание), страница
увидит это по отсутствию его PID в `/proc` и сообщит, а не будет крутить
распаковку вечно.

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

### Проверка модели и версии

Архив можно восстановить только на ту же модель устройства и ту же версию
OpenWrt, на которых он снят: внутри — модули ядра, конфигурация радио и база
пакетов конкретного выпуска и устройства. Не совпадёт — устройство может не
загрузиться. Поэтому это проверяется, причём до того, как что-либо изменено.

**Паспорт архива.** Перед каждым бэкапом плагин пишет `/etc/overlaybackup.meta`:
имя платы, модель, версию, ревизию и цель сборки. Файл пишется обычным путём,
через объединённый корень, и потому попадает в архив вместе с остальным overlay.
Имя платы берётся оттуда же, откуда его берёт сама OpenWrt (`board_name` в
`/lib/functions.sh`): из `/tmp/sysinfo/board_name`, который заполняется при
ранней загрузке из device tree — одинаково в 24.10 и 25.12.

**Сверка.** После распаковки, перед постановкой подмены в очередь, паспорт из
архива сверяется с этим устройством: сначала имя платы, затем версия OpenWrt.
Не совпало — распакованное удаляется, на странице сообщение с обоими
значениями, ничего не изменено.

Архивы, снятые прежними версиями плагина, паспорта не имеют. Для них модель
сверяется по `etc/board.json`: OpenWrt создаёт его на первой загрузке
(`model.id` — то же имя платы), он лежит в overlay и поэтому есть в любом
бэкапе. Версию у таких архивов проверить не по чему — следите за ней сами,
она есть в имени файла.

Какой архив подходит этому роутеру, видно прямо на странице — в карточке
восстановления указаны модель, имя платы и версия.

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
  usr/libexec/overlaybackup          паспорт архива и фоновая распаковка
  usr/lib/lua/luci/controller/…lua    контроллер (маршруты и логика)
  usr/lib/lua/luci/view/…htm          шаблон страницы
  usr/lib/lua/luci/i18n/…ru.lmo       собранный русский каталог
install.sh                            установка и обновление, в том числе с GitHub
uninstall.sh                          удаление, в том числе с GitHub
MANIFEST                              список файлов и путей установки
po/                                   исходники переводов и инструменты к ним
Makefile                              необязательная сборка ipk для OpenWrt
```

## Предупреждение

Восстановление перезаписывает текущее содержимое overlay и перезагружает
устройство. Архив с другой модели или другой версии OpenWrt плагин не примет,
но саму подмену слоя на загрузке на каждом устройстве стоит впервые делать,
зная, как войти в failsafe: если восстановленная система не поднимется,
откат делается оттуда (см. «Откат»), а в крайнем случае — сбросом к
заводским настройкам.

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

Supports OpenWrt **24.10.x** (opkg package manager) and **25.12.x** (apk): the
installer works out which one the router has.
Tested on Netis NX30 v2 / GL.iNet Flint 2 running vanilla OpenWrt 25.12.5.

## Features

* **Download a backup** — the entire overlay content (installed packages,
  configuration, modified and added files) is packed and streamed straight to
  the browser as
  `overlay-backup-<hostname>-<OpenWrt version>-<YYYY-MM-DD>.tar.gz`. Nothing is
  written to the router, so the size of the overlay is not limited by free RAM.
* **Restore** from a previously saved archive. The new layer is unpacked next
  to the live one and swapped in early during boot - the way overlayfs allows.
* **Model and version check**: an archive from another device or another
  OpenWrt version will not be restored - this is checked before anything
  changes.
* **Rollback**: the layer replaced by the last restore is kept.
* Failures are reported on the page along with the `tar` output.
* Install, update and removal - one command each, on 24.10 and 25.12.

## Installation

### Option 1: one command from GitHub

Installing and updating - on the router:

```sh
wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/install.sh | sh
```

Removing:

```sh
sh /usr/share/luci-app-overlaybackup/uninstall.sh
```

That is all - no `git`, no computer in between, no installing packages by hand.
`install.sh` is the same script for every case: read from a pipe, it downloads
the `main` branch as an archive and runs itself from there, and then:

1. checks the dependencies (`luci-compat`, `luci-lua-runtime`, `luci-lib-nixio`,
   `tar`) and installs whatever is missing through `apk` on 25.12 or `opkg` on
   24.10. If everything is already there, it does not go online at all;
2. lays out the files along the paths in `MANIFEST` and leaves a copy of the
   manifest and `uninstall.sh` on the router in
   `/usr/share/luci-app-overlaybackup/` - so removal works offline and after a
   reboot, and removes exactly what was installed;
3. enables the layer-swap init script, raises `uhttpd`'s `script_timeout`,
   drops the LuCI caches and restarts `uhttpd`.

`uninstall.sh` can also be run straight from GitHub, it needs no project files:
`wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/uninstall.sh | sh`. It leaves
`/overlay/.overlaybackup/previous` alone - the layer replaced by the last
restore - because that is your data; `--purge` removes it as well. The
dependency packages stay installed too: other software may use them.

Options go after `sh -s --`. For a router without internet access, install the
dependencies beforehand and run with `--no-deps` - the installer then only
checks the packages are there:

```sh
wget -q -O - https://raw.githubusercontent.com/p0sixxx/luci-app-overlaybackup/main/install.sh | sh -s -- --no-deps
```

#### From a computer over scp

```sh
scp -O -r luci-app-overlaybackup root@<router IP>:/tmp/
ssh root@<router IP> 'sh /tmp/luci-app-overlaybackup/install.sh'
```

`-O` is required: modern OpenSSH copies over SFTP by default, and OpenWrt ships
no `sftp-server` - without the flag you get `sftp-server: not found`.

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

`install.sh` installs them itself, and installing the package pulls them
in too. The commands above are only needed with `--no-deps`.

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

So the plugin looks for GNU tar - the `tar` package installs it as
`/usr/libexec/tar-gnu` on 24.10 and 25.12 alike, and points `/bin/tar` at it
through alternatives - and, when it finds it, adds
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

Streaming runs into a different limit instead - time. `uhttpd` kills any CGI
request that lasts longer than `script_timeout` seconds **in total** (60 by
default): the timer is armed when the process starts and is not extended by
sending or receiving data. Compressing an overlay of a few hundred megabytes on
a router CPU takes more than a minute, so the stream would be cut off halfway.
That is why `install.sh` raises `uhttpd.main.script_timeout` to 1800,
remembering the previous value, and `uninstall.sh` puts it back.

The other trade-off of streaming: `Content-Length` cannot be set, because the size is not known in
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
than `/tmp`, for the same reason of memory. That is where the request ends.

Unpacking inside the request is impossible for the same reason as above: on a
large archive it takes minutes, and `uhttpd` would kill the process partway
through - which the browser shows as `Bad Gateway: The process did not produce
any response`. So the unpacking is done by a separate background process,
`/usr/libexec/overlaybackup stage`, while the page shows that it is running and
refreshes on its own.

It unpacks into `/overlay/.overlaybackup/staging`, a directory **next to**
`upper` and outside the mounted union, so the live system is left alone. A
broken archive fails to unpack and nothing changes. If the unpacked tree has no
`etc` directory the swap is called off too: a device without `etc` is a device
that does not boot. A flag is then set and the device reboots.

Should the background process die before finishing (a power cut, say), the page
notices that its PID is gone from `/proc` and reports it rather than showing the
unpacking forever.

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

### Model and version check

An archive can only be restored onto the same device model and the same OpenWrt
version it was taken from: it holds kernel modules, radio configuration and the
package database of one particular release and device. A mismatch may leave the
device unable to boot. So this is checked, and before anything is changed.

**The archive passport.** Before every backup the plugin writes
`/etc/overlaybackup.meta`: board name, model, version, revision and build
target. It is written the ordinary way, through the merged root, so it ends up
in the archive along with the rest of the overlay. The board name comes from
where OpenWrt itself takes it (`board_name` in `/lib/functions.sh`):
`/tmp/sysinfo/board_name`, filled in from the device tree early during boot -
the same on 24.10 and 25.12.

**The check.** After unpacking, before the swap is queued, the passport from
the archive is compared with this device: the board name first, then the
OpenWrt version. On a mismatch the unpacked tree is deleted, the page reports
both values, and nothing is changed.

Archives taken by earlier versions of the plugin have no passport. For those the
model is checked against `etc/board.json`: OpenWrt generates it on first boot
(`model.id` is the same board name), it lives in the overlay and so is in every
backup. Their version cannot be checked against anything - keep an eye on it
yourself, it is in the file name.

Which archive fits this router is shown right on the page: the restore card
lists its model, board name and version.

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
  usr/libexec/overlaybackup          archive passport and background unpacking
  usr/lib/lua/luci/controller/…lua    controller (routes and logic)
  usr/lib/lua/luci/view/…htm          page template
  usr/lib/lua/luci/i18n/…ru.lmo       compiled Russian catalog
install.sh                            install and update, GitHub included
uninstall.sh                          removal, GitHub included
MANIFEST                              file list and install paths
po/                                   translation sources and their tooling
Makefile                              optional ipk build for OpenWrt
```

## Warning

Restoring overwrites the current overlay content and reboots the device. The
plugin will not accept an archive from another model or another OpenWrt
version, but the first boot-time layer swap on each device is worth doing
knowing how to get into failsafe: should the restored system not come up, roll
back from there (see "Rolling back"), or, as a last resort, reset to factory
defaults.

## License

GPL-2.0-or-later.
