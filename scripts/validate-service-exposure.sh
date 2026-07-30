#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_TARGET="${SSH_TARGET:-master}"

MANIFEST_ROOT="${REPO_ROOT}/manifests/service-exposure"
SNAPSHOT_ROOT="${REPO_ROOT}/snapshots/phase-09"

FAILURES=0
WARNINGS=0

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

warn() {
  printf 'WARN: %s\n' "$1" >&2
  WARNINGS=$((WARNINGS + 1))
}

remote() {
  ssh -n -o BatchMode=yes "${SSH_TARGET}" "$1"
}

require_local_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "Local command available: $1"
  else
    fail "Required local command unavailable: $1"
  fi
}

require_file() {
  local file="$1"

  if [[ -s "$file" ]]; then
    pass "Evidence file is present and non-empty: ${file#${REPO_ROOT}/}"
  else
    fail "Evidence file is missing or empty: ${file#${REPO_ROOT}/}"
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if [[ ! -s "$file" ]]; then
    fail "${description}: evidence file missing or empty"
    return
  fi

  if grep -Eiq "$pattern" "$file"; then
    pass "$description"
  else
    fail "$description"
  fi
}

check_resource() {
  local resource="$1"
  local name="$2"

  if remote "kubectl get ${resource} ${name} >/dev/null 2>&1"; then
    pass "Resource exists: ${resource}/${name}"
  else
    fail "Resource missing: ${resource}/${name}"
  fi
}

check_service_vip() {
  local namespace="$1"
  local service="$2"
  local expected_vip="$3"

  local actual_vip

  actual_vip="$(
    remote \
      "kubectl -n ${namespace} get service ${service} \
       -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
  )"

  if [[ "$actual_vip" == "$expected_vip" ]]; then
    pass "Service ${namespace}/${service} uses VIP ${expected_vip}"
  else
    fail \
      "Service ${namespace}/${service} VIP is '${actual_vip}', expected '${expected_vip}'"
  fi
}

check_service_endpoints() {
  local namespace="$1"
  local service="$2"

  local endpoint_rows

  endpoint_rows="$(
    remote \
      "kubectl -n ${namespace} get endpointslices \
       -l kubernetes.io/service-name=${service} \
       -o jsonpath='{range .items[*].endpoints[*]}{.conditions.ready}{\"|\"}{.addresses[*]}{\"\\n\"}{end}'"
  )"

  if awk -F'|' '
    $1 == "true" && length($2) > 0 {
      found = 1
    }

    END {
      exit found ? 0 : 1
    }
  ' <<<"$endpoint_rows"
  then
    pass "Service ${namespace}/${service} has ready endpoints"
  else
    printf '%s\n' "$endpoint_rows" >&2
    fail "Service ${namespace}/${service} has no ready endpoints"
  fi
}

check_http() {
  local label="$1"
  local url="$2"

  local status

  status="$(
    curl \
      --silent \
      --show-error \
      --output /dev/null \
      --write-out '%{http_code}' \
      --max-time 5 \
      "$url" 2>/dev/null || true
  )"

  if [[ "$status" == "200" ]]; then
    pass "${label} returned HTTP 200"
  else
    fail "${label} returned HTTP ${status:-unavailable}"
  fi
}

printf '%s\n' '============================================================'
printf '%s\n' 'Phase 9 — Service Exposure Validation'
printf '%s\n' '============================================================'
printf 'Repository: %s\n' "$REPO_ROOT"
printf 'SSH target: %s\n\n' "$SSH_TARGET"

require_local_command ssh
require_local_command curl
require_local_command grep
require_local_command find

printf '\n%s\n' '--- Cluster access ---'

if remote "kubectl get nodes >/dev/null 2>&1"; then
  pass "Kubernetes API is reachable through ${SSH_TARGET}"
else
  fail "Kubernetes API is not reachable through ${SSH_TARGET}"
fi

if remote "cilium status >/dev/null 2>&1"; then
  pass "Cilium CLI reports cluster status"
else
  fail "Cilium CLI status command failed"
fi

printf '\n%s\n' '--- Kube-proxy replacement ---'

KPR_VALUE="$(
  remote "cilium config view" |
    awk '$1 == "kube-proxy-replacement" {
      print tolower($2)
      exit
    }'
)"

if [[ "$KPR_VALUE" == "true" ]]; then
  pass "Cilium kube-proxy replacement is enabled"
else
  fail \
    "Cilium kube-proxy replacement value is '${KPR_VALUE:-not detected}'"
fi

if remote \
  "kubectl -n kube-system get daemonset kube-proxy >/dev/null 2>&1"
