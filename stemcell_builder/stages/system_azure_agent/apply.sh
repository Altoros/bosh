#!/usr/bin/env bash

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

mkdir -p $chroot/tmp
cp $assets_dir/* $chroot/tmp

# Install hv kernel and Azure linux agent
pkg_mgr install linux-backports-modules-hv-precise-virtual hv-kvp-daemon-init #walinuxagent

# Temporary, while official package not released
run_in_chroot $chroot "
  dpkg -i /tmp/walinuxagent-data-saver_2.0.1_amd64.deb
  dpkg -i /tmp/walinuxagent_2.0.1_amd64.deb
"

# Install cloud-init
pkg_mgr install cloud-init cloud-initramfs-growroot cloud-initramfs-rescuevol

# Config cloud-init for Azure DataSource
run_in_chroot $chroot "
  cp /tmp/9*.cfg /etc/cloud/cloud.cfg.d/
"

# Remove firstboot script, cloud-init will manage to do this work
run_in_chroot $chroot "
  rm /etc/rc.local
  rm /root/firstboot.sh
  rm /etc/resolv.conf
"

# Fix GRUB timeout and boot options
sudo sed -i "s/\${GRUB_RECORDFAIL_TIMEOUT:--1}/5/ig" $chroot/etc/grub.d/00_header
sudo sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyS0 rootdelay=300\"/ig" $chroot/boot/grub/default
sudo sed -i "s/atapiix.disable_driver//g" $chroot/boot/grub/default

run_in_chroot $chroot 'update-grub'

rm -f $chroot/tmp/*.{deb,cfg}
