# Phase 08 — Advanced Cilium Policies

Phase 08 extends the initial network policy implementation with namespace-aware access control, DNS-aware egress, FQDN filtering, Layer 7 HTTP rules, cluster-wide policy and explicit deny behaviour.

All manifests, validation results and Hubble captures in this phase were derived from the working cluster.

---

## Scope

Phase 08 implemented and verified:

* cross-namespace ingress control;
* DNS-aware egress through the Cilium DNS proxy;
* FQDN-based HTTPS access control;
* Layer 7 HTTP method and path filtering;
* `CiliumClusterwideNetworkPolicy`;
* explicit `ingressDeny`;
* pod-template label and Cilium identity diagnostics;
* Hubble verification of forwarded, dropped, proxied and cross-node traffic.

The cluster continues to use `kube-proxy`.

Kube-proxy replacement is not enabled.

---

## Repository Artefacts

Phase 08 manifests are stored under:

```text
manifests/advanced-policies/
```

The scenarios are separated by namespace:

```text
manifests/advanced-policies/
├── frontend-zone/
├── backend-zone/
├── untrusted-zone/
├── l7-demo/
├── ccnp-team-a/
├── ccnp-team-b/
├── ccnp-ops/
├── ccnp-untrusted/
├── deny-demo/
└── clusterwide/
```

Phase 08 evidence is stored under:

```text
snapshots/phase-08/
├── policies/
├── hubble/
├── diagnostics/
└── validation-results.txt
```

The validation script is:

```text
scripts/validate-advanced-policies.sh
```

---

# 8.1 Cross-Namespace Ingress

## Namespaces

The scenario uses:

```text
frontend-zone
backend-zone
untrusted-zone
```

The backend workload is selected by:

```text
app=backend
```

It is exposed internally on TCP/80 through the `backend` Service in the `backend-zone` namespace.

## Policy Model

A standard Kubernetes `NetworkPolicy` provides default-deny ingress for the backend.

The policy is stored under:

```text
manifests/advanced-policies/backend-zone/
```

The Cilium allow policy is:

```text
allow-frontend-zone-to-backend
```

It permits traffic only when all of the following conditions match:

* source namespace is `frontend-zone`;
* source pod has `app=frontend`;
* destination pod has `app=backend`;
* destination port is TCP/80.

Traffic from `untrusted-zone` does not match the allow rule.

## Validation

Observed results:

```text
frontend-zone/frontend
  → backend.backend-zone.svc.cluster.local:80
  → HTTP 200

untrusted-zone/untrusted-client
  → backend.backend-zone.svc.cluster.local:80
  → timeout / denied
```

Hubble recorded the permitted flow as `FORWARDED` and the denied flow as `DROPPED`.

---

# 8.2 DNS-Aware and FQDN Egress

## Policy

The frontend egress policy is:

```text
frontend-controlled-egress
```

It is stored in:

```text
manifests/advanced-policies/frontend-zone/
```

The policy allows:

* DNS queries to CoreDNS over UDP/53;
* DNS queries to CoreDNS over TCP/53;
* HTTPS traffic to `example.com` on TCP/443;
* TCP/80 traffic to the internal backend in `backend-zone`.

Other external HTTPS destinations are not permitted.

## DNS Proxy Behaviour

DNS traffic is processed through the Cilium DNS proxy.

The policy permits DNS queries to CoreDNS so that the frontend can resolve names required by the allowed FQDN rule.

DNS resolution and destination access are separate decisions.

This means that a name can resolve successfully without the resulting IP address being authorised for application traffic.

## Validation

Observed results:

```text
CoreDNS queries:                    ALLOWED
example.com DNS resolution:        ALLOWED
example.com TCP/443:               ALLOWED
github.com DNS resolution:         ALLOWED
github.com TCP/443:                DENIED
internal backend TCP/80:           ALLOWED
```

The successful `github.com` DNS lookup does not grant HTTPS access.

Only the destination selected by the `toFQDNs` rule is authorised on TCP/443.

## `ndots:5`

Pods use the DNS resolver configuration supplied by Kubernetes.

With:

```text
options ndots:5
```

a name containing fewer than five dots is initially treated as potentially relative.

For a query such as:

```text
github.com
```

the resolver may first attempt names containing the configured Kubernetes search suffixes, including forms similar to:

```text
github.com.<namespace>.svc.cluster.local
github.com.svc.cluster.local
github.com.cluster.local
```

It then queries the original absolute name.

These additional DNS requests are normal resolver behaviour and may appear in Hubble DNS flow output.

They do not mean that matching Kubernetes Services exist.

---

# 8.3 Layer 7 HTTP Policy

## Namespace and Workloads

The Layer 7 scenario uses:

```text
l7-demo
```

It contains:

* `l7-backend`;
* `l7-client`;
* the `l7-backend` Service;
* the `l7-nginx-config` ConfigMap.

The nginx configuration exposes:

```text
/public
/admin
```

## Policy

The Cilium policy is:

```text
allow-public-get-only
```

It allows only:

```text
HTTP method: GET
HTTP path:   /public
```

Other methods and paths are rejected by the Cilium Layer 7 proxy.

## Validation

Observed results:

```text
GET  /public → HTTP 200
GET  /admin  → HTTP 403
POST /public → HTTP 403
```

## Hubble Interpretation

Hubble recorded:

* the allowed `GET /public` request as `FORWARDED`;
* disallowed HTTP requests as `DROPPED` by policy;
* proxy-generated HTTP 403 responses as `FORWARDED` back to the client.

The forwarded 403 response does not mean that the original request was allowed.

It means that the Cilium proxy returned an application-layer denial response to the client.

---

