# Invalid CiliumNetworkPolicy Default-Deny Attempt

This document records a policy validation issue observed during the `netpol-demo` network policy tests.

The case is included because it was reproduced and verified in the working lab.

---

## Context

A default-deny ingress policy was required for the `backend` workload in the `netpol-demo` namespace.

The initial attempt used a `CiliumNetworkPolicy` containing an empty ingress rule:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  namespace: netpol-demo
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress: []
```

The Kubernetes API accepted the object, but Cilium did not consider the policy valid.

---

## Observed Result

Policy status:

```text
VALID: False
```

Cilium validation message:

```text
rule must have at least one of Ingress, IngressDeny, Egress, EgressDeny
```

This demonstrated that successful object creation does not guarantee that a `CiliumNetworkPolicy` is valid or enforced.

---

## Diagnosis

The empty `ingress` list did not create a valid Cilium rule in this lab.

The policy object existed in Kubernetes, but Cilium rejected its rule structure.

The policy status was checked with:

```bash
kubectl -n netpol-demo get ciliumnetworkpolicies
```

The `VALID` column must be reviewed after applying a Cilium policy.

---

## Resolution

A standard Kubernetes `NetworkPolicy` was used for the backend default-deny ingress rule:

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

A separate `CiliumNetworkPolicy` was then used for the explicit frontend-to-backend TCP/80 allow rule.

This produced the intended policy model:

```text
Kubernetes NetworkPolicy:
  backend default-deny ingress

CiliumNetworkPolicy:
  frontend → backend TCP/80 allow
```

---

## Verification

After applying the corrected policies:

```text
frontend → backend TCP/80: allowed
client → backend TCP/80: denied
```

The Cilium policy reported:

```text
VALID: True
```

Hubble also showed the expected forwarded and dropped flows.

---

## Lesson

For simple default-deny behaviour, standard Kubernetes `NetworkPolicy` provided a clear and valid implementation.

`CiliumNetworkPolicy` was retained for the explicit Cilium allow rules.

After applying any Cilium policy:

1. Confirm that the object exists.
2. Check the `VALID` column.
3. Review the policy status if validation fails.
4. Test both allowed and denied traffic.
5. Confirm the resulting flow verdicts with Hubble.