then
  KUBE_PROXY_STATE="$(
    remote \
      "kubectl -n kube-system get daemonset kube-proxy \
       -o custom-columns='DESIRED:.status.desiredNumberScheduled,READY:.status.numberReady' \
       --no-headers"
  )"

  warn \
    "Cilium kube-proxy replacement is enabled, but the kube-proxy DaemonSet remains present (${KUBE_PROXY_STATE})"
else
  pass "kube-proxy DaemonSet is absent"
fi

printf '\n%s\n' '--- Declarative Cilium resources ---'

check_resource ciliumloadbalancerippool k8s-lan-pool
check_resource ciliumloadbalancerippool bgp-vip-pool
check_resource ciliuml2announcementpolicy lan-loadbalancer-services
check_resource ciliumbgppeerconfig pfsense-peer
check_resource ciliumbgpadvertisement pfsense-service-vips
check_resource ciliumbgpclusterconfig pfsense-bgp

printf '\n%s\n' '--- Workload and LoadBalancer Services ---'

if remote \
  "kubectl -n lb-ipam-demo rollout status deployment/web \
   --timeout=15s >/dev/null 2>&1"
then
  pass "Deployment lb-ipam-demo/web is ready"
else
  fail "Deployment lb-ipam-demo/web is not ready"
fi

check_service_vip lb-ipam-demo web 10.10.10.200
check_service_vip lb-ipam-demo web-bgp 10.30.0.100

check_service_endpoints lb-ipam-demo web
check_service_endpoints lb-ipam-demo web-bgp

printf '\n%s\n' '--- L2 Announcement Lease ---'

LEASE_LINE="$(
  remote \
    "kubectl -n kube-system get leases \
     -o custom-columns='NAME:.metadata.name,HOLDER:.spec.holderIdentity' \
     --no-headers" |
    awk '
      $1 ~ /^cilium-l2announce-/ && $1 ~ /web/ {
        print
        exit
      }
    '
)"

if [[ -z "$LEASE_LINE" ]]; then
  LEASE_LINE="$(
    remote \
      "kubectl -n kube-system get leases \
       -o custom-columns='NAME:.metadata.name,HOLDER:.spec.holderIdentity' \
       --no-headers" |
      awk '
        $1 ~ /^cilium-l2announce-/ {
          print
          exit
        }
      '
  )"
fi

LEASE_NAME="$(awk '{print $1}' <<<"$LEASE_LINE")"
LEASE_HOLDER="$(awk '{print $2}' <<<"$LEASE_LINE")"

if [[ -n "$LEASE_NAME" ]]; then
  pass "L2 announcement Lease found: ${LEASE_NAME}"
else
  fail "No Cilium L2 announcement Lease found"
fi

case "$LEASE_HOLDER" in
  k8s-worker1 | k8s-worker2)
    pass "L2 announcement Lease holder is ${LEASE_HOLDER}"
    ;;
  *)
    fail \
      "Unexpected or missing L2 announcement Lease holder: ${LEASE_HOLDER:-none}"
    ;;
esac

printf '\n%s\n' '--- Cilium BGP sessions ---'

BGP_PEERS="$(remote "cilium bgp peers" 2>/dev/null || true)"

if grep -Eiq 'k8s-worker1' <<<"$BGP_PEERS"; then
  pass "BGP state includes k8s-worker1"
else
  fail "BGP state does not include k8s-worker1"
fi

if grep -Eiq 'k8s-worker2' <<<"$BGP_PEERS"; then
  pass "BGP state includes k8s-worker2"
else
  fail "BGP state does not include k8s-worker2"
fi

if grep -Eiq '64512' <<<"$BGP_PEERS"; then
  pass "BGP peer ASN 64512 is present"
else
  fail "BGP peer ASN 64512 is not present"
fi

if grep -Eiq '64513' <<<"$BGP_PEERS"; then
  pass "Cilium local ASN 64513 is present"
else
  fail "Cilium local ASN 64513 is not present"
fi

ESTABLISHED_COUNT="$(
  grep -Eic 'established' <<<"$BGP_PEERS" || true
)"

if (( ESTABLISHED_COUNT >= 2 )); then
  pass "At least two BGP sessions are established"
else
  fail \
    "Expected at least two established BGP sessions, found ${ESTABLISHED_COUNT}"
fi

printf '\n%s\n' '--- Current HTTP validation ---'

check_http "L2 VIP 10.10.10.200" "http://10.10.10.200"
check_http "BGP VIP 10.30.0.100" "http://10.30.0.100"

printf '\n%s\n' '--- Recorded L2 failover evidence ---'

