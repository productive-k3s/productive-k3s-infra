#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${TESTS_DIR}/.." && pwd)"
INSTALLER="${TESTS_DIR}/bin/install-kcov.sh"
WORKFLOW="${REPO_DIR}/.github/workflows/pr-validation.yml"
DOCS_WORKFLOW="${REPO_DIR}/.github/workflows/docs.yml"
MATERIALS_LOCK="${REPO_DIR}/materials.lock.yaml"
REMOTE_COMMON="${REPO_DIR}/ansible/roles/remote_cluster/files/common.sh"

grep -Fq 'KCOV_VERSION="43"' "${INSTALLER}"
grep -Fq 'KCOV_SHA256="4cbba86af11f72de0c7514e09d59c7927ed25df7cebdad087f6d3623213b95bf"' "${INSTALLER}"
grep -Fq 'CI_PYTHON_VERSION="3.11.17"' "${INSTALLER}"
grep -Fq "bash productive-k3s-infra/tests/bin/install-kcov.sh" "${WORKFLOW}"
grep -Fq 'python-version: "3.11.17"' "${WORKFLOW}"
grep -Fq 'python-version: "3.11.17"' "${DOCS_WORKFLOW}"
grep -Fq ': "${K3SUP_VERSION:=0.13.13}"' "${REMOTE_COMMON}"
grep -Fq ': "${K3SUP_RELEASE_BASE_URL:=https://github.com/alexellis/k3sup/releases/download}"' "${REMOTE_COMMON}"
grep -Fq ': "${K3SUP_LINUX_AMD64_SHA256:=7f2db0cf4c28d413bc094aa2e1a809bd772875486f385bd57dd2d7575e7c7509}"' "${REMOTE_COMMON}"
grep -Fq ': "${K3SUP_LINUX_ARM64_SHA256:=0d3d5894dda1013943cfbfc443580d973402972ebda36a42365cf8b67aa22ea5}"' "${REMOTE_COMMON}"
grep -Fq ': "${K3SUP_LINUX_ARMHF_SHA256:=c4c5c27ac6c932d35788608e90c34948e5b8836d4391390fd3c19f6d26cf0fcc}"' "${REMOTE_COMMON}"
grep -Fq ': "${K3SUP_DARWIN_AMD64_SHA256:=b7120a217264b5a6465457733599bacb5d8dc55da08362c50c01efcf641d297a}"' "${REMOTE_COMMON}"
grep -Fq ': "${K3SUP_DARWIN_ARM64_SHA256:=e25fe8461b296d2f677e8ff1e5ca2380d59acbf75c25e571e1f60b7382262784}"' "${REMOTE_COMMON}"
grep -Fq '    - id: k3sup' "${MATERIALS_LOCK}"
grep -Fq '      version: 0.13.13' "${MATERIALS_LOCK}"
grep -Fq '    - id: python-ci' "${MATERIALS_LOCK}"
grep -Fq '    - id: kcov' "${MATERIALS_LOCK}"
grep -Fq '        source-archive: sha256:4cbba86af11f72de0c7514e09d59c7927ed25df7cebdad087f6d3623213b95bf' "${MATERIALS_LOCK}"
[[ "$(grep -Fc '      distribution: excluded' "${MATERIALS_LOCK}")" -ge 2 ]]

if grep -Fq 'get.k3sup.dev' "${REMOTE_COMMON}"; then
  printf 'Infra must not execute the mutable k3sup installer script.\n' >&2
  exit 1
fi

if grep -Eq 'apt-get install[^[:cntrl:]]*kcov' "${WORKFLOW}"; then
  printf 'The workflow must install kcov through the pinned repository installer.\n' >&2
  exit 1
fi

printf 'pinned tool installer contracts: ok\n'
