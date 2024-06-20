local systemslab = import 'systemslab.libsonnet';
local bash = systemslab.bash;
local upload_artifact = systemslab.upload_artifact;
#local config = import '/tmp/kafka_spec.json';
local default_config = import './default-config.jsonnet';

# all parameters are string
function(linger_ms="5", batch_size="524288", key_size = "8", message_size="512", tls='plain', jdk='jdk11', ec2='m7i.xlarge', compression="none", compression_ratio="1.0", update_dirty_ratio="true", pause="false") { 
    local jdk_path = {
      'jdk8': '/usr/lib/jvm/java-8-openjdk-amd64/jre',
      'jdk11': "/usr/lib/jvm/java-11-openjdk-amd64",
      'jdk17': "/usr/lib/jvm/java-17-openjdk-amd64",
    },
    local config = default_config+{
      "linger_ms": linger_ms,
      "batch_size": batch_size,
      "key_size": std.parseJson(key_size),
      "message_size": std.parseJson(message_size),
      "jdk": jdk_path[jdk],
      "kafka_tags": ["kafka", ec2],
      "compression_type": compression,
      "compression_ratio": std.parseJson(compression_ratio),
      "update_dirty_ratio": std.parseJson(update_dirty_ratio),
      "pause": std.parseJson(pause),
      "kafka_port": if tls == 'plain' then 9092 else 9093,
    },
    local rpc_perf_config = {
      general: {
          protocol: 'kafka',
          interval: 1,
          duration: config.duration, 
          metrics_output: 'rpcperf.parquet',
          metrics_format: 'parquet',
          metrics_interval: "1s",
          admin: '0.0.0.0:9091',
          initial_seed: '0',
      },
      debug: {
          log_level: 'error',
          log_backup: 'rperf-stdout.txt',
          log_max_size: 1073741824,
      },
      target: {
          // KAFKA_ENDPOINTS will be replaced with Kafka server address at run time.
          endpoints: 'KAFKA_ENDPOINTS',
      },
      pubsub: {
          connect_timeout: 10000,
          publish_timeout: 10000,
          publisher_threads: config.producer_threads,
          publisher_poolsize: config.producer_connections,
          publisher_concurrency: config.producer_concurrency,
          subscriber_threads: config.consumer_threads,
          kafka_acks: config.acks,
          kafka_linger_ms: config.linger_ms,         
          kafka_batch_size: config.batch_size,
          kafka_fetch_message_max_bytes: config.kafka_fetch_message_max_bytes,
          # none, gzip, snappy, lz4, zstd
          kafka_compression_type: config.compression_type,
      },
      workload: {
          threads: 1,
          ratelimit: {
            start: 1000
          },
          strict_ratelimit: true,
          topics: [
            {
              weight: 1,
              kafka_single_subscriber_group: true,
              subscriber_poolsize: config.consumer_connections,
              subscriber_concurrency: config.consumer_concurrency,              
              topics: config.topics,
              partitions: config.partitions,
              topic_len: 7,
              topic_names: ["rpcperf"],
              message_len: config.message_size,
              key_len: config.key_size,
              compression_ratio: std.get(config, "compression_ratio", 1.0),
            },
          ],
      },
    } + if tls == 'tls' then  
    {
      tls: {
        ca_file: "/opt/kafka-keys/ca-cert",
        private_key: "/opt/kafka-keys/client_shared_client.key",
        private_key_password: "abcdefgh",
        certificate: "/opt/kafka-keys/client_shared_client.pem",
      },
    } else {},
    local kafka_config = [
      "listeners=PLAINTEXT://:9092,SSL://:9093",
      "ssl.truststore.location=/opt/kafka-keys/broker_shared_server.truststore.jks",
      "ssl.truststore.password=abcdefgh",
      "ssl.keystore.location=/opt/kafka-keys/broker_shared_server.keystore.jks",
      "ssl.keystore.password=abcdefgh",
      "ssl.key.password=abcdefgh",
      "ssl.client.auth=none",
      "ssl.protocol=TLS",
      std.format("ssl.enabled.protocols=%s", config.tls),
      "ssl.endpoint.identification.algorithm=",
      std.format("num.network.threads=%d", config.kafka_network_threads),
      std.format("num.io.threads=%d", config.kafka_io_threads),
      std.format("log.dirs=%s", config.kafka_storage),
      std.format("default.replication.factor=%d", config.replicas),
      "num.partitions=1",
      "num.recovery.threads.per.data.dir=1",
      "offsets.topic.replication.factor=1",
      "transaction.state.log.replication.factor=1",
      "transaction.state.log.min.isr=1",
      "zookeeper.connect=ZOOKEEPER_SERVER_ADDR",
    ],
    local zookeeper_config = [
      std.format("dataDir=%s", config.zookeeper_storage),
      std.format("clientPort=%d", 2181),
      std.format("maxClientCnxns=%d", 0),
      "admin.EnableServer=false",
    ],
    name: config.name,
    metadata: config,
    jobs: {
      # let's put zookeeper and experiment controller on the same machine
      zookeeper_server: {
        host: {
          tags: config.zookeeper_tags,
        },      
        steps: [
          systemslab.write_file('./zookeeper.properties', std.lines(zookeeper_config)),         
          systemslab.upload_artifact('zookeeper.properties'),
          bash(
            |||                          
              ZOOKEEPER_DIR=%s
              ZOOKEEPER_DATADIR=%s
              ZOOKEEPER_JVM_LOG=/tmp/zookeeper_jvm
              rm -rf $ZOOKEEPER_DATADIR
              rm -rf $ZOOKEEPER_JVM_LOG
              mkdir $ZOOKEEPER_DATADIR              
              LOG_DIR=$ZOOKEEPER_JVM_LOG $ZOOKEEPER_DIR/bin/zookeeper-server-start.sh zookeeper.properties&
              echo $! > ./zookeeper.pid
              sleep 5
            ||| % [config.kafka_dir, config.zookeeper_storage]),          
          systemslab.barrier('zookeeper-start'),
          systemslab.barrier('kafka-start'),
          systemslab.barrier('kafka-finish'),
          bash('ls -h /tmp/zookeeper_jvm'),
          bash(
            |||
              ls -h /tmp/zookeeper_jvm
              pkill java || true
              sleep 3
              tar -czvf zookeeper_jvm_log.gz /tmp/zookeeper_jvm
            |||),
          systemslab.upload_artifact('zookeeper_jvm_log.gz')
        ],
      },
      kafka_server_1: {        
        local broker_config = kafka_config + ["broker.id=1"],
        host: {
          tags: config.kafka_tags,
        },      
        steps: 
          ( if config.update_dirty_ratio == true then [
            bash(
            |||
              DIRTY_BACKGROUND_RATIO=%s
              DIRTY_EXPIRE_CENTISECS=%s
              DIRTY_RATIO=%s
              DIRTY_WRITEBACK_CENTISECS=%s
              cat /proc/sys/vm/dirty_background_ratio > curr_dirty_background_ratio
              cat /proc/sys/vm/dirty_expire_centisecs > curr_dirty_expire_centisecs
              cat /proc/sys/vm/dirty_ratio > curr_dirty_ratio
              cat /proc/sys/vm/dirty_writeback_centisecs > curr_dirty_writeback_centisecs
              sudo bash -c "echo $DIRTY_BACKGROUND_RATIO > /proc/sys/vm/dirty_background_ratio"
              sudo bash -c "echo $DIRTY_EXPIRE_CENTISECS > /proc/sys/vm/dirty_expire_centisecs"
              sudo bash -c "echo $DIRTY_RATIO > /proc/sys/vm/dirty_ratio"
              sudo bash -c "echo $DIRTY_WRITEBACK_CENTISECS > /proc/sys/vm/dirty_writeback_centisecs"
              echo "Set dirty_background_ratio to `cat /proc/sys/vm/dirty_background_ratio`"
              echo "Set dirty_expire_centisecs to `cat /proc/sys/vm/dirty_expire_centisecs`"
              echo "Set dirty_ratio to `cat /proc/sys/vm/dirty_ratio`"
              echo "Set dirty_writeback_centisecs TO `cat /proc/sys/vm/dirty_writeback_centisecs`"
            ||| % [config.dirty_background_ratio, config.dirty_expire_centisecs, config.dirty_ratio, config.dirty_writeback_centisecs]),
          ] else [] )
          + [
          systemslab.barrier('zookeeper-start'),          
          systemslab.write_file('server.properties', std.lines(broker_config)),
          bash(
            |||
              sed -ie "s/ZOOKEEPER_SERVER_ADDR/$ZOOKEEPER_SERVER_ADDR:2181/g" server.properties            
            |||),
          systemslab.upload_artifact('server.properties'),
          bash(
            |||
              echo "Start Kafka Broker"            
              KAFKA_DIR=%s
              KAFKA_STORAGE=%s
              JDK=%s
              echo "Clean $KAFKA_STORAGE"
              rm -rf $KAFKA_STORAGE
              echo "Clean the JVM log"
              rm -rf /tmp/kafka_jvm_log 
              JAVA_HOME=$JDK LOG_DIR=/tmp/kafka_jvm_log $KAFKA_DIR/bin/kafka-server-start.sh server.properties&                
              sleep 5
              $KAFKA_DIR/bin/kafka-cluster.sh  cluster-id  --bootstrap-server localhost:9092
            ||| % [config.kafka_dir, config.kafka_storage, config.jdk]),          
          systemslab.barrier('kafka-start'),
          // waiting for the client to finish
          systemslab.barrier('kafka-finish'),
          ] + ( if config.update_dirty_ratio == true then [        
          bash(
            |||
              sudo bash -c "echo `cat ./curr_dirty_background_ratio` > /proc/sys/vm/dirty_background_ratio"
              sudo bash -c "echo `cat ./curr_dirty_expire_centisecs` > /proc/sys/vm/dirty_expire_centisecs"
              sudo bash -c "echo `cat ./curr_dirty_ratio` > /proc/sys/vm/dirty_ratio"
              sudo bash -c "echo `cat ./curr_dirty_writeback_centisecs` > /proc/sys/vm/dirty_writeback_centisecs"
              echo "Reset dirty_ratio to `cat /proc/sys/vm/dirty_background_ratio`"
              echo "Reset expire_centisecs to `cat /proc/sys/vm/dirty_expire_centisecs`"
              echo "Reset dirty_ratio to `cat /proc/sys/vm/dirty_ratio`"
              echo "ReSet dirty_writeback_centisecs TO `cat /proc/sys/vm/dirty_writeback_centisecs`"
            |||) ] else [] ) + [
          bash(
            |||
              ls -h /tmp/kafka_jvm_log
              pkill java || true
              sleep 3
              tar -czvf kafka_jvm_log.gz /tmp/kafka_jvm_log
            |||),
          systemslab.upload_artifact('kafka_jvm_log.gz', tags=['jvm_log'])
          #systemslab.upload_artifact('/tmp/kafka_jvm_log'),
        ],
      },
      rpc_perf_1: {             
        host: {
          tags: config.client_tags,
        },
        steps: [           
          systemslab.write_file('rpcperf-kafka.toml', std.manifestTomlEx(rpc_perf_config, '')),
          bash(
            |||
              KAFKA_PORT=%s
              sed -ie "s/\"KAFKA_ENDPOINTS\"/[\"${KAFKA_SERVER_1_ADDR}:${KAFKA_PORT}\"]/g" rpcperf-kafka.toml
            ||| % [config.kafka_port]),
          systemslab.upload_artifact('rpcperf-kafka.toml'),
          systemslab.barrier('kafka-start'),
        ] + ( if config.pause == true then [
          bash(
            |||
              echo 1 > ./rpcperf-pause
              while [ `cat ./rpcperf-pause` -eq '1' ]; do              
                sleep 10
              done
            |||
          )
        ] else [
          bash(
            |||            
              RPC_PERF_BINARY=%s
              STEP_DURATION=%s
              STEPS="%s"
              $RPC_PERF_BINARY rpcperf-kafka.toml&
              sleep 1
              for RPS in $STEPS; do
                for RPC_SERVER in ${RPC_PERF_1_ADDR}; do
                  curl http://$RPC_SERVER:9091/vars
                  curl http://$RPC_SERVER:9091/metrics
                  echo "=======$RPS ${RPC_PERF_1_ADDR}======="
                  curl -s -X PUT http://$RPC_SERVER:9091/ratelimit/$RPS
                done
                sleep $STEP_DURATION
              done
              wait              
            ||| % [config.rpc_perf, config.step_duration, config.steps]),            
          systemslab.upload_artifact('rpcperf.parquet', tags=['rpcperf']),                 
          # generate the experiment spec.json
        ] ) + [
          systemslab.barrier('kafka-finish'),
        ]
      },
    },
  }
  