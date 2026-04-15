TARGET := iphone:clang:latest:12.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GetDictPwd

GetDictPwd_FILES = Tweak.x
GetDictPwd_CFLAGS = -fobjc-arc
GetDictPwd_FRAMEWORKS = UIKit Foundation

# 注意：这里已经删除了上一轮的 GetDictPwd_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
