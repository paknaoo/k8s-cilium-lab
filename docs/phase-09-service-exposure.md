# Phase 09 — Cilium Service Exposure

## Scope

Phase 9 implements and validates Kubernetes `LoadBalancer` service exposure using Cilium.

The completed implementation includes:

* Cilium kube-proxy replacement;
* Cilium LoadBalancer IP Address Management;
* Cilium L2 Announcements;
* L2 Lease-based ownership and failover;
* Cilium BGP Control Plane v2;
* BGP peering with pfSense FRR;
* redundant BGP advertisement paths through both Kubernetes worker nodes;
* controlled L2 and BGP failover testing;
* HTTP availability validation before, during and after failover.

The implementation is limited to the configuration and services validated in the working lab.

## Repository Artefacts

Declarative configuration is stored under:

```text
manifests/service-exposure/
├── bgp-control-plane/
├── l2-announcements/
├── loadbalancer-ipam/
└── services/
```

Runtime and validation evidence is stored under:

```text
snapshots/phase-09/
├── bgp/
├── cilium/
├── failover/
└── l2/
```

Automated validation is provided by:

```text
scripts/validate-service-exposure.sh
```

## 9.1 Cilium LoadBalancer IPAM

Cilium LoadBalancer IPAM allocates external addresses to Kubernetes Services of type `LoadBalancer`.

Two address pools are configured:

| Pool           | Purpose                              |
| -------------- | ------------------------------------ |
| `k8s-lan-pool` | LAN-reachable LoadBalancer addresses |
| `bgp-vip-pool` | Service VIP advertised through BGP   |

The Phase 9 demonstration namespace is:

```text
lb-ipam-demo
```

It contains one web Deployment and two LoadBalancer Services.

### L2 Service

The Service:

```text
lb-ipam-demo/web
```

uses:

```text
10.10.10.200
```

This address is allocated from the LAN LoadBalancer pool and announced on the local network through Cilium L2 Announcements.

### BGP Service

The Service:

```text
lb-ipam-demo/web-bgp
```

uses:

```text
10.30.0.100
```

The address is allocated from the BGP VIP pool and advertised as:

```text
10.30.0.100/32
```

Both Services select the same validated web workload.

EndpointSlice snapshots confirm that both Services had ready backend endpoints during validation.

## 9.2 Cilium L2 Announcements

L2 service advertisement is controlled by:

```text
CiliumL2AnnouncementPolicy/lan-loadbalancer-services
```

The policy selects the intended LAN LoadBalancer Service through its configured Service selector.

Cilium maintains a Kubernetes Lease for the announced Service. The Lease determines which eligible node currently owns the L2 announcement.

The observed Lease was:

```text
cilium-l2announce-lb-ipam-demo-web
```

### L2 Failover Validation

Before the controlled failover:

```text
Lease holder: k8s-worker1
VIP:          10.10.10.200
HTTP result:  200
```

During the test, the original policy selector was temporarily changed using the same controlled procedure used during live implementation.

After failover:

```text
Lease holder: k8s-worker2
VIP:          10.10.10.200
HTTP result:  200
```

The Lease holder changed successfully while the Service remained reachable.

After validation:

* the original L2 policy selector was restored;
* temporary node labels were removed;
* the Service continued returning HTTP 200.

The test demonstrates that L2 ownership can move between eligible worker nodes without changing the client-facing VIP.

## 9.3 Cilium BGP Control Plane v2

The BGP implementation uses Cilium BGP Control Plane v2 and pfSense FRR.

The declarative Cilium resources are:

```text
CiliumBGPClusterConfig/pfsense-bgp
CiliumBGPPeerConfig/pfsense-peer
CiliumBGPAdvertisement/pfsense-service-vips
```

Cilium automatically generated node-specific runtime configuration for:

```text
CiliumBGPNodeConfig/k8s-worker1
CiliumBGPNodeConfig/k8s-worker2
```

The generated `CiliumBGPNodeConfig` objects are stored as runtime snapshots rather than declarative repository manifests.

No `CiliumBGPNodeConfigOverride` objects are configured.

### Autonomous Systems

The validated Autonomous System numbers are:

| Component           |     ASN |
| ------------------- | ------: |
| pfSense FRR         | `64512` |
| Cilium worker nodes | `64513` |

### BGP Peers

Both worker nodes establish BGP sessions with pfSense:

| Node          | Node address  | Local ASN | Peer ASN |
| ------------- | ------------- | --------: | -------: |
| `k8s-worker1` | `10.10.10.21` |   `64513` |  `64512` |
| `k8s-worker2` | `10.10.10.22` |   `64513` |  `64512` |

The Cilium BGP peer state confirmed that both sessions were established during normal operation.

### Advertised VIP

The BGP Service VIP is:

```text
10.30.0.100/32
```

Before failover, pfSense FRR received two paths:

```text
10.30.0.100/32 via 10.10.10.21
10.30.0.100/32 via 10.10.10.22
```

