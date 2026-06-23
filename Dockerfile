# Dockerfile to build a bootable Debian image for MIPS Magnum platform using GRUB as bootloader
# Steps to build and run:
# mkdir tmpdir && cd tmpdir
# podman build -v $(pwd):/workspace --target build-grub .
# podman build -v $(pwd):/workspace --target grubexe .
# podman build -v $(pwd):/workspace --target build-kernel .
# podman build -v $(pwd):/workspace --device /dev/fuse --cap-add SYS_ADMIN --target rootfs .
# podman build -v $(pwd):/workspace --target final .
# qemu-system-mips64el -M magnum -m 128 -net nic -net user -global ds1225y.filename=nvram -bios NTPROM.RAW -hda disk.img

# rootfs may take a while, you can use your host debootstrap to speed it up.
# GRUB actually faults after loading the kernel/initrd, this also happens on when using
# mips-arc on a SGI Indy

FROM debian:latest as build-grub
RUN apt-get update && \
	apt-get install -y git automake libtool wget pkg-config make gettext autopoint libx11-dev libpci-dev libpng-dev libfreetype-dev gcc-mipsel-linux-gnu python3 flex bison gawk fonts-dejavu xfonts-unifont help2man libfuse3-dev libtasn1-dev libdevmapper-dev liblzma-dev && \
	rm -rf /var/lib/apt/lists/* && \
	apt-get clean
ADD https://git.savannah.gnu.org/git/grub.git /grub
WORKDIR /grub
VOLUME /workspace
RUN mkdir -p /workspace/grub && \
	./bootstrap && \
	./configure --target=mipsel-linux-gnu --with-platform=arc --prefix=/workspace/grub 'TARGET_CFLAGS=-Wa,-march=r4000 -mips3' 'TARGET_CCASFLAGS=-Wa,-march=r4000 -mips3'
RUN make
RUN make install

FROM debian:latest as build-kernel
RUN <<EOF cat > /etc/apt/sources.list.d/bookworm.sources
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: bookworm
Architectures: mipsel
Components: main
EOF
RUN cat /etc/apt/sources.list.d/bookworm.sources
RUN apt update && \
	apt install -y dpkg-dev debhelper quilt python3 flex bison gcc-mipsel-linux-gnu libssl-dev bc && \
	apt source -t bookworm linux && \
	rm -rf /var/lib/apt/lists/* && \
	apt-get clean
RUN <<EOF cat | patch -p1 -d linux-*
diff --git a/arch/mips/fw/arc/identify.c b/arch/mips/fw/arc/identify.c
index 5527e0f54079..93557929260c 100644
--- a/arch/mips/fw/arc/identify.c
+++ b/arch/mips/fw/arc/identify.c
@@ -98,11 +98,13 @@ void __init prom_identify_arch(void)
 	 * The root component tells us what machine architecture we have here.
 	 */
 	p = ArcGetChild(PROM_NULL_COMPONENT);
