DIR_UBOOT = $(DIR_BUILD_VARIANT)/u-boot
DIR_UBOOT_CONFIG = $(DIR_CONFIG)/u-boot
DIR_BUILD_UBOOT = $(DIR_BUILD_VARIANT)/u-boot-build

STAMP_UBOOT_PATCH = $(DIR_BUILD_UBOOT)/.uboot-patched.stamp
STAMP_UBOOT_BUILT = $(DIR_BUILD_UBOOT)/.uboot-built.stamp

UBOOT_BUILD_FLAGS = $(GENERIC_BUILD_FLAGS) -C "$(DIR_UBOOT)" KBUILD_OUTPUT="$(DIR_BUILD_UBOOT)"

UBOOT_TARBALL = $(DIR_BUILD)/uboot-$(UBOOT_VERSION).tar.bz2
UBOOT_TARBALL_URL = ftp://ftp.denx.de/pub/u-boot/u-boot-$(UBOOT_VERSION).tar.bz2
UBOOT_TARBALL_HASH = e49337262ecac44dbdeac140f2c6ebd1eba345e0162b0464172e7f05583ed7bb

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


.PHONY: build_uboot
build_uboot: $(STAMP_UBOOT_BUILT)


.PHONY: patch_uboot
patch_uboot: $(STAMP_UBOOT_PATCH)


$(UBOOT_TARBALL):
	mkdir -p "$(dir $@)"
	wget -O "$(UBOOT_TARBALL)" "$(UBOOT_TARBALL_URL)"
	[ "$$(sha256sum "$(UBOOT_TARBALL)" | cut -d" " -f1)" = "$(UBOOT_TARBALL_HASH)" ]


$(DIR_UBOOT): $(UBOOT_TARBALL)
	mkdir -p "$(DIR_UBOOT)"
	tar xjf "$(UBOOT_TARBALL)" -C "$(DIR_UBOOT)" --strip 1


$(STAMP_UBOOT_PATCH): $(DIR_UBOOT)
	mkdir -p "$(dir $@)"
	find "$(DIR_UBOOT_CONFIG)/patches" -type f -name "*.patch" | sort | while read -r patch; do \
		patch -d "$(DIR_UBOOT)" -p1 <"$$patch"; \
	done
	touch "$@"


$(STAMP_UBOOT_BUILT): $(STAMP_UBOOT_PATCH)
	mkdir -p "$(dir $@)"
	$(MAKE) $(UBOOT_BUILD_FLAGS) "$(UBOOT_BUILD_TARGET)"
	$(MAKE) $(UBOOT_BUILD_FLAGS) u-boot.sb
	touch "$@"
