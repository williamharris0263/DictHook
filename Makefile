TARGET := iphone:clang:latest:12.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AllInOneDumper

AllInOneDumper_FILES = Tweak.x fishhook.c
AllInOneDumper_CFLAGS = -fobjc-arc
AllInOneDumper_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
