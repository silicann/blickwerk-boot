include makefilet-download-ondemand.mk

DEBIAN_UPLOAD_TARGET = silicann

# definitions
PWD = $(shell pwd)
COMPILER_PATH = /usr/bin/arm-linux-gnueabi-
VARIANT ?= production
NPROCS=$(shell nproc --all)
NMAKEJOBS=$(shell expr $(NPROCS) \+ 1)
MODULE_FLAGS = -DMODULE -fno-pic

# dirs
DIR_CONFIG = $(PWD)/configurations
DIR_UBOOT = $(PWD)/u-boot
DIR_UBOOT_CONFIG = $(DIR_CONFIG)/u-boot
DIR_LINUX = $(PWD)/linux
DIR_LINUX_CONFIG = $(DIR_CONFIG)/linux
DIR_BUILD = $(PWD)/build/$(VARIANT)
DIR_BUILD_LINUX = $(DIR_BUILD)/linux
DIR_BUILD_UBOOT = $(DIR_BUILD)/u-boot

GENERIC_BUILD_FLAGS = -j$(NMAKEJOBS) ARCH=arm CROSS_COMPILE="$(COMPILER_PATH)"
LINUX_BUILD_FLAGS = $(GENERIC_BUILD_FLAGS) -C "$(DIR_LINUX)" KBUILD_OUTPUT="$(DIR_BUILD_LINUX)"
UBOOT_BUILD_FLAGS = $(GENERIC_BUILD_FLAGS) -C "$(DIR_UBOOT)" KBUILD_OUTPUT="$(DIR_BUILD_UBOOT)"

# stamps
STAMP_UBOOT_PATCH = $(DIR_UBOOT)/.uboot-patched.stamp
STAMP_UBOOT_BUILT = $(DIR_BUILD_UBOOT)/.uboot-built.stamp
STAMP_LINUX_PATCH = $(DIR_LINUX)/.linux-patched.stamp
STAMP_LINUX_BUILT = $(DIR_BUILD_LINUX)/.linux-built.stamp

# target system
LINUX_VERSION = 4.4
LINUX_PATCH_LEVEL = 113
LINUX_NAME = "$(LINUX_VERSION).$(LINUX_PATCH_LEVEL)"

DEBIAN_PACKAGE_SUBMODULE_DIRECTORIES = linux u-boot


ifeq ($(VARIANT),development)
	UBOOT_BUILD_TARGET = urwerk_development_defconfig
	UBOOT_DTB = $(DIR_BUILD_LINUX)/arch/arm/boot/dts/urwerk-develop.dtb
else ifeq ($(VARIANT),init)
	UBOOT_BUILD_TARGET = urwerk_init_defconfig
	UBOOT_DTB = $(DIR_BUILD_LINUX)/arch/arm/boot/dts/urwerk-develop.dtb
else ifeq ($(VARIANT),production)
	UBOOT_BUILD_TARGET = urwerk_production_defconfig
	UBOOT_DTB = $(DIR_BUILD_LINUX)/arch/arm/boot/dts/urwerk-production.dtb
else
	$(error Invalid 'VARIANT': pick one of production / development / init)
endif


default-target: build


prep-source:: $(STAMP_UBOOT_PATCH) $(STAMP_LINUX_PATCH)


build: build_uboot build_linux


.PHONY: patch_uboot
patch_uboot: $(STAMP_UBOOT_PATCH)


$(STAMP_UBOOT_PATCH):
	mkdir -p "$(dir $@)"
	git -C "$(DIR_UBOOT)" am "$(DIR_UBOOT_CONFIG)/patches/"*.patch
	touch "$@"


.PHONY: build_uboot
build_uboot: $(STAMP_UBOOT_BUILT)


$(STAMP_UBOOT_BUILT): $(STAMP_UBOOT_PATCH)
	mkdir -p "$(dir $@)"
	$(MAKE) $(UBOOT_BUILD_FLAGS) "$(UBOOT_BUILD_TARGET)"
	$(MAKE) $(UBOOT_BUILD_FLAGS) u-boot.sb
	touch "$@"


.PHONY: patch_linux
patch_linux: $(STAMP_LINUX_PATCH)


