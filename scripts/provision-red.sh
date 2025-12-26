#!/bin/ash
set -eux

echo "[+] Cài package..."
apk update
apk add --no-cache \
  openssh \
  frr frr-openrc \
  iproute2 \
  curl \
  acpid \
  qemu-guest-agent \
  cloud-init cloud-init-openrc \
  busybox-extras \
  iptables iptables-openrc

# ---- SSH hardening (do NOT restart networking) ----
echo "[+] Ensure sshd runtime dir exists..."
mkdir -p /var/run/sshd

echo "[+] Hardening SSH: key-only, disable password..."
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
echo "[+] Fix Alpine NIC DOWN: auto ip link up at boot..."
mkdir -p /etc/local.d
cat > /etc/local.d/ifup.start <<'EOF'
#!/bin/sh
for i in eth0 eth1 eth2; do
  ip link set "$i" up 2>/dev/null || true
done
EOF
chmod +x /etc/local.d/ifup.start
rc-update add local default || true

# Enable networking so next boot it comes up (do NOT restart during Packer SSH)
rc-update add networking default || true
ip link set eth0 up 2>/dev/null || true

# ==========================================================
# Static IP config for internal NICs (do NOT touch eth0 DHCP)
# - eth1: transit 10.10.101.2/30 (peer Blue thường .1)
# - eth2: red LAN 10.10.171.1/24
# ==========================================================
echo "[+] Set runtime IP for eth1/eth2 (do NOT restart networking)..."
ip link set eth1 up 2>/dev/null || true
ip link set eth2 up 2>/dev/null || true
ip addr replace 10.10.101.2/30 dev eth1 2>/dev/null || true
ip addr replace 10.10.171.1/24 dev eth2 2>/dev/null || true

# Persist into /etc/network/interfaces (rewrite eth1/eth2 only)
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

# ==========================================================
# [IPTABLES] Configure iptables: default drop + forward + NAT
# ==========================================================
echo "[+] Configure iptables (policy drop + forward + NAT)..."

WAN_IF="eth0"
OSPF_IF="eth1"
LAN_IF="eth2"

# Flush sạch rules
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# Default policy
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# INPUT: cơ bản
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# DHCP client trên eth0 (để chắc ăn khi policy INPUT DROP)
iptables -A INPUT -i "$WAN_IF" -p udp --sport 67 --dport 68 -j ACCEPT

# Quản trị
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p icmp -j ACCEPT

# OSPF (proto 89) + IGMP (proto 2) cho multicast (OSPF hello dùng multicast)
iptables -A INPUT -p ospf -j ACCEPT
iptables -A INPUT -p igmp -j ACCEPT

# Cho phép mạng nội bộ truy cập router (eth1/eth2)
iptables -A INPUT -i "$OSPF_IF" -j ACCEPT
iptables -A INPUT -i "$LAN_IF" -j ACCEPT

# FORWARD
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 1) LAN -> Internet
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT

# 2) Transit/OSPF link -> Internet (nếu cần update/ping từ bên kia đi qua)
iptables -A FORWARD -i "$OSPF_IF" -o "$WAN_IF" -j ACCEPT

# 3) Routing nội bộ giữa LAN <-> Transit
iptables -A FORWARD -i "$OSPF_IF" -o "$LAN_IF" -j ACCEPT
iptables -A FORWARD -i "$LAN_IF" -o "$OSPF_IF" -j ACCEPT

# NAT: masquerade mọi thứ đi ra WAN
iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE

# Enable + start + save rules (persist)
rc-update add iptables default || true
rc-service iptables start > /dev/null 2>&1 || true
rc-service iptables save  > /dev/null 2>&1 || true

# ---- FRR OSPF: advertise transit + red LAN; no DMZ here ----
echo "[+] Configure FRR (standard OSPF; do not advertise DMZ)..."
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

rc-update add cloud-init default || true

chown -R frr:frr /etc/frr || true
chmod 640 /etc/frr/frr.conf || true
rc-update add networking default || true

# Start FRR (redirect output to avoid holding the session)
rc-update add frr default || true
rc-service frr start > /dev/null 2>&1 || true

# ---- ACPI + QEMU guest agent: graceful shutdown ----
echo "[+] Enable ACPI + QEMU guest agent..."
rc-update add acpid default || true
rc-service acpid start > /dev/null 2>&1 || true

rc-update add qemu-guest-agent default || true

# Use NoCloud datasource only (Proxmox cloud-init drive), do not probe EC2
mkdir -p /etc/cloud/cloud.cfg.d
cat > /etc/cloud/cloud.cfg.d/99-proxmox.cfg <<'EOF'
datasource_list: [ NoCloud, None ]

datasource:
  NoCloud:
    fs_label: cidata
EOF

# Disable cloud-init network module (it overwrites your interfaces)
cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<'EOF'
network: {config: disabled}
EOF

# Clean so clones still run user-data, but do not break network
cloud-init clean --logs > /dev/null 2>&1 || true

echo "[+] Cleaning cloud-init state/logs..."
cloud-init clean -l > /dev/null 2>&1 || true
rm -rf /var/lib/cloud/* > /dev/null 2>&1 || true

# FIX Alpine: if /sbin/shutdown is missing, create symlink for agent usage
if [ ! -f /sbin/shutdown ]; then
  ln -s /sbin/poweroff /sbin/shutdown
fi

rc-service qemu-guest-agent restart > /dev/null 2>&1 || true

echo "[+] Done."
