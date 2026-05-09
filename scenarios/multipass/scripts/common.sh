#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO_DIR="${SCENARIO_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
GENERATED_DIR="${SCENARIO_DIR}/generated"
OPENTOFU_DIR="${SCENARIO_DIR}/opentofu"
LOG_DIR="${GENERATED_DIR}/logs"
REPO_ROOT="$(cd "${SCENARIO_DIR}/../.." && pwd)"
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/release-config.sh"
PRODUCTIVE_K3S_REPO="${PRODUCTIVE_K3S_REPO:-$(cd "${SCENARIO_DIR}/../../../productive-k3s-core" && pwd)}"
PRODUCTIVE_K3S_SOURCE="${PRODUCTIVE_K3S_SOURCE:-${PRODUCTIVE_K3S_SOURCE_DEFAULT}}"
PRODUCTIVE_K3S_VERSION="${PRODUCTIVE_K3S_VERSION:-}"
if [[ -z "${PRODUCTIVE_K3S_VERSION}" && "${PRODUCTIVE_K3S_SOURCE}" == "remote" ]]; then
  PRODUCTIVE_K3S_VERSION="${PRODUCTIVE_K3S_CORE_VERSION_DEFAULT}"
fi
PRODUCTIVE_K3S_RELEASE_REPO="${PRODUCTIVE_K3S_RELEASE_REPO:-${PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT}}"
TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-}"
TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT:-}"
TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES:-3}"
TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS:-5}"
TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS:-10}"
TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR:-}"
TELEMETRY_USER_AGENT="${TELEMETRY_USER_AGENT:-productive-k3s-infra/multipass}"
TOFU_BIN="${TOFU_BIN:-}"
DEFAULT_REMOTE_DIR="/home/ubuntu/productive-k3s-core"
CLUSTER_JSON="${GENERATED_DIR}/cluster.json"
HOSTS_YML="${GENERATED_DIR}/hosts.yml"
NODES_ENV="${GENERATED_DIR}/nodes.env"
SERVER_TOKEN_FILE="${GENERATED_DIR}/server-token.txt"
SERVER_URL_FILE="${GENERATED_DIR}/server-url.txt"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

err() {
  printf '[ERROR] %s\n' "$*" >&2
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    err "required command not found: $1"
    exit 1
  }
}

ensure_base_requirements() {
  need_cmd multipass
  need_cmd jq
  need_cmd tar
  need_cmd curl
  need_cmd sha256sum
}

ensure_logs_dir() {
  mkdir -p "${LOG_DIR}"
}

can_use_tty() {
  [[ -t 0 && -t 1 && -r /dev/tty && -w /dev/tty ]]
}

prompt_yesno() {
  local var="$1" default="$2" msg="$3"
  local val
  if can_use_tty; then
    printf '%s [%s] (y/n): ' "${msg}" "${default}" > /dev/tty
    IFS= read -r val < /dev/tty
  else
    printf '%s [%s] (y/n): ' "${msg}" "${default}"
    IFS= read -r val
  fi
  val="${val:-$default}"
  case "${val}" in
    y|Y) printf -v "${var}" 'y' ;;
    n|N) printf -v "${var}" 'n' ;;
    *) warn "Invalid input, using default: ${default}"; printf -v "${var}" '%s' "${default}" ;;
  esac
}

resolve_telemetry_enabled() {
  if [[ -n "${TELEMETRY_ENABLED:-}" ]]; then
    return 0
  fi

  if can_use_tty; then
    local telemetry_consent="y"
    prompt_yesno telemetry_consent "y" "Productive K3S Infra can send anonymous telemetry about this scenario run to help improve the installation flow. It does not include any sensitive information like hostnames or other environment-specific identifiers. If enabled, this choice will also be propagated to the underlying productive-k3s bootstrap steps. Enable anonymous telemetry for this run?"
    if [[ "${telemetry_consent}" == "y" ]]; then
      TELEMETRY_ENABLED="true"
    else
      TELEMETRY_ENABLED="false"
    fi
    return 0
  fi

  TELEMETRY_ENABLED="false"
}

detect_tofu_bin() {
  if [[ -n "${TOFU_BIN}" ]]; then
    printf '%s' "${TOFU_BIN}"
    return
  fi
  if command -v tofu >/dev/null 2>&1; then
    printf 'tofu'
    return
  fi
  if command -v terraform >/dev/null 2>&1; then
    printf 'terraform'
    return
  fi
  err "tofu or terraform is required"
  exit 1
}