$(STAMP_LINUX_PATCH):
	mkdir -p "$(dir $@)"
	xz -cd "$(DIR_LINUX_CONFIG)/patch-$(LINUX_VERSION).$(LINUX_PATCH_LEVEL).xz" \
		| patch -d "$(DIR_LINUX)" -p1
	# workaround for a clean repository, maybe we can do better?
	git -C "$(DIR_LINUX)" add -A  && git -C "$(DIR_LINUX)" commit -m " Linux $(LINUX_NAME)"
	git -C "$(DIR_LINUX)" am "$(DIR_LINUX_CONFIG)/patches/"*.patch
	touch "$@"


.PHONY: menuconfig_linux
menuconfig_linux:
	$(MAKE) $(LINUX_BUILD_FLAGS) urwerk_defconfig
	$(MAKE) $(LINUX_BUILD_FLAGS) menuconfig


.PHONY: build_linux
build_linux: $(STAMP_LINUX_BUILT)


$(STAMP_LINUX_BUILT): $(STAMP_LINUX_PATCH)
	mkdir -p "$(dir $@)"
	$(MAKE) $(LINUX_BUILD_FLAGS) urwerk_defconfig
	# for debugging of kernel boot problems run this defconfig
	#$(MAKE) $(LINUX_BUILD_FLAGS) urwerk_earlyprintk_defconfig
	$(MAKE) $(LINUX_BUILD_FLAGS) KBUILD_CFLAGS_MODULE="$(MODULE_FLAGS)"
	touch "$@"


.PHONY: install
install: build_uboot build_linux
	$(MAKE) $(LINUX_BUILD_FLAGS) modules_install INSTALL_MOD_PATH="$(abspath $(DESTDIR))"
	rm -f "$(DESTDIR)/lib/modules/$(LINUX_NAME)"*/source
	rm -f "$(DESTDIR)/lib/modules/$(LINUX_NAME)"*/build
	mkdir -p "$(DESTDIR)/boot/"
	# copy uboot related files (elf)s
	cp "$(DIR_BUILD_UBOOT)/u-boot-nodtb.bin" "$(DESTDIR)/boot/u-boot.bin"
	cp "$(DIR_BUILD_UBOOT)/spl/u-boot-spl-nodtb.bin" "$(DESTDIR)/boot/u-boot-spl.bin"
	# copy linux related files (devicetree, kernel)
	cp "$(DIR_BUILD_LINUX)/arch/arm/boot/zImage" "$(DESTDIR)/boot/"
	cp "$(UBOOT_DTB)" "$(DESTDIR)/boot/urwerk.dtb"
	echo "$(LINUX_NAME)" >"$(DESTDIR)/boot/zImage.version"


.PHONY: initrd_header
initrd_header:
	"$(DIR_UBOOT)/tools/mkimage" -A arm  -T ramdisk -C gzip -n "urwerk-ramdisk" \
		-d "$(DESTDIR)/boot/initrd.img-$(LINUX_NAME)" "$(DESTDIR)/boot/ramdisk"


.PHONY: clean
clean: clean_uboot clean_linux


.PHONY: clean_linux
clean_linux:
	$(MAKE) $(LINUX_BUILD_FLAGS) mrproper
	# git commands may fail, when building from a source tarball
	if GIT_DIR="$(DIR_LINUX)/.git" git rev-parse > /dev/null 2>&1; then \
		git -C "$(DIR_LINUX)" reset --hard; \
		git -C "$(DIR_LINUX)" clean -f -d; \
		git submodule update "$(DIR_LINUX)"; \
		rm -f "$(STAMP_LINUX_BUILT)"; \
		rm -f "$(STAMP_LINUX_PATCH)"; \
	fi


.PHONY: clean_uboot
clean_uboot:
	$(MAKE) $(UBOOT_BUILD_FLAGS) mrproper
	# git commands may fail, when building from a source tarball
	if GIT_DIR="$(DIR_UBOOT)/.git" git rev-parse > /dev/null 2>&1; then \
		git -C "$(DIR_UBOOT)" reset --hard; \
		git -C "$(DIR_UBOOT)" clean -f -d; \
		git submodule update "$(DIR_UBOOT)"; \
		rm -f "$(STAMP_UBOOT_BUILT)"; \
		rm -f "$(STAMP_UBOOT_PATCH)"; \
	fi
