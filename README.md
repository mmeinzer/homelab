Steps taken to initialize cluster:
1. Download iso from talos factory with QEMU tools as only addition
2. Create talos-1 and talos-2 VMs, one on each proxmox node
3. Assign their IPs as static in the router (10.12.14.170 and 10.12.14.171)
4. `export CONTROL_PLANE_IP=10.12.14.170`
5. `talosctl gen config talos-proxmox-cluster https://$CONTROL_PLANE_IP:6443 --output-dir _out --install-image factory.talos.dev/nocloud-installer/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515:v1.12.0`
6. Edited `controlplane.yaml` to uncomment `allowSchedulingOnControlPlanes: true`
7. `talosctl apply-config --insecure --nodes $CONTROL_PLANE_IP --file _out/controlplane.yaml`
8. `export WORKER_IP=10.12.14.171`
9. `talosctl apply-config --insecure --nodes $WORKER_IP --file _out/worker.yaml`
10. export TALOSCONFIG="_out/talosconfig"
    talosctl config endpoint $CONTROL_PLANE_IP
    talosctl config node $CONTROL_PLANE_IP
11. `talosctl bootstrap`
12. `talosctl kubeconfig .` // get the kubeconfig

