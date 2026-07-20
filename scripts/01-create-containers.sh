#!/usr/bin/env bash
# Phase 1 - Step 1: create & start 4 Ubuntu 22.04 LXC containers.
set -euo pipefail

NODES=(dc-master dc-slave dr-master dr-slave)

for NODE in "${NODES[@]}"; do
  if lxc-info -n "$NODE" &>/dev/null; then
    echo "==> $NODE already exists, skipping creation"
  else
    echo "==> Creating $NODE"
    lxc-create -n "$NODE" -t download -- -d ubuntu -r jammy -a amd64
  fi
  lxc-start -n "$NODE" -d
done

sleep 5
lxc-ls -f
