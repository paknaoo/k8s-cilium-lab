# Phase 07 — Repository Artefacts

This document describes the seventh completed phase of the lab: capturing the current working configuration as safe, reproducible repository artefacts.

All artefacts in this phase were derived from the live `k8s-cilium-lab` environment.

---

## Scope

Phase 07 added the technical evidence required to reproduce and validate the completed Cilium networking work.

Implemented in this phase:

* Current `netpol-demo` resources exported from the live cluster.
* Runtime-generated metadata removed from exported manifests.
* Cilium status and configuration snapshots captured.
* Hubble status and workload snapshots captured.
* Cluster health validation script added.
* Network policy validation script added.
* Invalid `CiliumNetworkPolicy` case documented.
* Repository content scanned for sensitive information.
* Generated manifests validated against the live Kubernetes API.

No new cluster functionality was introduced during this phase.

---

## Source of Truth

The working lab was used as the only source of truth.

Artefacts were collected using:

* live `kubectl` output;
* live `cilium` output;
* live `hubble` output;
* existing Kubernetes resources;
* tests previously executed and confirmed in the lab.

Configuration was not reconstructed from generic examples or assumptions.

---

## Manifest Artefacts

The current `netpol-demo` resources are stored under:

```text
manifests/netpol-demo/
```

The exported resources include:

* the `netpol-demo` Namespace;
* backend Deployment;
* frontend Deployment;
* client Deployment;
* backend ClusterIP Service;
* backend default-deny ingress `NetworkPolicy`;
* client default-deny egress `NetworkPolicy`;
* frontend-to-backend `CiliumNetworkPolicy`;
* client DNS egress `CiliumNetworkPolicy`.

The manifests were generated from live cluster exports.

Only runtime-generated fields were removed, including:

* resource versions;
* UIDs;
* creation timestamps;
* managed fields;
* status sections;
* allocated Service addresses;
* server-generated annotations.

The effective workload and policy configuration was preserved.

---

## Configuration Snapshots

Cilium snapshots are stored under:

```text
snapshots/cilium/
```

They include:

```text
cilium-status.txt
cilium-config.txt
network-policy-status.txt
```

Hubble snapshots are stored under:

```text
snapshots/hubble/
```

They include:

```text
hubble-status.txt
cilium-hubble-pods.txt
cilium-hubble-services.txt
```

These files record the verified state of Cilium and Hubble at the Phase 7 checkpoint.

Snapshots represent a point-in-time state and are not intended to replace live health checks.

---

## Validation Scripts

The following scripts are stored under `scripts/`.

### Cluster health

```text
scripts/validate-cluster.sh
```

This script checks:

* Kubernetes node readiness;
* Cilium health;
* Hubble availability;
* Cilium and Hubble workloads;
* network policy inventory;
* `CiliumNetworkPolicy` validity;
* recent Hubble flows.

### Network policy behaviour

```text
scripts/validate-netpol-demo.sh
```

This script verifies the final policy state:

```text
frontend → backend TCP/80: allowed
client → backend TCP/80: denied
client → Kubernetes DNS: allowed
client → internet HTTPS: denied
```

It also queries Hubble for recent namespace flows and dropped flows.

The scripts execute the existing final-state tests and do not remove or replace cluster policies.

---

## Manifest Validation

Each generated manifest was validated against the working cluster using server-side dry-run:

```bash
for file in manifests/netpol-demo/*.yaml; do
  ssh master 'kubectl apply --dry-run=server -f -' < "$file" || exit 1
done
```

This validated the resources against:

* the Kubernetes API;
* installed API versions;
* the active Cilium Custom Resource Definitions.

No cluster resources were changed during validation.

---

## Script Validation

Both scripts were checked for valid Bash syntax:

```bash
bash -n scripts/validate-cluster.sh
bash -n scripts/validate-netpol-demo.sh
```

They were then executed against the working cluster through SSH:

```bash
ssh master 'bash -s' < scripts/validate-cluster.sh
ssh master 'bash -s' < scripts/validate-netpol-demo.sh
```

Both scripts completed with the expected results.

---

## Documented Policy Validation Case

The invalid empty-ingress `CiliumNetworkPolicy` case is documented in:

```text
docs/troubleshooting/invalid-cilium-network-policy.md
```

The document records:

* the attempted rule structure;
* the observed `VALID=False` state;
* the Cilium validation message;
* the corrected implementation;
* the final policy verification.

Only this confirmed case is included in the troubleshooting documentation.

---

## Security Controls

The repository must not contain:

* Kubernetes Secrets;
* kubeconfig files;
* service-account tokens;
* credentials or passwords;
* WireGuard private keys;
* TLS private keys;
* active secret values.

Live exports and generated artefacts were scanned before being added to the repository.

Private or sensitive source files remain outside the Git working tree.

---

## Artefact Layout

```text
manifests/
└── netpol-demo/
    ├── namespace
    ├── deployments
    ├── service
    └── network policies

snapshots/
├── cilium/
└── hubble/

scripts/
├── validate-cluster.sh
└── validate-netpol-demo.sh

docs/
├── phase-07-repository-artefacts.md
└── troubleshooting/
    └── invalid-cilium-network-policy.md
```

The exact manifest filenames reflect the names of the resources exported from the working cluster.

---

## Validation

Phase 07 was validated successfully.

* Cluster health: OK.
* All Kubernetes nodes Ready: OK.
* Cilium agents and operator healthy: OK.
* Hubble Relay and UI healthy: OK.
* Hubble flows visible: OK.
* Network policy inventory correct: OK.
* `CiliumNetworkPolicy` objects report `VALID=True`: OK.
* Ingress tests produced the expected results: OK.
* Egress DNS and internet tests produced the expected results: OK.
* Generated manifests passed server-side dry-run: OK.
* Validation scripts completed successfully: OK.
* Sensitive information scan completed: OK.

---

## Checkpoint

`Phase 07 checkpoint passed`

The current Cilium, Hubble and network policy configuration has been captured as validated repository artefacts without including credentials, private keys, kubeconfigs or active Secrets.