This provides redundant reachability through both worker nodes.

## 9.4 BGP Failover Validation

A controlled BGP failover was performed using the same selector-based procedure validated during live implementation.

### Before Failover

pfSense FRR reported two paths:

```text
10.30.0.100/32 via 10.10.10.21
10.30.0.100/32 via 10.10.10.22
```

The Service returned:

```text
HTTP 200
```

### During Failover

The route through `k8s-worker1` was withdrawn.

pfSense retained the remaining path:

```text
10.30.0.100/32 via 10.10.10.22
```

The Service continued returning:

```text
HTTP 200
```

### After Recovery

The original BGP selector was restored and temporary labels were removed.

Both paths returned:

```text
10.30.0.100/32 via 10.10.10.21
10.30.0.100/32 via 10.10.10.22
```

The Service continued returning:

```text
HTTP 200
```

The test confirms that withdrawal of one BGP path does not interrupt the Service while the second worker path remains available.

## Kube-Proxy Replacement

Cilium reports:

```text
kube-proxy-replacement: true
```

The Phase 9 validation confirms that Cilium kube-proxy replacement is enabled and both LoadBalancer Services operate successfully.

The legacy Kubernetes `kube-proxy` DaemonSet object remains present in the cluster. The validation script reports this condition as a warning rather than hiding it or treating the DaemonSet as absent.

The repository therefore documents both parts of the actual state:

* Cilium kube-proxy replacement is enabled;
* the `kube-proxy` DaemonSet object remains present.

No claim is made that the DaemonSet has been removed.

## Validation

The Phase 9 validation script checks:

* Kubernetes API access;
* Cilium status;
* kube-proxy replacement state;
* presence of the legacy kube-proxy DaemonSet;
* LoadBalancer IP pool resources;
* L2 Announcement Policy;
* BGP Control Plane v2 resources;
* Deployment readiness;
* both Service VIP assignments;
* ready EndpointSlice backends;
* current L2 Lease ownership;
* BGP sessions for both workers;
* Autonomous System numbers;
* current HTTP availability;
* recorded L2 failover evidence;
* recorded BGP failover evidence;
* server-side API validation of repository manifests.

Run:

```bash
./scripts/validate-service-exposure.sh
```

The validation script does not initiate a failover or modify cluster labels. It validates the current state and checks the recorded evidence from the controlled tests.

## Manifest Validation

All declarative Phase 9 manifests passed:

```text
kubectl apply --server-side --dry-run=server
```

The API server accepted:

* both `CiliumLoadBalancerIPPool` objects;
* the `CiliumL2AnnouncementPolicy`;
* the `CiliumBGPPeerConfig`;
* the `CiliumBGPAdvertisement`;
* the `CiliumBGPClusterConfig`;
* the demonstration Namespace;
* the web Deployment;
* both LoadBalancer Services.

Non-fatal warnings concerning migration of the historical `kubectl.kubernetes.io/last-applied-configuration` annotation were produced because the live objects had previously been managed through client-side apply.

No live resources were changed during server-side dry-run validation.

## Runtime Evidence

The repository snapshots include:

### Cilium

* Cilium status;
* Cilium configuration;
* kube-proxy status;
* networking component inventory;
* BGP peer state;
* advertised BGP routes;
* manifest server-side dry-run results.

### L2

* Kubernetes Lease inventory;
* full Lease snapshots;
* Service EndpointSlice state;
* Lease holder before and after failover;
* HTTP results before and after failover.

### BGP

* generated Cilium BGP node configuration;
* Service EndpointSlice state;
* pfSense FRR BGP summaries;
* BGP route state before, during and after failover;
* pfSense routing-table state before, during and after failover.

### Failover

* L2 Lease ownership transition;
* L2 HTTP availability;
* BGP HTTP availability before failover;
* BGP HTTP availability during failover;
* BGP HTTP availability after recovery;
* automated Phase 9 validation output.

## Security Controls

The Phase 9 repository artefacts do not contain:

* passwords;
* Kubernetes tokens;
* kubeconfig certificate data;
* private keys;
* BGP authentication keys;
* WireGuard keys;
* Secret values;
* unrelated pfSense configuration.

The pfSense evidence is limited to FRR operational state directly related to the validated BGP implementation.

Generated runtime objects such as Lease, EndpointSlice and `CiliumBGPNodeConfig` are stored only as snapshots. They are not presented as declarative configuration.

## Checkpoint

Phase 9 is complete.

The validated implementation provides:

* LoadBalancer IP allocation through Cilium;
* LAN Service exposure through L2 Announcements;
* Lease-based L2 ownership failover;
* BGP Service advertisement through pfSense FRR;
* two redundant BGP paths;
* controlled path withdrawal and recovery;
* uninterrupted HTTP availability through both tested failover scenarios.

The remaining project phases are:

* Phase 10 — controlled failure scenarios and troubleshooting;
* Phase 11 — automation, validation improvements, Makefile and final portfolio polish.
