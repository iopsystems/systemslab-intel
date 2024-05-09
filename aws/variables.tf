# variables

variable "aws_region" {
  default = "us-west-2"
}

variable "aws_zone" {
  default = "us-west-2b"
}

variable "aws_cred_file" {
  default = "~/.aws/credentials"
}

// TODO: put the user info with the AMI
variable "ubuntu_ssh_user" {
  default = "ubuntu"
}
variable "aws_private_key_file" {
  default = "~/.aws/systemslab_aws_key"
}
