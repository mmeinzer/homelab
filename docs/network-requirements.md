# Network Requirements

This document covers the network configuration required for the homelab cluster.

## Network Overview

```
Internet
    │
    ├── Cloudflare (DNS + Tunnel)
    │       │
    │       └── app.guavascheduler.com ──► Cloudflare Tunnel ──► guava pod
    │
Router (10.12.14.1)
    │
    ├── 10.12.14.170 ── Talos Control Plane
    ├── 10.12.14.171 ── Talos Worker
    │
    └── 10.12.14.200-210 ── MetalLB LoadBalancer Pool
            │
            ├── 10.12.14.200 ── Traefik (Ingress)
            │       │
            │       ├── argocd.vacant.dev
            │       ├── grafana.vacant.dev
            │       ├── longhorn.vacant.dev
            │       └── auth.vacant.dev
            │
            └── (Additional IPs available for other LoadBalancer services)
```

## IP Address Allocation

### Current Configuration

| IP Address | Purpose | Notes |
|------------|---------|-------|
| 10.12.14.1 | Router/Gateway | |
| 10.12.14.170 | Talos Control Plane | Static/DHCP reservation |
| 10.12.14.171 | Talos Worker | Static/DHCP reservation |
| 10.12.14.200-210 | MetalLB Pool | 11 IPs for LoadBalancer services |

### Adapting to Your Network

If your network uses a different subnet (e.g., `192.168.1.0/24`), update these files:

**1. MetalLB IP Pool** (`infrastructure/metallb-config/resources.yaml`):
```yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.1.200-192.168.1.210  # Change to your range
```

**2. Talos Machine Configs** - Update node IPs in your Talos configuration

### IP Range Requirements

| Purpose | Minimum IPs | Recommended |
|---------|-------------|-------------|
| Cluster nodes | 1 (single node) | 2+ (HA) |
| MetalLB pool | 1 | 5-10 |

## DNS Configuration

### External DNS (Cloudflare)

The following DNS records are managed automatically by external-dns:

| Record | Type | Value | Managed By |
|--------|------|-------|------------|
| `argocd.vacant.dev` | A | MetalLB IP | external-dns |
| `grafana.vacant.dev` | A | MetalLB IP | external-dns |
| `longhorn.vacant.dev` | A | MetalLB IP | external-dns |
| `auth.vacant.dev` | A | MetalLB IP | external-dns |
| `app.guavascheduler.com` | CNAME | Tunnel endpoint | Cloudflare Tunnel |

### Internal DNS (CoreDNS)

Kubernetes services are accessible via internal DNS:

```
<service>.<namespace>.svc.cluster.local
```

Examples:
- `prometheus.observability.svc.cluster.local`
- `guava-db-rw.guava.svc.cluster.local`

## Firewall / Port Requirements

### Inbound (from Internet)

With Cloudflare Tunnel, **no inbound ports need to be opened** on your router. The tunnel creates an outbound connection to Cloudflare.

### Inbound (Local Network → Cluster)

| Port | Protocol | Purpose |
|------|----------|---------|
| 6443 | TCP | Kubernetes API |
| 80 | TCP | HTTP (Traefik) |
| 443 | TCP | HTTPS (Traefik) |
| 50000 | TCP | Talos API |

### Outbound (Cluster → Internet)

| Destination | Port | Purpose |
|-------------|------|---------|
| Cloudflare | 443 | Tunnel, DNS API |
| Let's Encrypt | 443 | ACME challenges |
| Container registries | 443 | Image pulls |
| Helm repos | 443 | Chart downloads |

### Inter-Node Communication

Talos and Kubernetes require these ports between nodes:

| Port | Protocol | Purpose |
|------|----------|---------|
| 6443 | TCP | Kubernetes API |
| 2379-2380 | TCP | etcd |
| 10250 | TCP | Kubelet |
| 10257 | TCP | kube-controller-manager |
| 10259 | TCP | kube-scheduler |
| 50000-50001 | TCP | Talos API/trustd |
| 51820 | UDP | Talos KubeSpan (if enabled) |

## MetalLB Configuration

