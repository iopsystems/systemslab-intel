# Running Kafka Experiments on Systemslab
This document shows how to run Kafka experiments in Systemslab on AWS.

The resources we need are:
- One Systemslab server instance, we suggest one c5.xlarge with 100 GB gp3 storage. We also use this instance as the control machine to create agents, submit experiments, and analyse experiment artifacts.
- Multiple Systemslab agent instances for executing the Kafka experiments. We provide Terraform and Ansible scripts to create agents automatically.
- One S3 bucket for storing the experiment artifacts. 

You need to prepare the AWS environment, create one EC2 instance and deploy the Systemslab server there. Then you can use Terraform & Ansible to create multiple Systemslab agents from the server instance. After the agents are ready, you can submit Kafka experiments to the server. The server schedules the experiment on the agents, run the experiment, and store the artifacts in the S3 bucket. The Systemslab server also provides http APIs and a web UI for checking the status of the submitted experiments. After the experiments are finished, their artifacts are stored in the S3 bucket. You can use the Systemslab CLI, http APIs, or the web UI to download the artifacts.


## Prepare AWS EC2 and create the Systemslab server instance

- Enable AWS EC2 cli access. We suggest creating a dedicated user `systemslab` for the Systemslab service.
- Create a new security group `systemslab-sg` and enable all internal inbound and out bond traffics. For external traffics, please allow downloading Systemslab packages from https://packages.cloud.google.com, and ssh traffics between your local machine and Systemslab instances. Here is one example that enables all outbound, all internal inbound, and the external inbound SSH traffic.
    ```ingress {
       description = "internal inbound"
         from_port   = 0
         to_port     = 0
         protocol    = "-1"
         cidr_blocks = ["172.31.0.0/16"]
       }
       ingress {
         description = "ssh"
         from_port   = 22
         to_port     = 22
         protocol    = "tcp"
         cidr_blocks = ["0.0.0.0/0"]
       }
       egress {
         description = "outbound"
         from_port   = 0
         to_port     = 0
         protocol    = "-1"
         cidr_blocks = ["0.0.0.0/0"]
       }
    }
- Create a new EC2 key pair `systemslab_aws_key` and download the private key

The Systemslab server needs one x86 EC2 instance with four or more vCPUs, 8 GB memory, 100 GB EBS storage, and one S3 bucket to store the experiment artifacts. Both Debian-based distributions, such as Ubuntu, and Amazon Linux are supported. We suggest using one c5.xlarge which is the cheapest instance with 4 x86 vCPUs, 100 GB GP3 EBS root disk, and ubuntu 22.04.

Followng these steps to setup and config the server, more documents can be found [here](https://docs.iop.systems/install) and [here](https://docs.iop.systems/config):
* Create one c5.xlarge in the `systemslab-sg` security group with the EC2 key pair `systemslab_aws_key` attached, 100 GB gp3 root disk, ubuntu 22.04.
* Add a few files to the server instance under `/home/ubuntu/.aws`:
  - `~/.aws/credentials` that has the AWS access key, by default, the Terraform scripts use the `systemslab` profile.
  - `~/.aws/systemslab_aws_key` The private key of the `systemslab_aws_key` pair, The Ansible script use this to config the agents.
  - `~/.aws/systemslab-gcp-creds.json` The access key to access Systemslab's private repo.
* SSH to the server, set up the Systemslab repo and install the server:
  - Download the public repo package  `curl -fsSL "https://storage.googleapis.com/systemslab-public/deb/systemslab-repo-$(lsb_release -sc)_latest_all.deb" -o /tmp/systemslab-repo.deb`
  - Install the package to get the public repo `sudo apt-get install /tmp/systemslab-repo.deb`
  - `sudo apt-get update`
  - Install the private repo `sudo /usr/share/systemslab-repo/setup-repo.sh --credentials ~/.aws/systemslab-gcp-creds.json`
  - `sudo apt-get update`
  - Install the Systemslab server, database, and cli `sudo apt install systemslab-server systemslab-postgresql systemslab-cli`
  - `sudo systemslab-dbctl init --yes`
  - edit `/etc/systemslab/server.toml`, add these lines, cluster_id is just a name to identify this cluster, AWS_ACCESS_KEY and AWS_SECRET_ACCESS_KEY are the keys is in the `~/.aws/credentials` under the `systemslab` profile:
      ```
      cluster_id = "YOUR_COMPANY/YOUR_CLUSTER_NAME"
      [storage]
      bucket = "s3://YOUR_S3_BUCKET_NAME"      
      s3.access_key_id = "AWS_ACCESS_KEY_ID"
      s3.secret_access_key = "AWS_SECRET_ACCESS_KEY"
  - Start the Systemslab server `sudo systemctl enable systemslab-server` then `sudo systemctl start systemslab-server`.
  
By default, systemslab-server listens on the 80 port and hosts a website at http://SERVER_HOST:
- The http://SERVER_HOST:PORT/admin lists admin pages, such as the /admin/hosts showing the agent hosts.
- The http://SERVER_HOST:PORT/queue shows experiments waiting in the queue.
- The http://SERVER_HOST:PORT/experiment/runing lists the IDs of all running experiments.
- The http://SERVER_HOST:PORT/experiment/ID lists informaton of the experiment ID consisting of the experiment name, the jobs, and the artifacts.
- All these information can be queries from the http APIs. The http://SERVER_HOST:PORT/dev/scalar page presents an interactive document of the SystemsLab http APIs.

