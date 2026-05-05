terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 2.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "linode" {
  token = var.linode_token
}

# ─── SSH Key ─────────────────────────────────────────────────────────────────

resource "linode_sshkey" "kubeadm" {
  label   = "kubeadm-key"
  ssh_key = file(var.ssh_public_key_path)
}

# ─── Private VLAN (for inter-node communication) ──────────────────────────────

# We use a private IP on each node via Linode's private networking.
# All nodes go into the same region so they can reach each other
# on their private IPs without going over the public internet.

# ─── Control Plane ───────────────────────────────────────────────────────────

resource "linode_instance" "controlplane" {
  label           = "controlplane"
  region          = var.region
  type            = var.controlplane_type
  image           = "linode/ubuntu22.04"
  authorized_keys = [linode_sshkey.kubeadm.ssh_key]
  root_pass       = var.root_password

  # Enable private networking so nodes can talk to each other
  private_ip = true

  tags = ["kubeadm", "controlplane"]

  # Bootstrap script: sets hostname, enables kernel modules,
  # configures sysctl, and installs container runtime + kubeadm tooling
  metadata {
    user_data = base64encode(templatefile("${path.module}/scripts/bootstrap.sh", {
      hostname   = "controlplane"
      node_role  = "controlplane"
    }))
  }
}

# ─── Worker Nodes ─────────────────────────────────────────────────────────────

resource "linode_instance" "workers" {
  count           = var.num_workers
  label           = "node0${count.index + 1}"
  region          = var.region
  type            = var.worker_type
  image           = "linode/ubuntu22.04"
  authorized_keys = [linode_sshkey.kubeadm.ssh_key]
  root_pass       = var.root_password

  private_ip = true

  tags = ["kubeadm", "worker"]

  metadata {
    user_data = base64encode(templatefile("${path.module}/scripts/bootstrap.sh", {
      hostname   = "node0${count.index + 1}"
      node_role  = "worker"
    }))
  }
}

# ─── /etc/hosts provisioner ───────────────────────────────────────────────────
# Runs after all VMs exist; pushes /etc/hosts to every node so they can
# resolve each other by hostname (same as the Vagrantfile did).

resource "null_resource" "etc_hosts" {
  depends_on = [
    linode_instance.controlplane,
    linode_instance.workers,
  ]

  # Re-run if any node IP changes
  triggers = {
    controlplane_ip = linode_instance.controlplane.private_ip_address
    worker_ips      = join(",", linode_instance.workers[*].private_ip_address)
  }

  provisioner "local-exec" {
    command = templatefile("${path.module}/scripts/push-hosts.sh.tpl", {
      controlplane_ip      = linode_instance.controlplane.private_ip_address
      controlplane_pub_ip  = linode_instance.controlplane.ip_address
      worker_private_ips   = linode_instance.workers[*].private_ip_address
      worker_public_ips    = linode_instance.workers[*].ip_address
      num_workers          = var.num_workers
      ssh_private_key_path = var.ssh_private_key_path
    })
  }
}
