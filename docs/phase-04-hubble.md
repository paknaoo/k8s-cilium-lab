# Phase 04 — Hubble Observability

This document describes the fourth completed phase of the lab: enabling Hubble for Cilium observability and validating flow visibility across the Kubernetes cluster.

---

## Scope

Phase 04 added observability for the existing Cilium networking layer.

Implemented in this phase:

* Hubble enabled for Cilium.
* Hubble Relay deployed and validated.
* Hubble UI deployed and validated.
* Hubble services and endpoints verified.
* `hubble observe` validated with live flow output.
* Hubble UI accessed from the management workstation using an SSH tunnel.

Cilium Network Policies were not enabled as part of this phase. Basic policy enforcement is documented in [Phase 05 — Network Policies](phase-05-network-policies.md), while advanced policy scenarios are documented in [Phase 08 — Advanced Cilium Policies](phase-08-advanced-cilium-policies.md).

WireGuard management connectivity was implemented in [Phase 06 — WireGuard Full-Tunnel VPN](phase-06-wireguard.md).

---

## Hubble Components

Hubble provides visibility into network flows handled by Cilium.

| Component     | Purpose                                 | State   |
| ------------- | --------------------------------------- | ------- |
| Hubble Relay  | Aggregates flow data from Cilium agents | Running |
| Hubble UI     | Web interface for observing flows       | Running |
| Hubble CLI    | Command-line flow observation           | Working |
| Cilium agents | Source of flow visibility               | Running |

---

## Access Model

Hubble UI was accessed from the `mgmt` VM through an SSH tunnel to the control plane node.

The Hubble UI port-forward runs on the machine where the command is executed. When `cilium hubble ui` is run on `k8s-master`, `localhost:12000` refers to `k8s-master`, not the `mgmt` VM.

To access the UI from the `mgmt` VM, an SSH local port forward is used:

```bash
ssh -L 12000:127.0.0.1:12000 master
```

Inside the SSH session, Hubble UI is started:

```bash
cilium hubble ui
```

The UI is then accessed from the `mgmt` VM browser:

```text
http://localhost:12000
```

This keeps the Hubble UI bound to localhost while still allowing access from the management workstation.

---

## Validation

Hubble was validated after deployment.

Validated successfully:

* Cilium status healthy.
* Hubble Relay running.
* Hubble UI running.
* Hubble services available.
* Hubble endpoints available.
* `hubble observe` shows live flow output.
* Hubble UI accessible from the `mgmt` VM through an SSH tunnel.

---

## Current State

The lab now has Cilium networking with Hubble observability enabled.

Current state:

* Three-node Kubernetes cluster running.
* Cilium installed and healthy.
* Hubble enabled.
* Hubble Relay running.
* Hubble UI running.
* Flow visibility available through the Hubble CLI.
* Flow visibility available through the Hubble UI using an SSH tunnel.

---

## Checkpoint

`Phase 04 checkpoint passed`

Hubble observability is installed, running and validated. The environment is ready for Cilium Network Policies.
