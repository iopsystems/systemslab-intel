{ 
  "name":"produce_jdk8_m7i",
  "duration": 3600,
  "controller": "auto",
  "warmup_rate": 10000,
  "warmup_duration": 10,
  "start_rate": 10000,
  "step": 10000,
  "step_duration": 60,
  "good_rate": 0.95,
  "retry": 1,
  "termination": 1,  
  "aws_storage": "gp3",
  # aws instance
  "kafka_tags":["kafka", "m7i.xlarge"],
  # Plaintext 
  "client_tags":["kafka", "client"],
  "zookeeper_tags":["kafka","zookeeper"],
  "producer_threads":8, 
  "producer_connections":8,
  "producer_concurrency":200,
  "consumer_threads": 1, 
  "consumer_connections": 0,
  "consumer_concurrency": 0,
  "kafka_network_threads": 8,
  "kafka_io_threads": 8,
  # topics
  "topics": 1,
  "partitions": 32,
  "replicas": 1,
  "acks": "all",
  "exactly_once": false,
  "compression_type": "none",
  # messages
  "key_size": 0,
  "message_size": 512, 
  # batching
  "linger_ms": "0", 
  "batch_size": "524288",
  "kafka_fetch_message_max_bytes": "10485760",  
  # TLS 
  "tls": "TLSv1.3",    
  # storage
  "kafka_storage": "/tmp/kafka",
  "zookeeper_storage": "/tmp/zookeeper",
  # JVM
  "rpc_perf": "rpc-perf",
  "kafka_version": "2.13-3.6.1",
  "kafka_dir": "/opt/kafka_2.13-3.6.1",
  "jdk": "/usr/lib/jvm/java-11-openjdk-amd64",
  "client_jdk": "/usr/lib/jvm/java-11-openjdk-amd64",
  "dirty_background_ratio": 10,
  "dirty_expire_centisecs": 25,
  "dirty_ratio": 80,
  "dirty_writeback_centisecs": 25
}