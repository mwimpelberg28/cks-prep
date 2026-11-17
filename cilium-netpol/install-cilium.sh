#!/usr/bin/env bash
# Replaces the cluster's existing CNI (Canal/Calico/Flannel) with Cilium.
# THIS IS DISRUPTIVE: pod networking goes down until Cilium is up and pods are restarted.
#
#   CILIUM_VERSION=1.18.4 ./install-cilium.sh   # optional pin; default = latest chart
set -euo pipefail

echo "This removes the existing CNI and installs Cilium on context: $(kubectl config current-context)"
read -rp "Type 'yes' to continue: " ans
[[ $ans == yes ]] || { echo "Aborted."; exit 1; }

# ---- 1. remove the old CNI -------------------------------------------------
echo "Removing existing CNI components..."
kubectl -n kube-system delete ds canal calico-node kube-flannel-ds --ignore-not-found
kubectl -n kube-flannel delete ds kube-flannel-ds --ignore-not-found 2>/dev/null || true
kubectl -n kube-system delete deploy calico-kube-controllers --ignore-not-found

# ---- 2. install Cilium -----------------------------------------------------
helm repo add cilium https://helm.cilium.io >/dev/null 2>&1 || true
helm repo update cilium >/dev/null
VERSION_FLAG=()
[[ -n ${CILIUM_VERSION:-} ]] && VERSION_FLAG=(--version "$CILIUM_VERSION")

# - ipam=kubernetes reuses the node podCIDRs that kube-controller-manager already allocated
# - cni.exclusive (default true) makes the agent move other CNI configs out of /etc/cni/net.d
# - kube-proxy stays in place (kubeProxyReplacement=false)
helm upgrade --install cilium cilium/cilium -n kube-system "${VERSION_FLAG[@]}" \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=false \
  --set cni.exclusive=true \
  --set operator.replicas=1

kubectl -n kube-system rollout status ds/cilium --timeout=300s
kubectl -n kube-system rollout status deploy/cilium-operator --timeout=300s

# ---- 3. restart every non-hostNetwork pod so Cilium manages it -------------
echo "Restarting pods that don't use host networking..."
kubectl get pods -A -o jsonpath='{range .items[?(@.spec.hostNetwork!=true)]}{.metadata.namespace}{" "}{.metadata.name}{"\n"}{end}' \
  | while read -r ns pod; do
      kubectl -n "$ns" delete pod "$pod" --wait=false >/dev/null
    done

kubectl -n kube-system rollout status deploy/coredns --timeout=180s

cat <<'EOF'

Cilium is installed.

Calico's iptables rules can stay on the nodes. If pod traffic acts strangely,
drain and reboot each node one at a time (or flush the cali-* chains).
Then run: ./setup.sh
EOF
