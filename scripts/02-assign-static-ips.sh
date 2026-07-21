#!/usr/bin/env bash
# Phase 1 - Step 2: static IPs + /etc/hosts for all 4 nodes.
set -euo pipefail

declare -A IPS=(
  [dc-master]=10.0.3.11
  [dc-slave]=10.0.3.12
  [dr-master]=10.0.3.13
  [dr-slave]=10.0.3.14
)

HOSTS_BLOCK="10.0.3.11 dc-master
10.0.3.12 dc-slave
10.0.3.13 dr-master
10.0.3.14 dr-slave"

for NODE in "${!IPS[@]}"; do
  IP="${IPS[$NODE]}"
  echo "==> $NODE -> $IP"

  lxc-attach -n "$NODE" -- bash -c "cat > /etc/netplan/10-static.yaml <<NETEOF
network:
  version: 2
  ethernets:
    eth0:
      dhcp4: no
      addresses: [$IP/24]
      routes:
        - to: default
          via: 10.0.3.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
NETEOF"

  lxc-attach -n "$NODE" -- bash -c "chmod 600 /etc/netplan/10-static.yaml && netplan apply"
  lxc-attach -n "$NODE" -- hostnamectl set-hostname "$NODE"
  lxc-attach -n "$NODE" -- bash -c "grep -q dc-master /etc/hosts || echo '$HOSTS_BLOCK' >> /etc/hosts"
done

echo "==> Done."
