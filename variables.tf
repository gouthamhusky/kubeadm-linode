variable "linode_token" {
  description = "Linode API token. Set via TF_VAR_linode_token env var or terraform.tfvars."
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Linode region to deploy into."
  type        = string
  default     = "us-ord"
}

variable "num_workers" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

# Nanode (1 CPU / 1 GB) is too small for kubeadm.
# Linode 2 GB (g6-standard-1) works for workers; 4 GB for controlplane.
variable "controlplane_type" {
  description = "Linode plan for the control plane node."
  type        = string
  default     = "g6-standard-2"  # 2 vCPU / 4 GB RAM
}

variable "worker_type" {
  description = "Linode plan for worker nodes."
  type        = string
  default     = "g6-standard-1"  # 1 vCPU / 2 GB RAM
}

variable "root_password" {
  description = "Root password for all nodes. Use a strong password or SSH keys only."
  type        = string
  sensitive   = true
}

variable "ssh_public_key_path" {
  description = "Path to your SSH public key file."
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  description = "Path to your SSH private key file (used by the hosts provisioner)."
  type        = string
  default     = "~/.ssh/id_rsa"
}
