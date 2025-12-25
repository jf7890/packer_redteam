#!/bin/ash
set -eux

echo "[+] Installing packages..."
apk update
apk add --no-cache openssh nftables frr frr-openrc iproute2 curl

# --- SSH hardening (giữ như Blue) ---
mkdir -p /var/run/sshd
SSHD_CFG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CFG" ]; then
  sed -i \
    -e 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' \
    -e 's/^#\?KbdInteractiveAuthentication .*/KbdInteractiveAuthentication no/' \
    -e 's/^#\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' \
    -e 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' \
    -e 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' \
    "$SSHD_CFG" || true
fi
rc-update add sshd default || true
rc-service sshd start || true
rc-service sshd reload 2>/dev/null || true

# --- NIC UP safety net ---
mkdir -p /etc/local.d
cat > /etc/local.d/ifup.start <<'EOF'
#!/bin/sh
for i in eth0 eth1 eth2; do
  ip link set "$i" up 2>/dev/null || true
done
EOF
chmod +x /etc/local.d/ifup.start
rc-update add local default || true
rc-update add networking default || true
ip link set eth0 up 2>/dev/null || true

# --- IP cấu hình (đuôi .1 cho router) ---
# (để an toàn, chỉ set runtime cho eth1/eth2; eth0 đã có từ answers)
ip link set eth1 up 2>/dev/null || true
ip link set eth2 up 2>/dev/null || true
ip addr replace 10.10.101.2/30 dev eth1 2>/dev/null || true
ip addr replace 10.10.173.1/24 dev eth2 2>/dev/null || true

# --- IPv4 forwarding ---
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-router.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
sysctl -p /etc/sysctl.d/99-router.conf || true

# --- nftables NAT: cho Red LAN ra Internet qua eth0 ---
cat > /etc/nftables.conf <<'EOF'
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif "lo" accept
    ct state established,related accept
    tcp dport 22 accept
    ip protocol icmp accept
    ip protocol ospf accept
    iifname { "eth1", "eth2" } accept
  }

  chain forward {
    type filter hook forward priority 0; policy drop;
    ct state established,related accept
    iifname "eth2" oifname "eth0" accept
    iifname "eth1" accept
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}

table ip nat {
  chain postrouting {
    type nat hook postrouting priority 100;
    oif "eth0" ip saddr { 10.10.173.0/24 } masquerade
  }
}
EOF

rc-update add nftables default || true
rc-service nftables start || true
rc-service nftables reload 2>/dev/null || true

# --- FRR OSPF: KHÔNG mix interface+network; advertise transit + redlan ---
if [ -f /etc/frr/daemons ]; then
  sed -i \
    -e 's/^zebra=.*/zebra=yes/' \
    -e 's/^ospfd=.*/ospfd=yes/' \
    -e 's/^bgpd=.*/bgpd=no/' \
    -e 's/^ripd=.*/ripd=no/' \
    -e 's/^isisd=.*/isisd=no/' \
    /etc/frr/daemons || true
fi

cat > /etc/frr/frr.conf <<'EOF'
frr defaults traditional
hostname red-router
service integrated-vtysh-config
!
router ospf
 ospf router-id 10.10.100.22
 network 10.10.101.0/30 area 0
 network 10.10.173.0/24 area 0
!
line vty
!
EOF

chown -R frr:frr /etc/frr || true
chmod 640 /etc/frr/frr.conf || true
rc-update add frr default || true
rc-service frr start > /dev/null 2>&1 || true

echo "[+] Done."
