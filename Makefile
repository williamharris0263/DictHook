TARGET := iphone:clang:latest:12.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = GetDictPwd

GetDictPwd_FILES = Tweak.x
GetDictPwd_CFLAGS = -fobjc-arc
GetDictPwd_FRAMEWORKS = UIKit Foundation

# 👇 就是新增了这一行，告诉编译器忽略找不到的外部函数，留到运行时再解析
GetDictPwd_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
