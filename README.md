# luci-app-overlaybackup

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

### Обновление с прежних версий

Ранние версии плагина назывались `fullbackup` и `fullbackuprestore`. Их файлы
надо удалить, иначе в меню останутся лишние пункты, ведущие на устаревшие
страницы:

```sh
rm -f /usr/lib/lua/luci/controller/fullbackup.lua \
      /usr/lib/lua/luci/controller/fullbackuprestore.lua \
      /usr/lib/lua/luci/view/fullbackup.htm \
      /usr/lib/lua/luci/view/fullbackuprestore.htm
```

Скрипт `install.sh` делает это сам.

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
