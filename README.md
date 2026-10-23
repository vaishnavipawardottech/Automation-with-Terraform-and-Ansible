# Terraform and Ansible AWS Automation

<!-- Screenshot placeholder: add a project workflow or successful Ansible run image here. -->


This project demonstrates a two-stage infrastructure automation workflow on
Amazon Web Services (AWS):

1. **Terraform** provisions an Ansible control node and worker EC2 instances
   running Ubuntu, Red Hat, and Amazon Linux.
2. **Ansible** connects from the control node to the workers and configures
   them. The included playbook installs and enables Docker on each supported
   operating system.

Terraform also generates an Ansible inventory automatically from the
provisioned instance metadata. The inventory groups hosts by operating system
and uses private IP addresses for worker-to-worker communication.

> This repository is intended as a learning and lab environment. Review the
> security-group rules, AMI IDs, region, and instance sizes before using it for
> production workloads.

## Architecture

```text
Your workstation
      |
      | Terraform
      v
AWS default VPC
  ├── control-node-ubuntu  (Ansible control node)
  ├── worker-ubuntu
  ├── worker-redhat
  └── worker-amazon
      |
      | Ansible over SSH using private IP addresses
      v
Docker installed and managed on all worker instances
```

The default Terraform configuration creates:

| Instance | Operating system | SSH user | Ansible inventory group |
| --- | --- | --- | --- |
| `control-node-ubuntu` | Ubuntu | `ubuntu` | `control` |
| `worker-ubuntu` | Ubuntu | `ubuntu` | `ubuntu_workers` |
| `worker-redhat` | Red Hat | `ec2-user` | `redhat` |
| `worker-amazon` | Amazon Linux | `ec2-user` | `amazon` |

All workers are also members of the `workers` parent group, which is the
target used by the Docker playbook.

## Repository structure

```text
.
├── playbooks/
│   ├── install_docker.yml
│   └── roles/docker/
│       ├── tasks/
│       │   ├── install_ubuntu.yml
│       │   ├── install_redhat.yml
│       │   └── install_amazon.yml
│       └── handlers/
├── terraform/
│   ├── ec2.tf                 # EC2 instances, key pair, and security group
│   ├── generate_inventory.tf  # Generates the Ansible inventory
│   ├── templates/inventory.tpl
│   ├── variables.tf           # Region, AMIs, users, and instance definitions
│   └── providers.tf
├── example_inventory.ini       # Example inventory with SSH settings
└── README.md
```

## Prerequisites

Install or have access to the following:

- An AWS account with permission to manage EC2, VPC security groups, and key
  pairs.
- AWS credentials configured for the AWS provider. For example, use the AWS
  CLI profile or the standard `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and
  optional `AWS_SESSION_TOKEN` environment variables.
- [Terraform](https://developer.hashicorp.com/terraform/install), compatible
  with the AWS provider version declared in `terraform/terraform.tf`.
- An SSH client. OpenSSH is available on most Linux distributions, macOS, and
  current Windows installations.
- An Ansible installation on the control node. The control node must be able
  to reach the workers over their private IP addresses.

## 1. Clone the repository

```bash
git clone https://github.com/vaishnavipawardottech/Automation-with-Terraform-and-Ansible.git
cd Automation-with-Terraform-and-Ansible
```

## 2. Prepare the SSH key pair

The Terraform configuration creates an AWS key pair from
`terraform/terra-key-ansible.pub`. The public key is intentionally excluded
from version control, so create or obtain the key pair before running
Terraform.

For a new key pair, run:

```bash
ssh-keygen -t ed25519 -f terraform/terra-key-ansible
```

This creates:

- `terraform/terra-key-ansible` — private key; keep it secret.
- `terraform/terra-key-ansible.pub` — public key used by Terraform.

The private key must eventually be available on the control node. The examples
below use `~/keys/terra-key-ansible` on that machine.

On Linux or macOS, restrict the private-key permissions:

```bash
chmod 400 terraform/terra-key-ansible
```

On Windows, protect the private key using the file-permission controls
appropriate for your environment. Never commit either key to the repository.

## 3. Configure and apply Terraform

Change to the Terraform directory:

```bash
cd terraform
```

Initialize the working directory:

```bash
terraform init
```

Validate the configuration and review the proposed resources:

```bash
terraform validate
terraform plan
```

If the plan is correct, create the infrastructure:

```bash
terraform apply
```

Confirm the apply when Terraform prompts for approval. Terraform creates the
EC2 instances and writes the generated inventory to:

```text
inventories/dev/hosts.ini
```

The generated inventory includes the control node and workers discovered from
the Terraform resources. It uses the control node's local connection and the
workers' private IP addresses.

Return to the repository root before continuing with the SSH and Ansible
steps:

```bash
cd ..
```

### Optional Terraform overrides

The defaults can be overridden without editing the Terraform source. For
example:

```bash
terraform apply \
  -var='aws_region=us-east-1' \
  -var='instance_type=t3.small' \
  -var='volume_size=20'