multipass_instance_exists() {
  local name="$1"
  multipass info "${name}" >/dev/null 2>&1
}

multipass_ipv4() {
  local name="$1"
  multipass info --format json "${name}" | jq -r --arg name "${name}" '
    .info[$name].ipv4[0] // empty
  '
}

multipass_state() {
  local name="$1"
  multipass info --format json "${name}" | jq -r --arg name "${name}" '
    .info[$name].state // empty
  '
}

load_cluster_metadata() {
  [[ -f "${CLUSTER_JSON}" ]] || {
    err "missing ${CLUSTER_JSON}; run 'make infra-up' first"
    exit 1
  }
  SERVER_NAME="$(jq -r '.server.name' "${CLUSTER_JSON}")"
  SERVER_IP="$(jq -r '.server.ipv4' "${CLUSTER_JSON}")"
  SERVER_URL="$(jq -r '.server_url' "${CLUSTER_JSON}")"
  BASE_DOMAIN="$(jq -r '.base_domain' "${CLUSTER_JSON}")"
  RANCHER_HOST="$(jq -r '.rancher_host' "${CLUSTER_JSON}")"
  REGISTRY_HOST="$(jq -r '.registry_host' "${CLUSTER_JSON}")"
  REMOTE_DIR="$(jq -r '.remote_dir' "${CLUSTER_JSON}")"
  PRODUCTIVE_K3S_SOURCE_RESOLVED="$(jq -r '.productive_k3s.source' "${CLUSTER_JSON}")"
  PRODUCTIVE_K3S_VERSION_RESOLVED="$(jq -r '.productive_k3s.version' "${CLUSTER_JSON}")"
  PRODUCTIVE_K3S_RELEASE_REPO_RESOLVED="$(jq -r '.productive_k3s.release_repo' "${CLUSTER_JSON}")"
  TELEMETRY_ENABLED_RESOLVED="$(jq -r '.telemetry.enabled // false' "${CLUSTER_JSON}")"
  TELEMETRY_ENDPOINT_RESOLVED="$(jq -r '.telemetry.endpoint // empty' "${CLUSTER_JSON}")"
  TELEMETRY_MAX_RETRIES_RESOLVED="$(jq -r '.telemetry.max_retries // 3' "${CLUSTER_JSON}")"
  TELEMETRY_CONNECT_TIMEOUT_SECONDS_RESOLVED="$(jq -r '.telemetry.connect_timeout_seconds // 5' "${CLUSTER_JSON}")"
  TELEMETRY_REQUEST_TIMEOUT_SECONDS_RESOLVED="$(jq -r '.telemetry.request_timeout_seconds // 10' "${CLUSTER_JSON}")"
  TELEMETRY_OUTBOX_DIR_RESOLVED="$(jq -r '.telemetry.outbox_dir // empty' "${CLUSTER_JSON}")"
  TELEMETRY_USER_AGENT_RESOLVED="$(jq -r '.telemetry.user_agent // empty' "${CLUSTER_JSON}")"
  mapfile -t AGENT_NAMES < <(jq -r '.agents[].name' "${CLUSTER_JSON}")
  mapfile -t ALL_NODE_NAMES < <(jq -r '.nodes[].name' "${CLUSTER_JSON}")
}

export_resolved_telemetry_env() {
  export TELEMETRY_ENABLED="${TELEMETRY_ENABLED_RESOLVED}"
  export TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT_RESOLVED}"
  export TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES_RESOLVED}"
  export TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS_RESOLVED}"
  export TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS_RESOLVED}"
  export TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR_RESOLVED}"
  export TELEMETRY_USER_AGENT="${TELEMETRY_USER_AGENT_RESOLVED}"
}

export_resolved_cluster_config_env() {
  export PRODUCTIVE_K3S_SOURCE="${PRODUCTIVE_K3S_SOURCE_RESOLVED}"
  export PRODUCTIVE_K3S_VERSION="${PRODUCTIVE_K3S_VERSION_RESOLVED}"
  export PRODUCTIVE_K3S_RELEASE_REPO="${PRODUCTIVE_K3S_RELEASE_REPO_RESOLVED}"
  export_resolved_telemetry_env
}

validate_productive_k3s_source() {
  case "${PRODUCTIVE_K3S_SOURCE}" in
    local|remote) ;;
    *)
      err "PRODUCTIVE_K3S_SOURCE must be 'local' or 'remote', got '${PRODUCTIVE_K3S_SOURCE}'"
      exit 1
      ;;
  esac
}

