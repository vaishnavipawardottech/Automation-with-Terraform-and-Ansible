locals {
  inventory = { for name, inst in aws_instance.my_instance : name => {
    public_ip  = inst.public_ip
    private_ip = inst.private_ip
    user       = var.instances[name].user
    os_family  = var.instances[name].os_family
  } }

  control_hosts       = { for name, inst in local.inventory : name => inst if can(regex("control", name)) }
  ubuntu_worker_hosts = { for name, inst in local.inventory : name => inst if inst.os_family == "ubuntu" && can(regex("worker", name)) }
  redhat_hosts        = { for name, inst in local.inventory : name => inst if inst.os_family == "redhat" }
  amazon_hosts        = { for name, inst in local.inventory : name => inst if inst.os_family == "amazon" }
}

# Teaching inventory — used FROM the control node.
# Control node manages itself locally and reaches workers over PRIVATE IPs.
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/templates/inventory.tpl", {
    control        = local.control_hosts
    ubuntu_workers = local.ubuntu_worker_hosts
    redhat         = local.redhat_hosts
    amazon         = local.amazon_hosts
  })

  filename        = "${path.module}/../inventories/dev/hosts.ini"
  file_permission = "0644"
}

# Bootstrap inventory — used ONCE FROM your laptop to configure the control
# node (install Ansible, push the SSH key, clone the repo). Public IP + key.
resource "local_file" "bootstrap_inventory" {
  content = templatefile("${path.module}/templates/bootstrap.tpl", {
    ssh_key_path = var.ssh_key_path
    control      = local.control_hosts
  })

  filename        = "${path.module}/../inventories/dev/bootstrap.ini"
  file_permission = "0644"
}