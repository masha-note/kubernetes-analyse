# 深入解析Pod对象

kubernetes项目中最小编排单位是Pod，而Container就成了Pod属性里的一个普通字段。

凡是调度、网络、存储，以及安全相关的属性基本上都是Pod级别的。这些属性的共同特征是，他们描述的是“机器”这个整体，而不是里面运行的“程序”。比如配置这台“机器”的网卡（Pod的网络定义），配置这台“机器”的磁盘（Pod的存储定义），配置这台“机器”的防火墙（Pod的安全定义），更不用说Pod的调度。

## NodeSelector

用户可以通过NodeSelector将Pod与Node进行绑定，用法如下：

```YAML
apiVersion: v1
kind: Pod
...
spec:
  nodeSelector:
    disktype: disk
```

者意味着这个Pod只能在携带了`disktype: disk`标签的节点上运行，否则将导致调度失败。

## NodeName

一旦Pod的nodeName赋了值，kubernetes会认为这个Pod已调度，调度的结果就是赋值的节点名称。所以这个字段一般由调度器负责设置。

```YAML
apiVersion: v1
kind: Pod
...
spec:
  nodeName: myapp
```

## HostAliases

hostAliases定义了Pod的hosts文件（比如/etc/hosts）里的内容。

```YAML
apiVersion: v1
kind: Pod
...
spec:
  hostAliases:
  - ip: "10.1.2.3"
```

在这个Pod启动后，/etc/hosts文件的内容就会是hostAliases中所指定的。需要注意的是如果要设置hosts文件里的内容，—定要通过这种方法。如果直接修改了hosts文件，在Pod被删除重建之后，kubelet会自动覆盖被修改的内容。

## shareProcessNamespace

定义shareProcessNamespace=true表示这个Pod里的容器要共享PID Namespace。

```YAML
apiVersion: v1
kind: Pod
...
spec:
  shareProcessNamespace: true
```

## 共享宿主机的Namespace

如下定义共享宿主机的Network、IPC和PID Namespace。这就意味着，这个Pod里所有的容器会直接使用宿主机的网络，直接与宿主机进行IPC通信，能访问宿主机的进程。

```YAML
apiVersion: v1
kind: Pod
...
spec:
  hostNetwork: true
  hostIPC: true
  hostPID: true
```

## Containers

Pod里最重要的字段当属Containers。包括Init Containers，他们都属于Pod对容器的定义，内容也完全相同，知识Init Containers的生命周期会先于所有Containers，并且严格按照定义的顺序执行。

### ImagePullPolicy

ImagePullPolicy是Container级别的属性，定义了镜像拉取策略，默认值是Always，即每次创建Pod都要重新拉取一次镜像。

另外，当容器镜像是类似于nginx或者nginx:latest这样的名字时，ImagePullPolicy也会被认为是Always。

如果ImagePullPolicy被指定为Never或者IfNotPresent，则意味着Pod永远不会主动拉取这个镜像，或者只在宿主机上不存在这个镜像时才拉取。

### Lifecycle

lifecycle定义的是Container Lifecycle Hooks，也就是在容器状态发生变化时触发一系列“钩子”。例如：

```YAML
apiVersion: v1
kind: Pod
...
spec:
  containers:
  - name: lifecycle-demo-container
    image: nginx
    lifecycle:
    # postStart不严格保证顺序
      postStart:
        exec:
         command: ["sh", "-c", "echo 'PostStart hook executed.'"]
    # preStop中的语句执行完之后容器才能退出
    preStop:
        exec:
         command: ["/usr/sbin/nginx", "-s", "quit"]
```

postStart指的是在容器启动后立刻执行一个指定操作。postStart定义的操作虽然是在Docker容器ENTRYPOINT执行之后，但它并不严格保证顺序。也就是说在postStart启动时ENTRYPOINT有可能尚未结束。

当然，如果postStart执行超时或出错，kubernetes会在该Pod的Events中报出该容器启动失败的错误信息，导致Pod也处于失败状态。

类似的，preStop发生的时机则是容器被结束之前（比如收到了SIGKILL信号）。需要明确的是，preStop操作的执行是同步的。所以，这会阻塞当前的容器结束流程，直到这个Hook定义操作完成之后，才允许容器被结束，这跟postStart不同。

## Pod对象的生命周期

`Pending`。这个状态意味着Pod的YAML文件已经提交给Kubernetes，API对象已经被创建并保存到etcd中。但是这个Pod里有些容器因为某种原因不能被顺利创建，比如调度失败。

`Running`。这个状态下，Pod已经调度成功，跟一个具体的节点绑定。它包含的容器都已经创建成功，并且至少有一个正在运行。

`Succeeded`。这个状态意味着Pod里的所有容器都正常运行完毕，并且已经退出了。这种情况在运行一次性任务时最常见。

`Failed`。这个状态下，Pod里至少有一个容器以不正常的状态（非0的返回码）退出。出现这个状态意味着需要想办法调试这个容器的应用，比如查看Pod的Events和日志。

`Unknown`。这是一个异常状态，意味着Pod的状态不能持续地被kubelet汇报给kube-apiserver，这很有可能是主从节点（Master金额kubelet）间的通信出现了问题。

更进一步，Pod对象的Status字段还可以细分出一组Conditions。这些细分状态的值包括：PodSchedule、Ready、Initialized以及Unschedulable。他们主要用于描述造成当前Status的具体原因是什么。

比如Pod当前的Status是Pending，对应的Condition是Unschedulable，这就意味着它的调度出现了问题。

其中Ready这个细分状态意味着Pod不仅已经正常启动（Running状态），而且可以对外提供服务了。这两者（Running和Ready）之间是有区别的。

















