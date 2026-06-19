#!/bin/bash

set -e

# $1 is disk
# $2 is kernel
DISK_FILE=$1
VMLINUX=$2
LOOP=$(losetup -f)
echo "$LOOP" "$DISK_FILE"
losetup -P "$LOOP" "$DISK_FILE"
BOOT_PART="$LOOP"p1
TMP_MNT=$(mktemp -d)
mount "$BOOT_PART" "$TMP_MNT"
cp "$VMLINUX" "$TMP_MNT"/vmlinux
umount "$TMP_MNT"
losetup -D "$LOOP"
