import argparse, json

if __name__ == "__main__":
  parse = argparse.ArgumentParser('Generate the experiment list for the Intel Gen-to-Gen experiment')
  parse.add_argument('file')
  args = parse.parse_args()
  exps = []
  for tls in ['plain', 'tls']:
        for linger_ms in ["0", "5", "10"]:
            for batch_size in ["16384","524288"]:
              for compression in ["none", "gzip", "lz4", "snappy", "zstd"]:
                for jdk in ["jdk8", "jdk11"]:
                    for ec2 in ["m7i.xlarge", "m6i.xlarge"]:                        
                        for message_size in ["512", "1024"]:
                            for key_size in ["8", "0"]:
                              for compression_ratio in ["1.0", "4.0"]:                                
                                if compression_ratio == "4.0" and compression == "none":
                                  print("Skip compression:{} compression_ratio:{}".format(compression, compression_ratio))
                                  continue
                                exps.append({"linger_ms":linger_ms,
                                              "batch_size":batch_size,
                                              "key_size": key_size,
                                              "message_size": message_size,
                                              "tls": tls,
                                              "jdk": jdk,
                                              "ec2": ec2,
                                              "compression": compression,
                                              "compression_ratio": compression_ratio
                                              })
  print("There are {} experiments".format(len(exps)))
  with open(args.file, 'w') as f:
     json.dump(exps, f)
  
