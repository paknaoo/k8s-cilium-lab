# Phase 10 — Controlled NetworkPolicy Troubleshooting

## Scope

Phase 10 was intentionally limited to one minimal, controlled troubleshooting scenario.

The phase validated a complete diagnostic workflow for a logically incorrect `CiliumNetworkPolicy` without introducing node, Cilium agent, BGP, FRR, container runtime or network-interface failures.

All live changes, failure injection, validation, recovery and evidence collection were completed in the live-configuration environment.

The repository contains only:

* the validated troubleshooting documentation;
* the broken and corrected policy snapshots;
* datapath and endpoint evidence;
* cluster baseline and recovery evidence;
* a static evidence-validation script.

The repository does not recreate the failure or apply temporary Phase 10 resources.

## Scenario Objective

The scenario validated the following workflow:

```text
record healthy cluster baseline
→ deploy isolated test workloads
→ confirm connectivity before policy enforcement
→ apply a syntactically valid but logically incorrect policy
→ confirm the traffic failure
→ identify policy drops in the Cilium datapath
→ inspect the backend endpoint policy
→ determine the selector mismatch
→ correct the policy
→ validate selective access
→ remove all temporary resources
→ confirm full cluster recovery
```

## Isolated Test Environment

The temporary namespace was:

```text
phase10-netpol
```

The namespace contained:

```text
backend Deployment
backend ClusterIP Service
client-approved Pod
client-denied Pod
```

The test clients used:

```text
client-approved: access=approved
client-denied:   access=denied
```

The backend was exposed internally on TCP/80.

The scenario did not modify any existing:

* Phase 8 policy;
* Phase 9 Service;
* Cilium LoadBalancer IP pool;
* L2 Announcement Policy;
* BGP Control Plane resource;
* pfSense FRR configuration.

The entire temporary namespace was deleted after validation.

## Evidence Structure

Phase 10 evidence is stored under:

```text
snapshots/phase-10/
├── baseline/
├── policy/
├── failure/
├── diagnosis/
└── recovery/
```

### Baseline Evidence

```text
snapshots/phase-10/baseline/
├── baseline-before-networkpolicy.txt
└── netpol-before-policy.txt
```

### Policy Evidence

```text
snapshots/phase-10/policy/
├── netpol-broken-policy.yaml
└── netpol-fixed-policy.yaml
```

The policy files are troubleshooting snapshots rather than persistent desired-state manifests.

The broken policy is intentionally incorrect, and the temporary namespace no longer exists. Neither file is stored under the deployable manifest tree.

### Failure Evidence

```text
snapshots/phase-10/failure/
├── netpol-during-failure.txt
├── netpol-client-policy-drops.txt
└── netpol-datapath-drops.txt
```

### Diagnostic Evidence

```text
snapshots/phase-10/diagnosis/
├── netpol-cilium-host-address.txt
├── netpol-cilium-endpoints.txt
├── netpol-backend-endpoint.txt
└── netpol-root-cause.txt
```

### Recovery Evidence

```text
snapshots/phase-10/recovery/
├── netpol-after-fix.txt
├── baseline-after-networkpolicy.txt
└── validate-phase-10-evidence-output.txt
```

## Initial Cluster Baseline

Before deploying the temporary test environment, the existing lab state was checked.

The Kubernetes nodes reported:

```text
k8s-master:  Ready
k8s-worker1: Ready
k8s-worker2: Ready
```

The Cilium components reported:

```text
Cilium:       OK
Operator:     OK
Envoy:        OK
Hubble Relay: OK
```

The Phase 9 service-exposure state was also healthy:

```text
worker1 BGP peer: established
worker2 BGP peer: established
L2 Lease: active and renewing
L2 VIP: HTTP 200
BGP VIP: HTTP 200
```

Evidence:

```text
snapshots/phase-10/baseline/baseline-before-networkpolicy.txt
```

This baseline confirmed that the cluster, Cilium networking and external Service exposure were healthy before the troubleshooting test.

## Connectivity Before Policy Enforcement

Before applying the test policy:

```text
client-approved → backend: HTTP 200
client-denied   → backend: HTTP 200
```

The following objects were confirmed:

* the backend Pod was `Running` and `Ready`;
* the backend Service existed;
* the EndpointSlice contained the backend address;
* TCP/80 was exposed by the Service.

Evidence:

```text
snapshots/phase-10/baseline/netpol-before-policy.txt
```

This established that both clients could reach the backend before ingress policy enforcement was introduced.

## Controlled Failure Injection

The applied `CiliumNetworkPolicy` was syntactically valid but contained an intentional selector typo.

The broken selector was:

```yaml
fromEndpoints:
  - matchLabels:
      access: approve
```

The intended approved client used:

```yaml
access: approved
```

The missing final `d` caused the source selector to match no client endpoint.

Evidence:

```text
snapshots/phase-10/policy/netpol-broken-policy.yaml
```

The policy was accepted because:

* the YAML syntax was valid;
* the Cilium CRD schema was satisfied;
* the selector was structurally valid;
* the resource reported successful policy validation.

The policy status showed:

```text
Policy validation succeeded
status: "True"
```

A valid status confirmed that the policy could be installed and enforced. It did not confirm that the selector matched the intended workload.

## Failure Result

After applying the broken policy:

```text
client-approved → HTTP 000, curl exit 28
client-denied   → HTTP 000, curl exit 28
```

Both requests timed out.

Evidence:

```text
snapshots/phase-10/failure/netpol-during-failure.txt
```

During the failure:

* the backend Pod remained `Running` and `Ready`;
* the Service remained present;
* the EndpointSlice continued to contain the backend endpoint;
* TCP/80 remained exposed;
* the `CiliumNetworkPolicy` remained valid.

This ruled out:

* application failure;
* unavailable backend workload;
* missing Service;
* empty EndpointSlice;
* incorrect Service port;
* invalid policy syntax;
* rejected Cilium policy resource.

## Datapath Diagnosis

Cilium recorded policy-enforcement drops for TCP SYN packets sent to the backend.

Observed verdicts included:

```text
action deny
drop (Policy denied)
```

One validated flow was:

```text
10.244.2.27 → 10.244.2.113:80 TCP SYN
```

Evidence:

```text
snapshots/phase-10/failure/netpol-client-policy-drops.txt
snapshots/phase-10/failure/netpol-datapath-drops.txt
```

The datapath evidence confirmed that:

* the client reached the Cilium datapath;
* the request targeted the expected backend port;
* the traffic was rejected by policy enforcement;
* the timeout was not caused by DNS or Service discovery failure.

## Backend Endpoint Inspection

The backend Cilium endpoint reported:

```text
policy-enabled: ingress
policy health:  OK
```

The endpoint policy was derived from:

```text
CiliumNetworkPolicy/backend-ingress
```

The installed source selector contained:

```text
access=approve
```

Evidence:

```text
snapshots/phase-10/diagnosis/netpol-backend-endpoint.txt
snapshots/phase-10/diagnosis/netpol-cilium-endpoints.txt
```

This demonstrated that Cilium had installed and enforced the policy exactly as written.

The datapath was operating correctly. The logical content of the policy was incorrect.

## Root Cause

The policy expected:

```text
access=approve
```

The intended client was labelled:

```text
access=approved
```

The source selector therefore matched no client Pod identity.

Evidence:

```text
snapshots/phase-10/diagnosis/netpol-root-cause.txt
```

The root cause was a label-selection mismatch rather than:

* application failure;
* Service failure;
* EndpointSlice failure;
* Cilium agent failure;
* datapath malfunction;
* invalid YAML;
* invalid CRD syntax.

## Corrective Action

The source selector was corrected to:

```yaml
fromEndpoints:
  - matchLabels:
      access: approved
```

Evidence:

```text
snapshots/phase-10/policy/netpol-fixed-policy.yaml
```

The corrected policy continued to restrict:

```text
destination: backend
port:        TCP/80
source:      access=approved
```

The correction did not broaden the rule to all clients.

## Validation After Correction

After applying the corrected policy:

```text
client-approved → HTTP 200, curl exit 0
client-denied   → HTTP 000, curl exit 28
```

Evidence:

```text
snapshots/phase-10/recovery/netpol-after-fix.txt
```

