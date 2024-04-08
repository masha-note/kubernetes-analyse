# 2.1 从进程开始说起

容器本身的价值非常有限，真正有价值的是“容器编排”。

一个程序运行起来之后的计算机执行环境的总和就是进程。

**容器是怎么一回事儿？**

容器技术的核心功能，就是通过约束和修改进程的动态表现，为其创造一个“边界”。对于`Docker`等大多数Linux容器来说，`Cgroups`技术是用来制造约束的主要手段，而`Namespace`技术是用来修改进程视图的主要方法。

**理解Cgroups和Namespace**

首先创建一个容器

```shell
masha@MaSha_PC:~$ docker run -it busybox /bin/sh
Unable to find image 'busybox:latest' locally
latest: Pulling from library/busybox
7b2699543f22: Pull complete
Digest: sha256:c3839dd800b9eb7603340509769c43e146a74c63dca3045a8e7dc8ee07e53966
Status: Downloaded newer image for busybox:latest
/ #
```

`-it`参数告诉了Docker项目在启动容器后，需要给我们分配一个文本输入/输出环境，即[TTY](https://docs.kernel.org/driver-api/tty/index.html)，跟容器的标准输入相关联，这样我们就可以和这个Docker容器进行交互了。而/bin/sh就是我们要在Docker容器里运行的程序。

如此一来，我们的Linux机器就变成了宿主机，而一个运行着/bin/sh的容器就在这个宿主机里运行了。

```shell
/ # ps
PID   USER     TIME  COMMAND
    1 root      0:00 /bin/sh
    7 root      0:00 ps
```

在容器里面执行ps可以看到在Docker里最开始执行的/bin/sh就是1号进程，另一个进程是我们刚刚执行的ps，这意味着/bin/sh和ps已经被Docker隔离在了一个跟宿主机完全不同的空间中了(看不到宿主机的进程)。

**怎么做到隔离的？**

这就是Namespace的作用。Namesapce其实只是Linux创建新进程的一个可选参数。在Linux系统中创建线程的系统调用是`clone()`，比如

```C
int pid = clone(main_function, stack_size, SIGCHLD, NULL);
```

这回为我们创建一个新的进程并返回他的PID。而当我们用`clone()`系统调用创建一个新进程时，就可以在参数中指定`CLONE_NEWPID`参数，比如：

```C
int pid = clone(main_function, stack_size, CLONE_NEWPID | SIGCHLD, NULL);
```

这时，新创建的进程会被隔离在一个全新的进程空间。在这个进程空间里，它的PID是1，但在宿主机真实的进程空间里，这个进程的PID还是它真是的数值(并非1)。

如果多次执行上面的clone调用，就会创造出多个PID Namespace，每个Namespace都访问不了真实进程空间，也访问不了其他PID Namespace的进程空间。

除了PID Namespace，Linux操作系统还提供了Mount、UTS、IPC、Network和User这些Namespace。比如，Mount Namesapce用于让被隔离进程只能访问到当前Namesapce的挂载点信息，NetWork Namespace用于让被隔离的进程只能访问当前Namespace里的网络设备和配置。

关于Namespace：

* [RED HAT关于7个常用Namespace的介绍](https://www.redhat.com/sysadmin/7-linux-namespaces)

* Linux manual 的说明

    ```text
    A namespace wraps a global system resource in an abstraction that makes it appear to the processes within the namespace that they have their own isolated instance of the global resource. 

    Changes to the global resource are visible to other processes that are members of the namespace, but are invisible to other processes.

    One use of namespaces is to implement containers.
    ```

这就是Linux容器最基本的实现原理。可见，容器其实是一种特殊的进程。