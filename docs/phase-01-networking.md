# Phase 01 — Networking Foundation

This document describes the first completed phase of the lab: VMware networking, pfSense routing and the initial management access model.

---

## Scope

Phase 01 established the network foundation required before deploying Kubernetes.

Implemented in this phase:

* VMware virtual networks prepared.
* pfSense installed and configured.
* WAN uplink configured through VMware NAT.
* OUTSIDE management network configured.
* Kubernetes LAN configured.
* Dedicated management VM deployed.
* Initial pfSense firewall policy created.
* Baseline network connectivity validated.

---

## Design Summary

The lab uses pfSense as the routing and firewall boundary between the management network and the Kubernetes LAN.

```text
Windows Host
  ↓
VMware Workstation
  ↓
mgmt VM
  ↓
pfSense
  ↓
Kubernetes LAN
```

The Windows host runs VMware Workstation only. Daily administration is performed from the `mgmt` VM.

---

## VMware Networks

| VMware Network | Purpose                      | Subnet               |
| -------------- | ---------------------------- | -------------------- |
| VMnet8         | NAT / Internet uplink        | DHCP from VMware NAT |
| VMnet11        | OUTSIDE / management network | `192.168.50.0/24`    |
| VMnet10        | Kubernetes LAN               | `10.10.10.0/24`      |

VMware provides the virtual switching layer. pfSense provides routed connectivity and firewall control between the internal lab networks.

---

## pfSense Network Interfaces

| Interface Role | Purpose                        | Addressing          |
| -------------- | ------------------------------ | ------------------- |
| WAN            | Internet uplink via VMware NAT | DHCP                |
| OUTSIDE        | Management-side network        | `192.168.50.254/24` |
| LAN            | Kubernetes node network        | `10.10.10.254/24`   |

The lab uses `.254` as the gateway convention for routed internal networks.

---

## Management VM

The `mgmt` VM is the administrative entry point for the lab.

| VM     | Role                   | Address         |
| ------ | ---------------------- | --------------- |
| `mgmt` | Management workstation | `192.168.50.10` |

During installation, temporary NAT connectivity was used where required. After installation, daily management traffic was moved to the OUTSIDE network.

The `mgmt` VM is used for:

* pfSense WebGUI access.
* SSH administration.
* Kubernetes administration.
* Git and repository management.

---

## Initial Firewall Policy

The OUTSIDE interface policy was cleaned up and replaced with explicit management access from the `mgmt` VM.

Implemented OUTSIDE access:

| Source      | Destination             | Purpose                       |
| ----------- | ----------------------- | ----------------------------- |
| `HOST_MGMT` | pfSense HTTPS           | Firewall administration       |
| `HOST_MGMT` | pfSense ICMP            | Reachability testing          |
| `HOST_MGMT` | Kubernetes nodes TCP/22 | SSH administration            |
| `HOST_MGMT` | Kubernetes API TCP/6443 | Cluster administration        |
| `HOST_MGMT` | Any                     | Management VM outbound access |

LAN access:

| Source         | Destination | Purpose                                    |
| -------------- | ----------- | ------------------------------------------ |
| Kubernetes LAN | Any         | Node outbound connectivity through pfSense |

All other traffic is denied by the implicit firewall policy.

---

## pfSense Aliases

The following aliases were defined to keep firewall rules readable and maintainable.

### Network Aliases

| Alias         | Value             |
| ------------- | ----------------- |
| `NET_OUTSIDE` | `192.168.50.0/24` |
| `NET_K8S_LAN` | `10.10.10.0/24`   |

### Host Aliases

| Alias          | Value           |
| -------------- | --------------- |
| `HOST_MGMT`    | `192.168.50.10` |
| `HOST_MASTER`  | `10.10.10.20`   |
| `HOST_WORKER1` | `10.10.10.21`   |
| `HOST_WORKER2` | `10.10.10.22`   |

### Group Aliases

| Alias             | Value                                       |
| ----------------- | ------------------------------------------- |
| `GRP_K8S_NODES`   | `10.10.10.20`, `10.10.10.21`, `10.10.10.22` |
| `GRP_K8S_WORKERS` | `10.10.10.21`, `10.10.10.22`                |

### Port Aliases

| Alias          | Value   |
| -------------- | ------- |
| `PORT_SSH`     | `22`    |
| `PORT_K8S_API` | `6443`  |
| `PORT_WG`      | `51820` |
| `PORT_HTTPS`   | `443`   |

---

## Validation

The networking foundation was validated before moving on to Kubernetes node installation.

Validated successfully:

* pfSense WAN had upstream connectivity.
* pfSense could reach public DNS resolvers.
* `mgmt` could reach public DNS resolvers.
* `mgmt` could reach the pfSense OUTSIDE address.
* `mgmt` could access the pfSense WebGUI.
* pfSense OUTSIDE firewall baseline allowed required management traffic.
* Kubernetes LAN gateway was prepared for node connectivity.

---

## Checkpoint

`CHECKPOINT 1.1 PASSED`

The VMware networking and pfSense baseline were successfully completed. The environment was ready for Kubernetes node installation and static LAN addressing.
