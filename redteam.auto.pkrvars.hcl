proxmox_url      = "https://10.10.100.1:8006/api2/json"
proxmox_username = "root@pam!packer"
proxmox_token    = "28786dd2-1eed-44e6-b8a4-dc2221ce384d"
proxmox_node     = "homelab"
proxmox_insecure_skip_tls_verify = true
vm_id = 0

disk_storage_pool = "hdd-lvm"
disk_size         = "8G"
cpu_cores         = 2
memory_mb         = 2048

template_prefix = "tpl"
hostname        = "red-router"

wan_bridge     = "vmbr10"
transit_bridge = "transit"
red_bridge     = "red"

live_wan_iface = "eth0"

# WAN (để Packer SSH sau cài)
wan_ip_cidr = "10.10.100.22/24"
wan_gateway = "10.10.100.1"
dns_server  = "1.1.1.1"

ssh_host = "10.10.100.22"
ssh_private_key_file = "/root/.ssh/id_ed25519"

answerfile_name = "answers"