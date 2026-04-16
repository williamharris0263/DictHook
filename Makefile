TARGET := iphone:clang:latest:12.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DictDataMaster

# 包含 fishhook.c
DictDataMaster_FILES = Tweak.x fishhook.c
DictDataMaster_CFLAGS = -fobjc-arc
# 包含 WebKit 框架
DictDataMaster_FRAMEWORKS = UIKit Foundation WebKit

include $(THEOS_MAKE_PATH)/tweak.mk
