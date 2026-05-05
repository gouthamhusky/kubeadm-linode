#!/bin/bash
# bootstrap.sh — Runs on every node at first boot via cloud-init (user_data).
# Prepares Ubuntu 22.04 for kubeadm installation.
# Does NOT run kubeadm init/join — you do that manually.

set -euo pipefail
exec > /var/log/bootstrap.log 2>&1

HOSTNAME="${hostname}"
NODE_ROLE="${node_role}"

echo "=== Starting bootstrap for $HOSTNAME ($NODE_ROLE) ==="

# ─── Hostname ────────────────────────────────────────────────────────────────
hostnamectl set-hostname "$HOSTNAME"

# ─── Disable swap (required by kubeadm) ──────────────────────────────────────
swapoff -a
sed -i '/\bswap\b/d' /etc/fstab

# ─── Kernel modules required by containerd / Kubernetes ──────────────────────
cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# ─── sysctl params ───────────────────────────────────────────────────────────
cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# ─── Install containerd ───────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release apt-transport-https

# Docker/containerd repo
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq containerd.io

# Configure containerd to use systemd cgroup driver
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# ─── Install kubeadm, kubelet, kubectl ───────────────────────────────────────
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update -qq
apt-get install -y -qq kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

systemctl enable kubelet

# ─── Done ─────────────────────────────────────────────────────────────────────
echo "=== Bootstrap complete for $HOSTNAME ==="
echo "You can now SSH in and run kubeadm init (controlplane) or kubeadm join (workers)."
