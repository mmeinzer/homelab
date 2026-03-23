# Talos Machine Configuration

Talos-specific configuration required beyond what's in the README's cluster initialization steps. The actual machine configs live in `talos/`.

## Longhorn Storage Mount

Longhorn requires a bind mount on every node. Without it, Longhorn pods will get stuck in Init. This is already in the checked-in Talos configs, but if adding a new node you need to ensure it's present:

```bash
# Verify the mount exists on a node
talosctl -n <node-ip> mounts | grep longhorn
```

To patch an existing node that's missing it:

```bash
talosctl patch machineconfig -n <node-ip> --patch @longhorn-patch.yaml
talosctl reboot -n <node-ip>
```

The patch content is the `kubelet.extraMounts` block in `talos/controlplane.yaml`.

## Troubleshooting

### Longhorn pods stuck in Init

Verify the mount exists on all nodes:
```bash
talosctl -n <node-ip> ls /var/lib/longhorn
```

### Node not joining cluster

```bash
talosctl -n <node-ip> get machineconfig -o yaml
```

### Kubelet not starting

```bash
talosctl -n <node-ip> logs kubelet
```
