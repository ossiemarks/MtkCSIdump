include $(TOPDIR)/rules.mk

PKG_NAME:=csidump
PKG_VERSION:=0.1
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0
PKG_LICENSE_FILES:=LICENSE.txt

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/csidump
  SECTION:=net
  CATEGORY:=Network
  TITLE:=MediaTek mt76 CSI dump UDP server
  URL:=https://github.com/ossiemarks/MtkCSIdump
  DEPENDS:=+libnl-tiny +libstdcpp +libpthread
endef

define Package/csidump/description
  Streams Channel State Information from the mt76 driver's MediaTek
  vendor CSI interface to registered UDP clients. Requires an mt76
  build that implements the MTK vendor CSI_CTRL command.
endef

TARGET_CXXFLAGS += -I$(STAGING_DIR)/usr/include/libnl-tiny
CMAKE_OPTIONS += \
	-DLIBNL_TINY_INCLUDE_DIR=$(STAGING_DIR)/usr/include/libnl-tiny \
	-DLIBNL_TINY_LIBRARY=$(STAGING_DIR)/usr/lib/libnl-tiny.so

define Package/csidump/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/CSIdump $(1)/usr/bin/CSIdump
endef

$(eval $(call BuildPackage,csidump))
