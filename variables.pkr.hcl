variable "proxmox_url" { type = string }
variable "proxmox_username" { type = string }
variable "proxmox_token" { type = string, sensitive = true }
variable "proxmox_node" { type = string }
variable "proxmox_insecure_skip_tls_verify" { type = bool, default = true }
variable "vm_id" { type = number, default = 0 }

variable "disk_storage_pool" { type = string, default = "local-lvm" }
variable "disk_size" { type = string, default = "8G" }
variable "cpu_cores" { type = number, default = 2 }
variable "memory_mb" { type = number, default = 512 }

variable "template_prefix" { type = string, default = "tpl" }
variable "hostname" { type = string, default = "red-router" }

variable "wan_bridge" { type = string }
variable "transit_bridge" { type = string }
variable "red_bridge" { type = string }

variable "live_wan_iface" { type = string, default = "eth0" }
variable "wan_ip_cidr" { type = string }
variable "wan_gateway" { type = string }
variable "dns_server" { type = string, default = "1.1.1.1" }

variable "ssh_host" { type = string }
variable "ssh_private_key_file" { type = string }

variable "answerfile_name" {
  type    = string
  default = "answers"
}
