<img width="5603" height="14594" alt="image" src="https://github.com/user-attachments/assets/8beb50c9-b1b8-41d0-b873-c56c0518c007" /># Sdk-cConcurent
在多台服务器上并发启动sdk-c viewer和master
架构：
1、多台ec2 启动master，存放启动master的shell脚本和sn、channel数据
2、多台ec2 启动viewer，存放启动viewer的shell脚本和sn、channel数据
3、本地执行python脚本，通过ec2 host list 分布式启动多台ec2上的master和viewer
4、并发后，master和viewer产生日志文件，可以使用master和viewer各自对应的shell脚本分析，分析的结果是csv文件，内容：

![Uploading 792abeff-0e28-4e0f-b5a8-592d1cdbd8bb.png…]()
