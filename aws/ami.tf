
data "aws_ami" "ubuntu_x64_image" {
  most_recent = true
  owners      = ["amazon"]
  name_regex  = "^ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20230919$"

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ami" "ubuntu_arm64_image" {
  most_recent = true
  owners      = ["amazon"]
  name_regex  = "^ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-arm64-server-20230919$"

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

