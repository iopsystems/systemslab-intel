# variables

variable "aws_region" {
  default = "us-west-2"
}

variable "aws_zone" {
  default = "us-west-2b"
}

variable "systemslab_server_ip" {
  default = "172.31.11.125"
}

variable "systemslab_agent_key" {
  default = "systemslab_aws_key"
}

variable "systemslab_agent_sg" {
  default = "systemslab-sg"
}

variable "aws_cred_file" {
  default = "~/.aws/credentials"
}

variable "aws_cred_profile" {
  default = "systemslab"
}

// TODO: put the user info with the AMI
variable "ubuntu_ssh_user" {
  default = "ubuntu"
}
variable "aws_private_key_file" {
  default = "~/.aws/systemslab_aws_key"
}
