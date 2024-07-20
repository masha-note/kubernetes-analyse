# 2.3 深入理解容器镜像

Namespace的作用是“隔离”；而Cgroups的作用是“限制”。此外还需要一个文件系统，这应该是一个关于Mount Namespace的问题：容器里的应用进程理应“看到”一套完全独立的文件系统。这样他就可以在自己的容器目录（比如/tmp）下进行操作，而完全不会受宿主机以及其他容器的影响。

## Mount Namespace

借鉴“左耳朵耗子”的博客里的一小段用于在创建子进程时是开启指定的Namespace。

```C
#define _GNU_SOURCE
#include <sys/mount.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <stdio.h>
#include <sched.h>
#include <signal.h>
#include <unistd.h>

#define STACK_SIZE (1024 * 1024)
static char container_stack[STACK_SIZE];

char *const container_args[] = {"/bin/bash", NULL};

int container_main(void *arg)
{
    printf("Container - inside the container!\n");
    execv(container_args[0], container_args);
    printf("Something's wrong!\n");
    return 1;
}

int main()
{
    printf("Parent - start a container!\n");
    int container_pid = clone(container_main, container_stack + STACK_SIZE, CLONE_NEWNS | SIGCHLD, NULL);
    waitpid(container_pid, NULL, 0);
    printf("Parent - container stopped!\n");
    return 0;
}

```

代码功能：在main函数里，通过clone()系统调用创建了一个新的子进程container_main，并且声明要为它启用Mount Namespace（CLONE_NEWNS标志）。而这个子进程执行的是一个“/bin/bash”程序，也是一个shell。所以这个shell就运行在了Mount Namespace的隔离环境中。

```shell
masha@masha-dev-linux:~/projects/cppplayground/kubernetes$ gcc -o ns namespace.c
masha@masha-dev-linux:~/projects/cppplayground/kubernetes$ ./ns
Parent - start a container!
Parent - container stopped!
```

按照预期，这里应该进入容器，但是实际却是没有开启那个进程，需要排查代码。预期情况下，进入容器后查看/tmp目录下的文件，会看到很多宿主机上的东西，也就是说即便开启了Mount Namespace，容器进程访问到的文件系统也跟宿主机完全一样。

这是因为：Mount Namespace修改的是容器进程对文件系统“挂载点”的认知。这意味着***只有在“挂载”这个操作发生之后，进程的视图才会改变；而在此之前，新创建的容器会直接集成宿主机的各个挂载点***。

如果在容器进程启动之前以tmpfs（内存盘）格式重新挂载/tmp目录。

```C
int container_main(void *arg)
{
    printf("Container - inside the container!\n");
    // 如果机器的根目录的挂载类型是shared，那必须重新挂载根目录
    // mount("", "/", NULL, MS_PRIVATE, "");
    mount("none", "/tmp", "tmpfs", 0, "");
    execv(container_args[0], container_args);
    printf("Something's wrong!\n");
    return 1;
}
```

运行结果如下。

```shell
$ gcc -o ns namespace.c
$ ./ns
Parent - Start a container!
Container - inside the container!
$ ls /tmp
$ mount -l | grep tmpfs
none on /tmp type tempfs (rw,relatime)
```

可以看到，/tmp变成了一个空目录，这意味这重新挂载生效了。通过mount -l可以看到容器里的/tmp目录是以tempfs方式单独挂载的。更重要的是，因为创建的新进程启用了Mount Namespace，所以这次重新挂载的操作旨在容器进程的Mount Namespace中有效。如果在宿主机上用mount -l检查挂载就会发现它不存在。

## chroot

`chroot <目录> <程序>`可以改变程序的根目录为指定的目录。一般将一个完整操作系统的文件系统（比如Ubuntu的ISO）指定为容器进程的根目录，这个文件系统就是所谓的“容器镜像”，或叫rootfs（根文件系统）。

Docker的核心原理：

1. 启用Linux Namespace配置；
2. 设置指定的Cgroups参数；
3. 切换进程的根目录（优先使用pivot_root，其次才是chroot）。

## UnionFS

rootfs是一个文件系统，并不包含操作系统内核，容器配置、使用的依旧是宿主的操作系统内核。

rootfs可以打包整个文件系统，以此来确保应用的一致性（一致的执行环境）。为了保证rootfs的可复用性，docker镜像设计中引入了层（layer）的概念，镜像制作中的每一步都会生成一个层（增量rootfs）。

这使用到了UnionFS（union file system，联合文件系统）的能力，其功能是将不同位置的目录联合挂载（union mount）到同一个目录下。对挂载后的目录中的修改也会在挂载源的目录中生效。

作者原文中介绍的[AUFS](https://docs.docker.com/storage/storagedriver/aufs-driver/)已经被标注为Deprecated。我的系统中docker使用的是[overlay2](https://docs.docker.com/storage/storagedriver/overlayfs-driver/)，更多unionfs参考[Docker storage drivers](https://docs.docker.com/storage/storagedriver/select-storage-driver/)。


