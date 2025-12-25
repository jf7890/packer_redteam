# =========================
# Proxmox connection
# =========================
proxmox_url      = "https://10.10.100.1:8006/api2/json"
proxmox_username = "root@pam!packer"
proxmox_token    = "PUT_YOUR_TOKEN_SECRET_HERE"
proxmox_node     = "homelab"

proxmox_insecure_skip_tls_verify = true
vm_id = 0

# =========================
# VM sizing
# =========================
disk_storage_pool = "hdd-lvm"
disk_size         = "8G"
cpu_cores         = 2
memory_mb         = 2048

template_prefix = "tpl"
hostname        = "red-router"

# =========================
# Boot ISO storage + Cloud-Init storage
# =========================
iso_storage_pool        = "hdd-data"
cloud_init_storage_pool = "local-lvm"

# =========================
# WAN bridge (ONLY variable bridge)
# =========================
wan_bridge = "vmbr10"

# =========================
# Live ISO DNS + SSH key
# =========================
dns_server           = "1.1.1.1"
ssh_private_key_file = "~/.ssh/id_ed25519"
answerfile_name      = "answers"

# =========================
# Alpine ISO (public)
# =========================
alpine_iso_url      = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-virt-3.23.2-x86_64.iso"
alpine_iso_checksum = "file:https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-virt-3.23.2-x86_64.iso.sha256"

# Nếu môi trường khác: packer host không có internet nhưng PVE có internet => set true
iso_download_pve = false