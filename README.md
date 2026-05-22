# Isolated Local Talos Kubernetes Cluster with Cilium (eBPF Kube-Proxy Replacement)

A lightweight, rootless, laptop-sized Kubernetes PoC demo cluster running **Talos Linux (v1.13.2)**, **Kubernetes (v1.36.0)**, and **Cilium CNI (v1.19.4)** in strict eBPF `kube-proxy` replacement mode.

This project is optimized for developers and network engineers wanting to demo or experiment with modern eBPF networking locally without heavy hypervisors or host environment pollution.

---

## ⚡ Core Features

* **100% Host-Isolated**: Zero interference with other local or global Kubernetes and Talos configurations. It writes states, keys, and tokens directly inside this workspace directory, leaving your `~/.kube/config` and `~/.talos/config` pristine.
* **Rootless & Fast Deployment**: Boots the nodes as containerized processes using `talosctl cluster create docker`, bypassing virtual machines or root (`sudo`) privilege requirements.
* **Strict Kube-Proxy Replacement**: Kubernetes services are load-balanced directly inside the Linux host kernels by Cilium eBPF maps instead of legacy `iptables` or `ipvs` rules.
* **Observability Out-of-the-Box**: Hubble Relay is pre-configured so you can observe live packet flows and connection drops directly inside your terminal.

---

## 📂 Project Structure

```
├── bootstrap.sh                        # Wipes old state, boots Docker nodes, templates IPs, and installs Cilium
├── teardown.sh                         # Destroys all cluster containers, networks, and cleans local state
├── USAGE.md                            # Comprehensive operations manual & beginner cheat sheet (talosctl, cilium, kubectl)
├── cilium-values.yaml                  # Template Helm values for strict kube-proxy replacement and Hubble
├── talosconfig-patch-controlplane.yaml # Talos control plane patch (CNI: none, custom Pod/Service CIDRs, no kube-proxy)
├── talosconfig-patch-worker.yaml       # Talos worker node patch (disabled kube-proxy)
├── .gitignore                          # Confines cluster credentials, tokens, and active files to your local folder
└── state/                              # [Generated] Private directory for keys, talosconfig, and internal Talos state
```

---

## 🛠️ Prerequisites

Before executing the bootstrap script, make sure your host machine has the following tools installed and configured:

### 1. Host Requirements
* **Operating System**: Linux (Ubuntu, Debian, Fedora, Arch, etc.) or macOS with Docker Desktop.
* **Docker Engine** (or Docker Desktop): Used to spin up the containerized Talos nodes.
  > [!IMPORTANT]
  > **Docker Group Membership**: Your host user account must belong to the `docker` group so that you can run Docker commands without prefixing them with `sudo`.
  > Verify this by running `docker ps` in your terminal. If it returns an error or permission denied, add yourself using:
  > ```bash
  > sudo usermod -aG docker $USER && newgrp docker
  > ```

### 2. Required CLI Binaries
To interact with and manage the cluster, make sure the following commands are available in your `$PATH`:

* **`talosctl` CLI** (v1.13.2+ recommended): The Talos Linux API management utility.
  * *Quick Install (Linux)*:
    ```bash
    curl -sL https://talos.dev/install | sh
    ```
* **`kubectl` CLI**: The Kubernetes standard command-line utility.
  * *Quick Install (Debian/Ubuntu)*:
    ```bash
    sudo apt-get update && sudo apt-get install -y kubectl
    ```
* **`helm` CLI** (v3+): The Kubernetes package manager used to install Cilium.
  * *Quick Install (Binary)*:
    ```bash
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    ```

### 3. Optional (But Highly Recommended) Tools
* **`cilium` CLI**: Used to verify CNI status, run network connectivity tests, and manage Hubble.
  * *Quick Install (Linux)*:
    ```bash
    CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
    curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz
    sudo tar -C /usr/local/bin -xzvf cilium-linux-amd64.tar.gz
    rm cilium-linux-amd64.tar.gz
    ```
* **`hubble` CLI**: Used to observe real-time packet flows and connections on the eBPF datapath.
  * *Quick Install (Linux)*:
    ```bash
    HUBBLE_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/hubble/main/stable.txt)
    curl -L --fail --remote-name-all https://github.com/cilium/hubble/releases/download/${HUBBLE_VERSION}/hubble-linux-amd64.tar.gz
    sudo tar -C /usr/local/bin -xzvf hubble-linux-amd64.tar.gz
    rm hubble-linux-amd64.tar.gz
    ```

> [!NOTE]
> **No Pre-configured Helm Repositories Required**:
> The `bootstrap.sh` script automatically handles adding and updating the Cilium Helm repository (`https://helm.cilium.io/`) during the execution, so you do not need to add it manually beforehand.

---

## 🚀 Quick Start


### 1. Launch the Cluster
Execute the bootstrap script to dynamically resolve IPs, configure configs, and install the CNI:
```bash
./bootstrap.sh
```

### 2. Activate the Environment (Current Terminal Shell)
To route `kubectl` and `talosctl` commands directly to this isolated local sandbox:
```bash
source env.sh
```

### 3. Verify Health
```bash
# Check operating system health across all nodes (controlplane + workers)
talosctl health --control-plane-nodes 10.5.0.2 --worker-nodes 10.5.0.3,10.5.0.4

# Check Kubernetes node statuses
kubectl get nodes -o wide

# Check CNI & eBPF load-balancer status
kubectl -n kube-system exec -it ds/cilium -- cilium status
```

> [!TIP]
> **Why does bare `talosctl health` show "unexpected nodes"?**
> By default, `talosconfig` is configured to target only the controlplane node (`10.5.0.2`) for host-level commands. Running bare `talosctl health` only monitors the controlplane node. When it queries Kubernetes and detects the worker nodes (`10.5.0.3` and `10.5.0.4`) running, it flags them as "unexpected" because it doesn't have them in its target list. Specifying `--control-plane-nodes` and `--worker-nodes` explicitly directs `talosctl` to monitor and verify all nodes successfully.

---

## 📖 In-Depth Operations Guide

For a full list of "nice to know" beginner cheat sheets covering interactive node dashboards, advanced Hubble traffic flow filters, network debugging, and troubleshooting workflows, open the local operations guide:
👉 **[USAGE.md](USAGE.md)**

---

## 🧹 Clean Up
To remove all traces of this cluster, clear the Docker networks, and wipe out credentials from your host:
```bash
./teardown.sh
```