L2_BEFORE_LEASE="${SNAPSHOT_ROOT}/failover/l2-lease-before-failover.txt"
L2_AFTER_LEASE="${SNAPSHOT_ROOT}/failover/l2-lease-after-failover.txt"
L2_BEFORE_HTTP="${SNAPSHOT_ROOT}/failover/l2-http-before-failover.txt"
L2_AFTER_HTTP="${SNAPSHOT_ROOT}/failover/l2-http-after-failover.txt"

require_file "$L2_BEFORE_LEASE"
require_file "$L2_AFTER_LEASE"
require_file "$L2_BEFORE_HTTP"
require_file "$L2_AFTER_HTTP"

require_pattern \
  "$L2_BEFORE_LEASE" \
  'k8s-worker1' \
  "Recorded L2 holder before failover was k8s-worker1"

require_pattern \
  "$L2_AFTER_LEASE" \
  'k8s-worker2' \
  "Recorded L2 holder after failover was k8s-worker2"

require_pattern \
  "$L2_BEFORE_HTTP" \
  'HTTP[[:space:]]+200' \
  "L2 VIP returned HTTP 200 before failover"

require_pattern \
  "$L2_AFTER_HTTP" \
  'HTTP[[:space:]]+200' \
  "L2 VIP returned HTTP 200 after failover"

printf '\n%s\n' '--- Recorded BGP failover evidence ---'

BGP_BEFORE_ROUTE="${SNAPSHOT_ROOT}/bgp/bgp-vip-route-before-failover.txt"
BGP_DURING_ROUTE="${SNAPSHOT_ROOT}/bgp/bgp-vip-route-during-failover.txt"
BGP_AFTER_ROUTE="${SNAPSHOT_ROOT}/bgp/bgp-vip-route-after-recovery.txt"

BGP_BEFORE_HTTP="${SNAPSHOT_ROOT}/failover/bgp-http-before-failover.txt"
BGP_DURING_HTTP="${SNAPSHOT_ROOT}/failover/bgp-http-during-failover.txt"
BGP_AFTER_HTTP="${SNAPSHOT_ROOT}/failover/bgp-http-after-recovery.txt"

require_file "$BGP_BEFORE_ROUTE"
require_file "$BGP_DURING_ROUTE"
require_file "$BGP_AFTER_ROUTE"

require_file "$BGP_BEFORE_HTTP"
require_file "$BGP_DURING_HTTP"
require_file "$BGP_AFTER_HTTP"

require_pattern \
  "$BGP_BEFORE_ROUTE" \
  '10\.30\.0\.100/32' \
  "BGP VIP route existed before failover"

require_pattern \
  "$BGP_BEFORE_ROUTE" \
  '10\.10\.10\.21' \
  "Pre-failover BGP evidence includes worker1"

require_pattern \
  "$BGP_BEFORE_ROUTE" \
  '10\.10\.10\.22' \
  "Pre-failover BGP evidence includes worker2"

require_pattern \
  "$BGP_DURING_ROUTE" \
  '10\.10\.10\.22' \
  "BGP route through worker2 remained during failover"

require_pattern \
  "$BGP_AFTER_ROUTE" \
  '10\.10\.10\.21' \
  "Recovered BGP evidence includes worker1"

require_pattern \
  "$BGP_AFTER_ROUTE" \
  '10\.10\.10\.22' \
  "Recovered BGP evidence includes worker2"

require_pattern \
  "$BGP_BEFORE_HTTP" \
  'HTTP[[:space:]]+200' \
  "BGP VIP returned HTTP 200 before failover"

require_pattern \
  "$BGP_DURING_HTTP" \
  'HTTP[[:space:]]+200' \
  "BGP VIP returned HTTP 200 during failover"

require_pattern \
  "$BGP_AFTER_HTTP" \
  'HTTP[[:space:]]+200' \
  "BGP VIP returned HTTP 200 after recovery"

printf '\n%s\n' '--- Manifest API validation ---'

while IFS= read -r manifest <&3; do
  relative="${manifest#${REPO_ROOT}/}"

  if ssh -o BatchMode=yes "$SSH_TARGET" \
    'kubectl apply --server-side --dry-run=server -f -' \
    < "$manifest" >/dev/null
  then
    pass "Server-side dry-run passed: ${relative}"
  else
    fail "Server-side dry-run failed: ${relative}"
  fi
done 3< <(
  find "$MANIFEST_ROOT" \
    -type f \
    -name '*.yaml' \
    -print |
    sort
)

printf '\n%s\n' '============================================================'
printf 'Failures: %d\n' "$FAILURES"
printf 'Warnings: %d\n' "$WARNINGS"
printf '%s\n' '============================================================'

if (( FAILURES > 0 )); then
  exit 1
fi

printf '%s\n' 'Phase 9 service exposure validation completed successfully.'
