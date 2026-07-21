#!/usr/bin/env bash
# Phase 2: PostgreSQL 16 install + streaming replication setup.
# NOTE: This documents the steps already performed manually.
# Re-running against already-configured nodes is NOT idempotent - use with care.
set -euo pipefail

REPL_PASS="ReplPass123"

echo "==> Step 1: Install PostgreSQL 16 on all 4 nodes (run per node)"
for NODE in dc-master dc-slave dr-master dr-slave; do
  lxc-attach -n "$NODE" -- bash -c "
    apt-get update -y
    apt-get install -y curl ca-certificates gnupg
    install -d /usr/share/postgresql-common/pgdg
    curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
    echo 'deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt jammy-pgdg main' > /etc/apt/sources.list.d/pgdg.list
    apt-get update -y
    apt-get install -y postgresql-16
  "
done

echo "==> Step 2: Create replicator role on dc-master"
lxc-attach -n dc-master -- sudo -u postgres psql -c "CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '${REPL_PASS}';"

echo "==> Step 3: Configure dc-master as primary (sync to dc-slave)"
lxc-attach -n dc-master -- bash -c "cat >> /etc/postgresql/16/main/postgresql.conf <<EOF

# --- Replication settings (dc-master, primary) ---
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
synchronous_commit = on
synchronous_standby_names = 'dc_slave'
EOF"
lxc-attach -n dc-master -- bash -c "cat >> /etc/postgresql/16/main/pg_hba.conf <<EOF

# --- Replication access ---
host    replication     replicator      10.0.3.12/32            scram-sha-256
host    replication     replicator      10.0.3.13/32            scram-sha-256
host    replication     replicator      10.0.3.14/32            scram-sha-256
EOF"
lxc-attach -n dc-master -- systemctl restart postgresql@16-main

echo "==> Step 4: Clone dc-slave from dc-master (sync)"
lxc-attach -n dc-slave -- systemctl stop postgresql@16-main
lxc-attach -n dc-slave -- bash -c "rm -rf /var/lib/postgresql/16/main/*"
lxc-attach -n dc-slave -- sudo -u postgres env PGPASSWORD="${REPL_PASS}" pg_basebackup -h dc-master -U replicator -D /var/lib/postgresql/16/main -Fp -Xs -P -R
lxc-attach -n dc-slave -- sudo -u postgres sed -i "s/primary_conninfo = '/primary_conninfo = 'application_name=dc_slave /" /var/lib/postgresql/16/main/postgresql.auto.conf
lxc-attach -n dc-slave -- systemctl start postgresql@16-main

echo "==> Step 5: Configure dr-master to accept cascading replica (dr-slave)"
lxc-attach -n dr-master -- bash -c "cat >> /etc/postgresql/16/main/postgresql.conf <<EOF

# --- Replication settings (dr-master, cascading standby source) ---
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
EOF"

echo "==> Step 6: Clone dr-master from dc-master (async)"
lxc-attach -n dr-master -- systemctl stop postgresql@16-main
lxc-attach -n dr-master -- bash -c "rm -rf /var/lib/postgresql/16/main/*"
lxc-attach -n dr-master -- sudo -u postgres env PGPASSWORD="${REPL_PASS}" pg_basebackup -h dc-master -U replicator -D /var/lib/postgresql/16/main -Fp -Xs -P -R
lxc-attach -n dr-master -- sudo -u postgres sed -i "s/primary_conninfo = '/primary_conninfo = 'application_name=dr_master /" /var/lib/postgresql/16/main/postgresql.auto.conf
lxc-attach -n dr-master -- bash -c "cat >> /etc/postgresql/16/main/pg_hba.conf <<EOF

# --- Replication access (cascading to dr-slave) ---
host    replication     replicator      10.0.3.14/32            scram-sha-256
EOF"
lxc-attach -n dr-master -- systemctl start postgresql@16-main

echo "==> Step 7: Clone dr-slave from dr-master (async, cascading)"
lxc-attach -n dr-slave -- systemctl stop postgresql@16-main
lxc-attach -n dr-slave -- bash -c "rm -rf /var/lib/postgresql/16/main/*"
lxc-attach -n dr-slave -- sudo -u postgres env PGPASSWORD="${REPL_PASS}" pg_basebackup -h dr-master -U replicator -D /var/lib/postgresql/16/main -Fp -Xs -P -R
lxc-attach -n dr-slave -- sudo -u postgres sed -i "s/primary_conninfo = '/primary_conninfo = 'application_name=dr_slave /" /var/lib/postgresql/16/main/postgresql.auto.conf
lxc-attach -n dr-slave -- systemctl start postgresql@16-main

echo "==> Done. Verify with: sudo -u postgres psql -c 'SELECT pg_is_in_recovery();' on each standby"
