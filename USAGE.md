# talos-ebpf-lab: Operations Manual & Cheat Sheet (Kube-Proxy Replacement)

This documentation explains how to launch, operate, and tear down this cluster. All state, authentication configurations, and connection credentials stay **entirely on your laptop** inside this workspace directory. It will not interfere with other Kubernetes clusters on your machine.

---

## Architectural Isolation Design

This setup is fully self-contained using these mechanisms:
* **Local State Directory (`./state`)**: `talosctl cluster create docker` is invoked with `--state $(pwd)/state`. This writes all cluster control files, cryptographic assets, and internal Talos configurations inside this workspace instead of the default `~/.talos/clusters/` directory.
* **Isolated `talosconfig`**: Authenticating to the Talos API is done by setting `export TALOSCONFIG="$(pwd)/state/talosconfig"` in the session.
* **Isolated `kubeconfig`**: The Kubernetes API credentials are written directly to `./kubeconfig` in this workspace instead of modifying or merging with your global `~/.kube/config` file.
* **Zero Global Pollution**: Opening a new terminal tab leaves your normal kubectl configuration completely unmodified. Your current context will remain whatever it was previously.

---

## Step-by-Step Guide

### 1. Bootstrap the Cluster
Run the bootstrap script:
```bash
./bootstrap.sh
```
This script will:
* Remove any old cluster called `talos-demo` if it exists.
* Deploy one control plane node and two worker nodes inside local Docker containers running Kubernetes `v1.36.0`.
* Write isolated config files to `./state` and `./kubeconfig`.
* Automatically query the Docker network to resolve the exact internal bridge IP of the control plane.
* Compile and inject this IP into an active values file (`cilium-values-active.yaml`).
* Install the stable Helm release of Cilium (`1.19.4`).
* Wait for CNI deployment and verify node health.
* **Automatically generate a shell environment helper script: `env.sh`**.

### 2. Connect to the Cluster (Current Terminal Shell)
To automatically set the required environment variables in your current terminal session without manual export commands, run:
```bash
source env.sh
```

Now, any `kubectl` and `talosctl` commands you run will only target this local demo cluster:
```bash
kubectl get nodes -o wide
talosctl containers
```

### 3. Connect to the Cluster (New Terminal Shells)
If you open a new terminal window or tab, your normal Kubernetes configuration remains untouched to prevent interference. To direct the new shell to this cluster, simply source the `env.sh` file with its absolute path:
```bash
source <path-to-workspace>/env.sh
```
*(Tip: You can add an alias like `alias talos-demo="source <path-to-workspace>/env.sh"` in your `~/.bashrc` or `~/.zshrc` to activate the environment by simply typing `talos-demo`!)*

### 4. Verify Kube-Proxy Replacement
Since kube-proxy is fully disabled in the Talos machine patch, let's verify its absence:
```bash
kubectl get daemonset -n kube-system
```
*Expected Result*: There should be **no** daemonset named `kube-proxy`.

Verify Cilium is successfully load-balancing Kubernetes services:
```bash
kubectl -n kube-system exec -it ds/cilium -- cilium service list
```
This will print a list of all active ClusterIP and NodePort services being load-balanced in eBPF by Cilium rather than legacy iptables rules.

Verify Hubble network observability (works even if the local `cilium` CLI binary is not installed on your laptop):
```bash
kubectl -n kube-system exec -it ds/cilium -- hubble observe --last 10
```
This runs the `hubble` CLI tool directly from inside the active Cilium pod to retrieve and display the latest 10 network flow transactions in the cluster.



## Useful Commands for Beginners (Cheat Sheet)

Always ensure your environment is activated in your terminal session before running any commands:
```bash
source env.sh
```

---

### 1. Talos Linux (`talosctl`) Commands

Talos is an API-managed, immutable operating system with **no SSH and no shell**. You interact with it entirely via `talosctl` using Mutual TLS (mTLS) certificates stored in your local `state/` directory.

