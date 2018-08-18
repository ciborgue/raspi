mount -o rw,remount /boot
mount -o rw,remount /site
vim /boot/cmdline.txt
mount -o ro,remount /boot
mount -o ro,remount /site
snmpwalk -c 'P@ssw0rd' -v 1 172.31.255.32 .1.3.6.1.4.1.318.1.1.4.4.2.1.3
gpio readall
