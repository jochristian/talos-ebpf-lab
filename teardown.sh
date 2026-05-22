#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="talos-demo"

echo "=== 1. Destroying Talos cluster: ${CLUSTER_NAME} ==="
talosctl cluster destroy --name "${CLUSTER_NAME}" --state "$(pwd)/state"

echo "=== 2. Cleaning up local generated state files ==="
rm -f kubeconfig
rm -f cilium-values-active.yaml
rm -f env.sh
rm -rf state



echo "========================================================="
echo "Teardown complete! All local state has been cleaned up."
echo "========================================================="
