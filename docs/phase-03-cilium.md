# Phase 03 — Cilium Networking

This document describes the third completed phase of the lab: installing Cilium, completing worker node join and validating Kubernetes workload networking.

---

## Scope

Phase 03 completed the Kubernetes networking layer and brought the cluster to its current validated state.

Implemented in this phase:

* Cilium CLI installed.
* Cilium installed as the Kubernetes Container Network Interface.
* Kubernetes IPAM mode configured for Cilium.
* kube-proxy retained.
* Worker nodes joined to the cluster.
* Cilium health validated.
* CoreDNS validated.
* Basic workload networking tested.
* Pod-to-service connectivity verified.

Hubble was not enabled as part of this phase. It is documented separately in [Phase 04 — Hubble Observability](phase-04-hubble.md). Cilium Network Policies and WireGuard are planned for later phases.

---

## Cilium Installation

Cilium was installed after the Kubernetes control plane had been initialised with `kubeadm`.

The lab uses Cilium with Kubernetes IPAM:

```bash
cilium install \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=false
```

Configuration choices:

| Setting                | Value        |
| ---------------------- | ------------ |
| IPAM mode              | `kubernetes` |
| kube-proxy replacement | `false`      |
| kube-proxy             | Present      |
| CNI                    | Cilium       |

Full kube-proxy replacement was not enabled at this stage because the cluster was initialised with the default kube-proxy add-on.

---

## Cluster Node Join

After Cilium was installed, the worker nodes joined the cluster using `kubeadm join`.

Final node layout:

| Node          | Role          | Status |
| ------------- | ------------- | ------ |
| `k8s-master`  | Control plane | Ready  |
| `k8s-worker1` | Worker        | Ready  |
| `k8s-worker2` | Worker        | Ready  |

The cluster currently consists of one control plane node and two worker nodes.

---

## Cluster Networking Components

The current Kubernetes networking stack consists of:

| Component  | Purpose                     | State   |
| ---------- | --------------------------- | ------- |
| Cilium     | Kubernetes CNI and datapath | Running |
| CoreDNS    | Cluster DNS                 | Running |
| kube-proxy | Kubernetes service proxy    | Present |
| containerd | Container runtime           | Running |

Cilium provides the pod networking layer for the cluster. CoreDNS provides service discovery inside Kubernetes.

---

## Validation

Cilium and the Kubernetes networking layer were validated after all nodes joined the cluster.

Validated successfully:

* All Kubernetes nodes report `Ready`.
* Cilium reports a healthy status.
* Cilium DaemonSet is running across all nodes.
* CoreDNS pods are running.
* Kubernetes API access is working.
* A test `nginx` deployment was created successfully.
* A ClusterIP service was created successfully.
* DNS resolution from a test pod was verified.
* Pod-to-service connectivity was verified.

---

## Workload Networking Test

A basic workload networking test was used to confirm that the cluster networking layer was functional.

Test components:

| Component          | Purpose                                              |
| ------------------ | ---------------------------------------------------- |
| `nginx` deployment | Test workload                                        |
| ClusterIP service  | Internal Kubernetes service exposure                 |
| Test pod           | Client used to validate DNS and service connectivity |

Successful validation confirmed that workloads could be scheduled, exposed internally and reached through Kubernetes service discovery.

---

## Current Cluster State

The lab currently has a healthy three-node Kubernetes cluster with Cilium installed and basic workload networking validated.

Current state:

* pfSense routing and firewalling operational.
* `mgmt` VM used as the administrative workstation.
* Kubernetes control plane running on `k8s-master`.
* Worker nodes joined and ready.
* `containerd` running on all Kubernetes nodes.
* Cilium installed and healthy.
* CoreDNS running.
* Basic Kubernetes service networking verified.

---

## Checkpoint

`Phase 03 checkpoint passed`

The three-node Kubernetes cluster is running successfully with Cilium CNI. Basic pod, service and DNS networking have been validated.
