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

按照预期，这里应该进入容器，但是实际却是没有开启那个进程，需要排查代码。

### 问题排查

改写之前的main函数如下，打印错误信息。

```C
int main() {
    printf("Parent - start a container!\n");
    int container_pid = clone(container_main, container_stack + STACK_SIZE, CLONE_NEWNS | SIGCHLD, NULL);
    perror("error message:");
    waitpid(container_pid, NULL, 0);
    printf("Parent - container stopped!\n");
    return 0;
}
```

输出如下。

```shell
masha@masha-dev-linux:~/projects/testing/C/mount$ ./a.out
Parent - start a container!
error message:: Operation not permitted
Parent - container stopped!
masha@masha-dev-linux:~/projects/testing/C/mount$ ll
total 32
drwxrwxr-x 2 masha masha  4096 8月  15 23:04 ./
drwxrwxr-x 3 masha masha  4096 8月  15 22:44 ../
-rwxrwxr-x 1 masha masha 17088 8月  15 23:04 a.out*
-rw-rw-r-- 1 masha masha   769 8月  15 23:04 main.c
```

可以看出是因为权限不足。查看权限，本用户对输出文件也有执行权限。那接下来需要查看`clone`函数的相关信息。其中关于错误信息中权限不足的部分有如下描述。

```txt
CLONE_NEWNS (since Linux 2.4.19)
    If CLONE_NEWNS is set, the cloned child is started in a new mount namespace, initialized with a copy of the name‐
    space of the parent.  If CLONE_NEWNS is not set, the child lives in the same mount namespace as the parent.

    For further information on mount namespaces, see namespaces(7) and mount_namespaces(7).

    Only  a  privileged  process  (CAP_SYS_ADMIN)  can  employ  CLONE_NEWNS.   It  is  not  permitted to specify both
    CLONE_NEWNS and CLONE_FS in the same clone call.

EPERM   CLONE_NEWCGROUP,  CLONE_NEWIPC,  CLONE_NEWNET, CLONE_NEWNS, CLONE_NEWPID, or 
        CLONE_NEWUTS was specified by an unprivileged process (process without CAP_SYS_ADMIN).

EPERM   CLONE_PID was specified by a process other than process 0.  (This error occurs only on Linux 2.5.15 and earlier.)

EPERM   CLONE_NEWUSER was specified in the flags mask, but either the effective user ID or the effective group ID of the
        caller does not have a mapping in the parent namespace (see user_namespaces(7)).

EPERM   (since Linux 3.9)
        CLONE_NEWUSER  was specified in the flags mask and the caller is in a chroot environment (i.e., the caller's root
        directory does not match the root directory of the mount namespace in which it resides).

EPERM   (clone3() only)
        set_tid_size was greater than zero, and the caller lacks the CAP_SYS_ADMIN capability in one or more of the  user
        namespaces that own the corresponding PID namespaces.
```

从其中第一条和第二条可以看出，我们的子进程指定了`CLONE_NEWNS`但是父进程只有`masha`的权限。我们用管理员权限运行可以看到：

```shell
masha@masha-dev-linux:~/projects/testing/C/mount$ sudo ./a.out
Parent - start a container!
error message:: Success
Container - inside the container!

root@masha-dev-linux:/home/masha/projects/testing/C/mount# ls /tmp
{4B2A90A8-AF6C-467D-AC48-C06B004C5EBA}
appInsights-node38efe475-3afd-4e03-8af2-bbcfdeee3b7a
appInsights-nodeAIF-d9b70cd4-b9f9-4d70-929b-a071c400b217
一堆主机上的文件......
tracker-extract-files.1000
vscode-typescript1000

root@masha-dev-linux:/home/masha/projects/testing/C/mount# exit
exit
Parent - container stopped!

masha@masha-dev-linux:~/projects/testing/C/mount$ ls /tmp
{4B2A90A8-AF6C-467D-AC48-C06B004C5EBA}
appInsights-node38efe475-3afd-4e03-8af2-bbcfdeee3b7a
appInsights-nodeAIF-d9b70cd4-b9f9-4d70-929b-a071c400b217
一堆主机上的文件......
tracker-extract-files.1000
vscode-typescript1000
```

## mount

预期情况下，进入容器后查看/tmp目录下的文件，会看到很多宿主机上的东西，也就是说即便开启了Mount Namespace，容器进程访问到的文件系统也跟宿主机完全一样（根据mount_namespace的man的描述，子进程的namespace中的挂载点是父进程namespace的copy）。

这是因为：Mount Namespace修改的是容器进程对文件系统“挂载点”的认知。这意味着***只有在“挂载”这个操作发生之后，进程的视图才会改变；而在此之前，新创建的容器会直接集成宿主机的各个挂载点***。

如果在容器进程启动之前以tmpfs（内存盘）格式重新挂载/tmp目录（这相当于覆写了从父进程的namespace中拷贝来的挂载点）。

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
masha@masha-dev-linux:~/projects/testing/C/mount$ sudo ./a.out
Parent - start a container!
error message:: Success
Container - inside the container!

root@masha-dev-linux:/home/masha/projects/testing/C/mount# ls /tmp

root@masha-dev-linux:/home/masha/projects/testing/C/mount# exit
exit
Parent - container stopped!
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


