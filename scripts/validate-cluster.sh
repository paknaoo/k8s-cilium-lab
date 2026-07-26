#!/usr/bin/env bash

set -u

NAMESPACE="netpol-demo"
failures=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

echo "Kubernetes cluster health"
echo "========================="

echo
echo "Nodes"
kubectl get nodes -o wide

not_ready="$(
    kubectl get nodes --no-headers |
        awk '$2 != "Ready" {print $1}'
)"

if [[ -z "$not_ready" ]]; then
    pass "All Kubernetes nodes are Ready"
else
    fail "The following nodes are not Ready: $not_ready"
fi

echo
echo "Cilium status"

if cilium status --wait; then
    pass "Cilium is healthy"
else
    fail "Cilium health check failed"
fi

echo
echo "Hubble status"

if hubble status; then
    pass "Hubble is available"
else
    fail "Hubble status check failed"
fi

echo
echo "Cilium and Hubble workloads"

if kubectl -n kube-system get pods -o wide |
    grep -E 'cilium|hubble'; then
    pass "Cilium and Hubble workloads are present"
else
    fail "Cilium or Hubble workloads were not found"
fi

echo
echo "Network policy inventory"

if kubectl -n "$NAMESPACE" \
    get networkpolicies,ciliumnetworkpolicies; then
    pass "Network policy inventory is available"
else
    fail "Unable to retrieve the network policy inventory"
fi

echo
echo "CiliumNetworkPolicy validity"

cnp_status="$(
    kubectl -n "$NAMESPACE" \
        get ciliumnetworkpolicies \
        --no-headers
)"

printf '%s\n' "$cnp_status"

if [[ -n "$cnp_status" ]] &&
    ! grep -vq 'True' <<< "$cnp_status"; then
    pass "All CiliumNetworkPolicy objects report VALID=True"
else
    fail "One or more CiliumNetworkPolicy objects are invalid"
fi

echo
echo "Recent Hubble flows"

if hubble observe --namespace "$NAMESPACE" --last 10; then
    pass "Hubble flow query completed"
else
    fail "Hubble flow query failed"
fi

echo
echo "Summary"
echo "======="

if (( failures == 0 )); then
    echo "All cluster validation checks passed."
    exit 0
fi

echo "$failures validation check(s) failed." >&2
exit 1
