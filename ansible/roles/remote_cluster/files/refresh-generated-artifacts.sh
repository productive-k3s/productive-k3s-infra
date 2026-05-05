#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ensure_base_requirements
validate_productive_k3s_source

mkdir -p "${GENERATED_DIR}"

if [[ -f "${CLUSTER_JSON}" ]]; then
  REMOTE_SERVER_IP="${REMOTE_SERVER_IP:-$(jq -r '.server.ipv4 // empty' "${CLUSTER_JSON}")}"
  REMOTE_AGENT_IPS="${REMOTE_AGENT_IPS:-$(jq -r '.agents[].ipv4' "${CLUSTER_JSON}" | tr '\n' ' ')}"
  REMOTE_CLUSTER_NAME="${REMOTE_CLUSTER_NAME:-$(jq -r '.cluster_name // empty' "${CLUSTER_JSON}")}"
  BASE_DOMAIN="${BASE_DOMAIN:-$(jq -r '.base_domain // empty' "${CLUSTER_JSON}")}"
  RANCHER_HOST="${RANCHER_HOST:-$(jq -r '.rancher_host // empty' "${CLUSTER_JSON}")}"
  REGISTRY_HOST="${REGISTRY_HOST:-$(jq -r '.registry_host // empty' "${CLUSTER_JSON}")}"
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

require_node_inputs

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

if [[ -z "${REMOTE_DIR_OVERRIDE}" ]]; then
  remote_home="$(remote_home_dir "${REMOTE_SERVER_IP}")"
  REMOTE_DIR_OVERRIDE="${remote_home}/productive-k3s"
fi

all_node_ips=("${REMOTE_SERVER_IP}" "${AGENT_IPS_ARRAY[@]}")
all_node_names=("server")
for i in "${!AGENT_IPS_ARRAY[@]}"; do
  all_node_names+=("agent-$((i + 1))")
done

tmp_json="$(mktemp)"
{
  printf '{\n'
  printf '  "cluster_name": %s,\n' "$(jq -Rn --arg v "${REMOTE_CLUSTER_NAME}" '$v')"
  printf '  "base_domain": %s,\n' "$(jq -Rn --arg v "${BASE_DOMAIN}" '$v')"
  printf '  "remote_dir": %s,\n' "$(jq -Rn --arg v "${REMOTE_DIR_OVERRIDE}" '$v')"
  printf '  "ssh": {\n'
  printf '    "user": %s,\n' "$(jq -Rn --arg v "${SSH_USER}" '$v')"
  printf '    "port": %s,\n' "$(jq -n --argjson v "${SSH_PORT}" '$v')"
  printf '    "key_path": %s,\n' "$(jq -Rn --arg v "${SSH_KEY_PATH}" '$v')"
  printf '    "extra_opts": %s\n' "$(jq -Rn --arg v "${SSH_EXTRA_OPTS}" '$v')"
  printf '  },\n'
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
  printf '  "server_url": %s,\n' "$(jq -Rn --arg v "https://${REMOTE_SERVER_IP}:6443" '$v')"
  printf '  "rancher_host": %s,\n' "$(jq -Rn --arg v "${RANCHER_HOST}" '$v')"
  printf '  "registry_host": %s,\n' "$(jq -Rn --arg v "${REGISTRY_HOST}" '$v')"
  printf '  "server": {\n'
  printf '    "name": "server",\n'
  printf '    "ipv4": %s\n' "$(jq -Rn --arg v "${REMOTE_SERVER_IP}" '$v')"
  printf '  },\n'
  printf '  "agents": [\n'
  for i in "${!AGENT_IPS_ARRAY[@]}"; do
    agent_ip="${AGENT_IPS_ARRAY[$i]}"
    printf '    {"name": %s, "ipv4": %s}' \
      "$(jq -Rn --arg v "agent-$((i + 1))" '$v')" \
      "$(jq -Rn --arg v "${agent_ip}" '$v')"
    if (( i + 1 < ${#AGENT_IPS_ARRAY[@]} )); then
      printf ','
    fi
    printf '\n'
  done
  printf '  ],\n'
  printf '  "nodes": [\n'
  for i in "${!all_node_ips[@]}"; do
    node_ip="${all_node_ips[$i]}"
    node_name="${all_node_names[$i]}"
    role="agent"
    [[ "${node_name}" == "server" ]] && role="server"
    platform="$(remote_platform "${node_ip}")"
    support="unsupported"
    if is_supported_platform "${platform}"; then
      support="supported"
    fi
    printf '    {"name": %s, "role": %s, "ipv4": %s, "platform": %s, "support": %s}' \
      "$(jq -Rn --arg v "${node_name}" '$v')" \
      "$(jq -Rn --arg v "${role}" '$v')" \
      "$(jq -Rn --arg v "${node_ip}" '$v')" \
      "$(jq -Rn --arg v "${platform}" '$v')" \
      "$(jq -Rn --arg v "${support}" '$v')"
    if (( i + 1 < ${#all_node_ips[@]} )); then
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
  printf '    ansible_user: %s\n' "${SSH_USER}"
  printf '    ansible_port: %s\n' "${SSH_PORT}"
  printf '    productive_k3s_remote_dir: %s\n' "${REMOTE_DIR_OVERRIDE}"
  printf '    productive_k3s_server_url: %s\n' "https://${REMOTE_SERVER_IP}:6443"
  printf '    productive_k3s_base_domain: %s\n' "${BASE_DOMAIN}"
  printf '    productive_k3s_rancher_host: %s\n' "${RANCHER_HOST}"
  printf '    productive_k3s_registry_host: %s\n' "${REGISTRY_HOST}"
  printf '  children:\n'
  printf '    servers:\n'
  printf '      hosts:\n'
  printf '        server:\n'
  printf '          ansible_host: %s\n' "${REMOTE_SERVER_IP}"
  printf '    agents:\n'
  printf '      hosts:\n'
  for i in "${!AGENT_IPS_ARRAY[@]}"; do
    printf '        agent-%s:\n' "$((i + 1))"
    printf '          ansible_host: %s\n' "${AGENT_IPS_ARRAY[$i]}"
  done
} > "${HOSTS_YML}"

{
  printf 'CLUSTER_NAME=%q\n' "${REMOTE_CLUSTER_NAME}"
  printf 'BASE_DOMAIN=%q\n' "${BASE_DOMAIN}"
  printf 'REMOTE_DIR=%q\n' "${REMOTE_DIR_OVERRIDE}"
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
  printf 'SSH_USER=%q\n' "${SSH_USER}"
  printf 'SSH_PORT=%q\n' "${SSH_PORT}"
  printf 'SERVER_NAME=%q\n' "server"
  printf 'SERVER_IP=%q\n' "${REMOTE_SERVER_IP}"
  printf 'SERVER_URL=%q\n' "https://${REMOTE_SERVER_IP}:6443"
  printf 'RANCHER_HOST=%q\n' "${RANCHER_HOST}"
  printf 'REGISTRY_HOST=%q\n' "${REGISTRY_HOST}"
  printf 'AGENT_IPS=%q\n' "${AGENT_IPS_ARRAY[*]}"
} > "${NODES_ENV}"

if [[ -f "${SERVER_TOKEN_FILE}" ]]; then
  printf '%s\n' "https://${REMOTE_SERVER_IP}:6443" > "${SERVER_URL_FILE}"
fi

log "Generated ${CLUSTER_JSON} and ${HOSTS_YML}"
