# ansible-fabric

## 功能

- prod_prepare.yml
  - 对目标机器进行必要的准备，以使该机器可以进行后续的fabric部署
- prod_dnsmasq.yml
  - 根据inventory里面的主机，部署dnsmasq本地dns解析服务
- prod_monitor.yml
  - 部署基于grafana+prometheus+cadvisor的监控系统
- prod_fabric.yml
  - 部署多节点的fabric系统

      **注意：** 部署前会清理所有fabric相关的容器及fabric生成的镜像.

  - 目前支持的fabric部署拓扑为：

    ```bash
    2 * dnsmasq
    1 * orderer --> solo模式
    n * ca      --> 1 ca / org
    m * peer    --> m = m1/org1 + m2/org2 + ... + mx/orgx
    ```

  - 监控系统的拓扑为：

    ```bash
    1 * grafana
    1 * prometheus
    1 * alertmanager
    1 * prometheus-am-executor
    n * nodeexporter    --> 所有节点数量
    n * cadvisor        --> 所有节点数量
    ```

## 准备

所有节点，含监控系统的节点，建议采用如下系统拓扑：

- 独立云硬盘`/dev/vdb`
  - 挂载点 `/var/lib/docker`
  - docker存储建议使用`overlay`
- 独立云硬盘`/dev/vdc`
  - 挂载点 `/hfc-data/`，用于存储各节点容器的配置、数据及恢复文件
  - 例如，fabric各节点
    - `/hfc-data/<容器名>/configtx`，用来存储各容器节点的配置文件
    - `/hfc-data/<容器名>/restore`，用来存储各容器节点的手工恢复脚本
    - `/hfc-data/<容器名>/data`，用来存储各peer容器节点的数据

## 其他

- `config/`目录，为临时客户端所用
- `config_jcloud-blockchain_client.sh` 为临时测试客户端所用
- `registry.hfc.test.io:5000/grafana/`目录，为grafana的dashboard模板

## 版本

目前可以正常工作的版本为`1.0.0-snapshot-56b6d12`：

```bash
registry.hfc.test.io:5000/fabric/fabric-ca:x86_64-1.0.0-snapshot-f0f86b7
registry.hfc.test.io:5000/fabric/fabric-couchdb:x86_64-1.0.0-snapshot-56b6d12
registry.hfc.test.io:5000/fabric/fabric-orderer:x86_64-1.0.0-snapshot-56b6d12
registry.hfc.test.io:5000/fabric/fabric-peer:x86_64-1.0.0-snapshot-56b6d12
registry.hfc.test.io:5000/fabric/fabric-ccenv:x86_64-1.0.0-snapshot-56b6d12
hyperledger/fabric-baseimage:x86_64-0.3.0
hyperledger/fabric-baseos:x86_64-0.3.0
```

**注意：** 因此版本存在bug，因此默认禁用tls。

**注意：** 已经更新至最新的`v1.0.0-alpha2`，待客户端更新之后测试及调优。

## 用法

1. 登陆`docker-registry`主机
1. 切换到playbook将要存放的目录，如

    ```bash
    mkdir -p /tmp/playbook/
    cd /tmp/playbook/
    ```

1. 通过git下载playbook，并切换至相应的tag

    ```bash
    git clone http://10.10.0.11:3000/fabric/ansible-fabric.git
    git checkout tags/v1.0.0-Release-3
    ```

1. 根据实际修改`inventories/prod/hosts`中的ip地址及角色分配。

1. 执行部署脚本：`bash run_prod_playbook.sh <option>`，可用的option， 可通过 `bash run_prod_playbook.sh -help`查看。

1. 各容器节点默认端口：
- fabric服务
  - ca: 7054
  - orderer: 7050
  - peer:
    - grpc: 7051
    - event: 7053
- 监控服务
  - grafana: 9095
  - prometheus: 9090
  - altermanager: 9093
  - nodeexporter: 9100 <127.0.0.1:4321>
  - cadvisor: 8080

1. 所有云主机及云主机上的容器均加入prometheus监控，默认设置邮件报警，默认邮件会发送至liuchenglong3@jd.com

**注意：** 以上参数可通过修改`inventories/prod/hosts`和`inventories/prod/group_vars/*`等文件进行按需调整。

## 关于容器恢复

如果需要手工执行恢复脚本，请确保：

- `/hfc-data/<容器名>/configtx/`已经存在并且数据完整
- `/hfc-data/<容器名>/restore/`已经存在并且数据完整
  - 根据节点信息，确保`hosts`文件中该节点的IP信息正确
  - 根据实际节点的信息，确认`env.list`中的必要更新
- 如果是peer节点和orderer节点，需要确保`/hfc-data/<容器名>/data/`已经存在并且数据完整
- 默认备份文件存放在:
  - /var/lib/docker/dnsmasq-backup
  - /var/lib/docker/monitor-backup
  - /var/lib/docker/hfc-backup
- 备份文件以tgz格式存放
- 备份文件默认只保留7天

