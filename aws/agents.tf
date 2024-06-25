
# Agent template configs.
#
# See the comments in agents_expanded to see what they do.
locals {
  agents = [
    # Kafka Gen 4 Vs. Gen 3
    # two m7i.2xlarge client
    {
      type = "m7i.2xlarge",
      count = 0
      groups = ["kafka"]
      tags = ["kafka", "client"]
      root_volume_type = "gp3"
      root_volume_size = "200"
      autoshutdown = false
    },
    # one m7i.xlarge broker
    {
      type = "m7i.xlarge",
      count = 0
      groups = ["kafka"]
      tags = ["kafka", "broker"]
      root_volume_type = "gp3"
      root_volume_size = "200"
      autoshutdown = false
    },
    # one m6i.xlarge broker
    {
      type = "m6i.xlarge",
      count = 0
      groups = ["kafka"]
      tags = ["kafka", "broker"]
      root_volume_type = "gp3"
      root_volume_size = "200"
      autoshutdown = false
    }, 
    # two zookeeper
    {
      type   = "t3.large"
      count  = 0
      tags   = ["kafka", "zookeeper"]
      groups = ["kafka"]    
      autoshutdown = false
    },
  ]
}

locals {
  agents_expanded = [
    for instance in local.agents : {
      # The number of identical instances to create.
      #
      # To get rid of all the instances set this to 0.
      count = instance.count

      # The instance type.
      type = instance.type

      # Whether this instance is a spot instance.
      spot = try(instance.spot, false),

      # The base name for the instance. This is optional, if not specified then
      # one will be constructed based on the instance type.
      #
      # The full agent name will be "${basename}-${index}".
      basename = try(instance.basename, replace(instance.type, ".", "-"))

      # The machine image to use.
      #
      # If not provided then amd64 ubuntu image will be used.
      ami = try(instance.ami, data.aws_ami.ubuntu_x64_image.id)

      # The AWS availablility zone to run the instance in.
      zone = try(instance.zone, var.aws_zone)

      # Ansible groups that this host belongs to.
      #
      # Every agent declared here belongs to the agent group by default. You
      # can add additional groups here for group-specific plays to be applied
      # in the ansible playbook.
      groups = try(instance.groups, [])

      # Additional tags for the agent.
      #
      # The instance will always be tagged with its own name _and_ the instance
      # type. This gives you additional tags on top of that.
      tags = try(instance.tags, [])

      # Default root block: 100GB GP3 with the free tier 3000 IOPs
      root_volume_size = try(instance.root_volume_size, 100)
      root_volume_type = try(instance.root_volume_type, "gp3")
      root_volume_iops = try(instance.root_volume_iops, 3000)

      # Automatically shut down the instance after 30 minutes of inactivity
      autoshutdown = try(instance.autoshutdown, true),
    }
  ]

  # Expand out count to make the actual agent instances.
  agent_instances = flatten([
    for instance in local.agents_expanded : [
      for i in range(1, instance.count + 1) : {
        name             = "${instance.basename}-${i}"
        type             = instance.type
        spot             = instance.spot
        ami              = instance.ami
        zone             = instance.zone
        groups           = concat(instance.groups, instance.autoshutdown ? ["autoshutdown"] : [])
        root_volume_type = instance.root_volume_type
        root_volume_size = instance.root_volume_size
        root_volume_iops = instance.root_volume_iops
        tags = flatten([
          instance.tags,
          ["${instance.basename}-${i}", "${instance.type}"]
        ])
      }
    ]
  ])
}

resource "aws_instance" "agents" {
  for_each = { for agent in local.agent_instances : agent.name => agent }

  availability_zone = each.value.zone
  ami               = each.value.ami
  instance_type     = each.value.type
  security_groups   = [var.systemslab_agent_sg]
  key_name          = var.systemslab_agent_key

  instance_initiated_shutdown_behavior = each.value.spot ? null : "terminate"

  tags = {
    Name = each.value.name
  }

  root_block_device {
    volume_size = each.value.root_volume_size
    volume_type = each.value.root_volume_type
    iops        = each.value.root_volume_iops
  }

  connection {
    type        = "ssh"
    user        = var.ubuntu_ssh_user
    private_key = file(var.aws_private_key_file)
    host        = self.public_dns
  }

  dynamic "instance_market_options" {
    for_each = each.value.spot ? toset([1]) : toset([])

    content {
      market_type = "spot"
    }
  }

  # Wait for the host to be provisioned before completing
  provisioner "remote-exec" {
    inline = ["true"]
  }
}

# The inventory file for ansible looks like this:
#
# <group>:
#   hosts:
#     <host>:
#       <var>: <value>
#
# This is rather different from the format of local.agent_instances so we need
# to do a few rounds of expanding things and then regrouping them.
locals {
  instances = [
    for agent in local.agent_instances : {
      name       = agent.name
      groups     = agent.groups
      tags       = agent.tags
      public_dns = aws_instance.agents[agent.name].public_dns
    }
  ]

  instances_expanded = flatten(flatten([
    [
      for instance in local.instances : [
        for group in instance.groups : {
          group = group
          name  = instance.public_dns
          vars  = {}
        }
      ]
    ],
    [
      for instance in local.instances : [{
        group = "agent"
        name  = instance.public_dns
        vars = {
          agent_config = templatefile("agent.toml.tftpl", {
            systemslab_url = "http://${var.systemslab_server_ip}:3000"
            agent_name     = instance.name
            agent_tags     = flatten([[instance.public_dns], instance.tags])
          })
        }
      }]
    ]
  ]))

  grouped = {
    for item in local.instances_expanded : item.group => item...
  }

  inventory = {
    for group, instances in local.grouped : group => {
      hosts = {
        for instance in instances : instance.name => instance.vars
      }
    }
  }
}

resource "local_file" "ansible_inventory" {
  filename        = "inventory.yaml"
  content         = yamlencode(local.inventory)
  file_permission = "0644"
}

