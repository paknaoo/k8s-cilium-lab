#!/usr/bin/env bash

set -Eeuo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_ROOT="${REPO_ROOT}/snapshots/phase-10"

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

relative_path() {
  printf '%s' "${1#${REPO_ROOT}/}"
}

require_file() {
  local file="$1"

  if [[ -s "$file" ]]; then
    pass "Evidence present: $(relative_path "$file")"
  else
    fail "Evidence missing or empty: $(relative_path "$file")"
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

require_count() {
  local file="$1"
  local pattern="$2"
  local minimum="$3"
  local description="$4"

  local count

  if [[ ! -s "$file" ]]; then
    fail "${description}: evidence file missing or empty"
    return
  fi

  count="$(grep -Eic "$pattern" "$file" || true)"

  if (( count >= minimum )); then
    pass "${description} (${count} match(es))"
  else
    fail "${description}: expected at least ${minimum}, found ${count}"
  fi
}

require_pattern_any() {
  local pattern="$1"
  local description="$2"

  shift 2

  if grep -Eiq "$pattern" "$@"; then
    pass "$description"
  else
    fail "$description"
  fi
}

require_section_pattern() {
  local file="$1"
  local section_pattern="$2"
  local value_pattern="$3"
  local description="$4"

  if [[ ! -s "$file" ]]; then
    fail "${description}: evidence file missing or empty"
    return
  fi

  if awk \
    -v section="$section_pattern" \
    -v value="$value_pattern" '
      $0 ~ section {
        inside = 1
        next
      }

      inside && /^===/ {
        inside = 0
      }

      inside && $0 ~ value {
        found = 1
      }

      END {
        exit found ? 0 : 1
      }
    ' "$file"
  then
    pass "$description"
  else
    fail "$description"
  fi
}

printf '%s\n' '============================================================'
printf '%s\n' 'Phase 10 — Evidence Validation'
printf '%s\n' '============================================================'
printf 'Repository: %s\n' "$REPO_ROOT"
printf 'Evidence:   %s\n\n' "$EVIDENCE_ROOT"

BASELINE_BEFORE="${EVIDENCE_ROOT}/baseline/baseline-before-networkpolicy.txt"
BEFORE_POLICY="${EVIDENCE_ROOT}/baseline/netpol-before-policy.txt"

BROKEN_POLICY="${EVIDENCE_ROOT}/policy/netpol-broken-policy.yaml"
FIXED_POLICY="${EVIDENCE_ROOT}/policy/netpol-fixed-policy.yaml"

DURING_FAILURE="${EVIDENCE_ROOT}/failure/netpol-during-failure.txt"
CLIENT_DROPS="${EVIDENCE_ROOT}/failure/netpol-client-policy-drops.txt"
DATAPATH_DROPS="${EVIDENCE_ROOT}/failure/netpol-datapath-drops.txt"

CILIUM_HOST="${EVIDENCE_ROOT}/diagnosis/netpol-cilium-host-address.txt"
CILIUM_ENDPOINTS="${EVIDENCE_ROOT}/diagnosis/netpol-cilium-endpoints.txt"
BACKEND_ENDPOINT="${EVIDENCE_ROOT}/diagnosis/netpol-backend-endpoint.txt"
ROOT_CAUSE="${EVIDENCE_ROOT}/diagnosis/netpol-root-cause.txt"

AFTER_FIX="${EVIDENCE_ROOT}/recovery/netpol-after-fix.txt"
BASELINE_AFTER="${EVIDENCE_ROOT}/recovery/baseline-after-networkpolicy.txt"

REQUIRED_FILES=(
  "$BASELINE_BEFORE"
  "$BEFORE_POLICY"
  "$BROKEN_POLICY"
  "$FIXED_POLICY"
  "$DURING_FAILURE"
  "$CLIENT_DROPS"
  "$DATAPATH_DROPS"
  "$CILIUM_HOST"
  "$CILIUM_ENDPOINTS"
  "$BACKEND_ENDPOINT"
  "$ROOT_CAUSE"
  "$AFTER_FIX"
  "$BASELINE_AFTER"
)

printf '%s\n' '--- Evidence inventory ---'

for file in "${REQUIRED_FILES[@]}"; do
  require_file "$file"
done

printf '\n%s\n' '--- Initial cluster baseline ---'

require_pattern \
  "$BASELINE_BEFORE" \
  'k8s-master[[:space:]]+Ready' \
  "k8s-master was Ready before the test"

require_pattern \
  "$BASELINE_BEFORE" \
  'k8s-worker1[[:space:]]+Ready' \
  "k8s-worker1 was Ready before the test"

require_pattern \
  "$BASELINE_BEFORE" \
  'k8s-worker2[[:space:]]+Ready' \
  "k8s-worker2 was Ready before the test"

require_pattern \
  "$BASELINE_BEFORE" \
  'Cilium:.*OK' \
  "Cilium was healthy before the test"

require_pattern \
  "$BASELINE_BEFORE" \
  'Operator:.*OK' \
  "Cilium Operator was healthy before the test"

require_pattern \
  "$BASELINE_BEFORE" \
  'worker1.*established|established.*worker1' \
  "worker1 BGP peer was established before the test"

require_pattern \
  "$BASELINE_BEFORE" \
  'worker2.*established|established.*worker2' \
  "worker2 BGP peer was established before the test"

require_pattern \
  "$BASELINE_BEFORE" \
  '^L2 VIP:[[:space:]]*HTTP[[:space:]]*200$' \
  "L2 VIP returned HTTP 200 before the test"

require_pattern \
  "$BASELINE_BEFORE" \
  '^BGP VIP:[[:space:]]*HTTP[[:space:]]*200$' \
  "BGP VIP returned HTTP 200 before the test"

printf '\n%s\n' '--- Connectivity before policy enforcement ---'

require_section_pattern \
  "$BEFORE_POLICY" \
  '^=== CLIENT APPROVED -> BACKEND ===$' \
  '^HTTP[[:space:]]+200$' \
  "Approved client reached the backend before policy enforcement"

require_section_pattern \
  "$BEFORE_POLICY" \
  '^=== CLIENT DENIED -> BACKEND ===$' \
  '^HTTP[[:space:]]+200$' \
  "Denied client reached the backend before policy enforcement"

require_pattern \
  "$BEFORE_POLICY" \
  'backend.*Running|Running.*backend' \
  "Backend workload was running before policy enforcement"

require_pattern \
  "$BEFORE_POLICY" \
  'ENDPOINTSLICE' \
  "EndpointSlice evidence was captured before policy enforcement"

printf '\n%s\n' '--- Broken and fixed policy selectors ---'

require_pattern \
  "$BROKEN_POLICY" \
  '^[[:space:]]*access:[[:space:]]*approve[[:space:]]*$' \
  "Broken policy contains the intentional access=approve selector"

require_pattern \
  "$FIXED_POLICY" \
  '^[[:space:]]*access:[[:space:]]*approved[[:space:]]*$' \
  "Fixed policy contains the corrected access=approved selector"

if grep -Eq \
  '^[[:space:]]*access:[[:space:]]*approved[[:space:]]*$' \
  "$BROKEN_POLICY"
then
  fail "Broken policy unexpectedly contains the corrected selector"
else
  pass "Broken policy does not contain the corrected selector"
fi

if grep -Eq \
  '^[[:space:]]*access:[[:space:]]*approve[[:space:]]*$' \
  "$FIXED_POLICY"
then
  fail "Fixed policy unexpectedly contains the broken selector"
else
  pass "Fixed policy does not contain the broken selector"
fi

printf '\n%s\n' '--- Controlled failure evidence ---'

require_section_pattern \
  "$DURING_FAILURE" \
  '^=== CLIENT APPROVED -> BACKEND ===$' \
  '^HTTP[[:space:]]+000$' \
  "Approved client timed out with the broken policy"

require_section_pattern \
  "$DURING_FAILURE" \
  '^=== CLIENT DENIED -> BACKEND ===$' \
  '^HTTP[[:space:]]+000$' \
  "Denied client timed out with the broken policy"

require_section_pattern \
  "$DURING_FAILURE" \
  '^=== CLIENT APPROVED -> BACKEND ===$' \
  '^curl_exit=28$' \
  "Approved client recorded curl exit 28"

require_section_pattern \
  "$DURING_FAILURE" \
  '^=== CLIENT DENIED -> BACKEND ===$' \
  '^curl_exit=28$' \
  "Denied client recorded curl exit 28"

require_count \
  "$DURING_FAILURE" \
  'curl_exit=28' \
  2 \
  "Both failed requests recorded curl exit 28"

require_pattern \
  "$DURING_FAILURE" \
  'backend.*1/1.*Running|Running.*backend' \
  "Backend workload remained running during the failure"

require_pattern \
  "$DURING_FAILURE" \
  'ENDPOINTSLICE' \
  "Backend EndpointSlice information remained present during the failure"

require_pattern \
  "$DURING_FAILURE" \
  'Policy validation succeeded' \
  "CiliumNetworkPolicy validation succeeded during the failure"

require_pattern \
  "$DURING_FAILURE" \
  'status:[[:space:]]*"True"' \
  "CiliumNetworkPolicy status remained valid during the failure"

printf '\n%s\n' '--- Datapath diagnosis ---'

require_pattern_any \
  'Policy denied|action[[:space:]]+deny' \
  "Cilium recorded policy-denied datapath traffic" \
  "$CLIENT_DROPS" \
  "$DATAPATH_DROPS"

require_pattern_any \
  'TCP.*SYN|SYN.*TCP' \
  "Dropped TCP SYN traffic was captured" \
  "$CLIENT_DROPS" \
  "$DATAPATH_DROPS"

require_pattern_any \
  '10\.244\.2\.27.*10\.244\.2\.113.*80|10\.244\.2\.27.*80' \
  "Datapath evidence includes the approved client flow to TCP/80" \
  "$CLIENT_DROPS" \
  "$DATAPATH_DROPS"

require_pattern \
  "$BACKEND_ENDPOINT" \
  '"policy-enabled":[[:space:]]*"ingress"' \
  "Backend endpoint had ingress policy enforcement enabled"

require_pattern \
  "$BACKEND_ENDPOINT" \
  '"policy"[[:space:]]*:[[:space:]]*"OK"' \
  "Backend endpoint policy status was OK"

require_pattern \
  "$BACKEND_ENDPOINT" \
  'derived-from=CiliumNetworkPolicy' \
  "Backend endpoint policy was derived from CiliumNetworkPolicy"

require_pattern \
  "$BACKEND_ENDPOINT" \
  'policy\.name=backend-ingress' \
  "Backend endpoint policy referenced backend-ingress"

require_pattern \
  "$BACKEND_ENDPOINT" \
  'any\.access:[[:space:]]*approve[,}]' \
  "Backend endpoint policy reflected the broken source selector"

printf '\n%s\n' '--- Root cause ---'

require_pattern \
  "$ROOT_CAUSE" \
  'access=approve|access:[[:space:]]*approve' \
  "Root-cause evidence contains the incorrect selector"

require_pattern \
  "$ROOT_CAUSE" \
  'access=approved|access:[[:space:]]*approved' \
  "Root-cause evidence contains the actual client label"

require_pattern \
  "$ROOT_CAUSE" \
  'selector|label|mismatch|matched no' \
  "Root-cause evidence identifies a selector or label mismatch"

printf '\n%s\n' '--- Corrective action and selective access ---'

require_section_pattern \
  "$AFTER_FIX" \
  '^=== CLIENT APPROVED -> BACKEND ===$' \
  '^HTTP[[:space:]]+200$' \
  "Approved client returned HTTP 200 after the correction"

require_section_pattern \
  "$AFTER_FIX" \
  '^=== CLIENT APPROVED -> BACKEND ===$' \
  '^curl_exit=0$' \
  "Approved client recorded curl exit 0 after the correction"

require_section_pattern \
  "$AFTER_FIX" \
  '^=== CLIENT DENIED -> BACKEND ===$' \
  '^HTTP[[:space:]]+000$' \
  "Denied client remained blocked after the correction"

require_section_pattern \
  "$AFTER_FIX" \
  '^=== CLIENT DENIED -> BACKEND ===$' \
  '^curl_exit=28$' \
  "Denied client recorded curl exit 28 after the correction"

require_pattern \
  "$AFTER_FIX" \
  'access:[[:space:]]*approved' \
  "Active policy contained the corrected selector"

require_pattern \
  "$AFTER_FIX" \
  'Policy validation succeeded' \
  "Corrected policy validation succeeded"

require_pattern \
  "$AFTER_FIX" \
  'status:[[:space:]]*"True"' \
  "Corrected policy status was valid"

printf '\n%s\n' '--- Recovery baseline ---'

require_pattern \
  "$BASELINE_AFTER" \
  'k8s-master[[:space:]]+Ready' \
  "k8s-master was Ready after cleanup"

require_pattern \
  "$BASELINE_AFTER" \
  'k8s-worker1[[:space:]]+Ready' \
  "k8s-worker1 was Ready after cleanup"

require_pattern \
  "$BASELINE_AFTER" \
  'k8s-worker2[[:space:]]+Ready' \
  "k8s-worker2 was Ready after cleanup"

require_pattern \
  "$BASELINE_AFTER" \
  'Cilium:.*OK' \
  "Cilium was healthy after cleanup"

require_pattern \
  "$BASELINE_AFTER" \
  'Operator:.*OK' \
  "Cilium Operator was healthy after cleanup"

require_pattern \
  "$BASELINE_AFTER" \
  'worker1.*established|established.*worker1' \
  "worker1 BGP peer was established after cleanup"

require_pattern \
  "$BASELINE_AFTER" \
  'worker2.*established|established.*worker2' \
  "worker2 BGP peer was established after cleanup"

require_pattern \
  "$BASELINE_AFTER" \
  '^L2 VIP:[[:space:]]*HTTP[[:space:]]*200$' \
  "L2 VIP returned HTTP 200 after cleanup"

require_pattern \
  "$BASELINE_AFTER" \
  '^BGP VIP:[[:space:]]*HTTP[[:space:]]*200$' \
  "BGP VIP returned HTTP 200 after cleanup"

if grep -Eiq \
  'phase10-netpol.*(deleted|not found|absent)|No resources found' \
  "$BASELINE_AFTER"
then
  pass "Recovery evidence explicitly confirms test-resource cleanup"
else
  warn "Recovery baseline does not contain an explicit namespace cleanup marker"
fi

printf '\n%s\n' '--- Empty-file and sensitive-data checks ---'

if find "$EVIDENCE_ROOT" \
  -type f \
  -empty \
  -print \
  -quit |
  grep -q .
then
  fail "One or more Phase 10 evidence files are empty"
else
  pass "No Phase 10 evidence file is empty"
fi

SENSITIVE_RESULTS="$(
  grep -RniE \
    'kind:[[:space:]]*Secret|^[[:space:]]*password:|^[[:space:]]*token:|client-key-data:|client-certificate-data:|certificate-authority-data:|BEGIN .*PRIVATE KEY' \
    "$EVIDENCE_ROOT" || true
)"

if [[ -n "$SENSITIVE_RESULTS" ]]; then
  printf '%s\n' "$SENSITIVE_RESULTS" >&2
  fail "Potential sensitive data was found in Phase 10 evidence"
else
  pass "No high-risk credential or private-key patterns were found"
fi

printf '\n%s\n' '============================================================'
printf 'Failures: %d\n' "$FAILURES"
printf 'Warnings: %d\n' "$WARNINGS"
printf '%s\n' '============================================================'

if (( FAILURES > 0 )); then
  exit 1
fi

printf '%s\n' 'Phase 10 evidence validation completed successfully.'
