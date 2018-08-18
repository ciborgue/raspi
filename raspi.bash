#!/bin/bash -ex
# vim: set ts=4 sts=4 sw=4:

if [[ $(whoami) != root ]]; then
	echo This script has to be run as root, like \'sudo $0\'\; exiting
	exit 1
fi
src_image=${1:-img/minimal.img}; dst_image=${2:-/tmp/target.img}

node='/tmp/a'

cleanup() {
	set +e # allow umount to fail without terminating the cleanup
	trap - EXIT
	umountImages
	echo 'Removing temporary files ..'; rm -rf /tmp/tmp.*
}
trap cleanup EXIT

umountImages() {
	echo 'Unmounting ..'
	for a in $node/{src,dst}{/boot,}; do
		umount $a
	done
}

pFlags() {
	# args: disk/image partition returns: start:size
	set $(parted --script $1 unit s print | \
		sed -e "/^[[:space:]]\{1,\}$2[[:space:]]/!d")
	echo "offset=$((${2%s} * 512)),sizelimit=$((${4%s} * 512))"
}

# unpack target image; building this image can be automated but it
# does not worth an effort so I built it manually and keep a compressed copy
xz -cd img/target.img.xz | dd of=$dst_image conv=sparse status=none

### Prepare root filesystem ###################################################
src=$node/src; mkdir -p $src; dst=$node/dst; mkdir -p $dst
flags=$(pFlags $src_image 2); mount -o ro,$flags $src_image $src
mount -t tmpfs -o size=2g tmpfs $dst
tar cCf $src - . | tar xSCf $dst -

### Prepare /boot filesystem ##################################################
flags=$(pFlags $src_image 1); mount -o ro,$flags $src_image $src/boot
flags=$(pFlags $dst_image 1); mount -o $flags $dst_image $dst/boot
tar cCf $src/boot - . | tar xSCf $dst/boot -

ed -s $dst/etc/fstab <<EOF
/-01[[:space:]]/s/defaults/defaults,ro/
g/^PARTUUID=/s!^.*-0\([[:digit:]]\)[[:space:]]\{1,\}!/dev/mmcblk0p\1	!
\$a
#tmpfs	/tmp	tmpfs	nosuid,nodev	0 0
.
w
EOF

ed -s $dst/etc/shadow <<EOF
/^pi:/c
pi:\$6\$NF.NecYx\$fRs9zdsNX5DOXH9ilb7zmWwOnZTzj9.bV3Qlw1bwInVP6JvYPEEKbB8DtTEtgYMbynU4vo3W7K81dK7FbRVAw.:17713:0:99999:7:::
.
w
EOF

# enable UDP syslog server
ed -s $dst/etc/rsyslog.conf <<EOF
/#module.*immark/s/^#//
/#module.*imudp/s/^#//
/#input.*imudp/s/^#//
w
EOF

egrep -v '^\s*(#|$)' root-overlay/Manifest | while read line; do
	set -- ${line//,/ }
	case $1 in
		chmod)
			chmod $3 $dst/$2
			;;
		chown)
			chown $3 $dst/$2 # note: by default it's root:root
			;;
		mkdir)
			mkdir -p $dst/$2
			;;
		ln) # symlink, for rc?.d use
			ln -s $2 $dst/$3
			;;
		cp)
			mkdir -p $(dirname $dst/$2)
			cp root-overlay/$2 $dst/$2
			chown root:root $dst/$2
			;;
		append)
			cat root-overlay/$2 >> $dst/$2
			;;
		rm) # brace expansion special processing
			rm -rf $(eval echo $dst/${line#*,})
			;;
		patch)
			exit 1
			;;
		*)
			exit 1
			;;
	esac
done

find $dst/var/log -type f -name '*.log' | xargs rm -f

rm -f /tmp/root.sqfs; mksquashfs $dst /tmp/root.sqfs -comp xz -Xbcj arm -b 1M
#rm -f /tmp/root.sqfs; mksquashfs $dst /tmp/root.sqfs -comp gzip -b 1M

umountImages

seek=$(($(echo $(pFlags $dst_image 2) | sed -e 's/,.*//;s/.*=//') / 512))
dd if=/tmp/root.sqfs of=$dst_image seek=$seek conv=notrunc status=progress
