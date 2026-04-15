TARGET := iphone:clang:latest:12.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GetDictPwd

# 👇 注意这里，加上了 fishhook.c
GetDictPwd_FILES = Tweak.x fishhook.c
GetDictPwd_CFLAGS = -fobjc-arc
GetDictPwd_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
