= Beschreibung der Entwicklungsumgebung =
Das Makefile das dieses Repository enthaelt erzeugt bei einem `make` ein uboot und einen linux-Kernel sowie Kernel Module fuer den imx28 Prozessor diese Datein werden nach `INSTALL_ROOT` installiert und dort fuer die weitere Benutzung durch das repo 'imx28-utils' bereitgehalten.

Dieses README soll helfen den Bau des Kernels und des Uboots reibungslos zu ermoeglichen.

== Ersteinrichtung ==
* `git clone ssh://git@devel.neusy/imx28-linux`
* `cd imx28-linux`
* `git submodule init`
* `git submodule update`


== Build-Varianten ==

Folgende Varianten des erzeugten U-Boot & Kernel duos existieren:
	1. `init` -- Initialisierungs U-Boot + kernel-development devicetree
		* duart ist extern
		* U-Boot hat 3 sekunden bootdelay und kann mit der Eingabe `init` unterbrochen werden
		* liest von 2ter Partion der SD-Karte die datei `fuses.img` aus der Dateisystemwurzel und fuehrt sie im Nachgang aus
		* ausgewaehlt mit `make VARIANT=init`
	2. `development` -- Development U-Boot + Kernel-development devicetree
		* duart ist extern
		* U-Boot hat 3 sekunden bootdelay und kann mit der Eingabe `foo` unterbrochen werden
		* ausgewaehlt mit `make VARIANT=development`
	3. `production` -- production U-Boot + production devicetree
		* duart ist intern (testpads)
		* keinerlei U-Boot Ausgabe oder delay
		* ausgewaehlt mit `make VARIANT=production`

*Wichtig*: Damit dieses bootschema richtig funktioniert sind wir darauf angewiesen einen weitern fuse register zu setzen. Den DUART_ALTERNATIVE fuse (Bank 3, Wort 0, register 0-1). Dies erreichen wir mit dem Befehl `fuse prog 3 0 1`.

== Compiler installieren ==
=== Debian ===
* Datei /etc/apt/sources.list.d/crosstools.list mit Inhalt  "deb http://emdebian.org/tools/debian/ jessie main" erstellen
* `curl http://emdebian.org/tools/debian/emdebian-toolchain-archive.key | sudo apt-key add -`
* `dpkg --add-architecture armhf`
* `apt update`
* `apt install crossbuild-essential-armel`

== U-Boot ==
* `make build_uboot`

=== Informationen ===
* der Boot-Loader liest den zu bootenden Kernel aus einem Speichermedium und übergibt die Kontrolle an den Kernel
* allgemeine Quelle des Wissens: http://www.denx-cs.de/doku/?q=m28evkrunuboot

== Kernel ==
* `make build_linux`

=== Kernel aktualisieren ===
* um den Linux Kernel auf ein neues Patchlevel zu heben muss im Makefile die Variable `LINUX_PATCH_LEVEL` geandert werden und der entsprechende Patch heruntergeladen werden https://kernel.org/
	* dieses neue patch archiv muss unter `configurations/linux/patches` liegen
* um den Linux Kernel Release zu aendern muss im Makefile zusaetzlich die Variable `LINUX_VERSION` geandert werden. Und das Submodul an sich auf die entsprechende Version aktualsiert werden
* nach beiden aktionen muss ein make ausgefuehrt werden

== rootfs ==
* Debian: apt-get install binfmt-support qemu qemu-user-static debootstrap
* Arch: binfmt-support qemu-user-static und debootrap ueber das ArchlinuxUserRepository installieren

==== Erzeugen des Dateisystems ====
* zum _Neubauen_ des Root-Filesystems sind folgende Schritte notwendig:
 * `mkdir /tmp/rootfs; mkdir rootfs`
 * `mount -o bind /tmp/rootfs rootfs`
 * `debootstrap --include=sysvinit-core,openssh-server,python-apt --arch=armel --foreign jessie rootfs http://apt-proxy:9999/debian`
 * aufgrund der Cross-Plattform-Situation ist ein nachgelagerter Schritt innerhalb der chroot-Umgebung nötig:
  * `cp /usr/bin/qemu-arm-static rootfs/usr/bin/`
  * `chroot rootfs /bin/bash`
  * innerhalb der chroot-Umgebung:
   * `/debootstrap/debootstrap --second-stage`
   * `export PATH=$PATH:/bin/:/usr/local/sbin:/usr/sbin:/sbin`
   * Hostname setzen: `echo "pcs-x" > /etc/hostname`
   * `apt update`
   * `apt install debconf openssh-server openssh-client locales`
   * Locale erzeugen:
    * `echo "de_DE.UTF-8 UTF-8" > /etc/locale.gen`
    * `echo " en_GB.UTF-8 UTF-8" >> /etc/locale.gen`
    * `locale-gen`
   * root passwort setzen: `passwd`
   * `exit` verlassen der chroot
   * entfernen des qemu-arm-static binaries `rm rootfs/usr/bin/qemu-arm-static`
   * entfernen der bash_history `rm rootfs/root/.bash_history`
 * `cd rootfs/ ; tar -zcvf ../rootfs.tar * `
 * Installieren der Kernel-Module in das rootfs
  * `cd linux; make INSTALL_MOD_PATH=../rootfs modules_install`
 * unmounten des rootfs ordners `umount rootfs`
 * entfernen des rootfs ordners `rm -rf rootfs`

