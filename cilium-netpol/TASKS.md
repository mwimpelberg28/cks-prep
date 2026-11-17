# CKS Practice - Cilium Network Policies

Context: `kubectl config use-context kubernetes-admin@kubernetes`

Namespaces: `shop` (frontend, backend, db), `untrusted` (attacker), `qa` (tester).
Every client pod has a container named `curl`, e.g.

    kubectl -n shop exec deploy/frontend -c curl -- curl -s backend:8080/api/x

Use **Cilium** policies (`cilium.io/v2`), not `networking.k8s.io/v1` NetworkPolicies.
Docs allowed: https://docs.cilium.io

---

## Task 1 - Default deny (weight 4%)
Create a `CiliumNetworkPolicy` named **`default-deny-ingress`** in namespace `shop`
that denies **all ingress** traffic to **all pods** in the namespace.

## Task 2 - Public frontend (weight 4%)
Create a `CiliumNetworkPolicy` named **`frontend-ingress`** in `shop` that allows pods
with label `app=frontend` to receive traffic on **TCP 80** from **any pod in the cluster**.

## Task 3 - Fix a broken policy (weight 4%)
The `backend` pods can't reach the `db` pods on TCP 6379. An existing policy
**`db-ingress`** in `shop` is meant to allow this. **Fix it**. Don't create a new policy.
Only `app=backend` may reach `db`, and only on TCP 6379.

## Task 4 - Layer 7 (weight 6%)
Create a `CiliumNetworkPolicy` named **`backend-l7`** in `shop` so that `app=backend`
pods accept traffic **only from `app=frontend`** pods on **TCP 8080**, and only
HTTP **GET** requests whose path matches **`/api/.*`**. Cilium has to reject any
other HTTP request (it returns 403).

## Task 5 - Cluster-wide deny (weight 5%)
Pods in namespace `untrusted` must **never** reach any pod in namespace `shop`,
even when another policy allows it (e.g. Task 2).
Create a **`CiliumClusterwideNetworkPolicy`** named **`deny-untrusted`** that uses a
**deny** rule to enforce this.

## Task 6 - Egress lockdown + FQDN (weight 6%)
Create a `CiliumNetworkPolicy` named **`frontend-egress`** in `shop`. Pods with
`app=frontend` may only send egress traffic to:
- kube-dns (`k8s-app=kube-dns` in `kube-system`) on port 53 UDP and TCP
- `app=backend` pods on TCP 8080
- the FQDN **`kubernetes.io`** on TCP 443

All other egress from frontend (including to the kube-apiserver and other internet hosts) must be blocked.

---
Check your work with `./check.sh`. Reset with `./setup.sh`.
