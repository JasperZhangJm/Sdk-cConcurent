import paramiko

hosts = ['69.230.247.201', '52.83.211.74']

for host in hosts:
    with paramiko.SSHClient() as ssh:
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(hostname=host, username='ec2-user', key_filename='qa.pem')
        ssh.exec_command("touch 222.txt")


