#!/bin/bash
set -e

DEBIAN_FRONTEND=noninteractive apt-get -qq update
DEBIAN_FRONTEND=noninteractive apt-get install -y bison flex libelf-dev busybox-static 2>&1 >/dev/null

DEST=$(mktemp -d)
INITRD=$DEST/initramfs
[ -d $DEST ] && rm -rf $DEST
mkdir -p $INITRD/etc $INITRD/bin $INITRD/lib $INITRD/usr/share/terminfo/x

cd $INITRD

cp -f /bin/busybox $INITRD/bin/
#cp -f /usr/share/terminfo/x/xterm $INITRD/usr/share/terminfo/x/
#cp -f /lib/x86_64-linux-gnu/libnss_files-2.27.so $INITRD/lib/

curl -skL https://www.cpolar.com/static/downloads/cpolar-stable-linux-amd64.zip -o /tmp/cpolar.zip
unzip /tmp/cpolar.zip -d bin
chmod +x bin/cpolar
sed -i 's@127.0.0.1:4040@10.0.2.15:4040@g' bin/cpolar

cat << EOF > etc/hosts
10.0.2.8 cpolard.cpolar.com
10.0.2.9 cpolard.cpolar.cn
EOF

cat > init <<"EOF"
#!/bin/busybox sh
busybox mkdir -p /dev/net /dev/pts /proc /sys /etc
busybox mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devpts devpts /dev/pts
cd /bin && ln -s busybox sh
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
/bin/cpolar start-all -config /etc/cpolar.yml
EOF

chmod +x init

export KCONFIG_ALLCONFIG=$HOME/work/boot2cpolar/boot2cpolar/githubci/kernel.config
sed -i "s@CONFIG_INITRAMFS_SOURCE=@CONFIG_INITRAMFS_SOURCE=\"$INITRD\"@" "$KCONFIG_ALLCONFIG"

cd $DEST
wget -q $(wget -qO- https://www.kernel.org | grep downloadarrow_small.png | cut -d'"' -f2)
tar -xf linux-*.tar.xz
cd $(ls -d linux-*/)
make -s -j"$(nproc)" allnoconfig
make -s -j"$(nproc)" bzImage
cp "$(make -s image_name)" "/tmp/vmlinuz"
