#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

runtime_paths=(
  "${ROOT_DIR}/productive-k3s-infra.sh"
  "${ROOT_DIR}/scripts/productive-k3s-infra.sh"
  "${ROOT_DIR}/scripts/export-runtime.sh"
  "${ROOT_DIR}/scripts/release-config.sh"
  "${ROOT_DIR}/ansible/roles/remote_cluster/files"
)

# Infra may execute a declared profile package, but runtime code must not know
# catalog profile names or application-stack components. The Rancher project
# name is checked separately because upstream k3s/rke2 use /var/lib/rancher.
forbidden='longhorn|cert-manager|registry|nfs|argocd|cloudnative-pg|geoserver|kubent|kyverno|nginx|popeye|trivy-operator|stack-base|aws-single-node|gcp-basic|hetzner-basic|oci-arm|onprem-basic|multipass'
if rg -n -i "${forbidden}" "${runtime_paths[@]}"; then
  printf '[FAIL] Infra runtime contains profile- or stack-specific behavior\n' >&2
  exit 1
fi

if rg -n -i 'rancher' "${runtime_paths[@]}" \
  | rg -v '/var/lib/rancher/(k3s|rke2)|/etc/rancher/(k3s|rke2)' ; then
  printf '[FAIL] Infra runtime contains Rancher add-on-specific behavior\n' >&2
  exit 1
fi

if rg -n 'productive-k3s-addons\.tgz' "${ROOT_DIR}/ansible/roles/remote_cluster/files"; then
  printf '[FAIL] Infra remote runtime must not transfer an Addons source checkout\n' >&2
  exit 1
fi

printf '[PASS] Infra runtime boundaries remain profile- and stack-agnostic\n'
