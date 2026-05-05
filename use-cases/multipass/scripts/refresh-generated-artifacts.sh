#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
validate_productive_k3s_source

mkdir -p "${GENERATED_DIR}"

cluster_name=""
base_domain=""
remote_dir=""
server_name=""
rancher_host=""
registry_host=""
agent_names=()

while (($# > 0)); do
  case "$1" in
    --cluster-name) cluster_name="$2"; shift 2 ;;
    --base-domain) base_domain="$2"; shift 2 ;;
    --remote-dir) remote_dir="$2"; shift 2 ;;
    --server-name) server_name="$2"; shift 2 ;;
    --rancher-host) rancher_host="$2"; shift 2 ;;
    --registry-host) registry_host="$2"; shift 2 ;;
    --agent-name) agent_names+=("$2"); shift 2 ;;
    *)
      err "unknown argument: $1"
      exit 2
      ;;
  esac
done

if [[ -z "${cluster_name}" ]]; then
  TOFU="$(detect_tofu_bin)"
  cluster_name="$(${TOFU} -chdir="${OPENTOFU_DIR}" output -raw cluster_name)"
  base_domain="$(${TOFU} -chdir="${OPENTOFU_DIR}" output -raw base_domain)"
  remote_dir="$(${TOFU} -chdir="${OPENTOFU_DIR}" output -raw remote_dir)"
  server_name="$(${TOFU} -chdir="${OPENTOFU_DIR}" output -raw server_name)"
  rancher_host="$(${TOFU} -chdir="${OPENTOFU_DIR}" output -raw rancher_host)"
  registry_host="$(${TOFU} -chdir="${OPENTOFU_DIR}" output -raw registry_host)"
  mapfile -t agent_names < <(${TOFU} -chdir="${OPENTOFU_DIR}" output -json agent_names | jq -r '.[]')
fi

if [[ -f "${CLUSTER_JSON}" ]]; then
  if [[ -z "${PRODUCTIVE_K3S_VERSION}" ]]; then
    PRODUCTIVE_K3S_VERSION="$(jq -r '.productive_k3s.version // empty' "${CLUSTER_JSON}")"
  fi
  PRODUCTIVE_K3S_SOURCE="${PRODUCTIVE_K3S_SOURCE:-$(jq -r '.productive_k3s.source // empty' "${CLUSTER_JSON}")}"
  PRODUCTIVE_K3S_RELEASE_REPO="${PRODUCTIVE_K3S_RELEASE_REPO:-$(jq -r '.productive_k3s.release_repo // empty' "${CLUSTER_JSON}")}"
  TELEMETRY_ENABLED="${TELEMETRY_ENABLED:-$(jq -r '.telemetry.enabled // false' "${CLUSTER_JSON}")}"
  TELEMETRY_ENDPOINT="${TELEMETRY_ENDPOINT:-$(jq -r '.telemetry.endpoint // empty' "${CLUSTER_JSON}")}"
  TELEMETRY_MAX_RETRIES="${TELEMETRY_MAX_RETRIES:-$(jq -r '.telemetry.max_retries // 3' "${CLUSTER_JSON}")}"
  TELEMETRY_CONNECT_TIMEOUT_SECONDS="${TELEMETRY_CONNECT_TIMEOUT_SECONDS:-$(jq -r '.telemetry.connect_timeout_seconds // 5' "${CLUSTER_JSON}")}"
  TELEMETRY_REQUEST_TIMEOUT_SECONDS="${TELEMETRY_REQUEST_TIMEOUT_SECONDS:-$(jq -r '.telemetry.request_timeout_seconds // 10' "${CLUSTER_JSON}")}"
  TELEMETRY_OUTBOX_DIR="${TELEMETRY_OUTBOX_DIR:-$(jq -r '.telemetry.outbox_dir // empty' "${CLUSTER_JSON}")}"
  TELEMETRY_USER_AGENT="${TELEMETRY_USER_AGENT:-$(jq -r '.telemetry.user_agent // empty' "${CLUSTER_JSON}")}"
fi

resolve_telemetry_enabled

