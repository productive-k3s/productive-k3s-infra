#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCENARIO_DIR="${SCENARIO_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
GENERATED_DIR="${SCENARIO_DIR}/generated"
LOG_DIR="${GENERATED_DIR}/logs"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCENARIO_DIR}/../.." && pwd)}"
if [[ -r "${REPO_ROOT}/scripts/release-config.sh" ]]; then
  # shellcheck disable=SC1091
  source "${REPO_ROOT}/scripts/release-config.sh"
else
  : "${PRODUCTIVE_K3S_SOURCE_DEFAULT:=remote}"
  : "${PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:=0.9.1}"
  : "${PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT:=jemacchi/productive-k3s-core}"
fi
PRODUCTIVE_K3S_REPO="${PRODUCTIVE_K3S_REPO:-$(cd "${SCENARIO_DIR}/../../../productive-k3s-core" && pwd)}"
PRODUCTIVE_K3S_SOURCE="${PRODUCTIVE_K3S_SOURCE:-${PRODUCTIVE_K3S_SOURCE_DEFAULT}}"
PRODUCTIVE_K3S_VERSION="${PRODUCTIVE_K3S_VERSION:-}"
if [[ -z "${PRODUCTIVE_K3S_VERSION}" && "${PRODUCTIVE_K3S_SOURCE}" == "remote" ]]; then
  PRODUCTIVE_K3S_VERSION="${PRODUCTIVE_K3S_CORE_VERSION_DEFAULT}"
fi
PRODUCTIVE_K3S_RELEASE_REPO="${PRODUCTIVE_K3S_RELEASE_REPO:-${PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT}}"
TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-}"
TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT:-}"
TELEMETRY_MARKER="${TELEMETRY_MARKER:-pk3s-public-v1}"
TELEMETRY_BEARER_TOKEN="${TELEMETRY_BEARER_TOKEN:-}"
TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES:-3}"
TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS:-5}"
TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS:-10}"
TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR:-}"
TELEMETRY_USER_AGENT="${TELEMETRY_USER_AGENT:-productive-k3s-infra/onprem-basic}"
TELEMETRY_SESSION_ID="${TELEMETRY_SESSION_ID:-}"
TELEMETRY_PARENT_RUN_ID="${TELEMETRY_PARENT_RUN_ID:-}"
TELEMETRY_COMPONENT="${TELEMETRY_COMPONENT:-infra}"
ONPREM_CLUSTER_NAME="${ONPREM_CLUSTER_NAME:-productive-k3s-onprem}"
ONPREM_BASE_DOMAIN="${ONPREM_BASE_DOMAIN:-k3s.lab.internal}"
ONPREM_RANCHER_HOST="${ONPREM_RANCHER_HOST:-rancher.${ONPREM_BASE_DOMAIN}}"
ONPREM_REGISTRY_HOST="${ONPREM_REGISTRY_HOST:-registry.${ONPREM_BASE_DOMAIN}}"
ONPREM_SERVER_IP="${ONPREM_SERVER_IP:-}"
ONPREM_AGENT_IPS="${ONPREM_AGENT_IPS:-}"
ONPREM_SSH_USER="${ONPREM_SSH_USER:-ubuntu}"
ONPREM_SSH_PORT="${ONPREM_SSH_PORT:-22}"
ONPREM_SSH_KEY_PATH="${ONPREM_SSH_KEY_PATH:-}"
ONPREM_SSH_EXTRA_OPTS="${ONPREM_SSH_EXTRA_OPTS:-}"
ONPREM_REMOTE_DIR="${ONPREM_REMOTE_DIR:-}"
CLUSTER_JSON="${GENERATED_DIR}/cluster.json"
HOSTS_YML="${GENERATED_DIR}/hosts.yml"
NODES_ENV="${GENERATED_DIR}/nodes.env"
SERVER_TOKEN_FILE="${GENERATED_DIR}/server-token.txt"
SERVER_URL_FILE="${GENERATED_DIR}/server-url.txt"

SUPPORTED_PLATFORMS=(
  "ubuntu:24.04"
  "ubuntu:22.04"
  "debian:13"
  "debian:12"
)

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
  need_cmd jq
  need_cmd tar
  need_cmd curl
  need_cmd sha256sum
  need_cmd ssh
  need_cmd scp
  need_cmd python3
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

