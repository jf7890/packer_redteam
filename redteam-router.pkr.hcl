packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.0"
    }
  }
}

locals {
  template_name = "${var.template_prefix}-${var.hostname}"
}

source "proxmox-iso" "redteam_router" {
  # =========================
  # Proxmox connection
  # =========================
  proxmox_url              = var.proxmox_url
  insecure_skip_tls_verify = var.proxmox_insecure_skip_tls_verify

  username = var.proxmox_username
  token    = var.proxmox_token
  node     = var.proxmox_node

  vm_id   = var.vm_id
  vm_name = local.template_name

  template_name        = local.template_name
  template_description = "Alpine RedTeam Router (FRR + nftables NAT + key-only SSH + cloud-init + qemu-guest-agent)"
  tags                 = "alpine;router;redteam;template"

  # =========================
  # Boot ISO
  # =========================
  boot_iso {
    type             = "scsi"
    iso_url          = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-virt-3.23.2-x86_64.iso"
    iso_checksum     = "file:https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/x86_64/alpine-virt-3.23.2-x86_64.iso.sha256"
    iso_storage_pool = var.iso_storage_pool

    iso_download_pve = true
    unmount          = true
  }

  # =========================
  # VM hardware
  # =========================
  cores    = var.cpu_cores
  sockets  = 1
  cpu_type = "host"
  memory   = var.memory_mb

  os   = "l26"
  bios = "seabios"

  scsi_controller = "virtio-scsi-single"
  qemu_agent      = true

  # =========================
  # Disk
  # =========================
  disks {
    type         = "scsi"
    disk_size    = var.disk_size
    storage_pool = var.disk_storage_pool

    format     = "raw"
    cache_mode = "none"

    io_thread = true
    discard   = true
  }

  # =========================
  # Network adapters
  # =========================
  network_adapters {
    model  = "virtio"
    bridge = var.wan_bridge
  }

  network_adapters {
    model  = "virtio"
    bridge = "transit" # [Suy luận] sửa nếu bridge transit của bạn khác tên
  }

  network_adapters {
    model  = "virtio"
    bridge = "red" # [Suy luận] sửa nếu bridge red của bạn khác tên
  }

  # =========================
  # Packer HTTP server
  # =========================
  http_directory = "http"

  # =========================
  # Boot & unattended install
  # - WAN dùng DHCP (eth0 hardcode)
  # - Cài qemu-guest-agent TRƯỚC reboot để Packer tự lấy IP bằng agent
  # =========================
  boot_wait = "10s"

  boot_command = [
    "<enter><wait>",
    "root<enter><wait>",

    # Live ISO: bật eth0 + DHCP để kéo answerfile
    "ip link set eth0 up<enter>",
    "udhcpc -i eth0<enter>",
    "echo nameserver ${var.dns_server} > /etc/resolv.conf<enter>",

    # Fetch answerfile
    "wget -O /tmp/answers http://{{ .HTTPIP }}:{{ .HTTPPort }}/${var.answerfile_name}<enter>",

    # Install OS + inject qemu-guest-agent into installed system then reboot
    "ERASE_DISKS=/dev/sda setup-alpine -e -f /tmp/answers && mount /dev/sda3 /mnt && apk add --no-cache --root /mnt qemu-guest-agent && chroot /mnt rc-update add qemu-guest-agent default && reboot<enter>"
  ]

  # =========================
  # SSH communicator
  # - Không set ssh_host: sẽ tự discover bằng qemu-guest-agent
  # =========================
  communicator = "ssh"
  ssh_username = "root"
  ssh_port     = 22
  ssh_timeout  = "25m"

  ssh_private_key_file = pathexpand(var.ssh_private_key_file)

  # =========================
  # Cloud-Init drive for template
  # =========================
  cloud_init              = true
  cloud_init_storage_pool = var.cloud_init_storage_pool
}

build {
  sources = ["source.proxmox-iso.redteam_router"]

  provisioner "shell" {
    script = "scripts/provision-red.sh"
  }
}
