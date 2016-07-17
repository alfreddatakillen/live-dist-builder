#!/bin/bash
pushd "$(dirname $0)" >/dev/null 2>&1

HOSTNAME="machine"

function log() {
	echo -e "\n\e[90m--<\e[36m<\e[96m<\e[33m" $@ "\e[96m>\e[36m>\e[90m>--\e[0m"
}

STAGE="$1"
if [ "$STAGE" = "" ]; then
	STAGE="1"
fi

# BUILD DOCKER ENV
if [ "$STAGE" = "1" ]; then

	log "STAGE 1"

	log Build docker container.
	docker build -t machine .

	log Run docker container
	docker run --privileged -v $PWD:/root/build -t machine

	log Docker stopped.
fi

if [ "$STAGE" = "2" ]; then

	log "STAGE 2 (in docker env)"

	log Debootstrapping.
	if [ ! -e chroot ]; then
		debootstrap --arch=amd64 --variant=minbase jessie chroot http://ftp.se.debian.org/debian
	fi

	cp run.sh chroot/root/run.sh

	log Mount dev to chroot/dev
	mount -o bind /dev chroot/dev

	log "Start chroot (stage 3)."
	chroot chroot /root/run.sh 3

	log "Start stage 4"
	./run.sh 4
fi

if [ "$STAGE" = "3" ]; then
	log "STAGE 3 (in chroot env)"

	mount none -t proc /proc
	mount none -t sysfs /sys 
	mount none -t devpts /dev/pts

	log Install kernel.
	apt-get install -y linux-image-amd64

	log Set machine ID.
	if [ ! -e /var/lib/dbus/machine-id ]; then
		if [ -e /etc/machine-id ]; then
			mkdir -p /var/lib/dbus
			cp /etc/machine-id /var/lib/dbus/machine-id
		else 
			apt-get install dialog dbus --yes --force-yes
			mkdir -p /var/lib/dbus
			dbus-uuidgen > /var/lib/dbus/machine-id
		fi
	fi
	if [ ! -e /etc/machine-id ]; then
		cp /var/lib/dbus/machine-id /etc/machine-id
	fi

	log Set hostname.
	if [ "$(cat /etc/hostname)" != "$HOSTNAME" ]; then
		echo "$HOSTNAME" >/etc/hostname
	fi
	echo "127.0.0.1	$(cat /etc/hostname)" >>/etc/hosts

	log Create user and fix permissions.
	useradd -m user -s /bin/bash
	mkdir -p /etc/systemd/system/getty@tty1.service.d
	cat >/etc/systemd/system/getty@tty1.service.d/autologin.conf <<_EOF_
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin user --noclear %I 38400 linux
_EOF_
	apt-get install sudo
	cat >/etc/sudoers.d/999-nopasswd <<_EOF_
user   ALL=(ALL:ALL) NOPASSWD:ALL
_EOF_

	log Install kernel and live boot stuff.
	apt-get install -y \
		linux-image-amd64 \
		live-boot

	# Add cool stuff here...

	log Clean up chroot.
	apt-get clean
	rm -rf /tmp/*
	umount -lf /proc
	umount -lf /sys 
	umount -lf /dev/pts

	log Leaving chroot.
fi

if [ "$STAGE" = "4" ]; then
	log "STAGE 4 (back in docker env)"

	log Unmount chroot/dev
	umount -lf chroot/dev

	rm chroot/root/run.sh

	log Make directories that will be copied to our bootable medium.
	mkdir -p image/{live,isolinux}

	log Compress the chroot environment into a Squash filesystem.
	if [ ! -e image/live/filesystem.squashfs ]; then
		mksquashfs chroot image/live/filesystem.squashfs -e boot
	fi

	log Prepare USB/CD bootloader
	if [ ! -e image/live/vmlinuz ]; then
		cp chroot/boot/vmlinuz-* image/live/vmlinuz
	fi
	if [ ! -e image/live/initrd ]; then
		cp chroot/boot/initrd.img-* image/live/initrd
	fi
	mkdir -p image/isolinux
	cat >image/isolinux/isolinux.cfg <<_EOF_
UI menu.c32

prompt 0
menu title Boot Menu

timeout 40

label Machine
menu label ^Machine
menu default
kernel /live/vmlinuz
append initrd=/live/initrd boot=live

label hdt
menu label ^Hardware Detection Tool (HDT)
kernel /hdt.c32
text help
HDT displays low-level information about the systems hardware.
endtext

label memtest86+
menu label ^Memory Failure Detection (memtest86+)
kernel /memtest
_EOF_
	if [ ! -e usb.img ]; then
		log Create usb image file
		dd if=/dev/zero of=usb.img bs=1M count=300

		log Partition usb image file
		echo -e "o\nn\np\n1\n\n\na1\nw" | fdisk usb.img
		SECTOR_SIZE="$(fdisk -lu usb.img | grep ^Units: | sed 's/.*= //' | sed 's/ .*$//')"
		PARTITION_START="$(fdisk -lu usb.img | grep usb.img1 | sed 's/usb.img1 *\* *//' | sed 's/ .*$//')"
		OFFSET="$(( $SECTOR_SIZE * $PARTITION_START ))"

		syslinux -i usb.img

		log Mount usb image file as loop device
		losetup -o $OFFSET /dev/loop0 usb.img

		log Format FAT32 on usb image file
		apt-get install -y dosfstools
		mkfs.vfat /dev/loop0

		log Install syslinux to usb image
		syslinux -i /dev/loop0

		log Write syslinux master boot record to usb image
		dd if=/usr/lib/syslinux/mbr/mbr.bin of=usb.img conv=notrunc bs=440 count=1

		log Mount first usb image partition
		mount /dev/loop0 /mnt

		log Copy data to image partition
		cp /usr/lib/syslinux/modules/bios/* /mnt/
		cp /usr/share/misc/pci.ids /mnt/
		cp /boot/memtest86+.bin /mnt/memtest
		cp image/isolinux/isolinux.cfg /mnt/syslinux.cfg
		rsync -rv image/live /mnt/

		log Unmount first usb image partition
		umount -lf /mnt
		
		log Unmount usb image file as loop device
		losetup -d /dev/loop0
	fi
fi

popd >/dev/null 2>&1
