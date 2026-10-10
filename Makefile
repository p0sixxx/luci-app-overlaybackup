#
# Copyright (C) 2025 p0sixxx
#
# This is free software, licensed under the GNU General Public License v2.
#
# Optional: the project is normally deployed by copying files onto the
# router (see install.sh), but this builds a regular package when an OpenWrt
# buildroot or SDK is at hand. The format follows the target release -
# .apk on 25.12 and newer, .ipk up to 24.10 - and needs nothing here.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-overlaybackup
PKG_VERSION:=3.2
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=p0sixxx

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-overlaybackup
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Overlay backup and restore
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-compat +luci-lua-runtime +luci-lib-nixio +tar
endef

define Package/luci-app-overlaybackup/description
  LuCI page that packs the /overlay partition into an archive, lets you
  download it and restores the device from a previously saved copy.
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

# The Russian catalog is committed pre-compiled (see po/README.md), so it
# is installed as a plain file rather than built here.
define Package/luci-app-overlaybackup/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./runtime/etc/init.d/overlaybackup-restore \
		$(1)/etc/init.d/overlaybackup-restore
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./runtime/usr/libexec/overlaybackup \
		$(1)/usr/libexec/overlaybackup
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./runtime/usr/lib/lua/luci/controller/overlaybackup.lua \
		$(1)/usr/lib/lua/luci/controller/overlaybackup.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view
	$(INSTALL_DATA) ./runtime/usr/lib/lua/luci/view/overlaybackup.htm \
		$(1)/usr/lib/lua/luci/view/overlaybackup.htm
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_DATA) ./runtime/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo \
		$(1)/usr/lib/lua/luci/i18n/overlaybackup.ru.lmo
endef

define Package/luci-app-overlaybackup/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] && exit 0
/etc/init.d/overlaybackup-restore enable 2>/dev/null
# uhttpd cuts any CGI request longer than script_timeout (60 s by default)
# in total; large backups and restores need far more. See install.sh.
cur=$$(uci -q get uhttpd.main.script_timeout)
if [ -z "$$cur" ] || [ "$$cur" -lt 1800 ] 2>/dev/null; then
	[ -n "$$(uci -q get uhttpd.main.overlaybackup_orig_timeout)" ] || \
		uci set uhttpd.main.overlaybackup_orig_timeout="$${cur:-60}"
	uci set uhttpd.main.script_timeout=1800
	uci commit uhttpd
	/etc/init.d/uhttpd restart
fi
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null
exit 0
endef

define Package/luci-app-overlaybackup/postrm
#!/bin/sh
orig=$$(uci -q get uhttpd.main.overlaybackup_orig_timeout)
if [ -n "$$orig" ]; then
	uci set uhttpd.main.script_timeout="$$orig"
	uci -q delete uhttpd.main.overlaybackup_orig_timeout
	uci commit uhttpd
fi
rm -f /etc/rc.d/S*overlaybackup-restore 2>/dev/null
rm -f /etc/overlaybackup.meta 2>/dev/null
rm -rf /overlay/.overlaybackup/staging 2>/dev/null
rm -f /overlay/.overlaybackup/upload.tar.gz /overlay/.overlaybackup/pending \
      /overlay/.overlaybackup/working /overlay/.overlaybackup/restore.log 2>/dev/null
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null
exit 0
endef

$(eval $(call BuildPackage,luci-app-overlaybackup))
