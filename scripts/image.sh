#!/bin/sh

set -eu

ELFTOUSB_CONFIG="$(cat <<-EOF
options {
	flags = 0x01;
}

sources {
	u_boot_spl = "ivt/u-boot-spl.bin";
	u_boot_spl_ivt = "ivt/u-boot-spl.ivt";

	u_boot = "ivt/u-boot.bin";
	u_boot_ivt = "ivt/u-boot.ivt";

	zimage = "zImage";
	fdt = "urwerk.dtb";
	initrd = "ramdisk";
}

section (0) {
	load u_boot_spl > 0x1000;
	load u_boot_spl_ivt > 0x8000;
	hab call 0x8000;

	load u_boot > 0x40002000;
	load u_boot_ivt > 0x40001000;
	load zimage > 0x42000000;
	load fdt > 0x41000000;
	load initrd > 0x41500000;
	hab call 0x40001000;
}
EOF
)"

MOUNT_ROOT_SCRIPT="$(cat <<-EOF
#!/bin/sh
[ -e /dev/root ] || ln -s /dev/mmcblk0p2 /dev/root
EOF
)"

NETWORK_CONFIG="$(cat <<-EOF
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp
iface eth0 inet6 auto
EOF
)"

check_root() {
    # Are we running as root?
    if [ "$(id -u)" -ne "0" ]; then
      echo "error: this script must be executed with root privileges!" 1>&2
      exit 1
    fi
}

chroot_exec() {
    local returncode
    # procfs is helpful during the "update-initramfs" execution (preventing harmless warnings)
    mount -t proc procfs "$CHROOT_DIR/proc"
    if LANG=C LC_ALL=C DEBIAN_FRONTEND=noninteractive \
            PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
            chroot "${CHROOT_DIR}" "$@"; then
        returncode=0
    else
        returncode=$?
    fi
    umount "$CHROOT_DIR/proc"
    return "$returncode"
}

size() {
    echo $(( $(stat -c "%s" "$1") + 64 + 3904 + 128 ))
}

create_ivt() {
    local boot_dir="$1"
    mkdir -p "$boot_dir/ivt"

    dd if="$boot_dir/u-boot.bin" of="$boot_dir/ivt/u-boot.bin" ibs=64 conv=sync 2>/dev/null

    local bin_size
    bin_size="$(size "$boot_dir/ivt/u-boot.bin")"
    echo -n "0x402000d1 0x40002000 0 0 0  0x40001000 0x40001040 0 $bin_size 0 0 0 0 0 0 0" | \
        tr -s " " | xargs -d " " -i printf "%08x\\n" "{}" | rev | \
        sed "s/\\(.\\)\\(.\\)/\\\\\\\\x\\2\\1\\n/g" | xargs -i printf "{}" >"$boot_dir/ivt/u-boot.ivt"
}

create_ivt_spl() {
    local boot_dir="$1"
    mkdir -p "$boot_dir/ivt"

    dd if="$boot_dir/u-boot-spl.bin" of="$boot_dir/ivt/u-boot-spl.bin" ibs=64 conv=sync 2>/dev/null

    local bin_size
    bin_size="$(size "$boot_dir/ivt/u-boot-spl.bin")"
    echo -n "0x402000d1 0x00001000 0 0 0  0x00008000 0x00008040 0 $bin_size 0 0 0 0 0 0 0" | \
        tr -s " " | xargs -d " " -i printf "%08x\\n" "{}" | rev | \
        sed "s/\\(.\\)\\(.\\)/\\\\\\\\x\\2\\1\\n/g" | xargs -i printf "{}" >"$boot_dir/ivt/u-boot-spl.ivt"
}

