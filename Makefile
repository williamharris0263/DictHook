TARGET := iphone:clang:latest:12.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DictCoreDumper

DictCoreDumper_FILES = Tweak.x fishhook.c
DictCoreDumper_CFLAGS = -fobjc-arc
DictCoreDumper_FRAMEWORKS = UIKit Foundation WebKit

include $(THEOS_MAKE_PATH)/tweak.mk