MetalLB runs in Layer 2 mode, which uses ARP to announce IPs on your local network.

### How It Works

1. MetalLB assigns an IP from the pool to a `LoadBalancer` service
2. MetalLB responds to ARP requests for that IP
3. Traffic is routed to the node running the MetalLB speaker pod
4. kube-proxy forwards traffic to the service's pods

### Requirements

- The MetalLB IP range must be on the same subnet as your nodes
- IPs in the pool must not be used by other devices
- Your router should not assign these IPs via DHCP

### Verifying MetalLB

```bash
# Check speaker pods are running
kubectl get pods -n metallb-system

# Check IP assignments
kubectl get svc -A | grep LoadBalancer

# Test ARP response (from another machine on the network)
arping -c 3 10.12.14.200
```

## Traefik Ingress

Traefik is the ingress controller and receives the first MetalLB IP.

### Service Configuration

```bash
# Get Traefik's external IP
kubectl get svc traefik -n traefik
```

Expected output:
```
NAME      TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)
traefik   LoadBalancer   10.96.x.x      10.12.14.200   80:xxxxx/TCP,443:xxxxx/TCP
```

### IngressRoute Example

Services are exposed via Traefik's `IngressRoute` CRD:

```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: my-app
  annotations:
    external-dns.alpha.kubernetes.io/hostname: myapp.vacant.dev
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`myapp.vacant.dev`)
      kind: Rule
      services:
        - name: my-app-service
          port: 80
  tls:
    secretName: myapp-tls
```

## Troubleshooting

### Service not getting external IP

1. Check MetalLB is running:
   ```bash
   kubectl get pods -n metallb-system
   ```

2. Check IP pool has available addresses:
   ```bash
   kubectl get ipaddresspool -n metallb-system -o yaml
   ```

3. Check for events:
   ```bash
   kubectl describe svc <service-name> -n <namespace>
   ```

### Can't reach LoadBalancer IP from local network

1. Verify MetalLB speaker is on the same L2 network:
   ```bash
   kubectl logs -n metallb-system -l app=metallb,component=speaker
   ```

2. Check ARP table on your machine:
   ```bash
   arp -a | grep 10.12.14.200
   ```

3. Verify no IP conflict (check router's DHCP leases)

### DNS not resolving

1. Check external-dns logs:
   ```bash
   kubectl logs -n external-dns -l app.kubernetes.io/name=external-dns
   ```

2. Verify the IngressRoute has the correct annotation:
   ```yaml
   annotations:
     external-dns.alpha.kubernetes.io/hostname: myapp.vacant.dev
   ```

3. Check Cloudflare dashboard for the DNS record

### Can't access from outside network

This is expected! External access is only via Cloudflare Tunnel.

To add external access for a new service:
1. Create a new Cloudflare Tunnel (or add hostname to existing)
2. Deploy cloudflared with the new route
3. See [cloudflare-setup.md](./cloudflare-setup.md) for details

## Network Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         Local Network                           │
│                        10.12.14.0/24                           │
│                                                                 │
│  ┌──────────┐     ┌──────────────┐     ┌──────────────┐       │
│  │  Router  │     │ Control Plane│     │    Worker    │       │
│  │   .1     │     │    .170      │     │    .171      │       │
│  └────┬─────┘     └──────┬───────┘     └──────┬───────┘       │
│       │                  │                     │               │
│       └──────────────────┼─────────────────────┘               │
│                          │                                      │
│                   ┌──────┴───────┐                             │
│                   │   MetalLB    │                             │
│                   │ .200 - .210  │                             │
│                   └──────┬───────┘                             │
│                          │                                      │
│                   ┌──────┴───────┐                             │
│                   │   Traefik    │                             │
│                   │    .200      │                             │
│                   └──────────────┘                             │
│                          │                                      │
│              ┌───────────┼───────────┐                         │
│              │           │           │                         │
│         argocd.*    grafana.*   longhorn.*                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                           │
                    Cloudflare Tunnel
                           │
                    ┌──────┴───────┐
                    │  Cloudflare  │
                    │    Edge      │
                    └──────┬───────┘
                           │
                     app.guavascheduler.com
                           │
                       Internet
```
