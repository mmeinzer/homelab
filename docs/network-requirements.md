# Network Requirements

Prerequisites and constraints for the network this cluster runs on. For current IP allocations and domains, see `infrastructure/metallb-config/resources.yaml`, IngressRoute manifests, and the README.

## Firewall / Port Requirements

### Inbound (from Internet)

With Cloudflare Tunnel, **no inbound ports need to be opened** on your router.

### Inbound (Local Network to Cluster)

| Port | Protocol | Purpose |
|------|----------|---------|
| 6443 | TCP | Kubernetes API |
| 80 | TCP | HTTP (Traefik) |
| 443 | TCP | HTTPS (Traefik) |
| 50000 | TCP | Talos API |

### Outbound (Cluster to Internet)

| Destination | Port | Purpose |
|-------------|------|---------|
| Cloudflare | 443 | Tunnel, DNS API |
| Let's Encrypt | 443 | ACME challenges |
| Container registries | 443 | Image pulls |
| Helm repos | 443 | Chart downloads |

### Inter-Node Communication

| Port | Protocol | Purpose |
|------|----------|---------|
| 6443 | TCP | Kubernetes API |
| 2379-2380 | TCP | etcd |
| 10250 | TCP | Kubelet |
| 10257 | TCP | kube-controller-manager |
| 10259 | TCP | kube-scheduler |
| 50000-50001 | TCP | Talos API/trustd |
| 51820 | UDP | Talos KubeSpan (if enabled) |

## MetalLB Requirements

MetalLB runs in Layer 2 mode (ARP-based). Requirements:

- The MetalLB IP range must be on the same subnet as your nodes
- IPs in the pool must not be used by other devices
- Your router should not assign these IPs via DHCP

To change the IP range, edit `infrastructure/metallb-config/resources.yaml`.
