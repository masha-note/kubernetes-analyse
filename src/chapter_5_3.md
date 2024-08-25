# Pod对象使用进阶

kubernetes中的projected volume是一种特殊的volume。他们既不用于容器和宿主机之间的数据交换也不用来存放容器里的数据，而是为容器提供预先定义好的数据。

## Projected Volume

在这本书写成的时候，Kubernetes支持的常用Projected Volume共有以下4种：`Secret`、`ConfigMap`、`Downward API`、`ServiceAccountToken`。

### Secret

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

### ConfigMap

与Secret类似，但是ConfigMap保存的是无需加密的、应用所需要的配置信息。用法几乎与Sceret完全相同，可以使用`kubectl create configmap`从文件或者目录创建ConfigMap，也可以直接编写ConfigMap对象的YAML文件。

```SHELL
# 文件中的内容
masha@kind-single-node:~/Projects/masha-note/kubernetes-analyse/example$ cat ui.properties
color.good=purple
color.bad=yellow
allow.textmode=true
how.nice.to.look=fairlyNice

# 从properties文件创建ConfigMap
masha@kind-single-node:~/Projects/masha-note/kubernetes-analyse/example$ kubectl create configmap ui-config --from-file=ui.properties
configmap/ui-config created

# 查看这个ConfigMap里保存的信息
masha@kind-single-node:~/Projects/masha-note/kubernetes-analyse/example$ kubectl get configmaps ui-config -o yaml
apiVersion: v1
data:
  ui.properties: |
    color.good=purple
    color.bad=yellow
    allow.textmode=true
    how.nice.to.look=fairlyNice
kind: ConfigMap
metadata:
  ...
```

`kubectl get -o yaml`将会以yaml的格式输出获取到的内容。

### Downward API

Downward API的作用是让Pod里的容器能够直接获取到这个Pod API对象本身的信息。例如：

```YAML
apiVersion: v1
kind: Pod
metadata:
  name: test-downwardapi
  labels:
    name: test-downwardapi
    ip: 192.168.50.60
spec:
  containers:
  - name: test-downwardapi
    image: k8s.gcr.io/busybox
    resources:
      limits:
        memory: "128Mi"
        cpu: "500m"
    volumeMounts:
      - name: podinfo
        mountPath: /etc/podinfo
        readOnly: false
  volumes:
    - name: podinfo
      projected:
        sources:
        - downwardAPI:
            items:
              - path: "labels"
                fieldRef:
                  fieldPath: metadata.labels
```

projected类型的Volume的数据源是Downward API，该Downward API Volume声明了要暴露Pod的meta.labels信息给容器。通过这样的声明方式，当前Pod的Labels字段的值就会被kubernetes自动挂载成容器里的/etc/podinfo/labels文件。

当前Downward API支持的字段示例如下。

#### 使用fieldRef可以声明使用的

metadata.name——Pod名称  
metadata.namesoace——Pod的Namespace  
metadata.uid——Pod的UID  
metadata.labels['key']——指定key值对应的Label值  
metadata.annotations['key']——指定key值对应的annotation值  
metadata.labels——Pod的所有Labels  
metadata.annotations——所有的annotation  

#### 使用resourceFieldRef可以声明使用的

容器的CPU limit  
容器的CPU request  
容器的memory limit  
容器的memory request  
容器的ephemeral-storage limit  
容器的ephemeral-storage request  

#### 通过环境变量声明使用

status.podIP——Pod的IP  
spec.serviceAccountName——Pod的ServiceAccount名字  
spec.nodeName——Node的名字  
status.hostIP——Node的IP  

需要注意的是，Downward API能够获取的信息一定是Pod里的容器进程启动之前就能够确定下来的信息。如果想要获取Pod容器运行后才会出现的信息，比如容器的PID，就无法使用Downward API而应该考虑sidecar容器。













