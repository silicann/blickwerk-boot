include makefilet-download-ondemand.mk

DEBIAN_UPLOAD_TARGET = silicann

# definitions
PWD = $(shell pwd)
VARIANT ?= production
DEBIAN_BUILDPACKAGE_COMMAND ?= dpkg-buildpackage

# dirs
DIR_CONFIG = $(PWD)/configurations
DIR_BUILD = $(PWD)/build
DIR_BUILD_VARIANT = $(DIR_BUILD)/$(VARIANT)

# compiler settings
GENERIC_BUILD_FLAGS = -j$(NMAKEJOBS) ARCH=arm CROSS_COMPILE="$(COMPILER_PATH)"
COMPILER_PATH = /usr/bin/arm-linux-gnueabi-
NPROCS=$(shell nproc --all)
NMAKEJOBS=$(shell expr $(NPROCS) \+ 1)
MODULE_FLAGS = -DMODULE -fno-pic

# dependencies
# if you change these, update the hash in the corresponding mk file in make.d/
LINUX_VERSION = 4.4.181
UBOOT_VERSION = 2017.03


.PHONY: default-target
default-target: build


# include after default target
include make.d/linux.mk
include make.d/uboot.mk


.PHONY: prep-source
prep-source:: patch_uboot patch_linux


.PHONY: build
build: build_uboot build_linux


.PHONY: install
install: build_uboot build_linux
	$(MAKE) $(LINUX_BUILD_FLAGS) modules_install INSTALL_MOD_PATH="$(abspath $(DESTDIR))"
	rm -f "$(DESTDIR)/lib/modules/$(LINUX_VERSION)"*/source
	rm -f "$(DESTDIR)/lib/modules/$(LINUX_VERSION)"*/build
	mkdir -p "$(DESTDIR)/boot/"
	# copy uboot related files (elf)s
	cp "$(DIR_BUILD_UBOOT)/u-boot-nodtb.bin" "$(DESTDIR)/boot/u-boot.bin"
	cp "$(DIR_BUILD_UBOOT)/spl/u-boot-spl-nodtb.bin" "$(DESTDIR)/boot/u-boot-spl.bin"
	# copy linux related files (devicetree, kernel)
	cp "$(DIR_BUILD_LINUX)/arch/arm/boot/zImage" "$(DESTDIR)/boot/"
	cp "$(UBOOT_DTB)" "$(DESTDIR)/boot/urwerk.dtb"
	echo "$(LINUX_VERSION)" >"$(DESTDIR)/boot/zImage.version"


.PHONY: initrd_header
initrd_header: build_uboot
	"$(DIR_UBOOT)/tools/mkimage" -A arm  -T ramdisk -C gzip -n "urwerk-ramdisk" \
		-d "$(DESTDIR)/boot/initrd.img-$(LINUX_VERSION)" "$(DESTDIR)/boot/ramdisk"