resolved_source="${PRODUCTIVE_K3S_SOURCE}"
resolved_version="${PRODUCTIVE_K3S_VERSION}"
resolved_telemetry_enabled="${TELEMETRY_ENABLED}"
resolved_telemetry_endpoint="${TELEMETRY_ENDPOINT}"
resolved_telemetry_max_retries="${TELEMETRY_MAX_RETRIES}"
resolved_telemetry_connect_timeout_seconds="${TELEMETRY_CONNECT_TIMEOUT_SECONDS}"
resolved_telemetry_request_timeout_seconds="${TELEMETRY_REQUEST_TIMEOUT_SECONDS}"
resolved_telemetry_outbox_dir="${TELEMETRY_OUTBOX_DIR}"
resolved_telemetry_user_agent="${TELEMETRY_USER_AGENT}"
if [[ "${resolved_source}" == "remote" && -z "${resolved_version}" ]]; then
  resolved_version="$(resolve_productive_k3s_release_tag)"
fi

all_names=("${server_name}" "${agent_names[@]}")

server_ip="$(multipass_ipv4 "${server_name}")"
[[ -n "${server_ip}" ]] || {
  err "could not determine server IP for ${server_name}"
  exit 1
}

tmp_json="$(mktemp)"
{
  printf '{\n'
  printf '  "cluster_name": %s,\n' "$(jq -Rn --arg v "${cluster_name}" '$v')"
  printf '  "base_domain": %s,\n' "$(jq -Rn --arg v "${base_domain}" '$v')"
  printf '  "remote_dir": %s,\n' "$(jq -Rn --arg v "${remote_dir}" '$v')"
  printf '  "productive_k3s": {\n'
  printf '    "source": %s,\n' "$(jq -Rn --arg v "${resolved_source}" '$v')"
  printf '    "version": %s,\n' "$(jq -Rn --arg v "${resolved_version}" '$v')"
  printf '    "release_repo": %s\n' "$(jq -Rn --arg v "${PRODUCTIVE_K3S_RELEASE_REPO}" '$v')"
  printf '  },\n'
  printf '  "telemetry": {\n'
  printf '    "enabled": %s,\n' "$(jq -n --arg v "${resolved_telemetry_enabled}" '$v == "true"')"
  printf '    "endpoint": %s,\n' "$(jq -Rn --arg v "${resolved_telemetry_endpoint}" '$v')"
  printf '    "max_retries": %s,\n' "$(jq -n --argjson v "${resolved_telemetry_max_retries}" '$v')"
  printf '    "connect_timeout_seconds": %s,\n' "$(jq -n --argjson v "${resolved_telemetry_connect_timeout_seconds}" '$v')"
  printf '    "request_timeout_seconds": %s,\n' "$(jq -n --argjson v "${resolved_telemetry_request_timeout_seconds}" '$v')"
  printf '    "outbox_dir": %s,\n' "$(jq -Rn --arg v "${resolved_telemetry_outbox_dir}" '$v')"
  printf '    "user_agent": %s\n' "$(jq -Rn --arg v "${resolved_telemetry_user_agent}" '$v')"
  printf '  },\n'
  printf '  "server_url": %s,\n' "$(jq -Rn --arg v "https://${server_ip}:6443" '$v')"
  printf '  "rancher_host": %s,\n' "$(jq -Rn --arg v "${rancher_host}" '$v')"
  printf '  "registry_host": %s,\n' "$(jq -Rn --arg v "${registry_host}" '$v')"
  printf '  "server": {\n'
  printf '    "name": %s,\n' "$(jq -Rn --arg v "${server_name}" '$v')"
  printf '    "ipv4": %s\n' "$(jq -Rn --arg v "${server_ip}" '$v')"
  printf '  },\n'
  printf '  "agents": [\n'
  for i in "${!agent_names[@]}"; do
    agent_name="${agent_names[$i]}"
    agent_ip="$(multipass_ipv4 "${agent_name}")"
    printf '    {"name": %s, "ipv4": %s}' \
      "$(jq -Rn --arg v "${agent_name}" '$v')" \
      "$(jq -Rn --arg v "${agent_ip}" '$v')"
    if (( i + 1 < ${#agent_names[@]} )); then
      printf ','
    fi
    printf '\n'
  done
  printf '  ],\n'
  printf '  "nodes": [\n'
  for i in "${!all_names[@]}"; do
    node_name="${all_names[$i]}"
    node_ip="$(multipass_ipv4 "${node_name}")"
    role="agent"
    [[ "${node_name}" == "${server_name}" ]] && role="server"
    printf '    {"name": %s, "role": %s, "ipv4": %s}' \
      "$(jq -Rn --arg v "${node_name}" '$v')" \
      "$(jq -Rn --arg v "${role}" '$v')" \
      "$(jq -Rn --arg v "${node_ip}" '$v')"
    if (( i + 1 < ${#all_names[@]} )); then
      printf ','
    fi
    printf '\n'
  done
  printf '  ]\n'
  printf '}\n'
} > "${tmp_json}"
mv "${tmp_json}" "${CLUSTER_JSON}"

{
  printf 'all:\n'
  printf '  vars:\n'
  printf '    ansible_user: ubuntu\n'
  printf '    productive_k3s_remote_dir: %s\n' "${remote_dir}"
  printf '    productive_k3s_server_url: %s\n' "https://${server_ip}:6443"
  printf '    productive_k3s_base_domain: %s\n' "${base_domain}"
  printf '    productive_k3s_rancher_host: %s\n' "${rancher_host}"
  printf '    productive_k3s_registry_host: %s\n' "${registry_host}"
  printf '  children:\n'
  printf '    servers:\n'
  printf '      hosts:\n'
  printf '        %s:\n' "${server_name}"
  printf '          ansible_host: %s\n' "${server_ip}"
  printf '    agents:\n'
  printf '      hosts:\n'
  for agent_name in "${agent_names[@]}"; do
    agent_ip="$(multipass_ipv4 "${agent_name}")"
    printf '        %s:\n' "${agent_name}"
    printf '          ansible_host: %s\n' "${agent_ip}"
  done
} > "${HOSTS_YML}"

{
  printf 'CLUSTER_NAME=%q\n' "${cluster_name}"
  printf 'BASE_DOMAIN=%q\n' "${base_domain}"
  printf 'REMOTE_DIR=%q\n' "${remote_dir}"
  printf 'PRODUCTIVE_K3S_SOURCE=%q\n' "${resolved_source}"
  printf 'PRODUCTIVE_K3S_VERSION=%q\n' "${resolved_version}"
  printf 'PRODUCTIVE_K3S_RELEASE_REPO=%q\n' "${PRODUCTIVE_K3S_RELEASE_REPO}"
  printf 'TELEMETRY_ENABLED=%q\n' "${resolved_telemetry_enabled}"
  printf 'TELEMETRY_ENDPOINT=%q\n' "${resolved_telemetry_endpoint}"
  printf 'TELEMETRY_MAX_RETRIES=%q\n' "${resolved_telemetry_max_retries}"
  printf 'TELEMETRY_CONNECT_TIMEOUT_SECONDS=%q\n' "${resolved_telemetry_connect_timeout_seconds}"
  printf 'TELEMETRY_REQUEST_TIMEOUT_SECONDS=%q\n' "${resolved_telemetry_request_timeout_seconds}"
  printf 'TELEMETRY_OUTBOX_DIR=%q\n' "${resolved_telemetry_outbox_dir}"
  printf 'TELEMETRY_USER_AGENT=%q\n' "${resolved_telemetry_user_agent}"
  printf 'SERVER_NAME=%q\n' "${server_name}"
  printf 'SERVER_IP=%q\n' "${server_ip}"
  printf 'SERVER_URL=%q\n' "https://${server_ip}:6443"
  printf 'RANCHER_HOST=%q\n' "${rancher_host}"
  printf 'REGISTRY_HOST=%q\n' "${registry_host}"
  printf 'AGENT_NAMES=%q\n' "${agent_names[*]}"
} > "${NODES_ENV}"

if [[ -f "${SERVER_TOKEN_FILE}" ]]; then
  printf '%s\n' "https://${server_ip}:6443" > "${SERVER_URL_FILE}"
fi

log "Generated ${CLUSTER_JSON} and ${HOSTS_YML}"
