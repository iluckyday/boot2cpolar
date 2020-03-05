#!/bin/bash
set -ex

pacman --noconfirm -Sy busybox libisoburn syslinux curl tar grep unzip cpio coreutils xz findutils gzip zstd >/dev/null 2>&1

DEST=$(mktemp -d)
INITRD=$DEST/initramfs
ISODIR=$DEST/iso
[ -d $DEST ] && rm -rf $DEST
mkdir -p $INITRD/etc $INITRD/usr/bin $INITRD/usr/lib $ISODIR

cd $INITRD

cp -f /usr/bin/busybox $INITRD/usr/bin/
cp -f /lib/libnss_files.so.* $INITRD/usr/lib/

VMLINUZ_KO="*/vmlinuz *e1000.*"
curl -skL https://www.archlinux.org/packages/core/x86_64/linux/download/ | tar --wildcards --no-anchored -x $VMLINUZ_KO
mv usr/lib/modules/*/vmlinuz $ISODIR/vmlinuz

curl -skL https://www.cpolar.com/static/downloads/cpolar-stable-linux-amd64.zip -o /tmp/cpolar.zip
unzip /tmp/cpolar.zip -d usr/bin
chmod +x usr/bin/cpolar
sed -i 's@127.0.0.1:4040@10.0.2.15:4040@g' usr/bin/cpolar

cat << EOF > etc/hosts
10.0.2.8 cpolard.cpolar.com
10.0.2.9 cpolard.cpolar.cn
EOF

cat > init <<"EOF"
#!/usr/bin/busybox sh
busybox mkdir -p /dev/net /dev/pts /proc /sys /etc
busybox mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devpts  devpts /dev/pts
cd /usr/bin/ && ln -s busybox sh
ln -s /usr/lib /lib
ln -s /usr/lib64 /lib64
ln -s /usr/bin /bin
modprobe e1000
mdev -s
ifconfig lo 127.0.0.1 netmask 255.0.0.0 up
ifconfig eth0 up
ifconfig eth0 10.0.2.15 netmask 255.255.255.0 up
tftp -g -l /etc/token -r token 10.0.2.2
TOKEN=$(cat /etc/token)
cat > /etc/cpolar.yml <<CPOLAR
authtoken: $TOKEN
region: cn
console_ui: false
http_proxy: false
log: stdout
tunnels:
  v:
    addr: 10.0.2.10:1024
    proto: tcp
CPOLAR
/usr/bin/cpolar start-all -config /etc/cpolar.yml
EOF

chmod +x init
find . | cpio --quiet -H newc -o | xz -9 --check=none > $ISODIR/initrd

cd $ISODIR
cp /usr/lib/syslinux/bios/isohdpfx.bin /usr/lib/syslinux/bios/ldlinux.c32 /usr/lib/syslinux/bios/isolinux.bin .
echo default vmlinuz initrd=initrd append ipv6.disable=1 net.ifnames=0 > isolinux.cfg
[ -s /tmp/boot2cpolar.iso ] && rm -rf /tmp/boot2cpolar.iso
xorriso \
    -as mkisofs -o /tmp/boot2cpolar.iso \
    -A 'Boot2Cpolar' \
    -V "Boot2Cpolar" \
    -isohybrid-mbr isohdpfx.bin \
    -b isolinux.bin \
    -c boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    ./