-	if (p == NULL) {
+/*
+	if (p == NULL || p->iname == 0) {
 		iname = "Unknown";
 	} else
 		iname = (char *) (long) p->iname;
-
+*/
+	iname = "Microsoft-Jazz";
 	printk("ARCH: %s\n", iname);
 	mach = string_to_mach(iname);
 	system_type = mach->liname;
diff --git a/arch/mips/mm/init.c b/arch/mips/mm/init.c
index e8660d06f663..c72674c7efe6 100644
--- a/arch/mips/mm/init.c
+++ b/arch/mips/mm/init.c
@@ -496,7 +496,7 @@ void __weak __init prom_free_prom_memory(void)

 void __ref free_initmem(void)
 {
-	prom_free_prom_memory();
+//	prom_free_prom_memory();
 	/*
 	 * Let the platform define a specific function to free the
 	 * init section since EVA may have used any possible mapping
--
EOF

RUN chmod -x linux-*/debian/*.install # https://github.com/sonic-net/sonic-linux-kernel/issues/117#issuecomment-2742269309
RUN cd linux-* && debian/rules source
# in the future this may break, compiling using gcc-14 currently works
RUN sed -i 's/gcc-12/gcc/g' linux-*/debian/rules.gen
RUN sed -i 's/vmlinuz/vmlinux/g' linux-*/debian/rules.gen
RUN sed -i 's/vmlinuz/vmlinux/g' linux-*/debian/config/mipsel/defines
RUN sed -i 's/vmlinuz/vmlinux/g' linux-*/debian/linux-image-*-4kc-malta.*
RUN dpkg-architecture -a mipsel -c "make -C linux-* -f debian/rules.gen setup_mipsel_none"
RUN linux-*/scripts/config -d CONFIG_MIPS_MALTA -e CONFIG_MACH_JAZZ -e CONFIG_MIPS_MAGNUM_4000 --file linux-*/debian/build/build_mipsel_none_4kc-malta/.config
# For some reason ZSTD is not working
RUN linux-*/scripts/config -d CONFIG_RD_ZSTD -e CONFIG_FB_G364 -e CONFIG_JAZZ_ESP --file linux-*/debian/build/build_mipsel_none_4kc-malta/.config
RUN dpkg-architecture -a mipsel -c "make -C linux-*/debian/build/build_mipsel_none_4kc-malta olddefconfig"
RUN dpkg-architecture -a mipsel -c "DEB_RULES_REQUIRES_ROOT=no make -C linux-* -f debian/rules.gen binary-arch_mipsel_none_4kc-malta_real_image -j$(nproc)"
VOLUME /workspace
RUN cp *.deb /workspace/

FROM debian:latest as rootfs
RUN apt-get update && apt-get install -y debootstrap e2fsprogs qemu-user-static guestmount && \
	rm -rf /var/lib/apt/lists/* && \
	apt-get clean
VOLUME /workspace
WORKDIR /workspace
RUN <<EOF cat > mkroot.sh && chmod +x mkroot.sh && ./mkroot.sh
#!/bin/bash
set -euo pipefail
DISKNAME=rootfs.ext4
TOTAL_SZ=2G
MOUNTDIR=\$(mktemp -d)

cleanup() {
	guestunmount "\$MOUNTDIR" || true
	rmdir "\$MOUNTDIR" || true
}
trap cleanup EXIT

truncate -s \$TOTAL_SZ \$DISKNAME
mkfs.ext4 \$DISKNAME
guestmount -a \$DISKNAME -m /dev/sda "\$MOUNTDIR"

debootstrap --foreign --arch=mipsel --variant=minbase --components=main,non-free bookworm "\$MOUNTDIR" http://deb.debian.org/debian/

cp /usr/bin/qemu-mipsel-static "\$MOUNTDIR"/usr/bin
cp /workspace/*.deb "\$MOUNTDIR"/
chroot "\$MOUNTDIR" /bin/bash <<EOT
/debootstrap/debootstrap --second-stage
apt install -y locales
locale-gen en_US.UTF-8
echo -e "password\npassword" | passwd
apt install -y ./*.deb

# Weird bug, where the initramfs is huge
update-initramfs -ck all
EOT
cp "\$MOUNTDIR"/vmlinux . || true
cp "\$MOUNTDIR"/initrd.img . || true
rm "\$MOUNTDIR"/*.deb || true
rm "\$MOUNTDIR"/usr/bin/qemu-mipsel-static || true

EOF

FROM debian:latest as grubexe
RUN apt-get update && apt-get install -y libdevmapper1.02.1 libarchive13 && \
	rm -rf /var/lib/apt/lists/* && \
	apt-get clean
VOLUME /workspace
WORKDIR /workspace
RUN /workspace/grub/bin/grub-mkimage -O mipsel-arc -p "(arc/scsi0/disk0/rdisk0,msdos1)/grub" -o grub.exe disk part_msdos normal fat

FROM debian:latest as final
RUN apt-get update && apt-get install -y wget unzip dosfstools mtools fdisk && \
	rm -rf /var/lib/apt/lists/* && \
	apt-get clean
VOLUME /workspace
WORKDIR /workspace
RUN <<EOF cat > grub.cfg
set pager=1
set timeout=30

set timeout_style=menu
set default=debian

menuentry "Debian GNU/Linux, with Linux" --class debian --class gnu-linux --class gnu --class os -id debian {
	echo	'Loading Linux kernel ...'
        linux   (arc/scsi0/disk0/rdisk0,msdos1)/vmlinux root=/dev/sda2 earlyprintk=ttyS0 console=ttyS0 video=g364fb fbcon=map:0 console=tty0 earlyprintk=tty0
	echo	'Loading initial ramdisk ...'
	initrd	(arc/scsi0/disk0/rdisk0,msdos1)/initrd.img
}
EOF
RUN <<EOF cat > ./mkboot.sh && chmod +x mkboot.sh && ./mkboot.sh
#!/bin/bash
set -euo pipefail

DISKNAME=boot.fat
BOOTDIR=\$(mktemp -d)
ROUND_TO=1M

cp -r /workspace/grub/lib/grub "\$BOOTDIR"
cp vmlinux "\$BOOTDIR"
cp initrd.img "\$BOOTDIR"
cp grub.cfg "\$BOOTDIR"/grub/grub.cfg
mkdir -p "\$BOOTDIR"/os/nt/
cp grub.exe "\$BOOTDIR"/os/nt/osloader.exe

DIR_SZ=\$(du -sb "\$BOOTDIR" | cut -d $'\t' -f1)
BUFFER_SZ=\$((1024 * 1024))
TOTAL_SZ=\$((DIR_SZ + BUFFER_SZ))
truncate -s \$TOTAL_SZ \$DISKNAME
truncate -s %"\$ROUND_TO" \$DISKNAME # Round to nearest N-MB
truncate -s ">16M" \$DISKNAME # Ensure minimum size of 16MB
mkfs.vfat -F 16 \$DISKNAME
mcopy -i \$DISKNAME -s "\$BOOTDIR"/* ::
rm -rf "\$BOOTDIR"
EOF
RUN <<EOF cat > ./mkimage.sh && chmod +x ./mkimage.sh && ./mkimage.sh
#!/bin/bash
set -euo pipefail
DISKNAME=disk.img
ROUND_TO=1M

ROOTFS_SZ=\$(stat -c %s rootfs.ext4)
BOOTFS_SZ=\$(stat -c %s boot.fat)
BOOTBUFFER_SZ=4096
BOOTPART_SZ=\$(( BOOTFS_SZ + BOOTBUFFER_SZ ))
BOOTPART_SZ_K=\$(( (BOOTPART_SZ + 1023) / 1024 ))
BUFFER_SZ=4096
TOTAL_SZ=\$((ROOTFS_SZ + BOOTFS_SZ + BUFFER_SZ))

echo "Total size: \$TOTAL_SZ"
truncate -s \$TOTAL_SZ \$DISKNAME
truncate -s %"\$ROUND_TO" \$DISKNAME
cat <<EOT | fdisk -u \$DISKNAME
o
n
p


+\${BOOTPART_SZ_K}K
t
6
n
p



w
EOT

BOOT_OFFSET=\$(partx -n 1 -go START disk.img)
ROOT_OFFSET=\$(partx -n 2 -go START disk.img)
dd if=boot.fat of=\$DISKNAME seek="\$BOOT_OFFSET" conv=notrunc status=progress
dd if=rootfs.ext4 of=\$DISKNAME seek="\$ROOT_OFFSET" conv=notrunc status=progress
EOF
RUN wget http://web.archive.org/web/20150809205748if_/http://hpoussineau.free.fr/qemu/firmware/magnum-4000/setup.zip && \
	unzip -o setup.zip NTPROM.RAW && \
	rm setup.zip
RUN echo qemu-system-mips64el -M magnum -m 128 -net nic -net user -global ds1225y.filename=nvram -bios NTPROM.RAW -hda disk.img
