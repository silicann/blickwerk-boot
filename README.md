# Blickwerk Boot

This repository contains the source patches for u-boot and the linux kernel that are required
to boot a blickwerk sensor. 

All sources are released under the terms of the GPLv3+ unless stated otherwise in the source files
or patches.


## Hardware

Blickwerk sensors use an *i.MX 28* processor from Freescale Semiconductor (now part of NXP). All
sensors are shipped with support for unencrypted bootstreams so that you can build your own
u-boot and kernel image and run your software on them.


## Build Instructions

`make prep-source` will download the u-boot and kernel sources and will apply all patches.

`make build` will compile u-boot and the kernel sources using an arm cross-compiler.

`make dist-deb` will create a deb package that can be installed in a Debian distribution.


## Build Variants

The make targets support different variants that control the boot behaviour. There are currently 
three distinct variants that can be set via the `VARIANT` environment variable. These are:

1. `production`
    * disables any u-boot boot delay 
    * u-boot shell is deactivated
    * u-boot and kernel log are redirected to internal UART
    
2. `development`
    * u-boot delay is set to 3 seconds
    * u-boot shell is started by typing 'foo'
    * u-boot and kernel log are redirected to the external UART
    
3. `init`
    * u-boot delay is set to 3 seconds
    * u-boot shell is started by typing 'init'
    * u-boot mounts the ext2 filesystem on the second partition 
      of the SD card and tries to execute the `fuses.img` file
    * u-boot and kernel log are redirected to the external UART
    
Note: The build system will build all three variants when building deb packages.


## Building .deb Packages

It is highly recommended, that you’ll build this kernel in a Debian environment.
There’s a high chance, that you will encounter difficulties on other platforms, that
are not covered by this guide. 

In order to build a kernel you’ll need a few build dependencies. These are listed in the
`debian/control` file in the line starting with `Build-Depends`. The names listed there
are Debian packages that you can install with `apt`. You can’t do anything wrong: 
the debian build tools will abort relatively early into the build process in the event 
that you forgot something. 

After you have installed the build dependencies you can continue with building the actual
kernel and the .deb packages. The `dist-deb` make target from above will build the three
kernel variants and the `mxsboot` tool, that is required in order to create bootstreams
for SD cards. Continue by running:
 
 ```make dist-deb DEBIAN_BUILDPACKAGE_COMMAND="dpkg-buildpackage -us -uc"```
  
Once this task is finished (which might take a while), you’ll find a number of .deb files
in the `build/debian` directory.

**Note**: The DEBIAN_BUILDPACKAGE_COMMAND override is necessary, to prevent the debian build
tools from signing the .deb files. This is the default behaviour, but will fail because the
email address used for signing is the one from the last `debian/changelog` entry. 


## Creating a booting system image

The build targets only compile the kernel image, the u-boot image, and the kernel modules. But
before you can create a system image you’ll need a kernel .deb package. If you haven’t already, 
refer to the previous section on how to build .deb packages.

In order to make the sensor boot an actual linux operating system there are a few prerequisites:

1. Make sure you have these tools in your PATH:
   * `cdebootstrap-static`, part of the `cdebootstrap-static` Debian package
   * `mkfs.ext4`, part of the `e2fsprogs` Debian package
   * `guestfish`, part of the `libguestfs-tools` Debian package
   * [`mkimage`](http://www.denx.de/wiki/U-Boot/), part of `u-boot-tools` Debian package
   * [`elftosb`](https://github.com/eewiki/elftosb)
   * [`mxsboot`](http://www.denx.de/wiki/U-Boot/), a deb package named imx28-mxsboot 
     is part of this repository
2. Run `scripts/image.sh create /path/to/a/linux-image-wurzelwerk-imx28-$variant.deb` 
   as root or via sudo 
3. That’s it! There’s an `.img` file next to the `.deb` that you can now write to an SD card.


## Todos

* deb packages are set to Architecture=all which indicates that they are 
  architecture independent (they are not). This is an easy but dirty 
  work-around to support cross-compilation on other platforms. 

## Legal

Linux® is the registered trademark of Linus Torvalds in the U.S. and other countries.