validate_productive_k3s_bundle_archive() {
  local archive="$1"
  local prefix listing
  local required=(
    "bundle-info.json"
    "productive-k3s-core.sh"
    "scripts/productive-k3s-core.sh"
    "scripts/preflight-host.sh"
    "scripts/bootstrap-k3s-stack.sh"
    "scripts/backup-k3s-stack.sh"
    "scripts/validate-k3s-stack.sh"
    "scripts/send-telemetry.sh"
  )

  listing="$(tar -tzf "${archive}")"
  prefix="$(printf '%s\n' "${listing}" | head -n 1 | cut -d/ -f1)"
  [[ -n "${prefix}" ]] || {
    err "could not determine extracted directory from remote archive ${archive}"
    exit 1
  }

  local rel
  for rel in "${required[@]}"; do
    printf '%s\n' "${listing}" | grep -Fx "${prefix}/${rel}" >/dev/null || {
      err "productive-k3s-core remote bundle is incomplete; missing ${rel} in ${archive}"
      exit 1
    }
  done
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

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

parse_agent_ips() {
  local raw
  raw="$(trim "${ONPREM_AGENT_IPS}")"
  AGENT_IPS_ARRAY=()
  if [[ -n "${raw}" ]]; then
    read -r -a AGENT_IPS_ARRAY <<< "${raw}"
  fi
}

require_node_inputs() {
  ONPREM_SERVER_IP="$(trim "${ONPREM_SERVER_IP}")"
  [[ -n "${ONPREM_SERVER_IP}" ]] || {
    err "ONPREM_SERVER_IP is required"
    exit 1
  }
  parse_agent_ips
  local seen="${ONPREM_SERVER_IP}"
  for agent_ip in "${AGENT_IPS_ARRAY[@]}"; do
    [[ -n "${agent_ip}" ]] || continue
    if [[ " ${seen} " == *" ${agent_ip} "* ]]; then
      err "duplicate IP detected in ONPREM_AGENT_IPS: ${agent_ip}"
      exit 1
    fi
    seen+=" ${agent_ip}"
  done
}

ssh_base_args() {
  local args=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=10
    -p "${ONPREM_SSH_PORT}"
  )
  if [[ -n "${ONPREM_SSH_KEY_PATH}" ]]; then
    args+=(-i "${ONPREM_SSH_KEY_PATH}")
  fi
  if [[ -n "${ONPREM_SSH_EXTRA_OPTS}" ]]; then
    local extra=()
    read -r -a extra <<< "${ONPREM_SSH_EXTRA_OPTS}"
    args+=("${extra[@]}")
  fi
  printf '%s\0' "${args[@]}"
}

ssh_args_array() {
  local -n __out_ref="$1"
  __out_ref=()
  while IFS= read -r -d '' arg; do
    __out_ref+=("${arg}")
  done < <(ssh_base_args)
}

ssh_target() {
  local ip="$1"
  printf '%s@%s' "${ONPREM_SSH_USER}" "${ip}"
}

remote_exec() {
  local ip="$1"
  local script="$2"
  local ssh_args=()
  ssh_args_array ssh_args
  ssh "${ssh_args[@]}" "$(ssh_target "${ip}")" "bash -lc $(printf '%q' "${script}")"
}

remote_exec_tty() {
  local ip="$1"
  local script="$2"
  local ssh_args=()
  ssh_args_array ssh_args
  ssh -tt "${ssh_args[@]}" "$(ssh_target "${ip}")" "bash -lc $(printf '%q' "${script}")"
}

scp_to() {
  local source="$1"
  local ip="$2"
  local destination="$3"
  local scp_args=(
    -o BatchMode=yes
    -o StrictHostKeyChecking=accept-new
    -o ConnectTimeout=10
    -P "${ONPREM_SSH_PORT}"
  )
  if [[ -n "${ONPREM_SSH_KEY_PATH}" ]]; then
    scp_args+=(-i "${ONPREM_SSH_KEY_PATH}")
  fi
  if [[ -n "${ONPREM_SSH_EXTRA_OPTS}" ]]; then
    local extra=()
    read -r -a extra <<< "${ONPREM_SSH_EXTRA_OPTS}"
    scp_args+=("${extra[@]}")
  fi
  scp "${scp_args[@]}" "${source}" "$(ssh_target "${ip}"):${destination}"
}

is_supported_platform() {
  local platform="$1"
  local candidate
  for candidate in "${SUPPORTED_PLATFORMS[@]}"; do
    [[ "${candidate}" == "${platform}" ]] && return 0
  done
  return 1
}

remote_platform() {
  local ip="$1"
  remote_exec "${ip}" 'source /etc/os-release && printf "%s:%s\n" "${ID}" "${VERSION_ID}"'
}

remote_home_dir() {
  local ip="$1"
  remote_exec "${ip}" 'printf "%s" "$HOME"'
}