```

The AMI IDs in `terraform/variables.tf` are region-specific. If you change
`aws_region`, provide AMI IDs that exist in that region by supplying a
replacement `instances` map through a `.tfvars` file or another Terraform
variable mechanism.

## 4. Install Ansible on the control node

Find the public IP address of `control-node-ubuntu` in the AWS EC2 console,
then connect to it from your workstation:

```bash
ssh -i terraform/terra-key-ansible ubuntu@<CONTROL_NODE_PUBLIC_IP>
```

Install Ansible on the control node. On Ubuntu, the following is one supported
approach:

```bash
sudo apt update
sudo apt install -y software-properties-common
sudo apt-add-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible
ansible --version
```

## 5. Copy the inventory and key to the control node

Run these commands from your workstation, replacing
`<CONTROL_NODE_PUBLIC_IP>` with the public IP address of the control node:

```bash
scp -i terraform/terra-key-ansible \
  inventories/dev/hosts.ini \
  ubuntu@<CONTROL_NODE_PUBLIC_IP>:/home/ubuntu/inventory.ini

scp -i terraform/terra-key-ansible \
  terraform/terra-key-ansible \
  ubuntu@<CONTROL_NODE_PUBLIC_IP>:/home/ubuntu/terra-key-ansible
```

On the control node, secure the copied key:

```bash
chmod 400 ~/terra-key-ansible
```

Add the SSH settings required by Ansible to the `[all:vars]` section of
`~/inventory.ini`:

```ini
[all:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_private_key_file=/home/ubuntu/terra-key-ansible
ansible_host_key_checking=false
```

`ansible_host_key_checking=false` is convenient for a disposable lab whose
instances may be recreated. For a longer-lived environment, prefer host-key
verification instead of disabling this protection.

## 6. Create the Ansible role

Ansible roles are reusable units that organize tasks, handlers, variables,
templates, and files. The `ansible-galaxy init` command creates the standard
role directory structure automatically.

Connect to the control node and create the role structure:

```bash
ssh -i terraform/terra-key-ansible ubuntu@<CONTROL_NODE_PUBLIC_IP>

mkdir -p ~/playbooks
cd ~/playbooks
ansible-galaxy init roles/docker
```

This creates a structure similar to:

```text
playbooks/roles/docker/
├── defaults/main.yml
├── handlers/main.yml
├── meta/main.yml
├── README.md
├── tasks/main.yml
├── tests/
│   ├── inventory
│   └── test.yml
├── vars/main.yml
├── files/
└── templates/
```

Add the role's implementation under the generated directories. For this
project, the role includes:

- `tasks/main.yml` to select the operating-system-specific task file;
- `tasks/install_ubuntu.yml` for Ubuntu;
- `tasks/install_redhat.yml` for Red Hat;
- `tasks/install_amazon.yml` for Amazon Linux; and
- `handlers/main.yml` for restarting Docker when required.

The playbook uses the role through `roles/docker`:

```yaml
- name: install Docker on all machines
  hosts: workers
  become: true
  roles:
    - role: docker
```

### Optional shortcut: copy the completed role from this repository

Instead of creating and filling the role files manually, copy the completed
playbooks directory from your workstation:

```bash
scp -i terraform/terra-key-ansible -r \
  playbooks \
  ubuntu@<CONTROL_NODE_PUBLIC_IP>:/home/ubuntu/
```

This copies `install_docker.yml` and the already implemented
`roles/docker` role to the control node. If you already ran
`ansible-galaxy init`, replace the generated role with the repository version
or copy only the missing task and handler files.

## 7. Verify connectivity

From the control node, test all worker hosts:

```bash
ansible -i ~/inventory.ini workers -m ping
```

The command should return `SUCCESS` for `worker-ubuntu`, `worker-redhat`, and
`worker-amazon`. Use the generated group names to test a specific platform:

```bash
ansible -i ~/inventory.ini ubuntu_workers -m ping
ansible -i ~/inventory.ini redhat -m ping
ansible -i ~/inventory.ini amazon -m ping
```

The control node is configured with `ansible_connection=local`, so it does not
need an SSH connection to itself.

## 8. Run the Ansible Docker playbook

From the control node:

```bash
cd ~/playbooks
ansible-playbook -i ~/inventory.ini install_docker.yml
```

The playbook:

- gathers facts on all workers;
- selects the operating-system-specific Docker installation tasks;
- installs Docker and any required packages or repositories;
- starts Docker and enables it at boot;
- adds `ubuntu` and `ec2-user` to the Docker group where applicable; and
- verifies the installed Docker version.

After the playbook completes, verify Docker on the workers:

```bash
ansible -i ~/inventory.ini workers -m command -a "docker --version"
```

Users added to the Docker group may need to start a new shell session before
running Docker without `sudo`.

## Updating the infrastructure

After changing Terraform configuration or variables:

```bash
cd terraform
terraform plan
terraform apply
```

When instances are replaced, regenerate and recopy
`inventories/dev/hosts.ini` and the SSH key to the control node before running
Ansible again.

## Destroying the lab

When the lab is no longer needed, remove the AWS resources to avoid ongoing
charges:

```bash
cd terraform
terraform destroy
```

Review the destroy plan and confirm only the resources belonging to this lab
will be removed.

## Security and cost notes

- The current security group allows inbound SSH, HTTP, and HTTPS from
  `0.0.0.0/0`. Restrict the CIDR ranges to trusted addresses before using this
  outside a temporary lab.
- Do not commit private keys, public keys, Terraform state, or `.tfvars` files
  containing secrets.
- Terraform state can contain sensitive infrastructure details. Store it
  securely and consider a remote, encrypted backend for team usage.
- EC2 instances, storage, and network resources can incur AWS charges. Destroy
  the lab when it is not in use.
- Review the AMI IDs before deployment because AMI availability and support
  vary by AWS region and over time.

## Troubleshooting

### `Permission denied (publickey)`

Check that:

1. the public key used by Terraform matches the private key used by SSH;
2. the private key has restrictive permissions;
3. the correct SSH username is being used (`ubuntu` or `ec2-user`); and
4. the private key path in `ansible_ssh_private_key_file` is correct on the
   control node.

### `Host key verification failed`

For a disposable lab, use the inventory setting shown above to disable host
key checking, or remove the stale host entry from `~/.ssh/known_hosts` and
connect again after confirming the instance identity. For production, keep
host-key checking enabled and manage known hosts explicitly.

### Ansible reports that no hosts matched

Make sure the generated inventory was copied after the latest Terraform
apply, and use `workers` or one of the defined groups (`ubuntu_workers`,
`redhat`, or `amazon`) rather than an undefined group such as `servers`.

### The inventory was not generated

Run Terraform from the `terraform/` directory and confirm that
`terraform apply` completed successfully. The `local_file` resource writes the
inventory to `inventories/dev/hosts.ini` relative to the repository root.

## License

No license has been specified for this repository. Add a license file before
redistributing the project or incorporating it into another project.
