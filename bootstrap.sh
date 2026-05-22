#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="talos-demo"
KUBERNETES_VERSION="1.36.0"
CILIUM_VERSION="1.19.4"

# Ensure the local state directory exists
mkdir -p state

# Set the TALOSCONFIG and KUBECONFIG environment variables early to fully isolate
# all configuration operations from the user's home directories.
export TALOSCONFIG="$(pwd)/state/talosconfig"
export KUBECONFIG="$(pwd)/kubeconfig"

echo "=== 1. Cleaning up any existing cluster named ${CLUSTER_NAME} ==="
talosctl cluster destroy --name "${CLUSTER_NAME}" --state "$(pwd)/state" || true
rm -rf state kubeconfig
mkdir -p state

echo "=== 2. Generating and applying Talos configs to boot local cluster ==="
# We use 'create docker' to run nodes inside lightweight Docker containers.
# We use --state and --talosconfig-destination to isolate all configs inside the workspace.
# Because KUBECONFIG is exported early, the kubeconfig will be written directly to ./kubeconfig.
talosctl cluster create docker \
  --name "${CLUSTER_NAME}" \
  --workers 2 \
  --kubernetes-version "${KUBERNETES_VERSION}" \
  --config-patch-controlplanes @talosconfig-patch-controlplane.yaml \
  --config-patch-workers @talosconfig-patch-worker.yaml \
  --state "$(pwd)/state" \
  --talosconfig-destination "${TALOSCONFIG}"

echo "=== 3. Exporting isolated kubeconfig ==="
echo "Kubeconfig written directly to: $(pwd)/kubeconfig (highly isolated)"



echo "=== 4. Dynamically discovering Control Plane container IP ==="
# Under the Docker provisioner, nodes run as containers. We extract the internal Docker bridge IP.
CONTAINER_NAME="${CLUSTER_NAME}-controlplane-1"
CONTROLPLANE_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTAINER_NAME}")

if [ -z "${CONTROLPLANE_IP}" ]; then
  echo "Error: Could not retrieve Control Plane container IP address!" >&2
  exit 1
fi
echo "Discovered Control Plane IP: ${CONTROLPLANE_IP}"

echo "=== 4b. Setting default target node in talosconfig ==="
talosctl config node "${CONTROLPLANE_IP}"

echo "=== 5. Injecting control plane IP into active Helm values ==="
sed "s/YOUR_CONTROLPLANE_IP/${CONTROLPLANE_IP}/g" cilium-values.yaml > cilium-values-active.yaml
echo "Active Helm values written to: $(pwd)/cilium-values-active.yaml"

echo "=== 6. Installing Cilium via Helm ==="
helm repo add cilium https://helm.cilium.io/
helm repo update
helm upgrade --install cilium cilium/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --values cilium-values-active.yaml

echo "=== 7. Waiting for Cilium DaemonSet to be fully rolled out ==="
kubectl rollout status daemonset/cilium -n kube-system --timeout=5m

echo "=== 8. Confirming CNI is up and running ==="
if command -v cilium >/dev/null 2>&1; then
  echo "Running 'cilium status'..."
  cilium status
else
  echo "Cilium CLI not installed. Displaying Cilium pod status via kubectl:"
  kubectl get pods -n kube-system -l app.kubernetes.io/part-of=cilium -o wide
fi

echo "=== 9. Cluster Node Status ==="
kubectl get nodes -o wide

# Generate env.sh helper script to make environment activation easy
cat <<'EOF' > env.sh
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
export KUBECONFIG="${SCRIPT_DIR}/kubeconfig"
export TALOSCONFIG="${SCRIPT_DIR}/state/talosconfig"
echo "=== Isolated Environment Activated ==="
echo "KUBECONFIG=${KUBECONFIG}"
echo "TALOSCONFIG=${TALOSCONFIG}"
echo "======================================"
EOF
chmod +x env.sh

echo "========================================================="
echo "Bootstrap complete! To activate the environment in this shell:"
echo "  source env.sh"
echo ""
echo "To activate in any new terminal shell:"
echo "  source $(pwd)/env.sh"
echo "========================================================="