resolve_hosts_entry_ip() {
  local host_target="$1"
  local resolved_ip=""

  if [[ "${host_target}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "${host_target}" == *:* ]]; then
    printf '%s\n' "${host_target}"
    return 0
  fi

  resolved_ip="$(getent ahostsv4 "${host_target}" 2>/dev/null | awk 'NR == 1 { print $1; exit }')"
  resolved_ip="$(trim "${resolved_ip}")"
  if [[ -n "${resolved_ip}" ]]; then
    printf '%s\n' "${resolved_ip}"
    return 0
  fi

  resolved_ip="$(remote_exec "${host_target}" "hostname -I 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if (\$i ~ /^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$/) {print \$i; exit}}'")"
  resolved_ip="$(trim "${resolved_ip}")"
  if [[ -n "${resolved_ip}" ]]; then
    printf '%s\n' "${resolved_ip}"
    return 0
  fi

  err "could not resolve an IPv4 address for host alias target '${host_target}'"
  exit 1
}

ensure_local_k3sup() {
  if command -v k3sup >/dev/null 2>&1; then
    K3SUP_BIN="$(command -v k3sup)"
    return 0
  fi

  local tmp_dir=""
  tmp_dir="$(mktemp -d)"
  log "Installing k3sup on the controller..."
  (
    cd "${tmp_dir}"
    curl -sLS https://get.k3sup.dev | sh
  )
  if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
    sudo install "${tmp_dir}/k3sup" /usr/local/bin/k3sup
    K3SUP_BIN="/usr/local/bin/k3sup"
  else
    mkdir -p "${HOME}/.local/bin"
    install "${tmp_dir}/k3sup" "${HOME}/.local/bin/k3sup"
    export PATH="${HOME}/.local/bin:${PATH}"
    K3SUP_BIN="${HOME}/.local/bin/k3sup"
  fi
  rm -rf "${tmp_dir}"
}

k3sup_controller_join_agent() {
  local agent_ip="$1"
  local server_ip="$2"
  local server_user="$3"
  local cmd=()

  [[ -n "${agent_ip}" ]] || {
    err "agent IP is required for controller-side k3sup join"
    exit 1
  }
  [[ -n "${server_ip}" ]] || {
    err "server IP is required for controller-side k3sup join"
    exit 1
  }
  [[ -n "${server_user}" ]] || {
    err "server SSH user is required for controller-side k3sup join"
    exit 1
  }

  ensure_local_k3sup
  cmd=(
    "${K3SUP_BIN}"
    join
    --ip "${agent_ip}"
    --user "${ONPREM_SSH_USER}"
    --server-ip "${server_ip}"
    --server-user "${server_user}"
    --k3s-channel stable
  )
  if [[ -n "${ONPREM_SSH_KEY_PATH}" ]]; then
    cmd+=(--ssh-key "${ONPREM_SSH_KEY_PATH}")
  fi
  if [[ -n "${ONPREM_SSH_PORT}" ]]; then
    cmd+=(--ssh-port "${ONPREM_SSH_PORT}")
  fi

  log "Joining ${agent_ip} to ${server_ip} with controller-side k3sup..."
  "${cmd[@]}"
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
  local release_json archive_name sha_name archive_url sha_url expected_sha

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
  validate_productive_k3s_bundle_archive "${destination}"
}

load_cluster_metadata() {
  [[ -f "${CLUSTER_JSON}" ]] || {
    err "missing ${CLUSTER_JSON}; run 'make preflight' first"
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
  SSH_USER_RESOLVED="$(jq -r '.ssh.user' "${CLUSTER_JSON}")"
  SSH_PORT_RESOLVED="$(jq -r '.ssh.port' "${CLUSTER_JSON}")"
  ONPREM_SSH_USER="${SSH_USER_RESOLVED}"
  ONPREM_SSH_PORT="${SSH_PORT_RESOLVED}"
  mapfile -t AGENT_NAMES < <(jq -r '.agents[].name' "${CLUSTER_JSON}")
  mapfile -t AGENT_IPS < <(jq -r '.agents[].ipv4' "${CLUSTER_JSON}")
  mapfile -t ALL_NODE_NAMES < <(jq -r '.nodes[].name' "${CLUSTER_JSON}")
  mapfile -t ALL_NODE_IPS < <(jq -r '.nodes[].ipv4' "${CLUSTER_JSON}")
}

export_resolved_telemetry_env() {
  export TELEMETRY_ENABLED="${TELEMETRY_ENABLED_RESOLVED}"
  export TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT_RESOLVED}"
  export TELEMETRY_BEARER_TOKEN="${TELEMETRY_BEARER_TOKEN:-}"
  export TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES_RESOLVED}"
  export TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS_RESOLVED}"
  export TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS_RESOLVED}"
  export TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR_RESOLVED}"
  export TELEMETRY_USER_AGENT="${TELEMETRY_USER_AGENT_RESOLVED}"
}

write_hosts_entry_on_node() {
  local node_ip="$1"
  local server_ip="$2"
  local rancher_host="$3"
  local registry_host="$4"
  local escaped_line
  escaped_line="${server_ip} ${rancher_host} ${registry_host}"
  remote_exec "${node_ip}" "
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
