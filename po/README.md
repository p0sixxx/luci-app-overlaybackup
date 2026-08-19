# Translations

The plugin ships its interface strings through LuCI's normal gettext
pipeline, so it translates the same way any other `luci-app-*` does.

```
po/templates/overlaybackup.pot   source strings, regenerated from the sources
po/ru/overlaybackup.po           Russian translation
po/extract.py                    extracts strings into the .pot
po/verify-lmo.py                 independently verifies a compiled .lmo
```

Strings come from two places: `<%: %>` in the page template, and the Lua
controller - the menu titles passed to `_()` plus the one message it
writes out itself through `i18n.translate()`.

Where the strings are resolved differs by kind, and the plugin does
nothing to arrange either:

* the page body is rendered on the router, so `<%: %>` and
  `i18n.translate()` go through `luci.i18n` server-side. Nothing loads
  the catalog explicitly - `luci-lua-runtime`'s dispatcher calls
  `i18n.setlanguage()` on every request, and that loads *every*
  `*.<lang>.lmo` in `/usr/lib/lua/luci/i18n` at once. There is no
  per-package load function in that runtime at all.
* the sidebar menu title is translated in the browser instead. `_()` in
  the Lua dispatcher returns its argument untouched - it exists only so
  the string can be extracted - and the menu is rendered client-side
  from `window.TR`, the same flat table every JS LuCI app uses.

Both paths key the message by the same hash of the same source string,
which is why one catalog serves both. The browser side normalises the
key with `trimws()` first, and that is why `extract.py` refuses msgids
whose whitespace is not already normalised.

The compiled catalog is committed at
`runtime/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo` and installed to
`/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo`. It is committed on
purpose: this project is deployed by copying files onto a router, which
has neither a compiler nor the LuCI build host tools.

## Every package shares one keyspace - beware generic phrases

Catalogs are keyed only by the hash of the source string, with no
per-package namespace, so a msgid that also exists in `luci-base` picks
up whichever translation happens to win.

This is not theoretical. Two of this plugin's strings originally
collided with `luci-base`, and both had a different translation there:

| msgid             | here                | `luci-base`                  |
|-------------------|---------------------|------------------------------|
| `Download backup` | Скачать бэкап       | Скачать резервную копию      |
| `Restore backup`  | Восстановить бэкап  | Восстановить резервную копию |

A JavaScript app can disambiguate with gettext's message context
(`msgctxt`), because its `_()` takes one. A Lua template has no way to
pass a context through `<%: %>`, so the fix here is to keep the msgids
themselves distinct: those two buttons now read `Download the archive`
and `Restore and reboot`, and `Delete backup` was renamed to
`Delete the archive` alongside them for consistency.

To re-check after adding strings, diff your msgids against LuCI's:

```sh
curl -sO https://raw.githubusercontent.com/openwrt/luci/master/modules/luci-base/po/ru/base.po
# then compare the msgid sets and look for differing msgstr values
```

## Adding or updating strings

1. Edit the sources, wrapping user-visible text in `<%: %>` in the
   template or `_()` / `i18n.translate()` in the controller.
2. Regenerate the template:

   ```sh
   python3 po/extract.py
   ```

3. Add the new msgids to `po/ru/overlaybackup.po` (and any other
   language).
4. Rebuild the catalog - see below.
5. Verify it:

   ```sh
   python3 po/verify-lmo.py po/ru/overlaybackup.po \
       runtime/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo
   ```

`extract.py` refuses to emit a msgid whose whitespace is not already
normalised, rather than producing a catalog that quietly half-works.

## Rebuilding the .lmo

`.lmo` is LuCI's own binary catalog format, produced by `po2lmo` from
`luci-base`. It is not part of a normal Linux distribution, so build it
from the LuCI sources once:

```sh
git clone --depth 1 https://github.com/openwrt/luci
cd luci/modules/luci-base/src
gcc -O2 -o po2lmo po2lmo.c lib/lmo.c
```

`lib/lmo.c` includes a header generated from `lib/plural_formula.y` by
*lemon* (not bison, despite the `.y` extension), and `po2lmo` never
calls that evaluator. If it is not at hand, compiling `po2lmo.c` against
just the `sfh_hash()` function copied out of `lib/lmo.c` produces a
byte-identical tool:

```sh
sed -n '/^uint32_t sfh_hash/,/^}/p' lib/lmo.c > sfh_only.c
sed -i '1i #include "lib/lmo.h"' sfh_only.c
gcc -O2 -o po2lmo po2lmo.c sfh_only.c
```

Then, from the repository root:

```sh
po2lmo po/ru/overlaybackup.po runtime/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo
```

## Why `verify-lmo.py` exists

`po2lmo` is a build tool that fails quietly: a catalog with wrong keys
is a well-formed file that simply never matches anything, and the UI
just stays English. `verify-lmo.py` reimplements both the hash and the
container format from scratch and checks every message round-trips, so
a broken catalog is caught here rather than on the router.

## Adding another language

```sh
mkdir -p po/<lang>
cp po/templates/overlaybackup.pot po/<lang>/overlaybackup.po
# translate, set a correct Plural-Forms header for that language, then:
po2lmo po/<lang>/overlaybackup.po \
    runtime/usr/lib/lua/luci/i18n/overlaybackup.<lang>.lmo
python3 po/verify-lmo.py po/<lang>/overlaybackup.po \
    runtime/usr/lib/lua/luci/i18n/overlaybackup.<lang>.lmo
```

Then add the new `.lmo` to `deploy/MANIFEST` so `install.sh` picks it up
and `uninstall.sh` removes it again, and to the `Makefile` so the ipk
carries it too.