It's not safe to expose the HTTP interface to public, you can use SSH to forward the server 80 port to your local machine:
- `ssh -NL 9000:localhost:80 SERVER_HOST`, then you can access the website at `http://localhost:9000`.

## Create Systemslab Agents
After the server is running. You can clone this repo and use the Terraform & Ansible scripts under `./aws` to automatically create agents.

After reviewing `./aws/agents` and replace the value of the `systemslab_server_ip` variable in file `./aws/variables.tf`, you can create agents in two steps:
- Enter `./aws`, run `terraform plan` to check the resources to be created then `terraform apply` to create the resources
- Enter `./aws`, run `ansible-playbook ./playbook.yaml` to deploy and config agent hosts.

Below shows how to edit `./aws/agents` and `./aws/variables.tf`.

The `./aws/agents` lists the agents we need to run the single-broker-single-producer Xeon V4 Vs. V3 experiments. Each experiment needs three instances: one Zookeeper, one client, and one broker. We would like to run two experiments in parallel, one on each generation, so create one m7i.xlarge, one m6i.xlarge for brokers, two m7i.2xlarge for the two clients, and two cheap t4g.small for Zookeeper.

To adjust the type and the number of agents, edit the item in the agents array at the top of `./aws/agents.ts`, such as:
```# two m7i.2xlarge client
    {
      # type decides the instance type
      type = "m7i.2xlarge",
      # count decides the number of this type of EC2 instance
      count = 2
      # add these instances to the Ansible host groups, by default, all agents are in the agent group, so the ansible scripts know how to 
      # set up the host
      groups = ["kafka"]
      # by default, agent instances have ["PUBLIC_DNS", "EC2_TYPE", "EC2_TYPE-ID"] default tags, this tags field add more tags to the
      # instances. Systemslab scheduler matches the instance tags with the job tags
      tags = ["kafka"]
      # root disk
      root_volume_type = "gp3"
      # size
      root_volume_size = "200"
      # by default, autoshutdown is true that the instance terminates itself after in the idle state for 30 minutes
      autoshutdown = false
    },
```

The `./aws/variables` lists the key variables:

After the `terraform apply` command, the Ansible inventory file is created at `./aws/
You can use Terraform and Ansible scripts under ./aws to automate the process of creating agent instances and deploying software. 

The Terraform scripts need the AWS EC2 CLI access and the Ansible playbook needs the SSH access to set up the instances:
- Create an IAM user `systemslab` and gives it EC2 access. Add its access key to `~/.aws/credentials`. If you want to use a different user, check how to set the variable below.
- Create an SSH keypair `systemslab_aws_key` and copy the key pairs to `~/.aws/systemslab_aws_key` and `~/.aws/systemslab_aws_key.pub`.

A few variables and config files are needed before using the scripts:
- aws_cred_profile and aws_cred_file in `./aws/variables.tf`. Using `systemslab` profile in `~/.aws/credentials` by default, if you use another AWS user, change the settings.
- systemslab_agent_key in `./aws/variables.tf`. You need to create an AWS EC2 SSH keypair for accessing the agent instances. Put the key pair at `~/.aws/systemslab_aws_key and systemslab_aws_key.pub`.
- aws_region in `./aws/variables.tf`, default us-west-2
- aws_zone in `./aws/variables.tf` default us-west-2b
- systemslab_server_ip in `./aws/variables.tf`, the IP address of the Systemslab server
- Systemslab private repo key at ~/.aws/systemslab_private_repo.json, editable here \TODO

To add new instances, edit aws/agents.tf. It has examples showing how to add agents for the Kafka Xeon Gen 4 Vs. Xeon Gen 3 experiments which One m7i.xlarge and m6i.xlarge for running Kafka brokers, two m7i.2xlarge for clients, and two spot i3en.large instances for Zookeeper.

To create new instances, enter the ./aws directory and initilizae the terraform "terraform init", then run "terraform apply". The autoshutdown is enabled by default. Instances turn themselvies off after 30 minutes idle. If the autoshutdown is disabled (autoshutdown = false), to terminate the instances, change the count field to 0 (count  = 0), then run "terraform apply" again.

The terraform script creates AWS instance and generate one 

To config the agents and deploy software there, run "ansible-pl


## Compose Experiment Specs

## Submit Experiments to The Systemslab

## View the Progress of Experiments

## Analyze Kafka Experiment Artifacts

## References

```ubuntu@systemslab-server:~$ systemslab -h
SystemsLab command-line interface

Usage: systemslab [OPTIONS] <COMMAND>

Commands:
  submit    Submit a new experiment to be run within SystemsLab
  evaluate  Evaluate an experiment specification and output it in json format
  logs      View the logs emitted by an experiment or job
  artifact
  sweep     Perform a sweep over a set of parameters and launch each configuration as an experiment
  export    Export systemslab objects
  import    Import exported systemslab objects
  help      Print this message or the help of the given subcommand(s)

Options:
      --systemslab-url <SYSTEMSLAB_URL>  The URL at which to access the systemslab server [env: SYSTEMSLAB_URL=]
      --color <WHEN>                     Controls when to use color [default: auto] [possible values: auto, always, never]
      --output-format <fmt>              [default: long] [possible values: long, short]
  -q, --quiet                            Silence progress bars
  -h, --help                             Print help (see more with '--help')
  -V, --version                          Print version

All arguments can also be provided via argfiles. An argument like @argfile will be replaced with the content of the file `argfile` with one
argument per line```