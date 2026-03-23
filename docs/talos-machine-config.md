# Talos Machine Configuration

This document covers the Talos Linux configuration required to run this homelab.

## Prerequisites

- [Talos Linux](https://www.talos.dev/) installed on your nodes
- `talosctl` CLI installed locally
- Basic familiarity with Talos machine configs

## Required Machine Config Patches

### Longhorn Storage Mount

Longhorn requires a dedicated host path for storing data. Apply this patch to **all nodes** (control plane and workers):

```yaml
machine:
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
```

### Applying the Patch

**Option 1: During initial install**

```bash
talosctl gen config my-cluster https://<control-plane-ip>:6443 \
  --config-patch @longhorn-patch.yaml
```

**Option 2: To an existing cluster**

```bash
# Create the patch file
cat > longhorn-patch.yaml << 'EOF'
machine:
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
EOF

# Apply to each node
talosctl patch machineconfig -n <node-ip> --patch @longhorn-patch.yaml

# Reboot the node to apply changes
talosctl reboot -n <node-ip>
```

## Network Configuration

### Static IPs

Talos nodes should have static IPs configured. You can either:

1. **DHCP Reservations** (recommended): Configure your router to assign fixed IPs based on MAC address
2. **Static IP in machine config**:

```yaml
machine:
  network:
    interfaces:
      - interface: eth0
        addresses:
          - 10.12.14.170/24
        routes:
          - network: 0.0.0.0/0
            gateway: 10.12.14.1
```

### Current IP Assignments

| Node | IP | Role |
|------|-----|------|
| Control Plane | 10.12.14.170 | Talos control plane |
| Worker | 10.12.14.171 | Talos worker |

## Complete Example Machine Config

Here's a complete control plane config with all required settings:

```yaml
version: v1alpha1
machine:
  type: controlplane
  kubelet:
    extraMounts:
      - destination: /var/lib/longhorn
        type: bind
        source: /var/lib/longhorn
        options:
          - bind
          - rshared
          - rw
  network:
    hostname: talos-cp
cluster:
  controlPlane:
    endpoint: https://10.12.14.170:6443
```

## Generating Configs

```bash
# Generate configs for a new cluster
talosctl gen config homelab https://10.12.14.170:6443 \
  --output-dir _out \
  --config-patch @longhorn-patch.yaml

# Bootstrap the cluster (run once on first control plane)
talosctl bootstrap -n 10.12.14.170 -e 10.12.14.170

# Get kubeconfig
talosctl kubeconfig -n 10.12.14.170 -e 10.12.14.170
```

## Verification

After configuration, verify the Longhorn mount is present:

```bash
talosctl -n <node-ip> mounts | grep longhorn
```

Expected output:
```
/var/lib/longhorn -> /var/lib/longhorn (bind,rshared,rw)
```

## Troubleshooting

### Longhorn pods stuck in Init

If Longhorn pods are stuck, verify the mount exists on all nodes:

```bash
talosctl -n <node-ip> ls /var/lib/longhorn
```

### Node not joining cluster

Check the machine config was applied:

```bash
talosctl -n <node-ip> get machineconfig -o yaml
```

### Kubelet not starting

View kubelet logs:

```bash
talosctl -n <node-ip> logs kubelet
```
