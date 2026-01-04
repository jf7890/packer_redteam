# Red router answerfile

KEYMAPOPTS="us us"

# Hostname
HOSTNAMEOPTS="-n red-router"

DEVDOPTS=mdev

# WAN: DHCP (eth0), các NIC khác để manual (script provision sẽ set static)
INTERFACESOPTS="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

auto eth1
iface eth1 inet manual

auto eth2
iface eth2 inet manual
"

DNSOPTS="1.1.1.1"
TIMEZONEOPTS="-z UTC"
PROXYOPTS=none

# Enable community (-c) để cài cloud-init / frr...
APKREPOSOPTS="-1 -c"

SSHDOPTS=openssh

# Root login via SSH key (no password)
ROOTSSHKEY="${pub_key}"
USEROPTS="-a -u packer"
# Disk install
DISKOPTS="-m sys /dev/sda"

NTPOPTS=none
LBUOPTS=none
APKCACHEOPTS=none
