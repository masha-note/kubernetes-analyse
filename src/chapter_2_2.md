# 2.2 隔离与限制

## 关于隔离

Linux容器使用Namespace技术来实现“隔离”。用户在容器里运行的应用进程跟宿主机的其他进程一样都由宿主机操作系统统一管理，只不过这些被隔离的进程拥有额外设置的Namespace参数。Docker不对这些进程负责，更多的是旁路式的辅助和管理。

Docker不需要像Hypervisor那样创建虚拟机并运行一个完整的操作系统来执行用户的应用进程，避免了额外的资源消耗和占用。容器化后的用户进程依然是宿主机上的普通进程，不存在因为虚拟化而产生的性能损耗；使用Namespace作为隔离手段的容器也不需要单独的操作系统，因此容器额外的资源占用几乎可以忽略不计。

存在的问题：隔离不彻底。

- 多个容器之间使用的还是同一个宿主机的操作系统内核。

- Linux内核中很多资源不能被Namespace化，最典型的例子就是时间。

    这意味着如果容器中使用`settimeodday`系统调用修改了时间，那么整个宿主机的时间都会随之修改。

- 由于共享宿主机的内核，容器向应用暴露的攻击面相当大，应用“越狱”的难度比虚拟机低得多。

    实践中可以使用`Seccomp`技术对容器内部发起的所有系统调用进行过滤和甄别来进行安全加固。但这种方法因为多了一层对系统调用的过滤，会拖累容器的性能。

所以在生产环境中，不会把物理机上的Linux容器直接暴露到公网上。基于虚拟化或者独立内核技术的容器实现可以比较好地在隔离与性能之间达到平衡。

## 关于限制

由于用Namespace技术创建出来的“容器”和其他宿主机上的进程是平等的竞争关系，因此它需要的资源可能会被宿主机上的其他进程用光，它自己也可能用光宿主机的所有资源。

