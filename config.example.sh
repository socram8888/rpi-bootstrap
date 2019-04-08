
# Debian version to install
Version=buster

# Boot partition. May be a file to create an image instead of working on a live disk.
BootPart=/dev/sdb1

# Root partition. May be a partition on the SD, on a USB, a file, a md RAID... Basically anything that could contain a partition.
RootPart=/dev/sdb2

# Device host name. Can be either a local, invented host or a FQDN.
Hostname=raspberry.orca.pet

# Static IP. If not specified (ie comented or empty), an automatic IP will be obtained by DHCP.
NetAddress=192.168.0.243

# Net mask for static IP
NetMask=255.255.255.0

# Default gateway for static IP
NetGateway=192.168.0.1

# List of comma-separated DNSes
NetDNS=8.8.8.8,8.8.4.4

# User name to create. If not specified, "root" with password "root" will be used.
UserName=marcos
UserPass=marcos

# User SSH keys for password-less remote login. Required for remotely unlocking an encrypted root.
UserSSHKeys="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBEMk6EAFLE8ObylO9lj3BQwcegc0tsKQzngSgkh72ID marcos@DESKTOP-IIEFA6N
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC0IFryYdrq5jbMxtG271aWT0pSxVQXTgHNupOWETwmebvtczRBmw18X2JALBJ1hlmw88DnETFLZaS+nNzBmsUZhe0MXlBuMaTFm31Obs1k20Y7SLTzf5LsXOmrvhQDp0xAzAWU1L3+GHz3qGwX0rtivuGPIrI3Zs3XS1jnonGGZQHxgqv/qy/00ldh3vq20cal1yOELJaKLcC4J57XJPUQw69G6b1MZDr4tAiZt/hz4kBV04bnXy+LEUqguT9u/JdvFcOVulBbT3a/Tkb6nzb0Vji+G+EuViwWyGvCj84DXwRpJohI3xrsMSGIVWSTgLaawydwMvB9qGd6vVxXB9Bv /home/marcos/.ssh/id_rsa"

# Set to true to enable LUKS root encryption. On boot, it will as for a password.
# If SSH keys are specified above, a limited Dropbear instance will be enabled on port 23 for mounting it.
EncryptRoot=true
