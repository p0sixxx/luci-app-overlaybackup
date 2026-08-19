#
# Copyright (C) 2025 p0sixxx
#
# This is free software, licensed under the GNU General Public License v2.
#
# Optional: the project is normally deployed by copying files onto the
# router (see deploy/), but this builds a regular ipk when an OpenWrt
# buildroot or SDK is at hand.
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
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null
exit 0
endef

define Package/luci-app-overlaybackup/postrm
#!/bin/sh
rm -f /tmp/luci-indexcache* 2>/dev/null
rm -rf /tmp/luci-modulecache 2>/dev/null
exit 0
endef

$(eval $(call BuildPackage,luci-app-overlaybackup))
