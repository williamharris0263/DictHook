TARGET := iphone:clang:latest:12.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GetDictPwd

GetDictPwd_FILES = Tweak.x
GetDictPwd_CFLAGS = -fobjc-arc
# 确保引入 UIKit 框架用于弹窗
GetDictPwd_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
