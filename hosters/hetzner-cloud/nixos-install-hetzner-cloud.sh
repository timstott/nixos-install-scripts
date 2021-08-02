#! /usr/bin/env bash

# Script to install NixOS from the Hetzner Cloud NixOS bootable ISO image.
# (tested with Hetzner's `NixOS 20.03 (amd64/minimal)` ISO image).
#
# This script wipes the disk of the server!
#
# Instructions:
#
# 1. Mount the above mentioned ISO image from the Hetzner Cloud GUI
#    and reboot the server into it; do not run the default system (e.g. Ubuntu).
# 2. To be able to SSH straight in (recommended), you must replace hardcoded pubkey
#    further down in the section labelled "Replace this by your SSH pubkey" by you own,
#    and host the modified script way under a URL of your choosing
#    (e.g. gist.github.com with git.io as URL shortener service).
# 3. Run on the server:
#
#       # Replace this URL by your own that has your pubkey in
#       curl -L https://raw.githubusercontent.com/timstott/nixos-install-scripts/master/hosters/hetzner-cloud/nixos-install-hetzner-cloud.sh | sudo bash
#
#    This will install NixOS and power off the server.
# 4. Unmount the ISO image from the Hetzner Cloud GUI.
# 5. Turn the server back on from the Hetzner Cloud GUI.
#
# To run it from the Hetzner Cloud web terminal without typing it down,
# you can either select it and then middle-click onto the web terminal, (that pastes
# to it), or use `xdotool` (you have e.g. 3 seconds to focus the window):
#
#     sleep 3 && xdotool type --delay 50 'curl YOUR_URL_HERE | sudo bash'
#
# (In the xdotool invocation you may have to replace chars so that
# the right chars appear on the US-English keyboard.)
#
# If you do not replace the pubkey, you'll be running with my pubkey, but you can
# change it afterwards by logging in via the Hetzner Cloud web terminal as `root`
# with empty password.

set -e

# Hetzner Cloud OS images grow the root partition to the size of the local
# disk on first boot. In case the NixOS live ISO is booted immediately on
# first powerup, that does not happen. Thus we need to grow the partition
# by deleting and re-creating it.
sgdisk -d 1 /dev/sda

# Create partition for boot
# - partition number 1
# - partition size is 500Mib
sgdisk -n 1:0:500Mib /dev/sda

sgdisk -d 2 /dev/sda
# Create partition for ZFS
# - partition number 2
# - fills the biggest available section of the disk
sgdisk -N 2 /dev/sda

partprobe /dev/sda

BOOT=/dev/sda1
ZFS=/dev/sda2

mkfs.vfat "$BOOT"

zpool create -f -m none -R /mnt \
  -o ashift=12 \
  -O compression=lz4 \
  rpool "$ZFS"

zfs create -p -o mountpoint=legacy rpool/local/root
zfs snapshot rpool/local/root@blank
mount -t zfs rpool/local/root /mnt

zfs create -p -o mountpoint=legacy rpool/local/nix
mkdir /mnt/nix
mount -t zfs rpool/local/nix /mnt/nix

zfs create -p -o mountpoint=legacy rpool/safe/home
mkdir /mnt/home
mount -t zfs rpool/safe/home /mnt/home

zfs create -p -o mountpoint=legacy rpool/safe/persist
mkdir /mnt/persist
mount -t zfs rpool/safe/persist /mnt/persist

mkdir /mnt/boot
mount "$BOOT" /mnt/boot

nixos-generate-config --root /mnt

# Delete trailing `}` from `configuration.nix` so that we can append more to it.
sed -i -E 's:^\}\s*$::g' /mnt/etc/nixos/configuration.nix

HOSTID=$(head -c8 /etc/machine-id)

# Extend/override default `configuration.nix`:
echo "
  networking.hostId = \"$HOSTID\";
  boot.zfs.devNodes = \"$ZFS\";
" >> /mnt/etc/nixos/configuration.nix

echo '
  boot.loader.grub.devices = [ "/dev/sda" ];

  # Initial empty root password for easy login:
  users.users.root.initialHashedPassword = "";
  services.openssh.permitRootLogin = "prohibit-password";

  services.openssh.enable = true;

  users.users.root.openssh.authorizedKeys.keys = [
    # Replace this by your SSH pubkey!
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDQ4w+/Ziw/oRMOJB9UwxTe0bOe8BCNfwHG2GFwoctJ/h7sYKvYs4shG3ZqxYqOWvFRCrR6gfrMXnXYOX5xJwk0emHYbiB4uF20ufH0OpVWKEA4N0ncn0rtvR7pGnPjEcnqqUf6NKtUvALi1d2kTVK75Wx7cep8zorL5Kc96CJLCI15Z8Km1JankOlBTEObExY2MP0VhZXgcWDA0mBjL25mQe3ieivtZw8Y+/0hHvTXgafW+TmjkuInGFcDYpGCTCaoLL95IJs9AN5aIHClzCDF6sCuAbMXJhowblLOqAhULnez8BD93LYDFAXY1R9LlfsAbsx4SeHvqlE3ds9jLpv1"
  ];
}
' >> /mnt/etc/nixos/configuration.nix

nixos-install --no-root-passwd
