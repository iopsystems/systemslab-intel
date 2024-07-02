import requests, time, json, sys, argparse

def get_rpcperf_metrics(rpcperf):
    res = requests.get("http://{}/vars.json".format(rpcperf))
    if res.status_code != 200:
        raise Exception("Failed to get metrics from {}".format(rpcperf))
    return res.json()

def get_rezolus_metrics(rezolus):    
    res = requests.get("http://{}/vars.json".format(rezolus))
    if res.status_code != 200:
        raise Exception("Failed to read metrics from rezolus {}".format(rezolus))
    return res.json()

def set_rpcperf_ratelimit(rpcperf, qps):
    r = requests.put("http://{}/ratelimit/{}".format(rpcperf, qps))
    if r.status_code != 200:
        raise Exception("Failed to update the ratelimt of rpcperf at {}".format(rpcperf))

def terminate_rpcperf(rpcperf):
    r = requests.post("http://{}/quitquitquit".format(rpcperf))
    if r.status_code != 200:
        raise Exception("Failed to terminate rpcperf at {}".format(rpcperf))
    
def get_publish_successrate(start, end, period):
    target_qps = end['ratelimit/current']
    publish_ok = end['publisher/publish/ok'] - start['publisher/publish/ok']
    publish_ok_rate = float(publish_ok) / period
    return (float(publish_ok_rate)/target_qps, publish_ok_rate, target_qps)    

def get_rezolus_cpu_util(start, end, period_ns):
    nr_cpu = end['cpu/cores']
    user_time = end['cpu/usage/user/total'] - start['cpu/usage/user/total']
    system_time = end['cpu/usage/system/total'] - start['cpu/usage/system/total']
    return float(user_time + system_time)/(period_ns * nr_cpu)

def get_rezolus_network_receive_mb(start, end, period):
    return float(end['network/receive/bytes'] - start['network/receive/bytes'])/ (period * 1024 * 1024)

def get_disk_write_mb(start, end, period):
    return float(end['blockio/write/bytes/total'] - start['blockio/write/bytes/total'])/ (period * 1024 * 1024)

def at_qps(rpcperf, rezolus, qps, delay, period):
    set_rpcperf_ratelimit(rpcperf, qps)
    if delay > 0:
        time.sleep(delay)
    start_ns = time.time_ns()
    start_rpcperf = get_rpcperf_metrics(rpcperf)
    start_rezolus = get_rezolus_metrics(rezolus)
    time.sleep(period)
    end_rezolus = get_rezolus_metrics(rezolus)
    end_rpcperf = get_rpcperf_metrics(rpcperf)
    end_ns = time.time_ns()
    period_ns = end_ns - start_ns
    period_s = period_ns / (1000 * 1000 * 1000.0)
    publish_success_rate, publish_ok_rate, target_qps = get_publish_successrate(start_rpcperf, end_rpcperf, period)
    cpu_util = get_rezolus_cpu_util(start_rezolus, end_rezolus, period_ns)        
    network_receive_mb = get_rezolus_network_receive_mb(start_rezolus, end_rezolus, period_s)
    disk_write_mb = get_disk_write_mb(start_rezolus, end_rezolus, period_s)
    return (end_ns, publish_success_rate, cpu_util, network_receive_mb, disk_write_mb)

# @rpcperf: rpcperf admin url
# @rezolus: rezolus admin url
# @start_qps: the starting qps
# @step: the qps step
# @step_period: the duration in each step
# @good_rate: the threshold of passing this step, if the producer success rate lower than the threshold, this step will be retried @retry times until the step is labeled as failure.
# @retry: the number of retry in each step
# @termination: how many failure steps before terminating the test
# @target_qps: (optional)
# @step_delay:
# return:
# [ { timestamp:, duration:, target_qps:, success_rate:, retry:, passed: } .... ]
def sweep(rpcperf, rezolus, start_qps, step, step_period, good_rate, retry, termination, target_qps=None, step_delay=0):
    ret = []
    nr_failure = 0
    if start_qps <= 0:
      raise Exception("start qps must be larger than 0")
    testing_qps = start_qps 
    nr_retry = 0
    while True:
        if target_qps and testing_qps > target_qps:
            break            
        if nr_failure >= termination:
            break
        timestamp, success_rate, cpu, network, disk = at_qps(rpcperf, rezolus, testing_qps, step_delay, step_period)
        passed = True if success_rate >= good_rate else False
        this_run = {"timestamp": timestamp, "qps": testing_qps, "passed": passed, "retry": nr_retry, "good_rate": success_rate, "cpu_util": cpu, "network_receive_mb": network, "disk_write_mb":disk}
        print(this_run)
        ret.append(this_run)
        if passed:
            # move to next step
            testing_qps += step
            nr_retry = 0
        else:
            # retry in current step
            if nr_retry < retry:
                nr_retry += 1                
            else:
                nr_retry = 0
                nr_failure += 1
                testing_qps += step
    return ret

if __name__ == "__main__":
  parse = argparse.ArgumentParser('rpcperf kafka workload controller')
  parse.add_argument('rpcperf')
  parse.add_argument('rezolus')
  parse.add_argument('startrate', type=int)
  parse.add_argument('step', type=int)
  parse.add_argument('period', type=float)
  parse.add_argument('goodrate', type=float)
  parse.add_argument('retry', type=int)
  parse.add_argument('termination', type=int)  
  args = parse.parse_args()
  print(args)
  steps = sweep(args.rpcperf, args.rezolus, args.startrate, args.step, args.period, args.goodrate, args.retry, args.termination)
  with open('./steps.json', 'w') as f:
      json.dump(steps, f)
