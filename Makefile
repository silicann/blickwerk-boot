# this requires the package "wurzelwerk-build-essential" to be installed
# alternatively you can add an include directory: "make -I make.d ..."
include wurzelwerk/packaging.mk

# definitions
PWD = $(shell pwd)
COMPILER_PATH = /usr/bin/arm-linux-gnueabi-
NPROCS=$(shell nproc --all)
NMAKEJOBS=$(shell expr $(NPROCS) \+ 1)
DEBIAN_BUILDPACKAGE_COMMAND = dpkg-buildpackage -us -uc

# dirs
DIR_CONFIG = $(PWD)/configurations
DIR_UBOOT = $(PWD)/u-boot
DIR_UBOOT_CONFIG = $(DIR_CONFIG)/u-boot
DIR_LINUX = $(PWD)/linux
DIR_LINUX_CONFIG = $(DIR_CONFIG)/linux
DIR_BUILD = $(PWD)/build

# stamps
STAMP_UBOOT_PATCH = $(DIR_UBOOT)/.uboot-patched.stamp
STAMP_UBOOT_BUILT = $(DIR_BUILD)/.uboot-built.stamp
STAMP_LINUX_PATCH = $(DIR_LINUX)/.linux-patched.stamp
STAMP_LINUX_BUILT = $(DIR_BUILD)/.linux-built.stamp

# target system
LINUX_VERSION = 4.4
LINUX_PATCH_LEVEL = 72
LINUX_NAME = "$(LINUX_VERSION).$(LINUX_PATCH_LEVEL)"

DEBIAN_PACKAGE_SUBMODULE_DIRECTORIES = linux u-boot

.PHONY: install initrd_header build_uboot build_linux clean clean_linux clean_uboot

default-target: install
prep-source:: $(STAMP_UBOOT_PATCH) $(STAMP_LINUX_PATCH)

$(STAMP_UBOOT_PATCH):
	mkdir -p "$(DIR_BUILD)"
	git -C $(DIR_UBOOT) am $(DIR_UBOOT_CONFIG)/patches/*.patch
	touch "$(STAMP_UBOOT_PATCH)"

$(STAMP_UBOOT_BUILT): $(STAMP_UBOOT_PATCH)
	mkdir -p "$(DIR_BUILD)"
	make -C $(DIR_UBOOT) ARCH=arm urwerk_defconfig
	make -C $(DIR_UBOOT) -j$(NMAKEJOBS) u-boot.sb ARCH=arm CROSS_COMPILE=$(COMPILER_PATH)
	touch "$(STAMP_UBOOT_BUILT)"

$(STAMP_LINUX_PATCH):
	mkdir -p "$(DIR_BUILD)"
	xz -cd $(DIR_LINUX_CONFIG)/patch-$(LINUX_VERSION).$(LINUX_PATCH_LEVEL).xz | patch -d $(DIR_LINUX) -p1
	# workaround for a clean repository, maybe we can do better?
	git -C $(DIR_LINUX) add -A  && git -C $(DIR_LINUX) commit -m " Linux $(LINUX_NAME)"
	git -C $(DIR_LINUX) am $(DIR_LINUX_CONFIG)/patches/*.patch
	touch "$(STAMP_LINUX_PATCH)"

$(STAMP_LINUX_BUILT): $(STAMP_LINUX_PATCH)
	mkdir -p "$(DIR_BUILD)"
	$(MAKE) -C $(DIR_LINUX) -j$(NMAKEJOBS) ARCH=arm CROSS_COMPILE=$(COMPILER_PATH) urwerk_defconfig
	#for debuggin boot problems run this defconfig
	#$(MAKE) -C $(DIR_LINUX) -j$(NMAKEJOBS) ARCH=arm CROSS_COMPILE=$(COMPILER_PATH) urwerk_defconfig
	$(MAKE) -C $(DIR_LINUX) -j$(NMAKEJOBS) ARCH=arm CROSS_COMPILE=$(COMPILER_PATH)
	touch "$(STAMP_LINUX_BUILT)"

patch_uboot: $(STAMP_UBOOT_PATCH)
patch_linux: $(STAMP_LINUX_PATCH)
build_uboot: $(STAMP_UBOOT_BUILT)
build_linux: $(STAMP_LINUX_BUILT)

install: build_uboot build_linux
	INSTALL_MOD_PATH=../$(DESTDIR) $(MAKE) -C $(DIR_LINUX) modules_install ARCH=arm CROSS_COMPILE=$(COMPILER_PATH)
	rm -f $(DESTDIR)/lib/modules/$(LINUX_NAME)*/source
	rm -f $(DESTDIR)/lib/modules/$(LINUX_NAME)*/build

	mkdir -p $(DESTDIR)/boot/
	# copy uboot related files (elf)s
	cp $(DIR_UBOOT)/u-boot-nodtb.bin $(DESTDIR)/boot/u-boot.bin
	cp $(DIR_UBOOT)/spl/u-boot-spl-nodtb.bin $(DESTDIR)/boot/u-boot-spl.bin
	# copy linux related files (devicetree, kernel)
	cp $(DIR_LINUX)/arch/arm/boot/zImage $(DESTDIR)/boot/.
	cp $(DIR_LINUX)/arch/arm/boot/dts/urwerk.dtb $(DESTDIR)/boot/.
	echo "$(LINUX_NAME)" > $(DESTDIR)/boot/zImage.version


initrd_header:
	$(DIR_UBOOT)/tools/mkimage -A arm  -T ramdisk -C gzip -n "urwerk-ramdisk" -d $(DESTDIR)/boot/initrd.img-$(LINUX_NAME) $(DESTDIR)/boot/ramdisk

uEnv.img:
	$(DIR_UBOOT)/tools/mkimage -A arm -T script -C none -n 'Initialization Script File' -d $(DIR_UBOOT_CONFIG)/uboot_script_example $@

clean: clean_uboot clean_linux

clean_linux:
	$(MAKE) -C $(DIR_LINUX) mrproper
	# git commands may fail, when building from a source tarball
	if GIT_DIR="$(DIR_LINUX)/.git" git rev-parse > /dev/null 2>&1; then \
		git -C "$(DIR_LINUX)" reset --hard; \
		git -C "$(DIR_LINUX)" clean -f -d; \
		rm -f "$(STAMP_LINUX_BUILT)"; \
		rm -f "$(STAMP_LINUX_PATCH)"; \
	fi

clean_uboot:
	$(MAKE) -C $(DIR_UBOOT) mrproper
	# git commands may fail, when building from a source tarball
	if GIT_DIR="$(DIR_UBOOT)/.git" git rev-parse > /dev/null 2>&1; then \
		git -C "$(DIR_UBOOT)" reset --hard; \
		git -C "$(DIR_UBOOT)" clean -f -d; \
		rm -f "$(STAMP_UBOOT_BUILT)"; \
		rm -f "$(STAMP_UBOOT_PATCH)"; \
	fi
