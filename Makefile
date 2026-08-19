#
# Copyright (C) 2025 p0sixxx
#
# This is free software, licensed under the GNU General Public License v2.
#

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-overlaybackup
PKG_VERSION:=3.1
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=p0sixxx

LUCI_TITLE:=Overlay backup and restore
LUCI_DESCRIPTION:=LuCI page that packs the /overlay partition into an archive, \
	lets you download it and restores the device from a previously saved copy.
LUCI_DEPENDS:=+luci-base +luci-compat +luci-lua-runtime +luci-lib-nixio +tar
LUCI_PKGARCH:=all

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