This confirmed that:

* the intended client identity was allowed;
* the non-matching client identity remained denied;
* ingress enforcement on TCP/80 worked correctly;
* the selector correction restored only the intended access.

Both positive and negative validation were required.

Testing only the approved client would not have confirmed that the policy remained selective.

## Cleanup

The temporary namespace was deleted:

```text
phase10-netpol
```

No Phase 10 test workload, Service or policy remains in the cluster.

The failure scenario was not retained as deployable desired-state configuration.

The broken and fixed policy YAML files remain only as point-in-time troubleshooting evidence under:

```text
snapshots/phase-10/policy/
```

## Recovery Baseline

After cleanup, the cluster baseline was checked again.

The Kubernetes nodes reported:

```text
k8s-master:  Ready
k8s-worker1: Ready
k8s-worker2: Ready
```

Cilium and its supporting components reported healthy status.

The Phase 9 service-exposure state was also restored and healthy:

```text
worker1 BGP peer: established
worker2 BGP peer: established
L2 Lease: active
L2 VIP: HTTP 200
BGP VIP: HTTP 200
```

Evidence:

```text
snapshots/phase-10/recovery/baseline-after-networkpolicy.txt
```

This confirmed that the controlled test did not leave the existing cluster, L2 or BGP configuration in a degraded state.

## Troubleshooting Case

The detailed troubleshooting case is documented in:

```text
docs/troubleshooting/ciliumnetworkpolicy-selector-mismatch.md
```

It describes:

* the initial symptoms;
* the logically incorrect selector;
* the distinction between policy validity and selector correctness;
* the datapath drop evidence;
* the backend endpoint inspection;
* the root-cause comparison;
* the corrected policy;
* selective access after recovery.

## Static Evidence Validation

The Phase 10 evidence validator is:

```text
scripts/validate-phase-10-evidence.sh
```

Run:

```bash
./scripts/validate-phase-10-evidence.sh
```

The script performs static validation only.

It checks:

* the presence of all required evidence files;
* empty-file status;
* initial cluster health markers;
* pre-policy connectivity;
* broken and fixed selectors;
* failed connectivity during the controlled scenario;
* `curl` exit codes;
* Cilium policy-denied evidence;
* backend endpoint enforcement state;
* root-cause evidence;
* selective connectivity after correction;
* recovery baseline;
* high-risk credential and private-key patterns.

The script does not:

* create the temporary namespace;
* deploy workloads;
* apply the broken policy;
* apply the corrected policy;
* change labels;
* inject a new failure;
* modify any live cluster resource.

The recorded result was:

```text
Failures: 0
Warnings: 1
Phase 10 evidence validation completed successfully.
```

The warning states that the final recovery baseline does not contain a literal namespace-deletion message.

Cleanup was performed during the controlled workflow, while the final baseline confirms that the cluster and existing service-exposure components returned to a healthy state.

## Security Controls

Phase 10 evidence was scanned for:

* Kubernetes Secrets;
* passwords;
* tokens;
* kubeconfig certificate data;
* private keys;
* BGP authentication keys;
* active credential values.

No high-risk credential or private-key patterns were found.

The repository contains only the troubleshooting data required to explain the validated scenario.

## Scope Limitations

Phase 10 contains one controlled NetworkPolicy troubleshooting scenario only.

The following failure types were not tested:

* Kubernetes node failure;
* control plane failure;
* Cilium agent failure;
* Cilium Operator failure;
* Envoy failure;
* Hubble failure;
* BGP session failure;
* pfSense FRR failure;
* container runtime failure;
* node interface failure;
* VMware network failure.

These scenarios must not be presented as implemented or validated.

## Checkpoint

Phase 10 is complete.

The validated result was:

```text
healthy baseline
→ controlled CiliumNetworkPolicy selector failure
→ workload and Service verification
→ Cilium datapath policy-denied evidence
→ endpoint-policy inspection
→ selector mismatch identification
→ policy correction
→ approved client allowed
→ non-matching client denied
→ temporary resources removed
→ full cluster recovery confirmed
```

The remaining repository phase is:

```text
Phase 11 — automation, validation improvements, Makefile and final portfolio polish
```
