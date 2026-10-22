resource "aws_key_pair" "ansible" {
  key_name   = var.key_name
  public_key = file("${path.module}/terra-key-ansible.pub")
}

data "aws_vpc" "default" {
  default = true
}

resource "aws_security_group" "ansible_lab" {
  name        = "ansible-lab-sg"
  description = "Security group for Ansible lab instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name = "ansible-lab-sg"
  }
}

resource "aws_instance" "my_instance" {
  for_each = var.instances

  ami                    = each.value.ami
  instance_type          = each.value.instance_type
  key_name               = aws_key_pair.ansible.key_name
  vpc_security_group_ids = [aws_security_group.ansible_lab.id]

  root_block_device {
    volume_size = var.volume_size
    volume_type = "gp3"
  }

  tags = {
    Name      = each.key
    OSFamily  = each.value.os_family
    ManagedBy = "terraform"
    Project   = "ansible-training"
  }

  depends_on = [aws_security_group.ansible_lab, aws_key_pair.ansible]
}