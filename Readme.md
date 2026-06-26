# Baremetal MIPS Magnum Linux
## Dockerfile to build a bootable Debian image for QEMU MIPS Magnum platform using GRUB as bootloader
Before this afaik there was no easy way to use QEMU to boot into MIPS-ARC Linux.
Qemu boots into Microsoft's magnum arc firmware, which loads grub and subsequently Debian Linux.


## Steps to build and run:
```bash
mkdir tmpdir && cd tmpdir
podman build -v $(pwd):/workspace --target build-grub .
podman build -v $(pwd):/workspace --target grubexe .
podman build -v $(pwd):/workspace --target build-kernel .
podman build -v $(pwd):/workspace --device /dev/fuse --cap-add SYS_ADMIN --target rootfs .
podman build -v $(pwd):/workspace --target final .
qemu-system-mips64el -M magnum -cpu MIPS64R2-generic -m 128 -net nic -net user -global ds1225y.filename=nvram -bios NTPROM.RAW -hda disk.img
```
rootfs may take a while, you can use your host debootstrap to speed it up.

## Notes:

Debugging QEMU with GDB does NOT WORK! QEMU's memorydump also doesnt work.
For some reason the mips arc firmware does not respond with a valid `iname`, casuing linux to halt as it does not know the system.
Linux oddly faults when calling `prom_free_prom_memory`, seems like another firmware issue.
Debian uses `MIPS64R2` as the default base architecture for MIPS a patch was added to allow the kernel to boot on `MIPS64R2`.
This allows us to pass `MIPS64R2-generic` to QEMU and run userspace binaries.

