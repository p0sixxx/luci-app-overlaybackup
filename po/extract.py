#!/usr/bin/env python3
"""
Extract translatable strings from the plugin into a gettext .pot template.

LuCI's own build uses xgettext with custom keywords; this project is
deployed by copying files rather than through the OpenWrt build system,
so this small extractor keeps po/templates/overlaybackup.pot in sync
without needing the LuCI build host tools.

Strings come from two places:

  * the page template, in LuCI's template syntax:

        <%:some text%>

  * the Lua controller, both the menu titles passed to _() and the one
    message it writes out itself through i18n.translate().

Both are resolved server-side against the same .lmo catalog, so a msgid
has to match the source string byte for byte. This script refuses to
emit a msgid whose whitespace is not already normalised, since a stray
double space would hash differently and silently never match.

Usage:  python3 po/extract.py
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VIEW = os.path.join(ROOT, 'runtime/usr/lib/lua/luci/view/overlaybackup.htm')
CONTROLLER = os.path.join(ROOT, 'runtime/usr/lib/lua/luci/controller/overlaybackup.lua')
OUTPUT = os.path.join(HERE, 'templates/overlaybackup.pot')

RE_TEMPLATE = re.compile(r'<%:(.*?)%>', re.S)
RE_LUA_UNDERSCORE = re.compile(r'(?<![A-Za-z0-9_])_\(\s*"((?:[^"\\]|\\.)*)"\s*\)')
RE_LUA_TRANSLATE = re.compile(r'i18n\.translate\(\s*"((?:[^"\\]|\\.)*)"')

HEADER = '''msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\\n"
"Content-Transfer-Encoding: 8bit\\n"
"Project-Id-Version: luci-app-overlaybackup\\n"
"Language-Team: none\\n"
"PO-Revision-Date: 2026-08-19 00:00+0000\\n"
"Last-Translator: none\\n"
"Language: \\n"
"MIME-Version: 1.0\\n"
'''


def po_escape(s):
    return s.replace('\\', '\\\\').replace('"', '\\"')


def unescape_lua(s):
    return s.replace('\\"', '"').replace('\\\\', '\\')


def main():
    view = open(VIEW, encoding='utf-8').read()
    controller = open(CONTROLLER, encoding='utf-8').read()

    found = []
    for m in RE_TEMPLATE.findall(view):
        if m not in found:
            found.append(m)
    for regex in (RE_LUA_UNDERSCORE, RE_LUA_TRANSLATE):
        for m in regex.findall(controller):
            m = unescape_lua(m)
            if m not in found:
                found.append(m)

    bad = [s for s in found if s != ' '.join(s.split())]
    if bad:
        print('Refusing to write a catalog with non-normalised whitespace.',
              file=sys.stderr)
        print('Fix these strings in the sources first:', file=sys.stderr)
        for s in bad:
            print('  %r' % s, file=sys.stderr)
        return 1

    with open(OUTPUT, 'w', encoding='utf-8') as f:
        f.write(HEADER)
        for s in found:
            f.write('\nmsgid "%s"\nmsgstr ""\n' % po_escape(s))

    print('%s: %d strings' % (os.path.relpath(OUTPUT, ROOT), len(found)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
