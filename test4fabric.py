from fabric import Connection
from concurrent.futures import ThreadPoolExecutor

ec2_hosts = ['69.230.247.201', '52.83.211.74']


def connect_ec2(host):
    # 登录EC2
    conn = Connection(host=host, user='ec2-user', connect_kwargs={"key_filename": "qa.pem"})

    # 执行shell脚本
    conn.run("cd kvs-webrtc-sdk/ && bash multi_master_v2.sh")


with ThreadPoolExecutor() as pool:
    futures = [pool.submit(connect_ec2, host) for host in ec2_hosts]
    for future in futures:
        future.result()
