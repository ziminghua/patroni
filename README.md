# Patroni 一款PGSQL高可用的方案

## 仓库目的

由于官方并为直接提供可用的docker镜像，只提供了有一些Dockerfile的例子，所以。。。。。。。。。基于官方的例子进行魔改。剔除了其中的haproxy的依赖，以及我们目前没有其他的DCS环境，所以直接采用了etcd进行部署。相关修改详见[Dockerfile](./Dockerfile)、[entrypoint.sh](./docker/entrypoint.sh)。

## 使用方式
```
docker run -t digibird/patroni_pgsql10 .
```

### 修改配置

patroni简化了pgsql本身的主从配置，都通过patroni进行管理，大致只需要有两个配置文件`patroni.env`和`postgres.yml`。

#### patroni.env

PS：集群时才需要

````
# etcd集群节点列表
ETCD_INITIAL_CLUSTER=etcd1=http://192.168.1.244:2380,etcd2=http://192.168.1.244:2381,etcd3=http://192.168.1.244:2382
# etc节点名称，对应节点例表中的数据
ETCD_NODENAME=etcd1
# etcd集群间访问地址
PATRONI_ETCD_PEER_URL=http://192.168.1.244:2380
# pgsql的外部连接地址
POSTGRESQL_CONNECT_ADDRESS=192.168.1.244:5433
# patroni模式，如果为cluster则启用集群模式
PATRONI_MODE=cluster
````
#### postgres.yml

常规使用，除了数据库的密码，其他几乎无需修改。详细的描述请参考[YAML Configuration Settings](https://github.com/zalando/patroni/blob/master/docs/SETTINGS.rst)

```
scope: batman
#namespace: /service/
name: postgresql0

restapi:
  listen: 127.0.0.1:8008
  connect_address: 127.0.0.1:8008
#  certfile: /etc/ssl/certs/ssl-cert-snakeoil.pem
#  keyfile: /etc/ssl/private/ssl-cert-snakeoil.key
#  authentication:
#    username: username
#    password: password

# ctl:
#   insecure: false # Allow connections to SSL sites without certs
#   certfile: /etc/ssl/certs/ssl-cert-snakeoil.pem
#   cacert: /etc/ssl/certs/ssl-cacert-snakeoil.pem

etcd:
  #Provide host to do the initial discovery of the cluster topology:
  host: 127.0.0.1:2379
  #Or use "hosts" to provide multiple endpoints
  #Could be a comma separated string:
  #hosts: host1:port1,host2:port2
  #or an actual yaml list:
  #hosts:
  #- host1:port1
  #- host2:port2
  #Once discovery is complete Patroni will use the list of advertised clientURLs
  #It is possible to change this behavior through by setting:
  #use_proxies: true

#raft:
#  data_dir: .
#  self_addr: 127.0.0.1:2222
#  partner_addrs:
#  - 127.0.0.1:2223
#  - 127.0.0.1:2224

bootstrap:
  # this section will be written into Etcd:/<namespace>/<scope>/config after initializing new cluster
  # and all other cluster members will use it as a `global configuration`
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
#    master_start_timeout: 300
#    synchronous_mode: false
    #standby_cluster:
      #host: 127.0.0.1
      #port: 1111
      #primary_slot_name: patroni
    postgresql:
      use_pg_rewind: true
#      use_slots: true
      parameters:
#        wal_level: hot_standby
#        hot_standby: "on"
         max_connections: 1000
#        max_worker_processes: 8
#        wal_keep_segments: 8
#        max_wal_senders: 10
#        max_replication_slots: 10
#        max_prepared_transactions: 0
#        max_locks_per_transaction: 64
#        wal_log_hints: "on"
#        track_commit_timestamp: "off"
#        archive_mode: "on"
#        archive_timeout: 1800s
#        archive_command: mkdir -p ../wal_archive && test ! -f ../wal_archive/%f && cp %p ../wal_archive/%f
#      recovery_conf:
#        restore_command: cp ../wal_archive/%f %p

  # some desired options for 'initdb'
  initdb:  # Note: It needs to be a list (some options need values, others are switches)
  - encoding: UTF8
  - data-checksums

  pg_hba:  # Add following lines to pg_hba.conf after running 'initdb'
  # For kerberos gss based connectivity (discard @.*$)
  #- host replication replicator 127.0.0.1/32 gss include_realm=0
  #- host all all 0.0.0.0/0 gss include_realm=0
  - host replication replicator all md5
  - host all all all md5
#  - hostssl all all 0.0.0.0/0 md5

  # Additional script to be launched after initial cluster creation (will be passed the connection URL as parameter)
# post_init: /usr/local/bin/setup_cluster.sh

  # Some additional users users which needs to be created after initializing new cluster
  users:
    admin:
      password: admin
      options:
        - createrole
        - createdb

postgresql:
  listen: 127.0.0.1:5432
  connect_address: 127.0.0.1:5432
  data_dir: /usr/lib/postgresql/10/data
#  bin_dir:
#  config_dir:
  pgpass: /tmp/pgpass0
  authentication:
    replication:
      username: replicator
      password: rep-pass
    superuser:
      username: postgres
      password: postgres@digibird
    rewind:  # Has no effect on postgres 10 and lower
      username: rewind_user
      password: rewind_password
  # Server side kerberos spn
#  krbsrvname: postgres
  parameters:
    # Fully qualified kerberos ticket file for the running user
    # same as KRB5CCNAME used by the GSS
#   krb_server_keyfile: /var/spool/keytabs/postgres
    unix_socket_directories: '.'
  # Additional fencing script executed after acquiring the leader lock but before promoting the replica
  #pre_promote: /path/to/pre_promote.sh

#watchdog:
#  mode: automatic # Allowed values: off, automatic, required
#  device: /dev/watchdog
#  safety_margin: 5

tags:
    nofailover: false
    noloadbalance: false
    clonefrom: false
    nosync: false

```

#### Datasource

相应的datasource也需要修改成多主机，如下：jdbc驱动会连接主节点进行数据访问。

```
spring:
  datasource:
    url: jdbc:${DATABASE_DBTYPE:postgresql}://192.168.1.244:5433,192.168.1.244:5434,192.168.1.244:5435/postgres?targetServerType=primary&currentSchema=public
```

### 启动容器

```
docker run -d --name test -p 2380:2380 -p 5433:5432 --env-file F:\3-cluster\pgsql\pgsql_conf\patroni.env  -v F:\3-cluster\pgsql\pgsql_conf\postgres.yml:/usr/lib/postgresql/10/postgres.yml digibird/patroni_pgsql10

docker run -d --name test1 -p 2381:2380 -p 5434:5432 --env-file F:\3-cluster\pgsql\pgsql_conf\patroni1.env  -v F:\3-cluster\pgsql\pgsql_conf\postgres.yml:/usr/lib/postgresql/10/postgres.yml digibird/patroni_pgsql10

docker run -d --name test2 -p 2382:2380 -p 5435:5432 --env-file F:\3-cluster\pgsql\pgsql_conf\patroni2.env  -v F:\3-cluster\pgsql\pgsql_conf\postgres.yml:/usr/lib/postgresql/10/postgres.yml digibird/patroni_pgsql10
```
