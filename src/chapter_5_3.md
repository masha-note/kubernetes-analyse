# Pod对象使用进阶

kubernetes中的projected volume是一种特殊的volume。他们既不用于容器和宿主机之间的数据交换也不用来存放容器里的数据，而是为容器提供预先定义好的数据。

## Projected Volume

在这本书写成的时候，Kubernetes支持的常用Projected Volume共有以下4种：`Secret`、`ConfigMap`、`Downward API`、`ServiceAccountToken`。

1. Secret

Secret可以把Pod想要访问的加密数据存放到etcd中，容器可以通过挂载这个Volume来访问这些Secret里保存的信息。

下面是一个典型的用Secret存放数据库Credential的典型场景。

```YAML
apiVersion: v1
kind: Pod
metadata:
  name: test-projected-volume
spec:
  volumes:
  - name: mysql-cred
    projected:
      sources:
      - secret:
          name: user
      - secret:
          name: pass
  containers:
  - name: test-secret-volume
    image: busybox
    args:
    - sleep
    - "86400"
    volumeMounts:
    - name: mysql-cred
      mountPath: "/projected-volume"
      readOnly: true
```

这里声明挂载的Volume是projected类型。这个Volume的数据来源是名为user和pass的Secret的对象，分别对应数据库的用户名和密码。

Secret对象可以用下面的方法创建：

```SHELL
$ cat ./username.txt
admin
$ cat ./password.txt
961110
$ kubectl create secret generic user --from-file=./username.txt
$ kubectl create secret generic pass --from-file=./password.txt
```

username.txt和password.txt文件里存放的就是用户名和密码，user和pass则是为Secret对象指定的名字。可以通过如下命令查看。

```SHELL
$ kubectl get secrets
NAME        TYPE        DATA    AGE
user        Opaque      1       53s
pass        Opaque      1       52s
```

此外，还可以直接通过编写YAML文件来创建这个Secret对象。

```YAML
apiVersion: v1
kind: Secret
metadata:
  name: mysecret
type: Opaque
data:
  user: YWRtaW4=
  password: MWYyZDF1MmU2N2Rm
```

这个yaml文件创建出来的Secret对象只有一个，但它的data字段以k-v的格式保存了两份Secret数据。其中的内容经过了Base64转码：`echo -n 'admin' | base64`。

在真正的生产环境中，需要在kubernetes中开启Secret的加密插件，增强数据的安全性。

像这样通过挂载方式进入容器的Secret，一旦其对应的etcd里的数据更新，这些Volume里的文件内容也会更新（kubelet组件在定时维护这些Volume，这通常会有一定的延时，需要做好重试和超时）。





