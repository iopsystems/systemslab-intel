# Running Kafka Experiments on Systemslab
This document shows how to run Kafka experiments in Systemslab on AWS.

The resources we need are:
- One Systemslab server instance, we suggest one c5.xlarge with 100 GB gp3 storage. We also use this instance as the control machine to create agents, submit experiments, and analyse experiment artifacts.
- Multiple Systemslab agent instances for executing the Kafka experiments. We provide Terraform and Ansible scripts to create agents automatically.
- One S3 bucket for storing the experiment artifacts. 

We need to prepare the AWS environment, create one EC2 instance and deploy the Systemslab server there. After the Systemslab server is ready, we can use Terraform & Ansible create multiple Systemslab agents. After the agents are ready, we submit Kafka experiments to the server. The server schedules the jobs in the experiment on agents and store the experiment artifacts in the S3 bucket. The Systemslab server also provides http APIs and a web UI for checking the status of submitted experiments. After experiments finished, their artifacts are stored in the S3 bucket. You can use the Systemslab CLI, http APIs, or the web UI to download the artifacts.


## Prepare AWS EC2 and create the Systemslab server instance

- Enable AWS EC2 cli access. We suggest creating a dedicated user `systemslab` for the Systemslab service.
- Create a new security group `systemslab-sg` and enable all internal inbound and outbond traffics. For external traffics, please allow downloading Systemslab packages from https://packages.cloud.google.com, and ssh traffics between your local machine and Systemslab instances. Here is one example that enables all outbound, all internal inbound, and the external inbound SSH traffic.
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
- Create a new EC2 key pair `systemslab_aws_key`

The Systemslab server needs one x86 EC2 instance with four or more vCPUs, 8 GB memory, 100 GB EBS storage, and one S3 bucket to store the experiment artifacts. Artifacts can be stored on the local storage of the Systemslab server, but we highly recommend of using the S3 bucket. 

Both Debian-based distributions, such as Ubuntu, and Amazon Linux are supported. We suggest using one c5.xlarge which is the cheapest instance with 4 x86 vCPUs, 100 GB GP3 EBS root disk, and ubuntu 22.04.

