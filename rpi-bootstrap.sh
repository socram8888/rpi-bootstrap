#!/bin/bash

# Fail on error
set -e

if [ $# -ne 1 ]; then
	echo "Usage: $0 config"
	exit 1
fi

# Sane defaults
Version=stable
NetAddress=""
EncryptRoot=false
UserName=root
UserPass=root

source "$1"

cd "$(dirname "$0")"

log_step() {
	echo -e "[\e[32m---\e[39m] $1"
}

log_step "Installing host dependencies"

ExtraLocal=""
if $EncryptRoot; then
	ExtraLocal=" cryptsetup"
fi

# util-linux contains blkid
apt install binfmt-support debootstrap qemu-user-static util-linux debian-keyring btrfs-progs $ExtraLocal

log_step "Unmounting old root filesystem"
if [ -d root ]; then
	! mountpoint root/boot || umount root/boot
	! mountpoint root/proc || umount root/proc
	! mountpoint root || umount root

	rm -r root
fi
[ ! -e /dev/mapper/rpicryptroot ] || cryptsetup close rpicryptroot

if $EncryptRoot; then
	log_step "Preparing crypt layer"

	# AES-128 in XTS mode (2 keys of 128 bits each), using SHA-256 as hashing
	cryptsetup luksFormat "$RootPart" --cipher=aes-xts-plain64 --key-size=256 --hash=sha256

	log_step "Mounting crypt layer"
	cryptsetup open "$RootPart" rpicryptroot

	RootPlainPart=/dev/mapper/rpicryptroot
else
	RootPlainPart="$RootPart"
fi

log_step "Preparing root filesystem"
mkfs.btrfs "$RootPlainPart"
mkdir root
mount "$RootPlainPart" root

# RootUUID will refer to plain block if plain, or LUKS container if encrypted
RootUUID="$(blkid -s UUID -o value "$RootPart")"

log_step "Preparing boot filesystem"
mkfs.vfat "$BootPart"
BootUUID="$(blkid -s UUID -o value "$BootPart")"
mkdir root/boot
mount "$BootPart" root/boot

log_step "Setting up target QEMU emulator"
# This must be done before executing debootstrap so it can execute the second stage.
mkdir -p root/usr/bin
cp /usr/bin/qemu-arm-static root/usr/bin

log_step "Executing debootstrap"

ExtraPackages=""
if [ -z "$NetAddress" ]; then
	# Install DHCP client if no user-specified address
	ExtraPackages=${ExtraPackages},isc-dhcp-client
fi

if $EncryptRoot; then
	# Install cryptsetup for unmounting on boot
	ExtraPackages=${ExtraPackages},cryptsetup-initramfs

	if [ ! -z "$UserSSHKeys" ]; then
		ExtraPackages=${ExtraPackages},dropbear-initramfs
	fi
fi

# We exclude init because it would force systemd to install.
debootstrap --arch=armhf --variant=minbase --include=apt-utils,aptitude,btrfs-progs,ca-certificates,gnupg,less,locales,man-db,nano,netbase,ntp,ifupdown,inetutils-ping,iproute2,irqbalance,openssh-server,psmisc,sudo,sysvinit-core,wget,whiptail${ExtraPackages} --exclude=init $Version root http://httpredir.debian.org/debian/

if $EncryptRoot; then
	log_step "Creating minimal cmdline.txt"
	# We need a delay to give time for USBs to be detected during boot
	echo "cryptdevice=UUID=$RootUUID:root_crypt root=/dev/mapper/root_crypt net.ifnames=0 bootdelay=5" >root/boot/cmdline.txt

	log_step "Populating fstab"
	cat <<EOF | cut -c3- >root/etc/fstab
		/dev/mapper/root_crypt	/	btrfs	noatime,nodiratime	0	1
		UUID=$BootUUID	/boot	vfat	umask=0077	0	1
EOF

	log_step "Populating crypttab"
	cat <<EOF | cut -c3- >root/etc/crypttab
		root_crypt	UUID=$RootUUID	none	luks
EOF
else
	log_step "Creating minimal cmdline.txt"
	# We need a delay to give time for USBs to be detected during boot
	echo "root=UUID=$RootUUID net.ifnames=0 bootdelay=5" >root/boot/cmdline.txt

	log_step "Populating fstab"
	cat <<EOF | cut -c3- >root/etc/fstab
		UUID=$RootUUID	/	btrfs	noatime,nodiratime	0	1
		UUID=$BootUUID	/boot	vfat	umask=0077	0	1
EOF
fi

log_step "Setting up system hostname"
echo "$Hostname" >root/etc/hostname
echo "127.0.1.1	$Hostname" >>root/etc/hosts

if ! grep -q "^auto lo$" root/etc/network/interfaces; then
	log_step "Configurating loopback interface"

	cat <<EOF | cut -c3- >>root/etc/network/interfaces
		# The loopback network interface
		auto lo
		iface lo inet loopback
EOF
fi

if [ ! -z "$NetAddress" ]; then
	log_step "Setting up static IP"
	cat <<EOF | cut -c3- >root/etc/network/interfaces.d/eth0
		auto eth0
		iface eth0 inet static
			address $NetAddress
			netmask $NetMask
			gateway $NetGateway
EOF
else
	log_step "Setting up DHCP"
	cat <<EOF | cut -c3- >root/etc/network/interfaces.d/eth0
		auto eth0
		iface eth0 inet dhcp
EOF
fi

log_step "Setting up DNS"
echo "$NetDNS" | tr ',' '\n' | sed "s/\(.\+\)/nameserver \1/" >root/etc/resolv.conf

if $EncryptRoot && [ ! -z "$UserSSHKeys" ]; then
	log_step "Configuring SSH encrypted root partition mounting"

	# Enable initramfs cryptsetup even if it can't detect it's encrypted (which won't due to being bootstrapped)
	sed -i 's/^#\?CRYPTSETUP=.*/CRYPTSETUP=y/' root/etc/cryptsetup-initramfs/conf-hook

	# Allow only cryptroot-unlock, disabling port forwarding and running on port 23 (so SSH does not complain about using different keys)
	sed -i 's/^#\?DROPBEAR_OPTIONS=.*/DROPBEAR_OPTIONS="-j -k -c \/bin\/cryptroot-unlock -p 23"/' root/etc/dropbear-initramfs/config

	# Dropbear is only compatible with RSA, but we'll put all in case it ever supports Ed25519
	echo "$UserSSHKeys" >root/etc/dropbear-initramfs/authorized_keys

	if [ ! -z "$NetAddress" ]; then
		echo "# Static IP for Dropbear root mounting shell">>root/etc/initramfs-tools/initramfs.conf
		echo "IP=${NetAddress}::${NetGateway}:${NetMask}::eth0:off">>root/etc/initramfs-tools/initramfs.conf
	fi
fi

log_step "Creating apt sources.list for Raspbian"
cat <<EOF | cut -c2- >root/etc/apt/sources.list.d/raspbian.list
	deb http://mirrordirector.raspbian.org/raspbian/ $Version main firmware
	deb-src http://mirrordirector.raspbian.org/raspbian/ $Version main firmware
EOF

log_step "Pinning Raspbian repositories"
cat <<EOF | cut -c2- >root/etc/apt/preferences.d/raspbian
	Package: *
	Pin: release o=Raspbian
	Pin-Priority: 50
EOF

log_step "Preparing Raspbian signing key"
wget -O root/raspbian.public.key http://archive.raspbian.org/raspbian.public.key
echo "ca59cd4f2bcbc3a1d41ba6815a02a8dc5c175467a59bd87edeac458f4a5345de root/raspbian.public.key" | sha256sum -c

log_step "Extracting third stage"
cat <<EOF | cut -c2- >root/third-stage.sh
	#!/bin/bash -e

	log_step() {
		echo -e "[\e[32m---\e[39m] \$1"
	}

	log_step "Installing Raspbian signing key"
	apt-key add raspbian.public.key

	log_step "Updating local apt repository"
	apt update

	log_step "Installing kernel and firmware"
	apt install -y --no-install-recommends raspberrypi-bootloader-nokernel linux-image-rpi2-rpfv

	if [ "$UserName" != root ]; then
		log_step "Creating user"
		useradd -m -G users,sudo "$UserName"
	fi

	log_step "Configuring user password"
	printf "%s\n%s\n" "$UserPass" "$UserPass" | passwd "$UserName"

	log_step "Changing shell to bash"
	chsh -s /bin/bash "$UserName"
EOF
chmod +x root/third-stage.sh

log_step "Executing third stage"
chroot root /third-stage.sh

if [ ! -z "$UserSSHKeys" ]; then
	log_step "Configuring key-less SSH login"

	UserHome=root/root
	if [ "$UserName" != root ]; then
		UserHome=root/home/$UserName
	fi

	mkdir -p "$UserHome/.ssh/"
	chmod 700 "$UserHome/.ssh/"
	echo "$UserSSHKeys">"$UserHome/.ssh/authorized_keys"
	chmod 600 "$UserHome/.ssh/authorized_keys"
	chown -R "$UserName:$UserName" "$UserHome/.ssh/"
fi

log_step "Creating minimal config.txt"
pushd root/boot
NewestKernel="$(ls -t1 vmlinu* | head -n1)"
NewestInitRD="$(ls -t1 init* | head -n1)"
cat <<EOF | cut -c2- >config.txt
	kernel=$NewestKernel
	initramfs $NewestInitRD followkernel
EOF
popd

log_step "Cleanup"
rm root/third-stage.sh
rm root/raspbian.public.key
rm root/usr/bin/qemu-arm-static

log_step "Unmounting"
umount root/boot
umount root

if $EncryptRoot; then
	cryptsetup close rpicryptroot
fi

sync