== Installationmauf SD-Karte ==
* um das system zu booten muessen alle bestandteile auf eine SD-Karte gebracht werden
=== Formatierung ===
* SD-Karte anschliessen
 * `export DISK=/dev/mmcblk0` (oder anderer Device-Deskriptor)
 * `sfdisk $DISK < configurations/sd_disk.dump`
  * sfdisk ab v2.26 ist erforderlich (v2.25 versteht das dump-Format nicht)
 * Ergebnis betrachten: `lsblk`
 * Bootpartition auf zweiter Partion legen:
  * `mkfs.vfat $DISK(PARTITION2)`
 * TODO: cryptsetup auf dritter Partition anwenden - erst darin das PV fuer das LVM erzeugen
 * LVM konfigurieren:
  * `pvcreate $DISK(PARTITION2)`
  * `vgcreate lvm-laplace $DISK(PARTITION2)`
  * `lvcreate -n root -L 1G lvm-laplace`
  * `mkfs.ext4 -O ^has_journal /dev/lvm-laplace/root`

=== U-Boot uebertragen ===
* TODO: update an dieser stelle wird nun ein ca 10MB grosser bootstream uebertragen der uboot,kernel,devicetree und initramfs enthaelt
* das zuvor kompilierte u-boot kommt auf die erste partition der sd-karte
 * `dd if=./u-boot/u-boot.sd of=$DISK(PARTITION1) bs=1M`

=== Filesystem uebertragen ===
* das vorhandene oder neu erzeugte rootfs muss auf die dritte partition des geraetes entpackt werden
 * `mkdir  root/`
 * `mount $DISK(PARTITION3) root/`
 * `tar xfvp rootfs.tar -C root; sync`

=== Kernel installieren ===
* der zuvor kompilierte linux-kernel sowie der devicetree blob muessen auf das geraet kopiert werden
 * `mount $DISK(PARTITION2) root/boot`
 * `cp ./linux/arch/arm/boot/zImage root/boot/.`
 * `cp ./linux/arch/arm/boot/dts/imx28-evk.dtb root/boot/.`
 * `sync`
* abschliessendes unmounten
 * `umount -R root`
 * `rm -rf root` entfernen des ordners

=== Anpassungen im Dateisystem ===
 * `echo -e "auto eth0\niface eth0 inet dhcp" >root/etc/network/interfaces.d/eth0`
 * `echo "1.0" >root/etc/laplace_version`
 * `echo "blickwerk" >root/etc/hostname`


=== initramfs fuer U-boot aufbereiten ===
* damit uboot mit dem initramfs umgehen kann muss  ein extra header darum geschrieben werden:
* `make initrd_header` dabei wird auf `INSTALL_ROOT/boot/initrd.$(LINUX_VERSION).$(LINUX_PATCHLEVEL).img` zugegriffen
* die veraenderte Ramdisk wird als `INSTALL_ROOT/boot/urwerk_ramdisk` abgelegt

== Quellen ==
* http://www.denx-cs.de/doku/?q=documentation
* https://eewiki.net/display/linuxonarm/i.MX53+Quick+Start#i.MX53QuickStart-DeviceTreeBinary
* http://free-electrons.com/doc/porting-u-boot.odp 
* http://www.slideshare.net/derkling/linux-porting-to-a-custom-board
* http://blackfin.uclinux.org/doku.php?id=linux-kernel:customizing_for_your_board
* http://processors.wiki.ti.com/index.php/Linux_Kernel_Users_Guide#Compiling_the_Kernel_Modules
* http://www.denx.de/wiki/pub/U-Boot/MiniSummitELCE2013/2013-u-boot-mxs-without-fsl-tools.pdf
