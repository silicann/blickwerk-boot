DIR_LINUX = $(DIR_BUILD_VARIANT)/linux
DIR_LINUX_CONFIG = $(DIR_CONFIG)/linux
DIR_BUILD_LINUX = $(DIR_BUILD_VARIANT)/linux-build

STAMP_LINUX_PATCH = $(DIR_BUILD_LINUX)/.linux-patched.stamp
STAMP_LINUX_BUILT = $(DIR_BUILD_LINUX)/.linux-built.stamp

LINUX_BUILD_FLAGS = $(GENERIC_BUILD_FLAGS) -C "$(DIR_LINUX)" KBUILD_OUTPUT="$(DIR_BUILD_LINUX)"

LINUX_TARBALL = $(DIR_BUILD)/linux-$(LINUX_VERSION).tar.gz
LINUX_TARBALL_URL = https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-$(LINUX_VERSION).tar.gz
LINUX_TARBALL_HASH = 654511b88e041e2b8090a2f366da8b9011446561d01abf199a81722704f93e47


.PHONY: patch_linux
patch_linux: $(STAMP_LINUX_PATCH)


.PHONY: build_linux
build_linux: $(STAMP_LINUX_BUILT)


.PHONY: menuconfig_linux
menuconfig_linux:
	$(MAKE) $(LINUX_BUILD_FLAGS) urwerk_defconfig
	$(MAKE) $(LINUX_BUILD_FLAGS) menuconfig


$(LINUX_TARBALL):
	mkdir -p "$(dir $@)"
	wget -O "$(LINUX_TARBALL)" "$(LINUX_TARBALL_URL)"
	[ "$$(sha256sum "$(LINUX_TARBALL)" | cut -d" " -f1)" = "$(LINUX_TARBALL_HASH)" ]


$(STAMP_LINUX_PATCH): $(LINUX_TARBALL)
	mkdir -p "$(dir $@)"
	mkdir -p "$(DIR_LINUX)"
	tar xzf "$(LINUX_TARBALL)" -C "$(DIR_LINUX)" --strip 1
	find "$(DIR_LINUX_CONFIG)/patches" -type f -name "*.patch" | sort | while read -r patch; do \
		patch -d "$(DIR_LINUX)" -p1 <"$$patch"; \
	done
	touch "$@"


$(STAMP_LINUX_BUILT): $(STAMP_LINUX_PATCH)
	mkdir -p "$(dir $@)"
	$(MAKE) $(LINUX_BUILD_FLAGS) urwerk_defconfig

	# for debugging of kernel boot problems run this defconfig
	#$(MAKE) $(LINUX_BUILD_FLAGS) urwerk_earlyprintk_defconfig

	$(MAKE) $(LINUX_BUILD_FLAGS) KBUILD_CFLAGS_MODULE="$(MODULE_FLAGS)"
	touch "$@"
