#!/usr/bin/env bash
# Grades the Cilium network policy scenario by testing real connectivity.
set -uo pipefail

PASS=0; FAIL=0
ok()   { printf '  \e[32m✔\e[0m %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  \e[31m✘\e[0m %s\n' "$*"; FAIL=$((FAIL+1)); }
skip() { printf '  \e[33m-\e[0m %s (skipped)\n' "$*"; }
hdr()  { printf '\n\e[1m%s\e[0m\n' "$*"; }

# code <ns> <deploy> <curl args...>  -> prints HTTP status, 000 = dropped/timeout
code() {
  local ns=$1 dep=$2; shift 2
  kubectl -n "$ns" exec "deploy/$dep" -c curl -- \
    curl -sk -o /dev/null -w '%{http_code}' --connect-timeout 3 --max-time 5 "$@" 2>/dev/null || true
}

# expect <desc> <want: 200|403|blocked|reachable> <ns> <deploy> <curl args...>
expect() {
  local desc=$1 want=$2; shift 2
  local got try
  for try in 1 2; do
    got=$(code "$@"); got=${got:-000}
    case $want in
      blocked)   [[ $got == 000 ]] && { ok "$desc"; return; } ;;
      reachable) [[ $got != 000 ]] && { ok "$desc"; return; } ;;
      *)         [[ $got == "$want" ]] && { ok "$desc"; return; } ;;
    esac
  done
  bad "$desc (want $want, got $got)"
}

has() { kubectl get "$@" >/dev/null 2>&1; }

FE=frontend.shop.svc.cluster.local
BE=backend.shop.svc.cluster.local:8080
DB=db.shop.svc.cluster.local:6379

hdr "Task 1 — default-deny-ingress"
has -n shop cnp default-deny-ingress && ok "policy exists" || bad "cnp shop/default-deny-ingress missing"
expect "qa → backend blocked"  blocked qa tester "http://$BE/api/x"
expect "qa → db blocked"       blocked qa tester "http://$DB/"

hdr "Task 2 — frontend-ingress"
has -n shop cnp frontend-ingress && ok "policy exists" || bad "cnp shop/frontend-ingress missing"
expect "qa → frontend:80 allowed" 200 qa tester "http://$FE/"

hdr "Task 3 — db-ingress fixed"
has -n shop cnp db-ingress && ok "policy exists" || bad "cnp shop/db-ingress missing"
expect "backend → db:6379 allowed"  200     shop backend  "http://$DB/"
expect "frontend → db:6379 blocked" blocked shop frontend "http://$DB/"
n=$(kubectl -n shop get cnp -o json 2>/dev/null \
    | grep -c '"app": "db"' || true)
[[ $n -le 1 ]] && ok "no extra policy selects app=db" || bad "more than one policy mentions app=db; fix db-ingress rather than adding a new one"

hdr "Task 4 — backend-l7"
has -n shop cnp backend-l7 && ok "policy exists" || bad "cnp shop/backend-l7 missing"
expect "frontend GET /api/products → 200"  200 shop frontend "http://$BE/api/products"
expect "frontend GET /admin → 403"         403 shop frontend "http://$BE/admin"
expect "frontend POST /api/products → 403" 403 shop frontend -X POST "http://$BE/api/products"

hdr "Task 5 — deny-untrusted (CCNP)"
if has ccnp deny-untrusted; then
  ok "ccnp exists"
  kubectl get ccnp deny-untrusted -o jsonpath='{.spec.ingressDeny}{.spec.egressDeny}' | grep -q . \
    && ok "uses a deny rule" || bad "ccnp has no ingressDeny/egressDeny"
else
  bad "ccnp deny-untrusted missing"
fi
expect "untrusted → frontend:80 blocked" blocked untrusted attacker "http://$FE/"
expect "qa → frontend:80 still allowed"  200     qa        tester   "http://$FE/"

hdr "Task 6 — frontend-egress"
has -n shop cnp frontend-egress && ok "policy exists" || bad "cnp shop/frontend-egress missing"
expect "frontend → backend still works (DNS + 8080)" 200     shop frontend "http://$BE/api/ok"
expect "frontend → kube-apiserver blocked"           blocked shop frontend "https://kubernetes.default.svc/healthz"
expect "qa → kube-apiserver reachable (control)"     reachable qa tester   "https://kubernetes.default.svc/healthz"
if [[ $(code qa tester https://kubernetes.io) != 000 ]]; then
  expect "frontend → https://kubernetes.io allowed" reachable shop frontend https://kubernetes.io
  expect "frontend → https://example.com blocked"   blocked   shop frontend https://example.com
else
  skip "FQDN checks (cluster has no internet egress)"
fi

hdr "Result: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
