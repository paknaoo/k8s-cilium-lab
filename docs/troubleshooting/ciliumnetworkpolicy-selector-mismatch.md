# CiliumNetworkPolicy Selector Mismatch

## Summary

This troubleshooting case documents a controlled `CiliumNetworkPolicy` failure caused by an incorrect source endpoint selector.

The policy was syntactically valid and reported a valid status, but the configured selector did not match the intended client Pod.

The failure was isolated to a temporary namespace and did not modify any existing Phase 8 or Phase 9 policy, Service, LoadBalancer IPAM, L2 Announcement or BGP configuration.

## Test Environment

The temporary namespace was:

```text
phase10-netpol
```

The test resources were:

```text
backend Deployment
backend ClusterIP Service
client-approved Pod
client-denied Pod
```

The client labels were:

```text
client-approved: access=approved
client-denied:   access=denied
```

The backend was exposed internally on TCP/80.

All temporary resources were removed after validation.

## Healthy Baseline

Before applying the test policy:

```text
client-approved → backend: HTTP 200
client-denied   → backend: HTTP 200
```

The following components were also verified:

* the backend Pod was `Running` and `Ready`;
* the backend Service existed;
* the EndpointSlice contained the backend endpoint;
* all Kubernetes nodes were `Ready`;
* Cilium and the Cilium Operator were healthy;
* both BGP sessions were established;
* the L2 and BGP Service VIPs returned HTTP 200.

Evidence:

```text
snapshots/phase-10/baseline/baseline-before-networkpolicy.txt
snapshots/phase-10/baseline/netpol-before-policy.txt
```

## Failure Injection

The test policy selected the backend and allowed ingress on TCP/80 from a source endpoint matching:

```yaml
fromEndpoints:
  - matchLabels:
      access: approve
```

The intended client was actually labelled:

```yaml
access: approved
```

The missing final `d` caused the selector to match no client Pod.

The policy was accepted by Kubernetes and Cilium because:

* the YAML syntax was valid;
* the Cilium CRD schema was satisfied;
* the selector itself was structurally valid.

The policy status reported:

```text
Policy validation succeeded
status: "True"
```

Evidence:

```text
snapshots/phase-10/policy/netpol-broken-policy.yaml
snapshots/phase-10/failure/netpol-during-failure.txt
```

## Observed Failure

After applying the broken policy:

```text
client-approved → HTTP 000, curl exit 28
client-denied   → HTTP 000, curl exit 28
```

Both connections timed out.

At the same time:

* the backend remained `Running` and `Ready`;
* the Service remained present;
* the EndpointSlice continued to contain the backend address and TCP/80;
* the `CiliumNetworkPolicy` remained valid.

This ruled out:

* a failed backend workload;
* a missing Service;
* an empty EndpointSlice;
* invalid YAML;
* CRD validation failure.

## Datapath Evidence

Cilium recorded policy enforcement drops for TCP SYN traffic sent to the backend.

Observed verdicts included:

```text
action deny
drop (Policy denied)
```

One validated flow was:

```text
10.244.2.27 → 10.244.2.113:80 TCP SYN
```

The backend Cilium endpoint reported:

```text
policy-enabled: ingress
policy health:  OK
```

The endpoint policy was derived from:

```text
CiliumNetworkPolicy/backend-ingress
```

The installed selector contained:

```text
access=approve
```

This confirmed that Cilium had installed and enforced the policy as written.

Evidence:

```text
snapshots/phase-10/failure/netpol-client-policy-drops.txt
snapshots/phase-10/failure/netpol-datapath-drops.txt
snapshots/phase-10/diagnosis/netpol-backend-endpoint.txt
snapshots/phase-10/diagnosis/netpol-cilium-endpoints.txt
```

## Root Cause

The policy expected:

```text
access=approve
```

The intended client used:

```text
access=approved
```

The source endpoint selector therefore matched no Pod identity.

The failure was not caused by the application, Service or Cilium datapath. It was caused by a logical mismatch between the policy selector and the actual workload label.

Root-cause evidence:

```text
snapshots/phase-10/diagnosis/netpol-root-cause.txt
```

## Corrective Action

The selector was corrected to:

```yaml
fromEndpoints:
  - matchLabels:
      access: approved
```

The corrected policy remained limited to:

```text
destination: backend
port:        TCP/80
source:      access=approved
```

Evidence:

```text
snapshots/phase-10/policy/netpol-fixed-policy.yaml
```

## Validation After the Fix

After applying the corrected policy:

```text
client-approved → HTTP 200, curl exit 0
client-denied   → HTTP 000, curl exit 28
```

This confirmed that:

* the intended client identity was allowed;
* the non-matching client remained denied;
* ingress enforcement on TCP/80 worked as designed;
* the correction did not create a broader allow rule.

Evidence:

```text
snapshots/phase-10/recovery/netpol-after-fix.txt
```

## Cleanup and Recovery

The temporary namespace was deleted after validation:

```text
phase10-netpol
```

No Phase 10 workloads, Services or policies remain in the cluster.

The final baseline confirmed:

* all three Kubernetes nodes were `Ready`;
* Cilium and the Cilium Operator were healthy;
* both BGP sessions were established;
* the L2 Lease remained active;
* `10.10.10.200` returned HTTP 200;
* `10.30.0.100` returned HTTP 200.

Evidence:

```text
snapshots/phase-10/recovery/baseline-after-networkpolicy.txt
```

## Troubleshooting Workflow

The validated diagnostic sequence was:

```text
confirm cluster baseline
→ verify backend workload
→ verify Service
→ verify EndpointSlice
→ inspect policy status
→ reproduce the timeout
→ inspect Cilium policy drops
→ inspect backend endpoint policy
→ compare policy selectors with Pod labels
→ correct the selector
→ validate selective connectivity
→ delete temporary resources
→ confirm cluster recovery
```

## Operational Lessons

A valid Cilium policy can still be logically incorrect.

A `Valid=True` status confirms that the resource is accepted and can be enforced. It does not confirm that its selectors match the intended workloads.

When a policy-controlled connection fails:

1. Confirm the destination workload is healthy.
2. Confirm the Service and EndpointSlice are correct.
3. Confirm the policy is installed and valid.
4. Inspect datapath verdicts for `Policy denied`.
5. Inspect the selected endpoint policy.
6. Compare policy selectors with the actual Pod labels.
7. Retest both intended allowed and denied traffic after correction.

The correction must be validated with both positive and negative tests. Testing only the allowed client would not confirm that selective enforcement remained intact.

## Evidence Validation

The static evidence validator is:

```text
scripts/validate-phase-10-evidence.sh
```

Run:

```bash
./scripts/validate-phase-10-evidence.sh
```

The final recorded result was:

```text
Failures: 0
Warnings: 1
Phase 10 evidence validation completed successfully.
```

The warning indicates that the final baseline does not contain a literal namespace deletion message. Cleanup was performed during the controlled test, and the recovery baseline confirms that the cluster and existing service-exposure components returned to their healthy state.

The validator does not recreate the test namespace, apply either policy or inject another failure.