> [!TIP]
> **Default Targeting**: During bootstrap, the control plane container IP (typically `10.5.0.2`) is automatically configured as the **default target node** in your local `talosconfig`.
> This means you can run commands like `talosctl containers`, `talosctl service`, or `talosctl logs` directly without any flags! If you want to target a specific worker node, simply append the `-n <ip>` flag (e.g. `talosctl -n 10.5.0.3 service`). Node IPs can be found by running `kubectl get nodes -o wide`.

* **Check cluster/node health**:
  ```bash
  # Check full cluster health (monitoring control plane and worker nodes)
  talosctl health --control-plane-nodes 10.5.0.2 --worker-nodes 10.5.0.3,10.5.0.4
  ```
  *Why use it*: Verifies that the operating system services, etcd membership, and Kubernetes API boot sequence are completely healthy across all nodes. Running a bare `talosctl health` only monitors the controlplane node configured in `talosconfig`, which flags worker nodes as "unexpected" when queried via Kubernetes. Explicitly passing these flags enables full cluster verification.

* **Launch the Interactive Terminal Dashboard**:
  ```bash
  # Targets the default control plane node
  talosctl dashboard
  
  # Or target a specific worker node
  talosctl -n 10.5.0.3 dashboard
  ```
  *Why use it*: Opens a gorgeous, real-time `htop`-like dashboard inside your terminal showing CPU, memory, disk, network, and active container counts on the selected node. *(Press `Ctrl+C` to exit)*.

* **View running containers (OS-level)**:
  ```bash
  # Targets default node (control plane)
  talosctl containers
  ```
  *Why use it*: Shows the actual running containers on the system (e.g. `kubelet`, `etcd`, `containerd`, and the pods managed by Kubernetes).

* **Check OS service states**:
  ```bash
  # Targets default node (control plane)
  talosctl service
  ```
  *Why use it*: Lists every core Talos OS service (like `etcd`, `machined`, `kubelet`, `networkd`) and their current status (Running, Stopped, etc.).

* **Stream host service logs directly**:
  ```bash
  # Streams kubelet logs from the control plane
  talosctl logs kubelet
  
  # Streams kubelet logs from a worker node
  talosctl -n 10.5.0.3 logs kubelet
  ```
  *Why use it*: Streams logs from core services. Essential if a node is not joining the cluster or `kubelet` fails to start.

* **Read system configuration files**:
  ```bash
  talosctl read /etc/resolv.conf
  ```
  *Why use it*: Since there is no SSH shell, this allows you to read files directly from the host filesystem.

* **Stream kernel dmesg logs**:
  ```bash
  talosctl dmesg -f
  ```
  *Why use it*: Streams the node's Linux kernel ring buffer. Extremely useful for identifying low-level hardware or filesystem errors.

* **Reboot or Reset a node safely**:
  ```bash
  # Soft reboot a specific worker node
  talosctl -n 10.5.0.3 reboot
  
  # Wipe a worker node and return it to unprovisioned state
  talosctl -n 10.5.0.4 reset
  ```

---

### 2. Cilium & Hubble (eBPF CNI) Commands

Cilium replaces `kube-proxy` entirely by compiling eBPF programs and loading them directly into the Linux kernel of each node. Since the Cilium CLI runs inside the agent container, we run commands using `kubectl exec` targeting the Cilium DaemonSet (`ds/cilium`).

* **Check Cilium CNI overall status**:
  ```bash
  kubectl -n kube-system exec -it ds/cilium -- cilium status
  ```
  *Why use it*: Verify CNI health, eBPF routing mode, and status of connection to Kubernetes API.

* **List eBPF Identities and Endpoints**:
  ```bash
  kubectl -n kube-system exec -it ds/cilium -- cilium endpoint list
  ```
  *Why use it*: Shows how Cilium abstracts pod IPs into integer **security identities**. This is the secret behind Cilium's lightning-fast firewall rules!

