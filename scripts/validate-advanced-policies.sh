#!/usr/bin/env bash

set -u
set -o pipefail

failures=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}

section() {
    echo
    echo "$1"
    printf '%*s\n' "${#1}" '' | tr ' ' '='
}

exec_deployment() {
    local namespace="$1"
    local deployment="$2"

    shift 2

    kubectl -n "$namespace" exec \
        "deployment/$deployment" -- "$@"
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

expect_http_code() {
    local description="$1"
    local namespace="$2"
    local deployment="$3"
    local method="$4"
    local url="$5"
    local expected_code="$6"

    local actual_code

    echo
    echo "TEST: $description"

    actual_code="$(
        exec_deployment \
            "$namespace" \
            "$deployment" \
            curl \
            -m 8 \
            -s \
            -o /dev/null \
            -w '%{http_code}' \
            -X "$method" \
            "$url"
    )"

    echo "HTTP status: $actual_code"

    if [[ "$actual_code" == "$expected_code" ]]; then
        pass "$description"
    else
        fail "$description: expected $expected_code, received $actual_code"
    fi
}

check_cnp_validity() {
    local output
    local invalid

    output="$(kubectl get ciliumnetworkpolicies -A --no-headers)"

    echo "$output"

    invalid="$(
        awk '$NF != "True" {print}' <<< "$output"
    )"

    if [[ -n "$output" && -z "$invalid" ]]; then
        pass "All CiliumNetworkPolicy objects report VALID=True"
    else
        fail "One or more CiliumNetworkPolicy objects are invalid"
    fi
}

check_ccnp_validity() {
    local output
    local invalid

    output="$(
        kubectl get ciliumclusterwidenetworkpolicies --no-headers
    )"

    echo "$output"

    invalid="$(
        awk '$NF != "True" {print}' <<< "$output"
    )"

    if [[ -n "$output" && -z "$invalid" ]]; then
        pass "All CiliumClusterwideNetworkPolicy objects report VALID=True"
    else
        fail "One or more CiliumClusterwideNetworkPolicy objects are invalid"
    fi
}

section "Policy inventory"

kubectl get networkpolicies -A
kubectl get ciliumnetworkpolicies -A
kubectl get ciliumclusterwidenetworkpolicies

echo
check_cnp_validity

echo
check_ccnp_validity

section "8.1 Cross-namespace ingress"

expect_success \
    "frontend-zone frontend reaches backend-zone backend on TCP/80" \
    exec_deployment \
    frontend-zone \
    frontend \
    curl \
    -m 5 \
    -fsS \
    -o /dev/null \
    http://backend.backend-zone.svc.cluster.local

expect_failure \
    "untrusted-zone client is denied access to backend-zone backend" \
    exec_deployment \
    untrusted-zone \
    untrusted-client \
    curl \
    -m 5 \
    -fsS \
    -o /dev/null \
    http://backend.backend-zone.svc.cluster.local

section "8.2 DNS and FQDN egress"

expect_success \
    "frontend can resolve example.com through CoreDNS" \
    exec_deployment \
    frontend-zone \
    frontend \
    nslookup \
    example.com

expect_success \
    "frontend can access example.com on TCP/443" \
    exec_deployment \
    frontend-zone \
    frontend \
    curl \
    -m 10 \
    -fsS \
    -o /dev/null \
    https://example.com

expect_success \
    "frontend can resolve github.com through CoreDNS" \
    exec_deployment \
    frontend-zone \
    frontend \
    nslookup \
    github.com

expect_failure \
    "frontend HTTPS access to github.com is denied" \
    exec_deployment \
    frontend-zone \
    frontend \
    curl \
    -m 8 \
    -fsS \
    -o /dev/null \
    https://github.com

expect_success \
    "frontend retains access to the internal backend on TCP/80" \
    exec_deployment \
    frontend-zone \
    frontend \
    curl \
    -m 5 \
    -fsS \
    -o /dev/null \
    http://backend.backend-zone.svc.cluster.local

section "8.3 Layer 7 HTTP policy"

expect_http_code \
    "GET /public is allowed" \
    l7-demo \
    l7-client \
    GET \
    http://l7-backend/public \
    200

expect_http_code \
    "GET /admin is denied by the L7 policy" \
    l7-demo \
    l7-client \
    GET \
    http://l7-backend/admin \
    403

expect_http_code \
    "POST /public is denied by the L7 policy" \
    l7-demo \
    l7-client \
    POST \
    http://l7-backend/public \
    403

section "8.4 Cluster-wide policy"

