#!/bin/bash

set -e

# $1 is disk
# $2 is grub
# $3 is kernel
DISK_FILE=$1
GRUB_DIR=$2
VMLINUX=$3
GRUB_CORE_DIR="$GRUB_DIR"/grub-core
LOOP=$(losetup -f)
echo "$LOOP" "$DISK_FILE"
losetup -P "$LOOP" "$DISK_FILE"
BOOT_PART="$LOOP"p1
TMP_MNT=$(mktemp -d)
MOD_DIR="$TMP_MNT"/grub/mipsel-arc/
mount "$BOOT_PART" "$TMP_MNT"
cp "$VMLINUX" "$TMP_MNT"/vmlinux
cp "$GRUB_DIR"/config.h "$MOD_DIR"
cp "$GRUB_CORE_DIR"/gdb_grub "$MOD_DIR"
cp "$GRUB_CORE_DIR"/gdb_helper.py "$MOD_DIR"
cp "$GRUB_CORE_DIR"/kernel.exec "$MOD_DIR"
cp "$GRUB_CORE_DIR"/*.mod "$MOD_DIR"
cp "$GRUB_CORE_DIR"/*.module "$MOD_DIR"
cp "$GRUB_CORE_DIR"/*.lst "$MOD_DIR"
cp "$GRUB_CORE_DIR"/*.img "$MOD_DIR"
cp "$GRUB_CORE_DIR"/*.image "$MOD_DIR"
"$GRUB_DIR"/grub-mkimage -d "$GRUB_CORE_DIR" -O mipsel-arc -p "(arc/scsi0/disk0/rdisk0,msdos1)/grub" \
        -o "$TMP_MNT"/os/nt/osloader.exe disk part_msdos normal fat
umount "$TMP_MNT"
losetup -D "$LOOP"