create_base_images() {
    local boot_deb="$1"
    local chroot_dir
    local chroot_dir_temp
    chroot_dir_temp="$(mktemp -du -p "$HOME/.cache")"
    chroot_dir="${CHROOT_DIR:-$chroot_dir_temp}"
    local boot_dir="${chroot_dir:?}/boot"
    local image_name
    image_name="$(dirname "$boot_deb")/$(basename "$boot_deb" .deb)"
    local boot_image_name_usb="$image_name-boot-usb.img"
    local boot_image_name_sd="$image_name-boot-sd.img"
    local root_image_name="$image_name-root.img"
    local bd_config_file="$boot_dir/bd/bootstream.bd"
    export CHROOT_DIR="$chroot_dir"
    echo "using chroot: $chroot_dir"

    # create a chroot and copy the selected linux-image to it
    if [ ! -d "$chroot_dir" ]; then
        mkdir -p "$(dirname "$chroot_dir")"
        cdebootstrap-static stretch "$chroot_dir" "${APT_MIRROR:-http://http.debian.net/debian}"
    fi
    cp "$boot_deb" "$chroot_dir/linux.deb"

    # remove any existing kernels and boot files
    chroot_exec apt purge -qq -y "linux-image-wurzelwerk-imx28-*" || true
    rm -rf "${boot_dir:?}"

    # install basic system dependencies
    chroot_exec apt update -qq -y
    chroot_exec apt install -qq -y sysvinit-core initramfs-tools locales openssh-server


    # configure base system
    echo "en_US.UTF-8 UTF-8" >"$chroot_dir/etc/locale.gen"
    echo "$NETWORK_CONFIG" >"$chroot_dir/etc/network/interfaces.d/eth0"
    echo "/dev/mmcblk0p2 / ext3 rw,noatime,discard,data=ordered 0 0" >"$chroot_dir/etc/fstab"
    chroot_exec locale-gen
    chroot_exec update-locale LANG=en_US.UTF-8
    grep -q "^PermitRootLogin yes" "$chroot_dir/etc/ssh/sshd_config" || \
        echo "PermitRootLogin yes" >>"$chroot_dir/etc/ssh/sshd_config"
    chroot_exec sh -c "echo root:root | chpasswd"
    INIT_DIR="$chroot_dir/usr/share/initramfs-tools/scripts/local-top" && \
        mkdir -p "$INIT_DIR" && \
        echo "$MOUNT_ROOT_SCRIPT" >"$INIT_DIR/system_select" && \
        chmod +x "$INIT_DIR/system_select"

    # install the linux kernel
    chroot_exec dpkg -i /linux.deb
    # create an initramfs
    chroot_exec update-initramfs -c -k "$(cat "$boot_dir/zImage.version")"
    # create a u-boot ramdisk
    mkimage -A arm -T ramdisk -C lzma -n wurzelwerk-ramdisk \
        -d "$boot_dir/initrd.img-$(cat "$boot_dir/zImage.version")" \
        "$boot_dir/ramdisk"
    # generate u-boot metadata
    create_ivt "$boot_dir"
    create_ivt_spl "$boot_dir"

    # create unencrypted usb bootstream
    mkdir -p "$(dirname "$bd_config_file")"
    echo "$ELFTOUSB_CONFIG" >"$bd_config_file"
    rm -f "$boot_image_name_usb" "$boot_image_name_sd" "$chroot_dir/linux.deb"
    elftosb --debug --verbose --chip-family imx28 \
        --search-path="$boot_dir" \
        --command "$bd_config_file" \
        --output "$boot_image_name_usb"
    # created unencrypted sd bootstream
    mxsboot sd "$boot_image_name_usb" "$boot_image_name_sd"
    # create base system image
    rm -rf "${boot_dir:?}" "${chroot_dir:?}/var/cache"
    dd if=/dev/zero bs=50M count=10 of="$root_image_name"
    mkfs.ext4 -q -d "$chroot_dir" "$root_image_name"

    # create sd card image
    guestfish <<-EOF
sparse "$image_name.img" 900M
add-ro "$boot_image_name_sd"
add-ro "$root_image_name"
run

part-init /dev/sda mbr
part-add /dev/sda primary 2048 43007
part-add /dev/sda primary 43008 1793007
part-set-mbr-id /dev/sda 1 0x53
part-set-mbr-id /dev/sda 2 0x83

copy-device-to-device /dev/sdb /dev/sda1
copy-device-to-device /dev/sdc /dev/sda2
EOF
    # cleanup intermediate images
    rm "$boot_image_name_usb" "$boot_image_name_sd" "$root_image_name"

    # delete temporary chroot
    if [ "$chroot_dir" = "$chroot_dir_temp" ]; then
        rm -rf "$chroot_dir"
    fi

    # set ownership to sudo user if sudo was used
    if [ -n "${SUDO_USER:-}" ]; then
        chown "$SUDO_USER:" "$image_name.img"
    fi
}

if [ "$#" -eq 2 ] && [ "$1" = "create" ]; then
    check_root
    linux_image_deb="$2"
    if [ ! -f "$linux_image_deb" ]; then
        echo "missing file: $linux_image_deb" >&2
        exit 1
    fi
    create_base_images "$linux_image_deb"
fi
