#!/bin/ash
set -eux

echo "[+] Cài package..."
apk update
apk add --no-cache \
  openssh \
  nftables \
  frr frr-openrc \
  iproute2 \
  curl \
  acpid \
  qemu-guest-agent \
  cloud-init cloud-init-openrc

# ---- SSH hardening (không restart networking) ----
echo "[+] Ensure sshd runtime dir exists..."
mkdir -p /var/run/sshd

echo "[+] Hardening SSH: chỉ cho key, tắt password..."
SSHD_CFG="/etc/ssh/sshd_config"
if [ -f "$SSHD_CFG" ]; then
  sed -i \
    -e 's/^#\?PasswordAuthentication .*/PasswordAuthentication no/' \
    -e 's/^#\?KbdInteractiveAuthentication .*/KbdInteractiveAuthentication no/' \
    -e 's/^#\?ChallengeResponseAuthentication .*/ChallengeResponseAuthentication no/' \
    -e 's/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/' \
    -e 's/^#\?PermitRootLogin .*/PermitRootLogin prohibit-password/' \
    "$SSHD_CFG" || true

  grep -q '^PasswordAuthentication ' "$SSHD_CFG" || echo 'PasswordAuthentication no' >> "$SSHD_CFG"
  grep -q '^KbdInteractiveAuthentication ' "$SSHD_CFG" || echo 'KbdInteractiveAuthentication no' >> "$SSHD_CFG"
  grep -q '^ChallengeResponseAuthentication ' "$SSHD_CFG" || echo 'ChallengeResponseAuthentication no' >> "$SSHD_CFG"
  grep -q '^PubkeyAuthentication ' "$SSHD_CFG" || echo 'PubkeyAuthentication yes' >> "$SSHD_CFG"
  grep -q '^PermitRootLogin ' "$SSHD_CFG" || echo 'PermitRootLogin prohibit-password' >> "$SSHD_CFG"
fi

rc-update add sshd default || true
rc-service sshd start || true
rc-service sshd reload 2>/dev/null || true

# ---- Fix NIC default DOWN: local.d ----
echo "[+] Fix Alpine NIC DOWN: auto ip link up lúc boot..."
mkdir -p /etc/local.d
cat > /etc/local.d/ifup.start <<'EOF'
#!/bin/sh
for i in eth0 eth1 eth2; do
  ip link set "$i" up 2>/dev/null || true
done
EOF
chmod +x /etc/local.d/ifup.start
rc-update add local default || true

# Enable networking để boot sau tự lên (không restart ngay lúc Packer đang SSH)
rc-update add networking default || true
ip link set eth0 up 2>/dev/null || true

# ==========================================================
# Cấu hình IP static cho NIC nội bộ (không đụng eth0 DHCP)
# - eth1: transit 10.10.101.2/30 (đầu kia Blue thường là .1)
# - eth2: red LAN 10.10.171.1/24
# ==========================================================
echo "[+] Set IP runtime cho eth1/eth2 (không restart networking)..."
ip link set eth1 up 2>/dev/null || true
ip link set eth2 up 2>/dev/null || true
ip addr replace 10.10.101.2/30 dev eth1 2>/dev/null || true
ip addr replace 10.10.171.1/24 dev eth2 2>/dev/null || true

# Persist vào /etc/network/interfaces (chỉ rewrite eth1/eth2)
IF_FILE="/etc/network/interfaces"
if [ -f "$IF_FILE" ]; then
  awk '
    function is_target(i) { return (i=="eth1" || i=="eth2") }
    BEGIN { skip=0 }
    /^auto[ \t]+/ {
      i=$2
      if (is_target(i)) { skip=1; next }
      if (skip && !is_target(i)) { skip=0; print }
      else if (!skip) { print }
      next
    }
    /^iface[ \t]+/ {
      i=$2
      if (is_target(i)) { skip=1; next }
      if (skip && !is_target(i)) { skip=0; print }
      else if (!skip) { print }
      next
    }
    { if (!skip) print }
  ' "$IF_FILE" > /tmp/interfaces.new

  cat >> /tmp/interfaces.new <<'EOF'

# --- Added by provision-red.sh ---
auto eth1
iface eth1 inet static
    address 10.10.101.2
    netmask 255.255.255.252

auto eth2
iface eth2 inet static
    address 10.10.171.1
    netmask 255.255.255.0
EOF

  mv /tmp/interfaces.new "$IF_FILE"
fi

# ---- IPv4 forwarding ----
echo "[+] Enable IPv4 forwarding..."
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-router.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
sysctl -p /etc/sysctl.d/99-router.conf || true

# ---- nftables: NAT + basic policy ----
echo "[+] Configure nftables (NAT cho red LAN ra internet qua eth0)..."
cat > /etc/nftables.conf <<'EOF'
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;

    iif "lo" accept
    ct state established,related accept

    # SSH
    tcp dport 22 accept

    # ICMP
    ip protocol icmp accept

    # OSPF (proto 89)
    ip protocol ospf accept

    # Cho phép traffic từ NIC nội bộ vào router (tuỳ bạn siết thêm sau)
    iifname { "eth1", "eth2" } accept
  }

  chain forward {
    type filter hook forward priority 0; policy drop;

    ct state established,related accept

    # Red LAN -> WAN
    iifname "eth2" oifname "eth0" accept

    # Transit forward (tuỳ topology bạn siết sau)
    iifname "eth1" accept
  }

  chain output {
    type filter hook output priority 0; policy accept;
  }
}

table ip nat {
  chain prerouting {
    type nat hook prerouting priority -100;
  }

  chain postrouting {
    type nat hook postrouting priority 100;

    # Masquerade red LAN ra WAN
    oif "eth0" ip saddr { 10.10.171.0/24 } masquerade
  }
}
EOF

rc-update add nftables default || true
rc-service nftables start || true
rc-service nftables reload 2>/dev/null || true

# ---- FRR OSPF: chỉ quảng bá transit + red LAN, không có DMZ ----
echo "[+] Configure FRR (OSPF chuẩn, không quảng bá DMZ)..."
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
 ospf router-id 10.10.101.2
 passive-interface default
 no passive-interface eth1
 network 10.10.101.0/30 area 0
 network 10.10.171.0/24 area 0
!
line vty
!
EOF

chown -R frr:frr /etc/frr || true
chmod 640 /etc/frr/frr.conf || true

# Start FRR (redirect để tránh giữ session lâu)
rc-update add frr default || true
rc-service frr start > /dev/null 2>&1 || true

# ---- ACPI + QEMU guest agent: shutdown graceful ----
echo "[+] Enable ACPI + QEMU guest agent..."
rc-update add acpid default || true
rc-service acpid start > /dev/null 2>&1 || true

rc-update add qemu-guest-agent default || true

# FIX Alpine: nếu thiếu /sbin/shutdown thì tạo symlink cho agent gọi
if [ ! -f /sbin/shutdown ]; then
  ln -s /sbin/poweroff /sbin/shutdown
fi

rc-service qemu-guest-agent restart > /dev/null 2>&1 || true

# Chỉ dùng datasource NoCloud (cloud-init drive của Proxmox), không probe EC2
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-proxmox.cfg <<'EOF'
datasource_list: [ NoCloud, None ]

datasource:
  NoCloud:
    fs_label: cidata
EOF

# ---- Cloud-init services ----
echo "[+] Enable cloud-init services..."
rc-update add cloud-init-local boot    || true
rc-update add cloud-init default       || true
rc-update add cloud-config default     || true
rc-update add cloud-final default      || true

echo "[+] Done."
