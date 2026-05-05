output "controlplane" {
  description = "Control plane node IPs"
  value = {
    public_ip  = linode_instance.controlplane.ip_address
    private_ip = linode_instance.controlplane.private_ip_address
  }
}

output "workers" {
  description = "Worker node IPs"
  value = [
    for w in linode_instance.workers : {
      label      = w.label
      public_ip  = w.ip_address
      private_ip = w.private_ip_address
    }
  ]
}

output "ssh_commands" {
  description = "SSH commands to connect to each node"
  value = concat(
    ["ssh root@${linode_instance.controlplane.ip_address}  # controlplane"],
    [
      for i, w in linode_instance.workers :
      "ssh root@${w.ip_address}  # node0${i + 1}"
    ]
  )
}
