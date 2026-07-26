#!/usr/bin/env bash

set -u

NAMESPACE="netpol-demo"
SERVICE="backend"
failures=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

expect_success() {
    local description="$1"
    shift

    echo
    echo "TEST: $description"

    if "$@"; then
        pass "$description"
    else
        fail "$description"
    fi
}

expect_failure() {
    local description="$1"
    shift

    echo
    echo "TEST: $description"

    if "$@"; then
        fail "$description unexpectedly succeeded"
    else
        pass "$description"
    fi
}

echo "netpol-demo validation"
echo "======================"

echo
echo "Current resources"

kubectl -n "$NAMESPACE" get \
    deployments,pods,services,networkpolicies,ciliumnetworkpolicies \
    -o wide

echo
echo "Waiting for test pods"

kubectl -n "$NAMESPACE" wait \
    --for=condition=Ready \
    pod \
    -l app=frontend \
    --timeout=60s

kubectl -n "$NAMESPACE" wait \
    --for=condition=Ready \
    pod \
    -l app=client \
    --timeout=60s

frontend="$(
    kubectl -n "$NAMESPACE" get pods \
        -l app=frontend \
        -o jsonpath='{.items[0].metadata.name}'
)"

client="$(
    kubectl -n "$NAMESPACE" get pods \
        -l app=client \
        -o jsonpath='{.items[0].metadata.name}'
)"

if [[ -z "$frontend" || -z "$client" ]]; then
    echo "Unable to identify the test pods." >&2
    exit 1
fi

echo
echo "Selected pods"
echo "frontend: $frontend"
echo "client:   $client"

expect_success \
    "frontend can reach backend on TCP/80" \
    kubectl -n "$NAMESPACE" exec "$frontend" -- \
        curl -m 3 -sI "$SERVICE"

expect_failure \
    "client is denied access to backend on TCP/80" \
    kubectl -n "$NAMESPACE" exec "$client" -- \
        curl -m 3 -sI "$SERVICE"

expect_success \
    "client can resolve Kubernetes DNS" \
    kubectl -n "$NAMESPACE" exec "$client" -- \
        nslookup kubernetes.default.svc.cluster.local

expect_failure \
    "client internet HTTPS access is denied" \
    kubectl -n "$NAMESPACE" exec "$client" -- \
        curl -m 5 -I https://example.com

echo
echo "Recent namespace flows"

if hubble observe --namespace "$NAMESPACE" --last 30; then
    pass "Hubble namespace flow query completed"
else
    fail "Hubble namespace flow query failed"
fi

echo
echo "Recent dropped flows"

if hubble observe \
    --namespace "$NAMESPACE" \
    --verdict DROPPED \
    --last 30; then
    pass "Hubble dropped-flow query completed"
else
    fail "Hubble dropped-flow query failed"
fi

echo
echo "Summary"
echo "======="

if (( failures == 0 )); then
    echo "All network policy validation checks passed."
    exit 0
fi

echo "$failures validation check(s) failed." >&2
exit 1