normalize_release_version() {
  local version="$1"
  printf '%s\n' "${version#v}"
}

productive_k3s_release_json() {
  local version="$1"
  local release_json=""
  if [[ -n "${version}" ]]; then
    if release_json="$(curl -fsSL "$(productive_k3s_release_api_url "${version}")" 2>/dev/null)"; then
      printf '%s\n' "${release_json}"
      return 0
    fi
    if [[ "${version}" != v* ]]; then
      release_json="$(curl -fsSL "$(productive_k3s_release_api_url "v${version}")")"
      printf '%s\n' "${release_json}"
      return 0
    fi
    return 1
  fi

  release_json="$(curl -fsSL "$(productive_k3s_release_api_url "")")"
  printf '%s\n' "${release_json}"
}

productive_k3s_release_api_url() {
  local version="$1"
  if [[ -n "${version}" ]]; then
    printf 'https://api.github.com/repos/%s/releases/tags/%s\n' "${PRODUCTIVE_K3S_RELEASE_REPO}" "${version}"
  else
    printf 'https://api.github.com/repos/%s/releases/latest\n' "${PRODUCTIVE_K3S_RELEASE_REPO}"
  fi
}

resolve_productive_k3s_release_tag() {
  validate_productive_k3s_source
  if [[ "${PRODUCTIVE_K3S_SOURCE}" != "remote" ]]; then
    printf 'local\n'
    return
  fi
  if [[ -n "${PRODUCTIVE_K3S_VERSION}" ]]; then
    normalize_release_version "${PRODUCTIVE_K3S_VERSION}"
    return
  fi
  productive_k3s_release_json "" | jq -r '.tag_name' | sed 's/^v//'
}

download_productive_k3s_release_bundle() {
  local destination="$1"
  local version="$2"
  local release_json archive_name sha_name archive_url sha_url

  version="$(normalize_release_version "${version}")"
  release_json="$(productive_k3s_release_json "${version}")"
  archive_name="productive-k3s-core-${version}.tar.gz"
  sha_name="${archive_name}.sha256"
  archive_url="$(printf '%s' "${release_json}" | jq -r --arg name "${archive_name}" '.assets[] | select(.name == $name) | .browser_download_url')"
  sha_url="$(printf '%s' "${release_json}" | jq -r --arg name "${sha_name}" '.assets[] | select(.name == $name) | .browser_download_url')"

  [[ -n "${archive_url}" && "${archive_url}" != "null" ]] || {
    err "could not find asset '${archive_name}' in release '${version}' from ${PRODUCTIVE_K3S_RELEASE_REPO}"
    exit 1
  }
  [[ -n "${sha_url}" && "${sha_url}" != "null" ]] || {
    err "could not find asset '${sha_name}' in release '${version}' from ${PRODUCTIVE_K3S_RELEASE_REPO}"
    exit 1
  }

  log "Downloading productive-k3s-core release ${version} from ${PRODUCTIVE_K3S_RELEASE_REPO}"
  curl -fsSL "${archive_url}" -o "${destination}"
  curl -fsSL "${sha_url}" -o "${destination}.sha256"
  expected_sha="$(cut -d' ' -f1 < "${destination}.sha256")"
  printf '%s  %s\n' "${expected_sha}" "${destination}" | sha256sum -c -
}

mp_exec() {
  local name="$1"
  shift
  multipass exec "${name}" -- bash -lc "$*"
}

mp_transfer_to() {
  local source="$1"
  local target_instance="$2"
  local target_path="$3"
  multipass transfer "${source}" "${target_instance}:${target_path}"
}

write_hosts_entry_on_node() {
  local node="$1" ip="$2" rancher_host="$3" registry_host="$4"
  local escaped_line
  escaped_line="${ip} ${rancher_host} ${registry_host}"
  mp_exec "${node}" "
    set -euo pipefail
    if grep -qE '[[:space:]]${rancher_host}([[:space:]]|\$)' /etc/hosts 2>/dev/null; then
      sudo sed -i '/[[:space:]]${rancher_host}\([[:space:]]\|\$\)/d' /etc/hosts
    fi
    if grep -qE '[[:space:]]${registry_host}([[:space:]]|\$)' /etc/hosts 2>/dev/null; then
      sudo sed -i '/[[:space:]]${registry_host}\([[:space:]]\|\$\)/d' /etc/hosts
    fi
    printf '%s\n' '${escaped_line}' | sudo tee -a /etc/hosts >/dev/null
  "
}