* **List BPF load-balanced services**:
  ```bash
  kubectl -n kube-system exec -it ds/cilium -- cilium service list
  ```
  *Why use it*: Proves that kube-proxy is replaced. This list shows every Kubernetes Service mapped to its backends directly in the eBPF datapath.

* **Watch live network flows in real-time**:
  ```bash
  kubectl -n kube-system exec -it ds/cilium -- hubble observe -f
  ```
  *Why use it*: Acts like `tail -f` for your network! Streams every packet flow occurring in the cluster.

* **Filter Hubble flows for dropped packets (Debug helper)**:
  ```bash
  kubectl -n kube-system exec -it ds/cilium -- hubble observe --type drop
  ```
  *Why use it*: The absolute best command for troubleshooting connection timeouts. Instantly displays whether a packet was dropped by a Network Policy.

* **Filter network flows by Pod or Namespace**:
  ```bash
  # Watch traffic specifically for a pod named 'nettool'
  kubectl -n kube-system exec -it ds/cilium -- hubble observe --pod nettool -f
  
  # Watch traffic inside the 'kube-system' namespace
  kubectl -n kube-system exec -it ds/cilium -- hubble observe --namespace kube-system
  ```

* **Run a comprehensive CNI validation suite**:
  ```bash
  kubectl -n kube-system exec -it ds/cilium -- cilium connectivity test
  ```
  *Why use it*: Deploys temporary pods to verify pod-to-pod, pod-to-service, and egress/ingress routing across all nodes in the cluster.

---

### 3. Kubernetes (`kubectl`) Commands

Standard commands optimized for local development, diagnostic testing, and quick workflow execution.

#### 💡 The "Golden Path" of Troubleshooting Failing Pods
If a deployment or pod is not working, follow this sequence to diagnose:
1. **Find the failing pod**:
   ```bash
   kubectl get pods -A
   ```
2. **Inspect the controller events**:
   ```bash
   kubectl describe pod <failing-pod-name>
   ```
   *Tip*: Scroll down to the **Events** section. It will tell you if the image name is wrong, if there is a scheduling constraint, or if a mount failed.
3. **View standard stdout/stderr logs**:
   ```bash
   kubectl logs <failing-pod-name>
   ```
4. **View logs from a crashed/rebooted container**:
   ```bash
   kubectl logs <failing-pod-name> --previous
   ```
   *Why use it*: If your pod is in `CrashLoopBackOff`, standard `logs` will show nothing because the current container is new. `--previous` fetches logs from the container that just died.

#### 🚀 Essential Laptop Development Commands

* **Port Forwarding (Access local cluster services in your browser)**:
  ```bash
  # Forward traffic from localhost:8080 to service port 80
  kubectl port-forward svc/my-service 8080:80
  ```
  *Why use it*: Allows you to open `http://localhost:8080` in your host laptop's browser to test web applications running inside the cluster without needing to set up DNS or external IPs.

* **Interactive Diagnostic Shell (Netshoot)**:
  ```bash
  kubectl run nettool --rm -i --tty --image=nicolaka/netshoot -- bash
  ```
  *Why use it*: Spins up a transient pod containing curl, dig, drill, tcpdump, and dozens of other networking tools, drops you into an interactive bash shell, and automatically deletes itself when you exit.

* **Imperative YAML Generation (Save time writing YAML)**:
  Instead of writing boilerplate Kubernetes YAML manifest from scratch, generate it in seconds:
  ```bash
  # Generate a Deployment YAML
  kubectl create deployment webserver --image=nginx --dry-run=client -o yaml > deployment.yaml
  
  # Generate a Service YAML for that deployment
  kubectl expose deployment webserver --port=80 --target-port=80 --dry-run=client -o yaml > service.yaml
  ```

---

### 4. Tear Down the Cluster

To completely clean up and remove the cluster from your laptop:
```bash
./teardown.sh
```
This destroys the Docker container nodes, tears down the dedicated Docker bridge network, and deletes all local configuration files (including `env.sh` and `./kubeconfig`), returning your laptop to a pristine state.