[Linux Cgroups(Linux control groups)](https://docs.kernel.org/admin-guide/cgroup-v1/cgroups.html)就是Linux内核中用来为进程设置资源限制的一个重要功能。它最主要的作用就是限制一个进程组能够使用的资源上限，包括CPU、内存、磁盘、网络带宽等等。

此外，Cgroups还能够对进程进行优先级设置、审计，以及将进程挂起和恢复等操作。

在Linux中，Cgroups向用户暴露出来的操作系统接口是文件系统，即它以文件和目录的方式组织在操作系统的`/sys/fs/cgroup`路径下。在Ubuntu 16.04(CentOS 8也可以)的机器里，可以用mount指令将其显示：

```shell
[masha@dev kubernetes-analyse]$ mount -t cgroup
cgroup on /sys/fs/cgroup/systemd type cgroup (rw,nosuid,nodev,noexec,relatime,xattr,release_agent=/usr/lib/systemd/systemd-cgroups-agent,name=systemd)
cgroup on /sys/fs/cgroup/hugetlb type cgroup (rw,nosuid,nodev,noexec,relatime,hugetlb)
cgroup on /sys/fs/cgroup/rdma type cgroup (rw,nosuid,nodev,noexec,relatime,rdma)
cgroup on /sys/fs/cgroup/cpu,cpuacct type cgroup (rw,nosuid,nodev,noexec,relatime,cpu,cpuacct)
cgroup on /sys/fs/cgroup/blkio type cgroup (rw,nosuid,nodev,noexec,relatime,blkio)
cgroup on /sys/fs/cgroup/devices type cgroup (rw,nosuid,nodev,noexec,relatime,devices)
cgroup on /sys/fs/cgroup/pids type cgroup (rw,nosuid,nodev,noexec,relatime,pids)
cgroup on /sys/fs/cgroup/net_cls,net_prio type cgroup (rw,nosuid,nodev,noexec,relatime,net_cls,net_prio)
cgroup on /sys/fs/cgroup/memory type cgroup (rw,nosuid,nodev,noexec,relatime,memory)
cgroup on /sys/fs/cgroup/freezer type cgroup (rw,nosuid,nodev,noexec,relatime,freezer)
cgroup on /sys/fs/cgroup/perf_event type cgroup (rw,nosuid,nodev,noexec,relatime,perf_event)
cgroup on /sys/fs/cgroup/cpuset type cgroup (rw,nosuid,nodev,noexec,relatime,cpuset)
```

这里输出的是一系列的文件系统目录，如果没有则需要自行挂载Cgroups。可以看到在`/sys/fs/cgroup`下面有很多诸如cpuset、cpu、memory这样的子目录，也叫子系统。这些都是宿主机当前可以被Cgroups限制的资源种类。而在子系统对应的资源种类下，可以看到这类资源具体可以被限制的方法。比如CPU子系统下可以看到这几个配置文件：

```shell
[masha@dev kubernetes-analyse]$ ls -l /sys/fs/cgroup/cpu
lrwxrwxrwx 1 root root 11 Apr 20 22:38 /sys/fs/cgroup/cpu -> cpu,cpuacct
[masha@dev kubernetes-analyse]$ ls -l /sys/fs/cgroup/cpu/
total 0
-rw-r--r-- 1 root root 0 Apr 21 12:10 cgroup.clone_children
-rw-r--r-- 1 root root 0 Apr 20 22:38 cgroup.procs
-r--r--r-- 1 root root 0 Apr 21 12:10 cgroup.sane_behavior
-r--r--r-- 1 root root 0 Apr 21 12:10 cpuacct.stat
-rw-r--r-- 1 root root 0 Apr 21 12:10 cpuacct.usage
-r--r--r-- 1 root root 0 Apr 21 12:10 cpuacct.usage_all
-r--r--r-- 1 root root 0 Apr 21 12:10 cpuacct.usage_percpu
-r--r--r-- 1 root root 0 Apr 21 12:10 cpuacct.usage_percpu_sys
-r--r--r-- 1 root root 0 Apr 21 12:10 cpuacct.usage_percpu_user
-r--r--r-- 1 root root 0 Apr 21 12:10 cpuacct.usage_sys
-r--r--r-- 1 root root 0 Apr 21 12:10 cpuacct.usage_user
-rw-r--r-- 1 root root 0 Apr 21 12:10 cpu.cfs_period_us
-rw-r--r-- 1 root root 0 Apr 20 22:39 cpu.cfs_quota_us
-rw-r--r-- 1 root root 0 Apr 21 12:10 cpu.rt_period_us
-rw-r--r-- 1 root root 0 Apr 21 12:10 cpu.rt_runtime_us
-rw-r--r-- 1 root root 0 Apr 21 12:10 cpu.shares
-r--r--r-- 1 root root 0 Apr 21 12:10 cpu.stat
-rw-r--r-- 1 root root 0 Apr 21 12:10 notify_on_release
-rw-r--r-- 1 root root 0 Apr 21 12:10 release_agent
-rw-r--r-- 1 root root 0 Apr 21 12:10 tasks
```

输出里由`cfs_period`和`cfs_quota`这样的关键词。这两个参数需要组合使用，可用于限制进程在长度为`cfs_period`的一段时间内只能被分配到总量为`cfs_quota`的CPU时间。

为了使用这样的配置文件，需要在对应的子系统下面创建一个目录：

```shell
[root@dev cpu]# pwd
/sys/fs/cgroup/cpu
[root@dev cpu]# mkdir container
[root@dev cpu]# ls -l container/
total 0
-rw-r--r-- 1 root root 0 Apr 21 12:19 cgroup.clone_children
-rw-r--r-- 1 root root 0 Apr 21 12:19 cgroup.procs
-r--r--r-- 1 root root 0 Apr 21 12:19 cpuacct.stat
-rw-r--r-- 1 root root 0 Apr 21 12:19 cpuacct.usage
-r--r--r-- 1 root root 0 Apr 21 12:19 cpuacct.usage_all
-r--r--r-- 1 root root 0 Apr 21 12:19 cpuacct.usage_percpu
-r--r--r-- 1 root root 0 Apr 21 12:19 cpuacct.usage_percpu_sys
-r--r--r-- 1 root root 0 Apr 21 12:19 cpuacct.usage_percpu_user
-r--r--r-- 1 root root 0 Apr 21 12:19 cpuacct.usage_sys
-r--r--r-- 1 root root 0 Apr 21 12:19 cpuacct.usage_user
-rw-r--r-- 1 root root 0 Apr 21 12:19 cpu.cfs_period_us
-rw-r--r-- 1 root root 0 Apr 21 12:19 cpu.cfs_quota_us
-rw-r--r-- 1 root root 0 Apr 21 12:19 cpu.rt_period_us
-rw-r--r-- 1 root root 0 Apr 21 12:19 cpu.rt_runtime_us
-rw-r--r-- 1 root root 0 Apr 21 12:19 cpu.shares
-r--r--r-- 1 root root 0 Apr 21 12:19 cpu.stat
-rw-r--r-- 1 root root 0 Apr 21 12:19 notify_on_release
-rw-r--r-- 1 root root 0 Apr 21 12:19 tasks
```

这个目录成为一个“控制组”，操作系统会在新建的目录下自动生成该子系统对应的资源限制文件。

以下是一个实验：

- 使用一个死循环占满CPU：

    ```shell
    [root@dev cpu]# while : ; do : ; done &
    [1] 8206
    [root@dev cpu]# top
    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND                                                                                    
    8206 root      20   0  236404   2412    576 R 100.0   0.1   0:27.09 bash      
    ```

- 查看container目录下的文件，CPU quota还没有任何限制(即-1)，CPU period则是默认的100ms(100,000us)：

    ```shell
    [root@dev cpu]# cat /sys/fs/cgroup/cpu/container/cpu.cfs_quota_us
    -1
    [root@dev cpu]# cat /sys/fs/cgroup/cpu/container/cpu.cfs_period_us
    100000
    ```

- 通过修改这些文件的内容来设置限制，比如向cfs_quota文件写入20ms(20,000us)，这意味着在每100ms的时间里，被该控制组限制的进程只能使用20ms的CPU时间，即该进程只能使用到20%的CPU带宽。然后再将进程的PID写入组里的tasks文件，该设置就会对该进程生效：

    ```shell
    [root@dev cpu]# echo 20000 > /sys/fs/cgroup/cpu/container/cpu.cfs_quota_us
    [root@dev cpu]# echo 8206 > /sys/fs/cgroup/cpu/container/tasks
    [root@dev cpu]# top
    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND                                                                                    
    8206 root      20   0  236404   2412    576 R  19.9   0.1  12:00.41 bash
    ```

    可以看到CPU使用率立刻降低到了20%。

除CPU子系统外，Cgroups的每一项子系统都有其独有的资源限制能力：

- blkio，为块设备设定I/O限制，一般用于磁盘等设备；

- cpuset，为进程分配单独的CPU核和对应的内存节点；

- memory，为进程设定内存使用限制。

简而言之，Linux Cgroups就是一个子系统目录加上一组资源限制文件的组合。而对于Docker等Linux容器项目来说，它们只需要在每个子系统下面为每个容器创建一个控制组(创建一个新目录)，然后在启动容器进程之后，把这个进程的PID填写到对应控制组的tasks文件中即可。至于控制组下面的资源文件里填上什么值，就靠用户执行容器运行命令时的参数指定了，比如`docker run`：

```shell
[root@dev cpu]# docker run -it --cpu-period=100000 --cpu-quota=20000 ubuntu /bin/bash
[root@dev cpu]# docker ps
CONTAINER ID   IMAGE     COMMAND       CREATED          STATUS          PORTS     NAMES
a767eb791447   ubuntu    "/bin/bash"   43 seconds ago   Up 42 seconds             inspiring_hamilton
```

容器启动后，查看Cgroups文件系统下CPU子系统中“docker”这个控制组里的资源限制文件：

```shell
[root@dev cpu]# cat /sys/fs/cgroup/cpu/docker/a767eb791447/cpu.cfs_period_us
100000
[root@dev cpu]# cat /sys/fs/cgroup/cpu/docker/a767eb791447/cpu.cfs_quota_us
20000
```

这就意味着这个docker容器只能使用20%的CPU带宽。

