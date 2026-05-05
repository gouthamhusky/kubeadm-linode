# kubeadm Linode

Spins up **1 control plane + 2 worker nodes** on Linode (us-ord) running Ubuntu 22.04.
Bootstrap script installs `containerd`, `kubeadm`, `kubelet`, and `kubectl` on every node automatically.

## Directory structure

```
kubeadm-linode/
├── main.tf                        # Linode instances + hosts provisioner
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example       # Copy → terraform.tfvars and fill in
├── .gitignore
└── scripts/
    ├── bootstrap.sh               # Runs on each VM at first boot (cloud-init)
    └── push-hosts.sh.tpl          # Populates /etc/hosts on all nodes
```

## Prerequisites

- [Terraform >= 1.3](https://developer.hashicorp.com/terraform/install)
- A [Linode API token](https://cloud.linode.com/profile/tokens) with Read/Write on Linodes
- An SSH keypair (`~/.ssh/id_rsa` / `id_rsa.pub` or change the paths in tfvars)

## 1. Provision the VMs

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your token, password, SSH key paths

terraform init
terraform plan
terraform apply
```

Terraform will:
1. Create 3 Linodes (controlplane, node01, node02) in `us-ord`
2. Run `bootstrap.sh` on each via cloud-init (installs kubeadm toolchain, ~3–5 min)
3. Push `/etc/hosts` entries so nodes resolve each other by hostname

After apply, you'll see output like:
```
ssh_commands = [
  "ssh root@45.33.x.x  # controlplane",
  "ssh root@45.33.x.y  # node01",
  "ssh root@45.33.x.z  # node02",
]
```

## 2. Wait for bootstrap to finish

SSH in and watch the log:
```bash
ssh root@<controlplane-ip>
tail -f /var/log/bootstrap.log
# Wait until you see: "Bootstrap complete for controlplane"
```

## 3. Initialize the control plane

```bash
# On controlplane — use the private IP for the API server
PRIVATE_IP=$(ip addr show eth1 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

kubeadm init \
  --apiserver-advertise-address=$PRIVATE_IP \
  --pod-network-cidr=192.168.0.0/16 \
  --node-name=controlplane
```

Then set up kubectl:
```bash
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

## 4. Install a CNI (Calico)

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

Wait for core-dns to come up:
```bash
kubectl get pods -n kube-system --watch
```

## 5. Join the worker nodes

Back on the controlplane, get the join command:
```bash
kubeadm token create --print-join-command
```

Copy the output and run it on **each worker node**:
```bash
# On node01 and node02:
kubeadm join <controlplane-private-ip>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

## 6. Verify the cluster

```bash
# On controlplane:
kubectl get nodes
# NAME           STATUS   ROLES           AGE   VERSION
# controlplane   Ready    control-plane   5m    v1.29.x
# node01         Ready    <none>          2m    v1.29.x
# node02         Ready    <none>          2m    v1.29.x
```

## Tear down

```bash
terraform destroy
```

## Cost estimate (us-ord)

| Node         | Plan           | vCPU | RAM  | $/month |
|--------------|----------------|------|------|---------|
| controlplane | g6-standard-2  | 2    | 4 GB | ~$18    |
| node01       | g6-standard-1  | 1    | 2 GB | ~$12    |
| node02       | g6-standard-1  | 1    | 2 GB | ~$12    |
| **Total**    |                |      |      | **~$42/mo** (~$0.06/hr) |

Remember to `terraform destroy` when you're done practicing!
