# Phase 05 — Network Policies

This document describes the fifth completed phase of the lab: validating Kubernetes and Cilium network policy behaviour with ingress and egress enforcement.

---

## Scope

Phase 05 validated basic network policy enforcement in the existing Kubernetes cluster.

Implemented in this phase:

* Demo namespace created for policy testing.
* Backend service deployed.
* Frontend test client deployed.
* Untrusted client pod deployed.
* Baseline connectivity validated before applying policies.
* Default-deny ingress policy applied to the backend.
* Cilium ingress allow policy applied for frontend-to-backend traffic.
* Default-deny egress policy applied to the client pod.
* Cilium egress allow policy applied for DNS access only.
* Hubble used to observe allowed and denied flows.

WireGuard and other roadmap items are not enabled in this phase. They are planned for later phases.

---

## Starting State

Network policy validation was performed after the following components had already been completed:

| Component          | State                               |
| ------------------ | ----------------------------------- |
| Kubernetes cluster | Running                             |
| Nodes              | Control plane and two workers Ready |
| Cilium             | Installed and healthy               |
| Hubble             | Installed and verified              |

The goal of this phase was to confirm that both ingress and egress policy enforcement worked as expected and that policy behaviour could be observed through Hubble.

---

## Demo Namespace

A dedicated namespace was created for the policy test environment:

```bash
kubectl create namespace netpol-demo
```

Demo workloads were deployed in the `netpol-demo` namespace.

| Workload   | Purpose               |
| ---------- | --------------------- |
| `backend`  | nginx backend service |
| `frontend` | Allowed client        |
| `client`   | Untrusted test client |

The backend was exposed through a ClusterIP service on port `80`.

---

## Baseline Connectivity

Before applying any policy, both test clients could reach the backend service.

Test commands:

```bash
kubectl -n netpol-demo exec "$FRONTEND" -- curl -sI backend
kubectl -n netpol-demo exec "$CLIENT" -- curl -sI backend
```

Observed result:

```text
frontend → backend: HTTP/1.1 200 OK
client   → backend: HTTP/1.1 200 OK
```

This confirmed the default behaviour: traffic is allowed unless a policy selects the target endpoint and restricts access.

---

## Backend Default-Deny Ingress

A default-deny ingress policy was applied to the backend using standard Kubernetes `NetworkPolicy`.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-default-deny-ingress
  namespace: netpol-demo
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
```

Validation commands:

```bash
kubectl -n netpol-demo exec "$FRONTEND" -- curl -m 3 -sI backend || echo "frontend blocked"
kubectl -n netpol-demo exec "$CLIENT" -- curl -m 3 -sI backend || echo "client blocked"
```

Observed result:

```text
frontend blocked
client blocked
```

This confirmed that the backend was isolated for ingress traffic after the default-deny policy was applied.

---

## Frontend-to-Backend Ingress Allow

A Cilium allow policy was applied to permit only the `frontend` pod to reach the `backend` pod on TCP port `80`.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: netpol-demo
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
```

Policy validation:

```bash
kubectl -n netpol-demo get ciliumnetworkpolicies
```

Expected policy state:

```text
allow-frontend-to-backend   VALID True
```

Final ingress test:

```bash
kubectl -n netpol-demo exec "$FRONTEND" -- curl -m 3 -sI backend || echo "frontend blocked"
kubectl -n netpol-demo exec "$CLIENT" -- curl -m 3 -sI backend || echo "client blocked"
```

Observed result:

```text
frontend → backend: HTTP/1.1 200 OK
client   → backend: blocked
```

The blocked `client` request returned a timeout, confirming that the untrusted client could not reach the backend service.

Final ingress result:

| Flow                          | Result  |
| ----------------------------- | ------- |
| `frontend` → `backend` TCP/80 | Allowed |
| `client` → `backend` TCP/80   | Denied  |

---

## Client Default-Deny Egress

After ingress validation, egress policy behaviour was tested.

A default-deny egress policy was applied to the `client` pod using standard Kubernetes `NetworkPolicy`.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: client-default-deny-egress
  namespace: netpol-demo
spec:
  podSelector:
    matchLabels:
      app: client
  policyTypes:
  - Egress
