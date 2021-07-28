#!/bin/sh

readonly PATRONI_SCOPE=${PATRONI_SCOPE:-batman}
PATRONI_NAMESPACE=${PATRONI_NAMESPACE:-/service}
readonly PATRONI_NAMESPACE=${PATRONI_NAMESPACE%/}
readonly DOCKER_IP=$(hostname --ip-address)

if [ "$PATRONI_MODE" = "cluster" ]; then
    export ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
    export ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
    export ETCD_INITIAL_CLUSTER_STATE=new
    export ETCD_INITIAL_CLUSTER_TOKEN=tutorial
    etcd --data-dir /tmp/etcd.data -name $ETCD_NODENAME -initial-advertise-peer-urls=$PATRONI_ETCD_PEER_URL -advertise-client-urls=http://127.0.0.1:2379 &
else
    export PATRONI_ETCD_URL="http://127.0.0.1:2379"
    etcd --data-dir /tmp/etcd.data -advertise-client-urls=http://127.0.0.1:2379 -listen-client-urls=http://0.0.0.0:2379 > /var/log/etcd.log 2> /var/log/etcd.err &
fi

export PATRONI_SCOPE
export PATRONI_NAMESPACE
export PATRONI_NAME="${PATRONI_NAME:-$(hostname)}"
export PATRONI_RESTAPI_CONNECT_ADDRESS="$DOCKER_IP:8008"
export PATRONI_RESTAPI_LISTEN="0.0.0.0:8008"
export PATRONI_admin_PASSWORD="${PATRONI_admin_PASSWORD:-admin}"
export PATRONI_admin_OPTIONS="${PATRONI_admin_OPTIONS:-createdb, createrole}"
export PATRONI_POSTGRESQL_CONNECT_ADDRESS="${POSTGRESQL_CONNECT_ADDRESS:-$DOCKER_IP:5432}"
export PATRONI_POSTGRESQL_LISTEN="0.0.0.0:5432"
export PATRONI_POSTGRESQL_DATA_DIR="${PATRONI_POSTGRESQL_DATA_DIR:-$PGDATA}"
export PATRONI_REPLICATION_USERNAME="${PATRONI_REPLICATION_USERNAME:-replicator}"
export PATRONI_REPLICATION_PASSWORD="${PATRONI_REPLICATION_PASSWORD:-replicate}"
export PATRONI_SUPERUSER_USERNAME="${PATRONI_SUPERUSER_USERNAME:-postgres}"
export PATRONI_SUPERUSER_PASSWORD="${PATRONI_SUPERUSER_PASSWORD:-postgres@digibird}"

chown postgres $PGDATA

exec gosu postgres python3 /patroni.py postgres.yml