Following these steps to setup and config the server, more documents can be found [here](https://docs.iop.systems/install) and [here](https://docs.iop.systems/config):
* Create one c5.xlarge in the `systemslab-sg` security group with the EC2 key pair `systemslab_aws_key` attached, at least 100 GB gp3 root disk, ubuntu 22.04.
* Add a few files to the server instance under `/home/ubuntu/.aws`:
  - `~/.aws/credentials` that has the AWS access key. Terraform needs the access key to create and terminate Systemslab agents. By default, the Terraform scripts use the `systemslab` profile which is created above.
  - `~/.aws/systemslab_aws_key` and `~/.aws/systemslab_aws_key.pub` The `systemslab_aws_key` pair, The Ansible script use this to config the agents. Please set the file permission of `~/.aws/systemslab_aws_key` to 600, otherwise ssh won't work.
  - `~/.aws/systemslab-gcp-creds.json` this is the access key to the Systemslab private repo and provided by IOP Systems.
* SSH to the server, set up the Systemslab repo and install the server:
  - Download the public repo package  `curl -fsSL "https://storage.googleapis.com/systemslab-public/deb/systemslab-repo-$(lsb_release -sc)_latest_all.deb" -o /tmp/systemslab-repo.deb`
  - Install the package to get the public repo `sudo apt-get install /tmp/systemslab-repo.deb`
  - `sudo apt-get update`
  - Install the private repo `sudo /usr/share/systemslab-repo/setup-repo.sh --credentials ~/.aws/systemslab-gcp-creds.json`
  - `sudo apt-get update`
  - Install the Systemslab server, database, and cli `sudo apt install systemslab-server systemslab-postgresql systemslab-cli`
  - Initialize the database `sudo systemslab-dbctl init --yes`
  - edit `/etc/systemslab/server.toml`, add the configs below (cluster_id is a name to identify this cluster, AWS_ACCESS_KEY and AWS_SECRET_ACCESS_KEY are the keys is in the `~/.aws/credentials` under the `systemslab` profile):
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
- `ssh -NL 9000:localhost:80 SERVER_HOST` forwards the Systemlab server port 80 to port 9000 on your local machine, then you can access the website and the APIs via `http://localhost:9000`.

## Create Systemslab Agents
After the server is running. You can clone this repo to the Systemslab server instance and use the Terraform & Ansible scripts under `./aws` to automatically deploy agents.

`./aws/agents.tf` is the place to add new agents and the `./aws/variables.tf` defines some critical variables.

After adding agents to `./aws/agents.tf` and set the variables in `./aws/variables.tf`, these two steps create and config the agents:
- In `./aws`, run `terraform plan` to check the resources to be created then `terraform apply` to create the resources
- In `./aws`, run `ansible-playbook ./playbook.yaml` to deploy and config agent hosts.

Below shows how to edit `./aws/agents` and `./aws/variables.tf`.

The `./aws/variables` lists the key variables, such as the aws region, the aws zone where we want to create agent instances. The `systemslab_server_ip` is the address of the Systemslab server, please change it to the private IP of the Systemslab server created above.

The `./aws/agents.tf` lists the agents we need to run the single-broker-single-producer Xeon V4 Vs. V3 experiments. Each experiment needs three instances: one Zookeeper, one client, and one broker. We would like to run two experiments in parallel, one on each generation, so we create one m7i.xlarge and one m6i.xlarge for brokers, two m7i.2xlarge for the two clients, and two t3.large for Zookeeper.

To adjust the type and the number of agents, edit the items in the agents array at the top of `./aws/agents.ts`, such as:
```# two m7i.2xlarge client
    {
      # type decides the instance type
      type = "m7i.2xlarge",
      # count decides the number of this type of EC2 instance
      count = 2
      # ansible groups for the ansible scripts. All agents are in the agents group and this groups field allow us adding more groups. In this case, we add the kafka group, so `./aws/tasks/kafka.ansible.yaml` can find the instances and deploy Kafka packages there.
      groups = ["kafka"]
      # by default, agent instances have ["PUBLIC_DNS", "EC2_TYPE", "EC2_TYPE-ID tags, this tags field add more tags to the instances. In the experiment spec, we can use the tag to assign the job to the instances we want.
      tags = ["kafka", "client"]
      # root disk
      root_volume_type = "gp3"
      # size
      root_volume_size = "200"
      # by default, autoshutdown is true that instance terminates itself after in the idle state for 30 minutes. If the autoshutdown is false, we need to explicitly terminate the instances by adjusting the count field and re-run `terraform apply`.
      autoshutdown = false
    },
```


After running the `terraform apply` command, agent instances are created in AWS whose name follow the pattern of `INSTANCETYPE-SIZE-ID`, for example, the above two m7i.2xlarge instances are named as `m7i-2xlarge-1` and `m7i-2xlarge-0`. 


The Ansible inventory file (`./aws/inventory.yaml`) is also updated with the instance information. For example, the two m7i.2xlarge appear in two groups:
```
"agent":
  "hosts":
    "ec2-35-91-183-125.us-west-2.compute.amazonaws.com":
      "agent_config": |
        name       = "m6i-xlarge-1"
        server_url = "http://172.31.11.125"
        tags       = ["ec2-35-91-183-125.us-west-2.compute.amazonaws.com","kafka","broker","m6i-xlarge-1","m6i.xlarge"]

        [log]
        cluster_id = "iop/aws"
    "ec2-35-92-2-25.us-west-2.compute.amazonaws.com":
      "agent_config": |
        name       = "m7i-2xlarge-2"
        server_url = "http://172.31.11.125"
        tags       = ["ec2-35-92-2-25.us-west-2.compute.amazonaws.com","kafka","client","m7i-2xlarge-2","m7i.2xlarge"]

        [log]
        cluster_id = "iop/aws"
"kafka":
  "hosts":
    "ec2-35-91-183-125.us-west-2.compute.amazonaws.com": {}
    "ec2-35-92-2-25.us-west-2.compute.amazonaws.com": {}    
```  

Running `ansible-playbook playbook.yaml` deploys the Systemlab agent, Kafka, and other other settings on the EC2 instance:
- `./aws/tasks/setup-agent.ansible.yaml` set up the Systemslab repo and installs the Systemslab agent service. It needs the "~/.aws/systemslab-gcp-creds.json".
- `./aws/tasks/setup-agent.ansible.yaml` installs multiple openjdks, the Kafka package to /opt/kafka_2.13-3.6.1, and TLS keys to /opt/kafka-keys.
- `./aws/tasks/sudo.ansible.yaml` set up users and ssh access.
- `./aws/tasks/limits.ansible.yaml` set the systems limits, such as vm.max_map_count and file fd limits.


After running the Ansible playbook, Systemslab agents should be ready. For example, the two m7i.2xlarge are shown in the agent list:
```
curl http://localhost/api/v1/host | jq

[
  {
    "id": "019033ac-75b9-7f70-6eb1-8304574269ac",
    "name": "m7i-2xlarge-1",
    "state": "idle",
    "tags": [
      "ec2-35-160-252-183.us-west-2.compute.amazonaws.com",
      "kafka",
      "client",
      "m7i-2xlarge-1",
      "m7i.2xlarge"
    ],
    "version": "0.0.93"
  },
 {
    "id": "019033ac-75d4-7f12-978b-98c2f109e956",
    "name": "m7i-2xlarge-2",
    "state": "idle",
    "tags": [
      "ec2-35-92-2-25.us-west-2.compute.amazonaws.com",
      "kafka",
      "client",
      "m7i-2xlarge-2",
      "m7i.2xlarge"
    ],
    "version": "0.0.93"
  },  
```

## Systemslab Experiment Specification
We use the [Systemslab specification](https://docs.iop.systems/reference/experiment) to express the experiment. Systemslab spec supports the [jsonnet](https://jsonnet.org) format. The structure of a spec follows this pattern:
``` function() {
      name: JOB_NAME,
      jobs: {
        job_1 : {
          host: {
            tags: [TAGS]
          },
          steps: [
            bash(BASH_SCRIPT)
               or
            barrier(BARRIER_NAME)
               or
            upload_artifact(ARTIFACT),
            ...
          ]
        },
        ...,
        job_n :...
      }
}
```


Each spec has a name and jobs. Each job is a scheduling unit that can be scheduled on the matched host that has the same tags to execute its tasks. The tasks are defined in the steps field. For example, the bash task invokes the bash script, the barrier task synchronize with other jobs who also execute the same barrier, and the upload_artifact task uploads the artifact to the Systemslab server. 

`./kafka/hello-world.jsonnet` shows a simple experiment that has two jobs that take turn to print messages and the IP address of the jobs.

`./kafka/aws-producing.jsonnet` is the single producer Kafka experiment. There are three tasks: zookeeper_server running the zookeeper service, kafka_server_1 running the Kafka broker, and rpc_perf_1 as the client.

## Submit Experiments to The Systemslab

We use the systemslab cli to submit the experiment to the systemslab. Before submitting the spec, we can evaluate the spec first checking whether the spec is in a good format.

```systemslab evaluate ./kafka/aws-producing.jsonnet```

After the spec is in good shape, we can submit the experiment to the Systemslab server.
```systemslab evaluate ./kafka/aws-producing.jsonnet -p PARAMETER=VALUE -p PARAMETER=value```

The CLI prints out the experiment webpage url ended with the experiment id. For example:
```
systemslab submit ./kafka/aws-producing.jsonnet
Experiment page is available at http://localhost/experiment/019035d5-a760-71e2-9116-9af07d659d29
```

The webpage shows the experiment information and artifacts after the experiment is done. When debugging the experiment, we might want to check the log of jobs from the terminal, we can add the `--tail` to the `systemslab submit` cmd.

### Sweeping Parameters

Sysemslab provides an efficient way of submitting multiple experiments to sweep the spec parameters. ```systemslab sweep --name <NAME> <SPEC> <SWEEPFILE>``` accepts a sweep file that shows the target sweeping parameters. It creates a context with the name of NAME and attaches the experiments to the context.

`./exp/double-exp.json` shows an example that sweeps the tls parameter.
```systemslab sweep --name tls-sweeping ./kafka/aws-producing.jsonnet ./exp/double-exp.json``` creates a new context named `tls-sweeping` and creates two experiments, one with the tls=plain and another with tls=tls. The cmd also prints out the context id. You can query the status of the experiment with the /context/{id} API: 
```
curl --request GET \
  --url http://localhost:9000/api/v1/context/CONTEXT_ID
```

## Reproducing The Experiments in Intel Gen-Over-Gen Analysis

The Intel gen-over-gen analysis executes 1782 experiments that sweep 9 parameters:
```
tls: plain, tls
linger_ms: 0, 5, 10
batch_size: 16384, 524288
compression: none, gzip, lz4, snappy, zstd
jdk: jdk8, jdk11
ec2: m7i.xlarge, m6i.xlarge
message_size: 512, 1024
key_size, 0, 8
compression_ratio: 1.0, 4.0
```
The `./exp/gen-to-gen.json` lists the 1782 experiments. To submit these experiments, run:
```
systemslab sweep ../kafka/aws-producing.jsonnet --name intel-gen-to-gen ./gen-to-gen.json
```