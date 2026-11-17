#!/usr/bin/env bash
# Removes all lab objects.
set -euo pipefail
kubectl delete ccnp deny-untrusted --ignore-not-found
kubectl delete ns shop untrusted qa --ignore-not-found
