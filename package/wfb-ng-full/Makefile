# =============================================================================
# [PXLABS] NOTICE — SUPERSEDED RECIPE. NOT A BUILD INPUT FOR THE DEPLOYED IMAGE.
# =============================================================================
# [PXLABS]
# [PXLABS] Status:   Superseded. Retained for historical traceability only.
# [PXLABS] Deployed: wfb-ng 25.01-r1, supplied by the official OpenWrt 24.10.4
# [PXLABS]           package feed and resolved automatically by the ImageBuilder.
# [PXLABS]
# [PXLABS] This recipe builds wfb-ng 24.9.7-r2 from svpcom/wfb-ng@3a05304. It
# [PXLABS] represents an earlier approach that compiled the package locally in the
# [PXLABS] OpenWrt SDK. That approach was abandoned once the package was found in
# [PXLABS] the official feed. It did not contribute to the committed firmware
# [PXLABS] image, as established by two facts:
# [PXLABS]
# [PXLABS]   - the resulting .ipk files were staged in the ImageBuilder's
# [PXLABS]     packages-local/ directory, whose index file Packages is zero bytes;
# [PXLABS]   - repositories.conf declares the local repository as file:packages,
# [PXLABS]     not packages-local.
# [PXLABS]
# [PXLABS] Do not use this recipe as a build input. To reproduce the deployed
# [PXLABS] image, follow README.md section 7.1.
# [PXLABS]
# [PXLABS] Reference: README.md section 3 and section 3.1.
# =============================================================================

include $(TOPDIR)/rules.mk

PKG_NAME:=wfb-ng-full
PKG_VERSION:=24.9.7
PKG_RELEASE:=2

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/svpcom/wfb-ng.git
PKG_SOURCE_VERSION:=3a053040442174e6c1ce76866c6da4b12c19dbb4
#PKG_MIRROR_HASH:=2451a64be61a5052c2625c859548adcea141afece7ad297e0043bb911035dcdd

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Vasily Evseenko <svpcom@p2ptech.org>

PKG_BUILD_PARALLEL:=1
PYPI_SOURCE_NAME:=wfb_ng
PKG_BUILD_DEPENDS:=libevent2

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/python/python3-package.mk

PYTHON3_VARS:=$(PYTHON3_VARS) VERSION=$(PKG_VERSION) COMMIT=$(PKG_SOURCE_VERSION) OMIT_DATA_FILES=1

define Build/Compile
	$(MAKE) $(PKG_JOBS) -C $(PKG_BUILD_DIR)/$(MAKE_PATH) \
		$(MAKE_FLAGS) \
		VERSION=$(PKG_VERSION) COMMIT=$(PKG_SOURCE_VERSION) \
		all_bin
	$(call Py3Build/Compile)
endef

define Package/wfb-ng-full
  SECTION:=net
  CATEGORY:=Network
  SUBMENU:=Wireless
  CONFLICTS:=wfb-ng
  TITLE:=Long-range packet radio link using raw WiFi
  URL:=https://github.com/svpcom/wfb-ng
  DEPENDS:=+bash +iw +kmod-tun +openssh-client +libpcap +libsodium +libstdcpp +python3-twisted +python3-pyserial +python3-msgpack +python3-jinja2 +python3-pyroute2
endef

define Package/wfb-ng-full/description
  The next generation of long-range packet radio link using raw WiFi.
  This is a full version that can act as cluster manager, standalone
  receiver or transmitter with divesity.
endef

define Package/wfb-ng/conffiles
/usr/sbin/wfb-ng.sh
/etc/wifibroadcast.cfg
endef

define Py3Package/wfb-ng-full/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(CP) $(PKG_INSTALL_DIR)/usr/bin/* $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/wfb_rx $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/wfb_tx $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/wfb_tx_cmd $(1)/usr/bin/
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/wfb_keygen $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/wfb-ng.init $(1)/etc/init.d/wfb-ng
endef

$(eval $(call Py3Package,wfb-ng-full))
$(eval $(call BuildPackage,wfb-ng-full))
