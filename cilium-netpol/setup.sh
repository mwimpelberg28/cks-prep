#!/usr/bin/env bash
# Sets up (or resets) the Cilium network policy CKS practice scenario.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACES=(shop untrusted qa)

red()   { printf '\e[31m%s\e[0m\n' "$*"; }
green() { printf '\e[32m%s\e[0m\n' "$*"; }

# ---- preflight -------------------------------------------------------------
if ! kubectl get crd ciliumnetworkpolicies.cilium.io >/dev/null 2>&1 \
   || ! kubectl -n kube-system get ds cilium >/dev/null 2>&1; then
  red "Cilium is not installed in this cluster (CiliumNetworkPolicy CRD / cilium DaemonSet missing)."
  echo "Run ./install-cilium.sh first. Warning: it replaces the existing CNI."
  exit 1
fi
kubectl -n kube-system rollout status ds/cilium --timeout=120s >/dev/null
green "Cilium is running."

# ---- clean previous run ----------------------------------------------------
echo "Removing earlier lab objects..."
kubectl delete ccnp deny-untrusted --ignore-not-found >/dev/null
for ns in "${NAMESPACES[@]}"; do
  kubectl delete ns "$ns" --ignore-not-found --wait=true >/dev/null
done

# ---- deploy ----------------------------------------------------------------
echo "Deploying workloads..."
kubectl apply -f "$DIR/manifests/workloads.yaml" >/dev/null
kubectl apply -f "$DIR/manifests/broken-db-ingress.yaml" >/dev/null

for ns in "${NAMESPACES[@]}"; do
  kubectl -n "$ns" wait --for=condition=Available deploy --all --timeout=180s >/dev/null
done
green "Workloads are ready."

kubectl get pods -n shop -o wide
echo
cat "$DIR/TASKS.md"