```

The purpose was to confirm that egress policy controls where a selected pod is allowed to send traffic.

Expected behaviour after applying the policy:

| Flow                | Expected Result |
| ------------------- | --------------- |
| `client` → DNS      | Denied          |
| `client` → Internet | Denied          |

Example validation commands:

```bash
kubectl -n netpol-demo exec "$CLIENT" -- nslookup kubernetes.default.svc.cluster.local || echo "dns blocked"
kubectl -n netpol-demo exec "$CLIENT" -- curl -m 5 -I https://example.com || echo "internet blocked"
```

---

## Client DNS Egress Allow

A Cilium egress policy was then applied to allow the `client` pod to reach CoreDNS only on UDP/TCP port `53`.

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-client-dns-egress
  namespace: netpol-demo
spec:
  endpointSelector:
    matchLabels:
      app: client
  egress:
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s:k8s-app: kube-dns
    toPorts:
    - ports:
      - port: "53"
        protocol: UDP
      - port: "53"
        protocol: TCP
```

Final egress result:

| Flow                          | Result  |
| ----------------------------- | ------- |
| `client` → CoreDNS UDP/TCP 53 | Allowed |
| `client` → Internet TCP/443   | Denied  |

This confirmed that egress policy can be used to permit specific required destinations while blocking broader outbound access.

---

## Hubble Verification

Hubble was used to observe policy behaviour and validate allowed and denied flows.

Useful commands:

```bash
hubble observe --namespace netpol-demo --last 30
hubble observe --namespace netpol-demo --verdict DROPPED --last 30
```

Observed flow behaviour included:

| Flow                             | Hubble Visibility |
| -------------------------------- | ----------------- |
| `frontend` → `backend`           | Forwarded         |
| `client` → `backend`             | Dropped / denied  |
| `client` → `kube-dns`            | Forwarded         |
| `client` → external destinations | Dropped           |

Hubble confirmed that policy behaviour was visible as real traffic flow verdicts, rather than only being inferred from client-side command results.

---

## Policy Validation Note

During testing, an initial default-deny ingress attempt used `CiliumNetworkPolicy` with an empty ingress list:

```yaml
ingress: []
```

The object was created, but Cilium marked it as invalid:

```text
VALID: False
```

Observed validation message:

```text
rule must have at least one of Ingress, IngressDeny, Egress, EgressDeny
```

The implementation decision was to use standard Kubernetes `NetworkPolicy` for simple default-deny behaviour and `CiliumNetworkPolicy` for explicit Cilium allow rules.

This also reinforced the need to check the `VALID` column when working with Cilium network policies.

---

## Lessons Learned

Key lessons from this phase:

* Cilium enforces both standard Kubernetes `NetworkPolicy` and `CiliumNetworkPolicy`.
* Standard Kubernetes `NetworkPolicy` is simple and effective for default-deny use cases.
* `CiliumNetworkPolicy` is useful for explicit Cilium policy rules.
* A `CiliumNetworkPolicy` object can be created but still be invalid.
* The `VALID` column should always be checked after applying Cilium policies.
* Hubble is useful for validating policy behaviour because it shows allowed and dropped flows.
* Ingress policy controls traffic entering selected pods.
* Egress policy controls traffic leaving selected pods.

---

## Validation

Network policy behaviour was validated successfully.

Ingress validation:

* Backend default-deny ingress policy applied.
* `frontend` to `backend` TCP/80 allowed.
* `client` to `backend` TCP/80 denied.

Egress validation:

* Client default-deny egress policy applied.
* `client` to CoreDNS UDP/TCP 53 allowed.
* `client` to internet access denied.

Observability validation:

* Hubble showed allowed flows.
* Hubble showed dropped flows.
* Policy behaviour was confirmed through both command-line tests and Hubble flow visibility.

---

## Current State

The lab now has basic Kubernetes and Cilium network policy behaviour validated.

Current state:

* Cilium installed and healthy.
* Hubble installed and working.
* Network policy demo completed.
* Ingress policy enforcement verified.
* Egress policy enforcement verified.
* Hubble flow observation verified.

---

## Checkpoint

`Phase 05 checkpoint passed`

Basic Kubernetes and Cilium network policy enforcement has been validated. The environment is ready for the next roadmap item: WireGuard.
