#!/bin/bash -ex

disk='/dev/sde'
if [[ ! -f $1 || ! -b $disk ]]; then
	cat <<EOF
This script prepares RPi boot image from Raspbian stock image.
Modifications:
	1. Disable partition resize
	2. Start SSH by default
	3. Add 'prepare' script to /boot
	4. (cosmetic) Change elevator to NOOP
EOF
	exit 1
fi

dd if=$1 of=$disk \
	obs=4M oflag=direct status=progress

set $(sfdisk --dump $disk | sed -e '/start=/!d;s/.*start=\s//;s/,.*//')
mount -o loop,offset=$(( 512 * $1 )) $disk /mnt
touch /mnt/ssh.txt
ed -s /mnt/cmdline.txt <<EOF
.s/[[:space:]]\{1,\}init=.*//
.s/[[:space:]]\{1,\}quiet.*//
.s/deadline/noop/
w
EOF
cat > /mnt/prepare.bash <<EOF
#!/bin/bash

apt update; apt -y full-upgrade
apt -y install \\
	ntp ntpstat ntpdate dnsutils \\
	snmp \\
	wiringpi \\
	vim tmux \\
	tcpdump nmap \\
	lsof \\
	telnet \\
	ruby \\
	xinetd \\
	dnsmasq \\
	busybox \\
	python3-pip \\
	minicom
pip3 install deepmerge pyaml
apt -y purge dphys-swapfile nano
#apt -y purge info man-db manpages build-essential \\
#	dpkg-dev libc-dev-bin libc6-dev libfreetype6-dev \\
#	libgcc-6-dev libmnl-dev libpng-dev libraspberrypi-dev \\
#	linux-libc-dev zlib1g-dev install-info python2.7 \\
#	samba-common dmidecode dphys-swapfile fbset \\
#	dosfstools groff-base gcc-4.{6,7,8,9}-base gcc-5-base \\
#	nano ncdu nfs-common perl wget
apt -y purge --auto-remove
EOF
umount /mnt

set $(sfdisk --dump $disk | sed -e '/start=/!d;s/.*start=\s//;s/,.*//')
mount -o loop,offset=$(( 512 * $2 )) $disk /mnt
rm -f /mnt/etc/rc3.d/S01resize2fs_once \
	/mnt/etc/init.d/resize2fs_once \
	/mnt/usr/lib/raspi-config/init_resize.sh \
	/mnt/etc/rc3.d/S01dphys-swapfile \
	/mnt/etc/rc5.d/S01dphys-swapfile \
	/mnt/etc/rc2.d/S01dphys-swapfile \
	/mnt/etc/dphys-swapfile \
	/mnt/etc/init.d/dphys-swapfile \
	/mnt/etc/rc4.d/S01dphys-swapfile \
	/mnt/var/swap
umount /mnt
