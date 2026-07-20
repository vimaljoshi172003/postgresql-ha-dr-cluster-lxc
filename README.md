# pg-ha-dr-cluster

A 4-node PostgreSQL High-Availability + Disaster-Recovery lab, built with plain
LXC containers on a single local Linux machine, with an interactive web GUI
for cluster status, failover, and ad-hoc query browsing.

## Topology

- **DC-Master** (10.0.3.11): primary, read-write, all app traffic
- **DC-Slave** (10.0.3.12): synchronous standby — zero data loss failover partner, same site
- **DR-Master** (10.0.3.13): asynchronous standby fed from DC-Master — promotable on full DC loss
- **DR-Slave** (10.0.3.14): cascading async standby off DR-Master — HA partner within the DR site

Patroni + etcd will handle leader election and automatic failover inside each
site. HAProxy will route client traffic to whichever node is currently the
leader. A custom web GUI (Node/Express + React) will give live cluster status,
one-click failover/switchover, and a pgAdmin-style query browser.

## Build phases

| Phase | What | Status |
|---|---|---|
| 1 | Host prep + 4 LXC containers with static IPs | in progress |
| 2 | PostgreSQL 16 install + streaming replication | next |
| 3 | Patroni + etcd automatic failover | next |
| 4 | HAProxy traffic routing | next |
| 5 | Web GUI (status / failover / query browser) | next |
