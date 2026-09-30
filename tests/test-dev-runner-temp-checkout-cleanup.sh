#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${TEST_DIR}/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

FAKE_INFRA="${TMP_DIR}/productive-k3s-infra"
FAKE_PROFILES="${TMP_DIR}/productive-k3s-profiles"
FAKE_CORE="${TMP_DIR}/productive-k3s-core"
FAKE_ADDONS="${TMP_DIR}/productive-k3s-addons"
CAPTURE_FILE="${TMP_DIR}/prepared-checkout.txt"

mkdir -p \
  "${FAKE_INFRA}/scripts" \
  "${FAKE_INFRA}/tests" \
  "${FAKE_INFRA}/ansible" \
  "${FAKE_PROFILES}/profiles" \
  "${FAKE_PROFILES}/scenarios/local/multipass/.terraform" \
  "${FAKE_PROFILES}/docs/.venv" \
  "${FAKE_PROFILES}/docs/site" \
  "${FAKE_PROFILES}/test-artifacts" \
  "${FAKE_CORE}" \
  "${FAKE_ADDONS}"

cp "${REPO_DIR}/scripts/productive-k3s-infra-dev.sh" "${FAKE_INFRA}/scripts/"
cp "${REPO_DIR}/scripts/release-config.sh" "${FAKE_INFRA}/scripts/"
printf 'keep\n' > "${FAKE_PROFILES}/profiles/keep.txt"
printf 'cache\n' > "${FAKE_PROFILES}/scenarios/local/multipass/.terraform/provider"
printf 'cache\n' > "${FAKE_PROFILES}/docs/.venv/python"
printf 'generated\n' > "${FAKE_PROFILES}/docs/site/index.html"
printf 'artifact\n' > "${FAKE_PROFILES}/test-artifacts/result.json"

cat > "${FAKE_INFRA}/tests/run-matrix.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
test -f "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/profiles/keep.txt"
test -f "$(dirname "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}")/.productive-k3s-infra-test-temp"
case "$(basename "$(dirname "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}")")" in
  productive-k3s-infra-profiles.*) ;;
  *) exit 1 ;;
esac
test ! -e "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/scenarios/local/multipass/.terraform"
test ! -e "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/docs/.venv"
test ! -e "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/docs/site"
test ! -e "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}/test-artifacts"
printf '%s\n' "${PRODUCTIVE_K3S_PROFILES_REPO_DIR}" > "${CAPTURE_FILE}"
EOF
chmod +x "${FAKE_INFRA}/scripts/productive-k3s-infra-dev.sh" "${FAKE_INFRA}/tests/run-matrix.sh"

CAPTURE_FILE="${CAPTURE_FILE}" \
PRODUCTIVE_K3S_PROFILES_REPO_DIR="${FAKE_PROFILES}" \
PRODUCTIVE_K3S_REPO="${FAKE_CORE}" \
PRODUCTIVE_K3S_ADDONS_REPO_DIR="${FAKE_ADDONS}" \
  bash "${FAKE_INFRA}/scripts/productive-k3s-infra-dev.sh" test-static

PREPARED_REPO="$(cat "${CAPTURE_FILE}")"
if [[ -e "${PREPARED_REPO}" || -e "$(dirname "${PREPARED_REPO}")" ]]; then
  printf 'temporary profiles checkout was not removed: %s\n' "${PREPARED_REPO}" >&2
  exit 1
fi

printf 'Development runner temporary checkout cleanup tests passed.\n'
