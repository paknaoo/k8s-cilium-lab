# Phase 02 — Kubernetes Bootstrap

This document describes the second completed phase of the lab: preparing the Kubernetes nodes, configuring the container runtime and initialising the Kubernetes control plane with `kubeadm`.

---

## Scope

Phase 02 prepared the Kubernetes nodes and bootstrapped the control plane.

Implemented in this phase:

* Kubernetes node operating system baseline configured.
* Static node addressing validated.
* Required kernel modules enabled.
* Required sysctl settings applied.
* Swap disabled.
* `containerd` installed and configured.
* Kubernetes packages installed.
* Kubernetes packages held at the installed version.
* Control plane initialised with `kubeadm`.
* `kubectl` access configured for the administrative user.

Worker nodes were prepared during this phase, but the final worker join and full cluster validation are covered in [Phase 03 — Cilium](phase-03-cilium.md), because Cilium installation was required before the cluster reached its final healthy state.

---

## Kubernetes Node Inventory

| Node          | Role          | Address       |
| ------------- | ------------- | ------------- |
| `k8s-master`  | Control plane | `10.10.10.20` |
| `k8s-worker1` | Worker        | `10.10.10.21` |
| `k8s-worker2` | Worker        | `10.10.10.22` |

All Kubernetes nodes use static addressing on the Kubernetes LAN and use pfSense as their default gateway.

| Setting | Value                |
| ------- | -------------------- |
| Gateway | `10.10.10.254`       |
| DNS     | `1.1.1.1`, `8.8.8.8` |

---

## Node Baseline

The following baseline tasks were completed on all Kubernetes nodes before installing Kubernetes components.

* System packages updated.
* Swap disabled.
* `overlay` kernel module enabled.
* `br_netfilter` kernel module enabled.
* IPv4 forwarding enabled.
* Bridge netfilter sysctl settings enabled.

Relevant sysctl settings:

```text
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
```

These settings prepare the Linux hosts for Kubernetes networking and container traffic forwarding.

---

## Container Runtime

`containerd` was installed on all Kubernetes nodes and configured as the container runtime.

The runtime was configured to use the systemd cgroup driver:

```text
SystemdCgroup = true
```

Validation completed:

* `containerd` service active on all nodes.
* `SystemdCgroup = true` confirmed in the containerd configuration.

---

## Kubernetes Packages

The following Kubernetes packages were installed on all Kubernetes nodes:

| Package   | Purpose                              |
| --------- | ------------------------------------ |
| `kubeadm` | Cluster bootstrap and node join tool |
| `kubelet` | Node agent                           |
| `kubectl` | Kubernetes command-line client       |

Installed Kubernetes version:

```text
v1.36.1
```

Validated versions:

| Component | Version   |
| --------- | --------- |
| `kubeadm` | `v1.36.1` |
| `kubelet` | `v1.36.1` |
| `kubectl` | `v1.36.1` |
| Kustomize | `v5.8.1`  |

The Kubernetes packages were placed on hold to prevent unintended upgrades:

* `kubeadm`
* `kubelet`
* `kubectl`

Before `kubeadm init` and `kubeadm join`, the `kubelet` service was expected to restart because the nodes did not yet have complete cluster configuration.

---

## Control Plane Initialisation

The control plane was initialised on `k8s-master` using `kubeadm`.

Configuration choices:

| Setting                      | Value           |
| ---------------------------- | --------------- |
| API server advertise address | `10.10.10.20`   |
| Control plane endpoint       | `10.10.10.20`   |
| Pod network CIDR             | `10.244.0.0/16` |

Conceptual command:

```bash
sudo kubeadm init \
  --apiserver-advertise-address=10.10.10.20 \
  --control-plane-endpoint=10.10.10.20 \
  --pod-network-cidr=10.244.0.0/16
```

After successful initialisation, the Kubernetes admin configuration was copied for the `adam` user on `k8s-master`:

```text
~/.kube/config
```

This enabled `kubectl` access from the control plane node.

---

## Expected State Before CNI Installation

After `kubeadm init`, the control plane was initialised but the cluster networking layer had not yet been installed.

Expected temporary state:

* `k8s-master` not fully ready until CNI installation.
* CoreDNS pending until CNI installation.
* Worker nodes prepared but not yet part of the final validated cluster state.

This was expected because Kubernetes requires a Container Network Interface before pod networking can operate correctly.

---

## Validation

Phase 02 was validated before moving to Cilium installation.

Validated successfully:

* Static IP addressing configured on all Kubernetes nodes.
* Default route configured through pfSense.
* DNS resolvers configured.
* SSH access from `mgmt` to all Kubernetes nodes confirmed.
* Kubernetes node baseline completed.
* Required kernel modules loaded.
* Required sysctl settings applied.
* `containerd` active on all nodes.
* Kubernetes packages installed and version-checked.
* Kubernetes packages placed on hold.
* `kubeadm init` completed successfully.
* `kubectl` access configured for the administrative user.

---

## Checkpoint

`Phase 02 checkpoint passed`

The Kubernetes control plane was successfully initialised. The environment was ready for Cilium installation and final cluster networking validation.