expect_success \
    "auditor reaches the protected backend in ccnp-team-a" \
    exec_deployment \
    ccnp-ops \
    ops-client \
    curl \
    -m 5 \
    -fsS \
    -o /dev/null \
    http://backend.ccnp-team-a.svc.cluster.local

expect_success \
    "auditor reaches the protected backend in ccnp-team-b" \
    exec_deployment \
    ccnp-ops \
    ops-client \
    curl \
    -m 5 \
    -fsS \
    -o /dev/null \
    http://backend.ccnp-team-b.svc.cluster.local

expect_failure \
    "untrusted client is denied access to ccnp-team-a" \
    exec_deployment \
    ccnp-untrusted \
    untrusted-client \
    curl \
    -m 5 \
    -fsS \
    -o /dev/null \
    http://backend.ccnp-team-a.svc.cluster.local

expect_failure \
    "untrusted client is denied access to ccnp-team-b" \
    exec_deployment \
    ccnp-untrusted \
    untrusted-client \
    curl \
    -m 5 \
    -fsS \
    -o /dev/null \
    http://backend.ccnp-team-b.svc.cluster.local

section "8.5 Explicit ingressDeny"

expect_success \
    "trusted client reaches the deny-demo backend" \
    exec_deployment \
    deny-demo \
    trusted-client \
    curl \
    -m 5 \
    -fsS \
    -o /dev/null \
    http://backend

expect_failure \
    "blocked client is denied despite the separate allow policy" \
    exec_deployment \
    deny-demo \
    blocked-client \
    curl \
    -m 5 \
    -fsS \
    -o /dev/null \
    http://backend

section "Pod-template label verification"

kubectl -n ccnp-team-a get deployment backend \
    -o custom-columns='NAME:.metadata.name,POD_TEMPLATE_LABELS:.spec.template.metadata.labels'

kubectl -n ccnp-team-b get deployment backend \
    -o custom-columns='NAME:.metadata.name,POD_TEMPLATE_LABELS:.spec.template.metadata.labels'

kubectl -n ccnp-ops get deployment ops-client \
    -o custom-columns='NAME:.metadata.name,POD_TEMPLATE_LABELS:.spec.template.metadata.labels'

kubectl -n deny-demo get deployments \
    -o custom-columns='NAME:.metadata.name,POD_TEMPLATE_LABELS:.spec.template.metadata.labels'

section "Cilium endpoint identities"

kubectl get ciliumendpoints -A -o wide |
    grep -E \
        'frontend-zone|backend-zone|untrusted-zone|l7-demo|ccnp-|deny-demo' ||
    fail "Unable to find Phase 8 Cilium endpoints"

section "Hubble FORWARDED evidence"

forwarded="$(
    hubble observe \
        --verdict FORWARDED \
        --last 100 \
        -o compact
)"

printf '%s\n' "$forwarded"

if [[ -n "$forwarded" ]]; then
    pass "Hubble returned recent FORWARDED flows"
else
    fail "No recent FORWARDED flows were returned"
fi

section "Hubble DROPPED evidence"

dropped="$(
    hubble observe \
        --verdict DROPPED \
        --last 100 \
        -o compact
)"

printf '%s\n' "$dropped"

if [[ -n "$dropped" ]]; then
    pass "Hubble returned recent DROPPED flows"
else
    fail "No recent DROPPED flows were returned"
fi

section "Hubble Layer 7 evidence"

l7_flows="$(
    hubble observe \
        -t l7 \
        --last 50 \
        -o compact
)"

printf '%s\n' "$l7_flows"

if grep -q '200' <<< "$l7_flows" &&
    grep -q '403' <<< "$l7_flows"; then
    pass "Hubble returned the expected HTTP 200 and 403 proxy responses"
else
    fail "Expected HTTP 200 and 403 evidence was not found"
fi

section "Hubble overlay-routing evidence"

overlay_flows="$(
    hubble observe \
        --last 200 \
        -o compact |
        grep 'to-overlay' ||
        true
)"

printf '%s\n' "$overlay_flows"

if [[ -n "$overlay_flows" ]]; then
    pass "Hubble returned cross-node to-overlay flows"
else
    fail "No recent to-overlay flows were found"
fi

section "kube-proxy state"

if kubectl -n kube-system get daemonset kube-proxy; then
    pass "kube-proxy remains deployed"
else
    fail "kube-proxy DaemonSet was not found"
fi

section "Summary"

if (( failures == 0 )); then
    echo "All Phase 8 advanced policy validation checks passed."
    exit 0
fi

echo "$failures Phase 8 validation check(s) failed." >&2
exit 1