# 8.4 CiliumClusterwideNetworkPolicy

## Namespaces

The cluster-wide scenario uses:

```text
ccnp-team-a
ccnp-team-b
ccnp-ops
ccnp-untrusted
```

Both backend workloads use the pod label:

```text
security-tier=protected
```

The operational client uses:

```text
access=auditor
```

## Policy

The cluster-wide policy is:

```text
allow-auditor-to-protected-backends
```

It is stored under:

```text
manifests/advanced-policies/clusterwide/
```

One `CiliumClusterwideNetworkPolicy` selects protected backend pods across namespaces and permits the auditor client to access TCP/80.

The same policy applies to both team namespaces without duplicating a namespaced policy in each namespace.

## Validation

Observed results:

```text
ccnp-ops/ops-client
  → ccnp-team-a/backend: HTTP 200

ccnp-ops/ops-client
  → ccnp-team-b/backend: HTTP 200

ccnp-untrusted/untrusted-client
  → ccnp-team-a/backend: timeout / denied

ccnp-untrusted/untrusted-client
  → ccnp-team-b/backend: timeout / denied
```

Hubble confirmed both allowed and denied decisions.

Cross-node traffic also showed the `to-overlay` routing direction.

This indicates that the flow was sent through the Cilium overlay between Kubernetes nodes.

---

# 8.5 Explicit `ingressDeny`

## Namespace and Workloads

The explicit deny scenario uses:

```text
deny-demo
```

It contains:

* `backend`;
* `trusted-client`;
* `blocked-client`.

Both client workloads match:

```text
role=client
```

The blocked client additionally has:

```text
access=blocked
```

## Allow Policy

The policy:

```text
allow-all-clients-to-backend
```

allows pods with:

```text
role=client
```

to access the backend on TCP/80.

## Deny Policy

The separate policy:

```text
deny-blocked-client-to-backend
```

uses `ingressDeny` to reject traffic from pods with:

```text
access=blocked
```

to the backend on TCP/80.

## Validation

Observed results:

```text
trusted-client → backend: HTTP 200
blocked-client → backend: timeout / denied
```

The blocked client matches both the general allow selector and the explicit deny selector.

The deny rule takes precedence.

This remains true even though the allow and deny rules are stored in separate Cilium policy objects.

---

# Diagnostic Findings

## Deployment Labels and Pod Labels

Running:

```bash
kubectl label deployment
```

changes labels on the Deployment object itself.

It does not automatically change the labels inside:

```text
spec.template.metadata.labels
```

Cilium policy selectors operate on endpoint identities derived from pod labels.

Therefore, labels required by Cilium policy must exist on the pod template.

After correcting the Deployment pod templates:

* Kubernetes created replacement pods;
* the new pods contained the required labels;
* Cilium assigned identities reflecting those labels;
* the expected policy rules began to match.

Older Hubble `DENIED` events were generated by earlier pods that did not contain the required labels.

The diagnostic details are recorded in:

```text
docs/troubleshooting/deployment-vs-pod-template-labels.md
```

---

# Policy Validation

Namespaced Cilium policies can be checked with:

```bash
kubectl get ciliumnetworkpolicies -A
```

Cluster-wide policies can be checked with:

```bash
kubectl get ciliumclusterwidenetworkpolicies
```

The `VALID` value must be:

```text
True
```

Kubernetes NetworkPolicy inventory can be checked with:

```bash
kubectl get networkpolicies -A
```

---

# Automated Validation

Run the complete Phase 8 validation from `mgmt`:

```bash
ssh master 'bash -s' \
  < scripts/validate-advanced-policies.sh
```

The script checks:

* CNP status;
* CCNP status;
* `VALID=True`;
* cross-namespace ingress;
* DNS and FQDN egress;
* Layer 7 HTTP filtering;
* cluster-wide policy;
* explicit deny precedence;
* pod-template labels;
* Cilium endpoint identities;
* recent Hubble `FORWARDED` flows;
* recent Hubble `DROPPED` flows;
* HTTP 200 and 403 proxy evidence;
* `to-overlay` evidence;
* the continued presence of `kube-proxy`.

Expected final result:

```text
All Phase 8 advanced policy validation checks passed.
```

---

# Hubble Evidence

The scenario captures are stored under:

```text
snapshots/phase-08/hubble/
```

They include:

```text
01-cross-namespace-hubble.txt
02-fqdn-egress-hubble.txt
03-l7-http-hubble.txt
04-clusterwide-policy-hubble.txt
05-ingress-deny-hubble.txt
```

These captures demonstrate:

* policy decisions;
* DNS proxy traffic;
* forwarded connections;
* dropped connections;
* HTTP Layer 7 filtering;
* proxy-generated responses;
* cross-node overlay routing.

Hubble files are point-in-time evidence and do not replace live validation.

---

# Security Controls

The Phase 8 repository artefacts must not include:

* kubeconfig files;
* service-account tokens;
* Kubernetes Secrets;
* credentials;
* passwords;
* WireGuard private keys;
* TLS private keys;
* active secret values.

The raw source exports remain outside the Git repository under:

```text
~/phase8-source/
```

Only cleaned manifests and approved evidence files are included in the repository.

---

# Checkpoint

```text
Phase 08 checkpoint passed
```

Verified results:

```text
Cross-namespace ingress:     PASSED
DNS-aware egress:            PASSED
FQDN filtering:              PASSED
Layer 7 HTTP policy:         PASSED
Cluster-wide policy:         PASSED
Explicit ingressDeny:        PASSED
CNP and CCNP validity:       PASSED
Hubble verification:         PASSED
Pod identity diagnostics:    PASSED
kube-proxy still deployed:   CONFIRMED
```
