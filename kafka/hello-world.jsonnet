local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local barrier = systemslab.barrier;
local upload_artifact = systemslab.upload_artifact;

function(msg="hello world") {
  name: "hello-world",
  jobs: {
    client : {
      host: {
        tags: ['client'],
      },
      steps: [
        bash(
          |||
            echo client: %s
            echo client: client IP address is $CLIENT_ADDR
            echo client: server IP address is $SERVER_ADDR
          ||| % [msg]
        ),      
        barrier('zookeeper-start'),
      ],
    },
    server : {
      host: {
        tags: ['broker'],
      },
      steps: [
        barrier('zookeeper-start'),
        bash(
          |||
            echo broker: %s
            echo broker: broker IP address is $SERVER_ADDR
            echo broker: client IP address is $CLIENT_ADDR            
          ||| % [msg]
        ),              
      ],
    },
  },
}