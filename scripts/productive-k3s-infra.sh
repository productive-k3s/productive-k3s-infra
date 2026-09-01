#!/usr/bin/env bash
set -euo pipefail

REQUESTED_PRODUCTIVE_K3S_VERSION="${PRODUCTIVE_K3S_VERSION-}"
REQUESTED_PRODUCTIVE_K3S_SOURCE="${PRODUCTIVE_K3S_SOURCE-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${PRODUCTIVE_K3S_INFRA_REPO_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
RELEASE_ENV_FILE="${SCRIPT_DIR}/release.env"
if [[ ! -f "${RELEASE_ENV_FILE}" && -f "${REPO_DIR}/scripts/release.env" ]]; then
  RELEASE_ENV_FILE="${REPO_DIR}/scripts/release.env"
fi
if [[ -f "${RELEASE_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${RELEASE_ENV_FILE}"
  set +a
fi
MAKE_BIN="${PRODUCTIVE_K3S_INFRA_MAKE_BIN:-make}"
TOFU_BIN="${PRODUCTIVE_K3S_INFRA_TOFU_BIN:-}"
VERSION="${PRODUCTIVE_K3S_INFRA_VERSION:-${PK3S_INFRA_RELEASE_TAG:-dev}}"
PROFILES_SOURCE_REPO_DIR="${PRODUCTIVE_K3S_PROFILES_REPO_DIR:-}"
TELEMETRY_EVENT_SENDER="${SCRIPT_DIR}/send-telemetry-event.sh"
if [[ ! -f "${TELEMETRY_EVENT_SENDER}" && -f "${REPO_DIR}/scripts/send-telemetry-event.sh" ]]; then
  TELEMETRY_EVENT_SENDER="${REPO_DIR}/scripts/send-telemetry-event.sh"
fi
TELEMETRY_MARKER="${TELEMETRY_MARKER:-pk3s-public-v1}"
RUNTIME_SURFACE="${PK3S_INFRA_RUNTIME_SURFACE:-source-plus-package}"
EXPORT_RUNTIME="${SCRIPT_DIR}/export-runtime.sh"
if [[ ! -f "${EXPORT_RUNTIME}" && -f "${REPO_DIR}/scripts/export-runtime.sh" ]]; then
  EXPORT_RUNTIME="${REPO_DIR}/scripts/export-runtime.sh"
fi

PROFILE_PATH=""
TGZ_PATH=""
OVERRIDE_ENV_PATH="${PK3S_PROFILE_OVERRIDE_ENV_FILE:-}"
OUTPUT_PATH=""
GLOBAL_DEBUG=0
GLOBAL_YES=0
GLOBAL_DRY_RUN=0
GLOBAL_JSON=0

# shellcheck disable=SC1090
source "${EXPORT_RUNTIME}"

can_use_tty() {
  [[ -t 0 && -t 1 ]]
}

prompt_yesno() {
  local var="$1" default="$2" msg="$3"
  local answer
  if can_use_tty; then
    printf '%s [%s]: ' "$msg" "$default" > /dev/tty
    IFS= read -r answer < /dev/tty
  else
    answer="$default"
  fi
  answer="${answer:-$default}"
  printf -v "$var" '%s' "$answer"
}

resolve_telemetry_enabled() {
  if [[ -n "${TELEMETRY_ENABLED:-}" ]]; then
    return 0
  fi

  if can_use_tty; then
    local telemetry_consent="y"
    prompt_yesno telemetry_consent "y" "Productive K3S Infra can send anonymous telemetry about this run to help improve the installation flow. It does not include any sensitive information like hostnames or other environment-specific identifiers. If enabled, this choice will also be propagated to the underlying productive-k3s bootstrap steps. Enable anonymous telemetry for this run?"
    if [[ "${telemetry_consent}" == "y" ]]; then
      TELEMETRY_ENABLED="true"
    else
      TELEMETRY_ENABLED="false"
    fi
    export TELEMETRY_ENABLED
    return 0
  fi

  TELEMETRY_ENABLED="false"
  export TELEMETRY_ENABLED
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|y|Y|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

generate_telemetry_id() {
  od -An -N8 -tx1 /dev/urandom | tr -d ' \n'
}

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e ':a;N;$!ba;s/\n/\\n/g' \
    -e 's/\r/\\r/g' \
    -e 's/\t/\\t/g'
}

prepare_telemetry_context() {
  resolve_telemetry_enabled
  export TELEMETRY_SESSION_ID="${TELEMETRY_SESSION_ID:-$(generate_telemetry_id)}"
  export TELEMETRY_RUN_ID="${TELEMETRY_RUN_ID:-$(generate_telemetry_id)}"
  export TELEMETRY_COMPONENT="infra"
}

infra_command_emits_telemetry() {
  local command="${1:-}"
  local subcommand="${2:-}"
  case "${command}" in
    apply|destroy)
      return 0
      ;;
    profile)
      [[ "${subcommand}" == "install" || "${subcommand}" == "apply" || "${subcommand}" == "destroy" ]]
      return
      ;;
    multipass|onprem|onprem-basic|on-prem|onprem-arm|onprem-basic-arm|on-prem-arm|aws-single-node)
      case "${subcommand:-up}" in
        up|destroy)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

write_generic_telemetry_event() {
  local event_name="$1"
  local command_name="$2"
  local result="$3"
  local scenario_name="$4"
  local event_file

  event_file="$(mktemp)"
  {
    printf '{\n'
    printf '  "schema_version": "1",\n'
    printf '  "event_family": "usage",\n'
    printf '  "event_name": "%s",\n' "$(json_escape "${event_name}")"
    printf '  "sent_at": "%s",\n' "$(json_escape "$(date -Iseconds)")"
    printf '  "session_id": "%s",\n' "$(json_escape "${TELEMETRY_SESSION_ID}")"
    printf '  "run_id": "%s",\n' "$(json_escape "${TELEMETRY_RUN_ID}")"
    printf '  "parent_run_id": "%s",\n' "$(json_escape "${TELEMETRY_PARENT_RUN_ID:-}")"
    printf '  "component": "infra",\n'
    printf '  "command": {\n'
    printf '    "name": "%s",\n' "$(json_escape "${command_name}")"
    printf '    "scenario": "%s",\n' "$(json_escape "${scenario_name}")"
    printf '    "result": "%s"\n' "$(json_escape "${result}")"
    printf '  },\n'
    printf '  "client": {\n'
    printf '    "repository": "productive-k3s-infra",\n'
    printf '    "script": "scripts/productive-k3s-infra.sh",\n'
    printf '    "telemetry_enabled": "%s"\n' "$(json_escape "${TELEMETRY_ENABLED}")"
    printf '  },\n'
    printf '  "telemetry_meta": {\n'
    printf '    "delivery_mode": "best-effort",\n'
    printf '    "anonymous_by_contract": true\n'
    printf '  }\n'
    printf '}\n'
  } > "${event_file}"

  TELEMETRY_RUN_ID="${TELEMETRY_RUN_ID}" TELEMETRY_MARKER="${TELEMETRY_MARKER}" bash "${TELEMETRY_EVENT_SENDER}" "${event_file}" >/dev/null 2>&1 || true
  rm -f "${event_file}"
}

usage() {
  if [[ "${RUNTIME_SURFACE}" == "package-only" ]]; then
    cat <<'EOF'
Usage:
  ./productive-k3s-infra.sh <command> [flags]
  ./productive-k3s-infra.sh profile <validate|install|plan|apply|destroy|status|export> --tgz <file> [flags]

Package-oriented commands:
  help
  version
  bundle info --json
  bom --json
  doctor
  profile validate --tgz <file>
  profile install --tgz <file>
  profile plan --tgz <file>
  profile apply --tgz <file>
  profile destroy --tgz <file>
  profile status --tgz <file>
  profile export --tgz <file> --output <file|dir>

Supported global flags:
  --tgz <file>
  --env-file <file>
  --output <file|dir>
  --debug
  --yes
  --dry-run
  --json
EOF
    return 0
  fi

  cat <<'EOF'
Usage:
  ./productive-k3s-infra.sh <command> --profile <file> [flags]
  ./productive-k3s-infra.sh export --profile <file> --output <file|dir> [flags]
  ./productive-k3s-infra.sh profile <validate|install|plan|apply|destroy|status|export> --tgz <file> [flags]
  ./productive-k3s-infra.sh dev profile <validate|plan|apply|destroy|status|export> --profile-env <file> [flags]
  ./productive-k3s-infra.sh <scenario> [command] [make-args...]

Profile-driven commands:
  help
  version
  bundle info --json
  bom --json
  doctor
  list-profiles
  profile validate --tgz <file>
  profile install --tgz <file>
  profile plan --tgz <file>
  profile apply --tgz <file>
  profile destroy --tgz <file>
  profile status --tgz <file>
  profile export --tgz <file> --output <file|dir>
  validate-profile --profile <file>
  validate --profile <file>
  plan --profile <file>
  apply --profile <file>
  destroy --profile <file>
  status --profile <file>
  export --profile <file> --output <file|dir>

Legacy compatibility:
  multipass [command]
  onprem | onprem-basic [command]
  onprem-arm | onprem-basic-arm [command]
  aws-single-node [command]

Supported global flags:
  --profile <file>
  --profile-env <file>
  --tgz <file>
  --output <file|dir>
  --debug
  --yes
  --dry-run
  --json
EOF
}

is_package_only_runtime() {
  [[ "${RUNTIME_SURFACE}" == "package-only" ]]
}

require_source_surface() {
  local command_label="$1"
  if is_package_only_runtime; then
    die 2 "the '${command_label}' command is not available in the package-only release surface; use 'profile <validate|install|plan|apply|destroy|status> --tgz <file>' or a source checkout"
  fi
}

resolve_source_repo_dir() {
  if [[ -z "${PROFILES_SOURCE_REPO_DIR}" ]]; then
    die 3 "the source-based '${COMMAND:-source}' surface requires PRODUCTIVE_K3S_PROFILES_REPO_DIR to point at a productive-k3s-profiles checkout"
  fi
  [[ -d "${PROFILES_SOURCE_REPO_DIR}" ]] || die 3 "productive-k3s-profiles checkout not found: ${PROFILES_SOURCE_REPO_DIR}"
  printf '%s\n' "${PROFILES_SOURCE_REPO_DIR}"
}

resolve_source_profiles_dir() {
  local source_repo="${PROFILES_SOURCE_REPO_DIR}"
  if [[ -z "${source_repo}" ]]; then
    die 3 "the source-based '${COMMAND:-source}' surface requires PRODUCTIVE_K3S_PROFILES_REPO_DIR to point at a productive-k3s-profiles checkout"
  fi
  [[ -d "${source_repo}" ]] || die 3 "productive-k3s-profiles checkout not found: ${source_repo}"
  [[ -d "${source_repo}/profiles" ]] || die 3 "profiles directory not found in productive-k3s-profiles checkout: ${source_repo}/profiles"
  printf '%s\n' "${source_repo}/profiles"
}

resolve_source_scenario_dir() {
  local scenario="$1"
  local source_repo="${PROFILES_SOURCE_REPO_DIR}" rel_dir
  if [[ -z "${source_repo}" ]]; then
    die 3 "the source-based '${COMMAND:-source}' surface requires PRODUCTIVE_K3S_PROFILES_REPO_DIR to point at a productive-k3s-profiles checkout"
  fi
  [[ -d "${source_repo}" ]] || die 3 "productive-k3s-profiles checkout not found: ${source_repo}"
  rel_dir="$(scenario_rel_dir "${scenario}")" || die 1 "unsupported scenario directory mapping: ${scenario}"
  [[ -d "${source_repo}/${rel_dir}" ]] || die 1 "scenario directory not found in productive-k3s-profiles checkout: ${source_repo}/${rel_dir}"
  printf '%s\n' "${source_repo}/${rel_dir}"
}

log() {
  local level="$1"
  shift
  printf '[pk3s-infra] %-5s %s\n' "${level}" "$*"
}

die() {
  local code="$1"
  shift
  log "ERROR" "$*" >&2
  exit "${code}"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die 5 "missing dependency: $1"
}

enforce_release_bound_productive_k3s_version() {
  local bound_version="${PK3S_CORE_SEMVER:-}"
  if [[ -z "${bound_version}" ]]; then
    return 0
  fi

  if [[ -n "${REQUESTED_PRODUCTIVE_K3S_VERSION:-}" && "${REQUESTED_PRODUCTIVE_K3S_VERSION}" != "${bound_version}" ]]; then
    die 4 "release ${VERSION} is bound to productive-k3s ${bound_version}; refusing requested PRODUCTIVE_K3S_VERSION=${REQUESTED_PRODUCTIVE_K3S_VERSION}"
  fi

  export PRODUCTIVE_K3S_VERSION="${bound_version}"
  if [[ -n "${REQUESTED_PRODUCTIVE_K3S_SOURCE:-}" && "${REQUESTED_PRODUCTIVE_K3S_SOURCE}" != "remote" ]]; then
    die 4 "release ${VERSION} requires PRODUCTIVE_K3S_SOURCE=remote; refusing requested PRODUCTIVE_K3S_SOURCE=${REQUESTED_PRODUCTIVE_K3S_SOURCE}"
  fi
  export PRODUCTIVE_K3S_SOURCE="remote"
}

resolve_tofu_bin() {
  if [[ -n "${TOFU_BIN}" ]]; then
    printf '%s\n' "${TOFU_BIN}"
    return 0
  fi
  if command -v tofu >/dev/null 2>&1; then
    printf 'tofu\n'
    return 0
  fi
  if command -v terraform >/dev/null 2>&1; then
    printf 'terraform\n'
    return 0
  fi
  return 1
}

render_bundle_info_json() {
  local bundle_version="${PK3S_INFRA_RELEASE_TAG:-${VERSION:-}}"
  [[ -n "${bundle_version}" ]] || {
    printf 'could not resolve bundle version\n' >&2
    exit 1
  }

  cat <<EOF
{
  "schema_version": "1",
  "bundle_name": "productive-k3s-infra",
  "bundle_type": "productive-k3s-infra",
  "bundle_version": "${bundle_version}",
  "cli_entrypoint": "productive-k3s-infra.sh",
  "platform": "any",
  "api_compatibility": {
    "contract": "productive-k3s-cli-bundle-info/v1"
  }
}
EOF
}

resolve_default_core_version() {
  local defaults_script="${SCRIPT_DIR}/release-config.sh"
  local default_core_version=""
  if [[ -f "${defaults_script}" ]]; then
    # shellcheck disable=SC1090
    default_core_version="$(
      set -a
      source "${defaults_script}"
      set +a
      printf '%s' "${PRODUCTIVE_K3S_CORE_VERSION_DEFAULT:-}"
    )"
  fi
  printf '%s\n' "${default_core_version}"
}

resolve_default_source_mode() {
  local defaults_script="${SCRIPT_DIR}/release-config.sh"
  local default_source=""
  if [[ -f "${defaults_script}" ]]; then
    # shellcheck disable=SC1090
    default_source="$(
      set -a
      source "${defaults_script}"
      set +a
      printf '%s' "${PRODUCTIVE_K3S_SOURCE_DEFAULT:-}"
    )"
  fi
  printf '%s\n' "${default_source:-remote}"
}

resolve_default_release_repo() {
  local defaults_script="${SCRIPT_DIR}/release-config.sh"
  local default_repo=""
  if [[ -f "${defaults_script}" ]]; then
    # shellcheck disable=SC1090
    default_repo="$(
      set -a
      source "${defaults_script}"
      set +a
      printf '%s' "${PRODUCTIVE_K3S_RELEASE_REPO_DEFAULT:-}"
    )"
  fi
  printf '%s\n' "${default_repo}"
}

render_bom_json() {
  local bundle_json bundle_version default_core_version default_source_mode default_release_repo bound_core_version
  bundle_json="$(render_bundle_info_json)"
  bundle_version="${PK3S_INFRA_RELEASE_TAG:-${VERSION:-}}"
  default_core_version="$(resolve_default_core_version)"
  default_source_mode="$(resolve_default_source_mode)"
  default_release_repo="$(resolve_default_release_repo)"
  bound_core_version="${PK3S_CORE_SEMVER:-}"

  cat <<EOF
{
  "schema_version": "1",
  "bom_type": "productive-k3s-cli-bom/v1",
  "cli": {
    "name": "productive-k3s-infra",
    "version": "${bundle_version}",
    "entrypoint": "productive-k3s-infra.sh"
  },
  "implementation": {
    "language": "bash",
    "bash_version": "$(json_escape "${BASH_VERSION:-unknown}")"
  },
  "bundle": ${bundle_json},
  "platform_support": {
    "developer_hosts": ["linux", "macos", "windows-wsl-or-powershell"],
    "runtime_targets": [
      {"profile_category": "local", "path": "scenarios/local/multipass", "host": "local workstation", "driver": "multipass"},
      {"profile_category": "edge", "path": "scenarios/edge/onprem-basic", "host": "remote linux over ssh", "driver": "ansible|shell"},
      {"profile_category": "cloud", "path": "scenarios/cloud/aws-single-node", "host": "aws ec2 over ssh", "driver": "opentofu"}
    ]
  },
  "productive_k3s": {
    "default_source": "${default_source_mode}",
    "default_core_version": "${default_core_version}",
    "default_release_repo": "$(json_escape "${default_release_repo}")",
    "bound_core_version": $(if [[ -n "${bound_core_version}" ]]; then printf '"%s"' "$(json_escape "${bound_core_version}")"; else printf 'null'; fi)
  },
  "requirements": {
    "required_commands": [
      {"name": "bash", "min_version": "5.1", "reason": "public CLI and scenario wrapper runtime"},
      {"name": "make", "min_version": "4.3", "reason": "scenario dispatch and orchestration entrypoint"},
      {"name": "tar", "min_version": "1.34", "reason": "profile package extraction"},
      {"name": "mktemp", "min_version": "8.32", "reason": "temporary package and merge workspaces"}
    ],
    "optional_commands": [
      {"name": "tofu", "min_version": "1.8.0", "reason": "preferred OpenTofu engine for local and cloud scenarios"},
      {"name": "terraform", "min_version": "1.8.0", "reason": "fallback CLI when OpenTofu is unavailable"},
      {"name": "jq", "min_version": "1.6", "reason": "JSON inspection and generated artifact helpers"},
      {"name": "multipass", "min_version": "1.14", "reason": "local multipass scenario execution and live validation"},
      {"name": "ansible-playbook", "min_version": "2.15", "reason": "remote on-prem scenario orchestration"},
      {"name": "curl", "min_version": "7.81", "reason": "release artifact and helper downloads"}
    ]
  },
  "scenarios": [
    {"name": "multipass", "category": "local", "engine": "opentofu", "path": "scenarios/local/multipass"},
    {"name": "onprem-basic", "category": "edge", "engine": "ansible|shell", "path": "scenarios/edge/onprem-basic"},
    {"name": "onprem-basic-arm", "category": "edge", "engine": "ansible|shell", "path": "scenarios/edge/onprem-basic-arm"},
    {"name": "aws-single-node", "category": "cloud", "engine": "opentofu", "path": "scenarios/cloud/aws-single-node"}
  ],
  "package_contract": {
    "profile_tgz_supported": true,
    "profile_env_role": "package-defaults",
    "input_metadata": "spec.inputs",
    "local_override_flag": "--env-file"
  }
}
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

resolve_scenario() {
  case "$1" in
    multipass)
      printf 'multipass\n'
      ;;
    onprem-arm|onprem-basic-arm|on-prem-arm)
      printf 'onprem-basic-arm\n'
      ;;
    onprem|onprem-basic|on-prem)
      printf 'onprem-basic\n'
      ;;
    aws-single-node)
      printf 'aws-single-node\n'
      ;;
    *)
      return 1
      ;;
  esac
}

scenario_rel_dir() {
  case "$1" in
    multipass)
      printf 'scenarios/local/multipass\n'
      ;;
    onprem-basic)
      printf 'scenarios/edge/onprem-basic\n'
      ;;
    onprem-basic-arm)
      printf 'scenarios/edge/onprem-basic-arm\n'
      ;;
    aws-single-node)
      printf 'scenarios/cloud/aws-single-node\n'
      ;;
    *)
      return 1
      ;;
  esac
}

profile_env_var_name() {
  case "$1" in
    onprem-basic|onprem-basic-arm)
      printf 'ONPREM_ENV_FILE\n'
      ;;
    aws-single-node)
      printf 'AWS_ENV_FILE\n'
      ;;
    *)
      printf '\n'
      ;;
  esac
}

profile_category() {
  case "${1:-}" in
    multipass)
      printf 'local\n'
      ;;
    onprem-basic|onprem-basic-arm)
      printf 'edge\n'
      ;;
    aws-single-node)
      printf 'cloud\n'
      ;;
    *)
      return 1
      ;;
  esac
}

command_to_target() {
  local command="$1"
  local scenario="$2"
  case "$command" in
    validate)
      printf 'validate\n'
      ;;
    apply)
      printf 'up\n'
      ;;
    plan)
      printf 'up\n'
      ;;
    destroy)
      case "$scenario" in
        multipass|aws-single-node)
          printf 'down\n'
          ;;
        onprem-basic|onprem-basic-arm)
          return 1
          ;;
      esac
      ;;
    status)
      printf 'status\n'
      ;;
    *)
      return 1
      ;;
  esac
}

source_profile() {
  local profile="$1"
  [[ -f "${profile}" ]] || die 3 "profile not found: ${profile}"
  set -a
  # shellcheck disable=SC1090
  source "${profile}"
  set +a
}

require_env() {
  local name="$1"
  local value="${!name:-}"
  [[ -n "$(trim "${value}")" ]] || die 4 "profile is missing required variable: ${name}"
}

validate_profile() {
  require_env PK3S_INFRA_PROFILE_NAME
  require_env PK3S_INFRA_ENGINE

  if [[ -z "$(trim "${PK3S_INFRA_SCENARIO:-}")" ]]; then
    die 4 "profile is missing required variable: PK3S_INFRA_SCENARIO"
  fi

  require_env PK3S_INFRA_SCENARIO

  PK3S_INFRA_SCENARIO="$(resolve_scenario "${PK3S_INFRA_SCENARIO}")" || die 4 "unsupported PK3S_INFRA_SCENARIO: ${PK3S_INFRA_SCENARIO}"
  export PK3S_INFRA_SCENARIO

  case "${PK3S_INFRA_ENGINE}" in
    opentofu|ansible|shell) ;;
    *)
      die 4 "unsupported PK3S_INFRA_ENGINE: ${PK3S_INFRA_ENGINE}"
      ;;
  esac

  case "${PK3S_INFRA_SCENARIO}" in
    multipass)
      if [[ "${PK3S_INFRA_ENGINE}" != "opentofu" ]]; then
        die 4 "multipass profiles must use PK3S_INFRA_ENGINE=opentofu"
      fi
      require_env TF_VAR_cluster_name
      require_env TF_VAR_image
      require_env TF_VAR_base_domain
      require_env TF_VAR_remote_dir
      require_env TF_VAR_server_cpus
      require_env TF_VAR_server_memory
      require_env TF_VAR_server_disk
      require_env TF_VAR_agent_cpus
      require_env TF_VAR_agent_memory
      require_env TF_VAR_agent_disk
      ;;
    onprem-basic|onprem-basic-arm)
      if [[ "${PK3S_INFRA_ENGINE}" != "ansible" && "${PK3S_INFRA_ENGINE}" != "shell" ]]; then
        die 4 "${PK3S_INFRA_SCENARIO} profiles must use PK3S_INFRA_ENGINE=ansible or shell"
      fi
      require_env ONPREM_SERVER_IP
      require_env ONPREM_SSH_USER
      if [[ -z "$(trim "${ONPREM_SSH_KEY_PATH:-${ONPREM_SSH_PRIVATE_KEY_PATH:-}}")" ]]; then
        die 4 "profile is missing required variable: ONPREM_SSH_KEY_PATH"
      fi
      ;;
    aws-single-node)
      if [[ "${PK3S_INFRA_ENGINE}" != "opentofu" ]]; then
        die 4 "aws-single-node profiles must use PK3S_INFRA_ENGINE=opentofu"
      fi
      require_env AWS_REGION
      require_env AWS_CLUSTER_NAME
      require_env AWS_INSTANCE_TYPE
      require_env AWS_SSH_USER
      require_env AWS_SSH_KEY_PATH
      require_env AWS_ROOT_VOLUME_SIZE_GB
      ;;
  esac
}

run_opentofu_plan() {
  local scenario_dir="$1"
  local profile_env_path="${2:-}"
  local opentofu_dir="${scenario_dir}/opentofu"
  local resolved_tofu
  local tf_env_file=""
  local make_bin="${PK3S_PROFILE_MAKE_BIN:-${MAKE_BIN}}"

  [[ -d "${opentofu_dir}" ]] || die 1 "opentofu directory not found: ${opentofu_dir}"
  resolved_tofu="$(resolve_tofu_bin)" || die 5 "missing dependency: tofu or terraform"
  log "INFO" "Running OpenTofu plan in ${opentofu_dir}"
  (
    if [[ -n "${profile_env_path}" ]]; then
      set -a
      # shellcheck disable=SC1090
      source "${profile_env_path}"
      set +a

      if [[ -f "${scenario_dir}/Makefile" ]]; then
        tf_env_file="$(mktemp)"
        (
          cd "${scenario_dir}"
          "${make_bin}" -pn \
            | awk -F' := ' '/^TF_VAR_/ {print $1"="$2}'
        ) > "${tf_env_file}"
        if [[ -s "${tf_env_file}" ]]; then
          set -a
          # shellcheck disable=SC1090
          source "${tf_env_file}"
          set +a
        fi
      fi
    fi
    "${resolved_tofu}" -chdir="${opentofu_dir}" init -backend=false
    "${resolved_tofu}" -chdir="${opentofu_dir}" plan
    if [[ -n "${tf_env_file}" ]]; then
      rm -f "${tf_env_file}"
    fi
  )
}

run_profile_doctor() {
  local profile="$1"
  enforce_release_bound_productive_k3s_version
  source_profile "${profile}"
  enforce_release_bound_productive_k3s_version
  validate_profile
  log "OK" "Profile file is readable: ${profile}"
  log "OK" "Profile scenario: ${PK3S_INFRA_SCENARIO}"
  log "OK" "Profile engine: ${PK3S_INFRA_ENGINE}"
  case "${PK3S_INFRA_ENGINE}" in
    opentofu)
      resolve_tofu_bin >/dev/null || die 5 "missing dependency: tofu or terraform"
      log "OK" "OpenTofu-compatible binary is available"
      ;;
    ansible|shell)
      need_cmd ssh
      log "OK" "ssh is available for remote-oriented profile validation"
      ;;
  esac
}

run_validate_profile_only() {
  local profile="$1"
  enforce_release_bound_productive_k3s_version
  source_profile "${profile}"
  enforce_release_bound_productive_k3s_version
  validate_profile
  log "INFO" "Loading profile: ${profile}"
  log "INFO" "Scenario: ${PK3S_INFRA_SCENARIO}"
  log "INFO" "Engine: ${PK3S_INFRA_ENGINE}"
  log "OK" "Profile validation passed"
}

profile_command_dispatch() {
  local command="$1"
  local profile="$2"
  local target env_file_var scenario_dir

  enforce_release_bound_productive_k3s_version
  source_profile "${profile}"
  enforce_release_bound_productive_k3s_version
  validate_profile

  target="$(command_to_target "${command}" "${PK3S_INFRA_SCENARIO}")" || die 2 "unsupported command '${command}' for scenario '${PK3S_INFRA_SCENARIO}'"
  scenario_dir="$(resolve_source_scenario_dir "${PK3S_INFRA_SCENARIO}")"

  log "INFO" "Loading profile: ${profile}"
  log "INFO" "Scenario: ${PK3S_INFRA_SCENARIO}"
  log "INFO" "Engine: ${PK3S_INFRA_ENGINE}"
  log "OK" "Profile validation passed"

  if [[ "${command}" == "apply" && "${GLOBAL_DRY_RUN}" -eq 1 ]]; then
    log "INFO" "Dry-run requested; switching apply to plan"
    command="plan"
  fi

  if [[ "${command}" == "plan" ]]; then
    case "${PK3S_INFRA_ENGINE}" in
      opentofu)
        run_opentofu_plan "${scenario_dir}"
        return $?
        ;;
      ansible|shell)
        log "INFO" "Plan mode delegates to 'make -n' for the current remote backend contract"
        env_file_var="$(profile_env_var_name "${PK3S_INFRA_SCENARIO}")"
        if [[ -n "${env_file_var}" ]]; then
          env "${env_file_var}=${profile}" "${MAKE_BIN}" -n -C "${scenario_dir}" "${target}"
          return $?
        fi
        "${MAKE_BIN}" -n -C "${scenario_dir}" "${target}"
        return $?
        ;;
    esac
  fi

  if [[ "${command}" == "destroy" && ( "${PK3S_INFRA_SCENARIO}" == "onprem-basic" || "${PK3S_INFRA_SCENARIO}" == "onprem-basic-arm" ) && "${GLOBAL_YES}" -ne 1 ]]; then
    die 2 "destroy is not supported for ${PK3S_INFRA_SCENARIO} in the stage-1 profile contract"
  fi

  env_file_var="$(profile_env_var_name "${PK3S_INFRA_SCENARIO}")"
  export TELEMETRY_PARENT_RUN_ID="${TELEMETRY_RUN_ID:-}"
  export TELEMETRY_RUN_ID=""
  export TELEMETRY_COMPONENT="infra"
  if [[ -n "${env_file_var}" ]]; then
    env "${env_file_var}=${profile}" "${MAKE_BIN}" -C "${scenario_dir}" "${target}"
    return $?
  fi
  "${MAKE_BIN}" -C "${scenario_dir}" "${target}"
}

legacy_dispatch() {
  local scenario command
  enforce_release_bound_productive_k3s_version
  scenario="$(resolve_scenario "$1")" || die 2 "unsupported scenario: $1"
  shift

  command="${1:-up}"
  if (($# > 0)); then
    shift
  fi

  local scenario_dir
  scenario_dir="$(resolve_source_scenario_dir "${scenario}")"

  export TELEMETRY_PARENT_RUN_ID="${TELEMETRY_RUN_ID:-}"
  export TELEMETRY_RUN_ID=""
  export TELEMETRY_COMPONENT="infra"
  "${MAKE_BIN}" -C "${scenario_dir}" "${command}" "$@"
}

run_doctor() {
  need_cmd bash
  need_cmd "${MAKE_BIN}"
  enforce_release_bound_productive_k3s_version
  log "OK" "bash is available"
  log "OK" "${MAKE_BIN} is available"
  if [[ -n "${PROFILES_SOURCE_REPO_DIR}" && -d "${PROFILES_SOURCE_REPO_DIR}/profiles" ]]; then
    log "OK" "productive-k3s-profiles checkout found: ${PROFILES_SOURCE_REPO_DIR}"
  else
    log "WARN" "productive-k3s-profiles checkout not configured; set PRODUCTIVE_K3S_PROFILES_REPO_DIR for source-based commands"
  fi
  if [[ -n "${PROFILE_PATH}" ]]; then
    run_profile_doctor "${PROFILE_PATH}"
  fi
}

run_list_profiles() {
  local source_repo="${PROFILES_SOURCE_REPO_DIR}"
  local profiles_dir
  if [[ -z "${source_repo}" ]]; then
    die 3 "the source-based '${COMMAND:-source}' surface requires PRODUCTIVE_K3S_PROFILES_REPO_DIR to point at a productive-k3s-profiles checkout"
  fi
  [[ -d "${source_repo}" ]] || die 3 "productive-k3s-profiles checkout not found: ${source_repo}"
  profiles_dir="${source_repo}/profiles"
  [[ -d "${profiles_dir}" ]] || die 3 "profiles directory not found in productive-k3s-profiles checkout: ${profiles_dir}"

  (
    cd "${profiles_dir}"
    find . -type f -name '*.env' | sort
  ) | while read -r profile; do
    profile="${profile#./}"
    printf 'profiles/%s\n' "${profile}"
  done
}

trim_yaml_value() {
  local value="$1"
  value="${value#*:}"
  value="${value# }"
  value="${value%\"}"
  value="${value#\"}"
  printf '%s' "${value}"
}

profile_yaml_get() {
  local file="$1"
  local key="$2"
  awk -v key="${key}" '
    /^metadata:/ { section="metadata"; subsection=""; next }
    /^spec:/ { section="spec"; subsection=""; next }
    section == "spec" && /^  scenario:/ { subsection="scenario"; next }
    section == "spec" && /^  engine:/ { subsection="engine"; next }
    section == "spec" && /^  execution:/ { subsection="execution"; next }
    section == "metadata" && key == "metadata.name" && /^  name:/ { print; exit }
    section == "metadata" && key == "metadata.version" && /^  version:/ { print; exit }
    section == "spec" && subsection == "scenario" && key == "spec.scenario.type" && /^    type:/ { print; exit }
    section == "spec" && subsection == "engine" && key == "spec.engine.type" && /^    type:/ { print; exit }
    section == "spec" && subsection == "execution" && key == "spec.execution.installScript" && /^    installScript:/ { print; exit }
  ' "${file}"
}

profile_package_metadata_path() {
  local profile="$1"
  case "${profile}" in
    *.env)
      printf '%s\n' "${profile%.env}.package.yaml"
      ;;
    *)
      die 4 "profile source metadata path could not be derived from: ${profile}"
      ;;
  esac
}

copy_profile_package_inputs_block() {
  local package_metadata="$1"
  local target_path="$2"
  [[ -f "${package_metadata}" ]] || return 0
  awk '
    /^inputs:/ { in_inputs=1 }
    in_inputs { print }
  ' "${package_metadata}" >> "${target_path}"
}

write_source_profile_install_wrapper() {
  local target_path="$1"
  local scenario_type="$2"
  local scenario_dir="$3"
  local env_var
  env_var="$(profile_env_var_name "${scenario_type}")"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -euo pipefail\n\n'
    printf 'PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n'
    printf 'SCENARIO_DIR="${PACKAGE_ROOT}/%s"\n' "${scenario_dir}"
    printf 'PROFILE_ENV="${PACKAGE_ROOT}/profile.env"\n'
    printf 'RUNTIME_ENV="$(mktemp)"\n'
    printf 'cleanup() {\n'
    printf '  rm -f "${RUNTIME_ENV}"\n'
    printf '}\n'
    printf 'trap cleanup EXIT\n'
    printf 'for key in \\\n'
    printf '  PRODUCTIVE_K3S_SOURCE \\\n'
    printf '  PRODUCTIVE_K3S_VERSION \\\n'
    printf '  PRODUCTIVE_K3S_RELEASE_REPO \\\n'
    printf '  PRODUCTIVE_K3S_REPO \\\n'
    printf '  PRODUCTIVE_K3S_CORE_REPO_DIR \\\n'
    printf '  PRODUCTIVE_K3S_ADDONS_REPO_DIR \\\n'
    printf '  PRODUCTIVE_K3S_STACK_TGZ_URL \\\n'
    printf '  PRODUCTIVE_K3S_STACK_REMOTE_PATH \\\n'
    printf '  PRODUCTIVE_K3S_ENGINE \\\n'
    printf '  PRODUCTIVE_K3S_DISTRO \\\n'
    printf '  PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS \\\n'
    printf '  PRODUCTIVE_K3S_AUTO_APPROVE_APPLY_PLAN \\\n'
    printf '  TELEMETRY_ENABLED \\\n'
    printf '  TELEMETRY_ENDPOINT \\\n'
    printf '  TELEMETRY_MARKER \\\n'
    printf '  TELEMETRY_BEARER_TOKEN \\\n'
    printf '  TELEMETRY_MAX_RETRIES \\\n'
    printf '  TELEMETRY_CONNECT_TIMEOUT_SECONDS \\\n'
    printf '  TELEMETRY_REQUEST_TIMEOUT_SECONDS \\\n'
    printf '  TELEMETRY_OUTBOX_DIR \\\n'
    printf '  TELEMETRY_USER_AGENT \\\n'
    printf '  TELEMETRY_SESSION_ID \\\n'
    printf '  TELEMETRY_PARENT_RUN_ID \\\n'
    printf '  TELEMETRY_COMPONENT; do\n'
    printf '  if [[ ${!key+x} ]]; then\n'
    printf '    printf '\''export %%s=%%q\\n'\'' "${key}" "${!key}" >>"${RUNTIME_ENV}"\n'
    printf '  else\n'
    printf '    printf '\''unset %%s\\n'\'' "${key}" >>"${RUNTIME_ENV}"\n'
    printf '  fi\n'
    printf 'done\n'
    printf 'set -a\n'
    printf 'source "${PROFILE_ENV}"\n'
    printf 'set +a\n'
    printf 'source "${RUNTIME_ENV}"\n'
    printf 'cd "${PACKAGE_ROOT}"\n'
    printf 'export REPO_ROOT="${PACKAGE_ROOT}"\n'
    printf 'export PRODUCTIVE_K3S_REPO="${PK3S_PROFILE_PACKAGE_PRODUCTIVE_K3S_REPO:-${PACKAGE_ROOT}}"\n'
    printf 'export PRODUCTIVE_K3S_SOURCE="${PRODUCTIVE_K3S_SOURCE:-remote}"\n'
    if [[ -n "${env_var}" ]]; then
      printf 'export %s="${PROFILE_ENV}"\n' "${env_var}"
    fi
    printf 'exec make -C "${SCENARIO_DIR}" up "$@"\n'
  } > "${target_path}"
  chmod +x "${target_path}"
}

write_source_profile_manifest() {
  local target_path="$1"
  local profile_name="$2"
  local scenario_type="$3"
  local engine_type="$4"
  local package_metadata="$5"

  {
    printf 'apiVersion: infra.productive-k3s.io/v1\n'
    printf 'kind: Profile\n'
    printf 'metadata:\n'
    printf '  name: %s\n' "${profile_name}"
    printf '  version: exported\n'
    printf '  category: %s\n' "$(profile_category "${scenario_type}")"
    printf 'spec:\n'
    printf '  scenario:\n'
    printf '    type: %s\n' "${scenario_type}"
    printf '  engine:\n'
    printf '    type: %s\n' "${engine_type}"
    printf '  execution:\n'
    printf '    installScript: scripts/install.sh\n'
    copy_profile_package_inputs_block "${package_metadata}" /dev/stdout
  } > "${target_path}"
}

create_source_profile_tgz() {
  local profile="$1"
  local output_tgz="$2"
  local package_root profile_name scenario_type engine_type source_repo scenario_dir_rel scenario_dir package_metadata

  enforce_release_bound_productive_k3s_version
  source_profile "${profile}"
  enforce_release_bound_productive_k3s_version
  validate_profile

  profile_name="${PK3S_INFRA_PROFILE_NAME}"
  scenario_type="${PK3S_INFRA_SCENARIO}"
  engine_type="${PK3S_INFRA_ENGINE}"
  source_repo="$(resolve_source_repo_dir)"
  scenario_dir_rel="$(scenario_rel_dir "${scenario_type}")"
  scenario_dir="${source_repo}/${scenario_dir_rel}"
  package_metadata="$(profile_package_metadata_path "${profile}")"

  package_root="$(mktemp -d)"
  mkdir -p "${package_root}/scripts" "${package_root}/${scenario_dir_rel}"
  cp "${profile}" "${package_root}/profile.env"
  cp -R "${scenario_dir}/." "${package_root}/${scenario_dir_rel}/"
  case "${scenario_type}" in
    aws-single-node|onprem-basic|onprem-basic-arm)
      mkdir -p "${package_root}/ansible/roles/remote_cluster"
      cp -R "${REPO_DIR}/ansible/roles/remote_cluster/files" "${package_root}/ansible/roles/remote_cluster/"
      ;;
  esac
  write_source_profile_manifest "${package_root}/profile.yaml" "${profile_name}" "${scenario_type}" "${engine_type}" "${package_metadata}"
  write_source_profile_install_wrapper "${package_root}/scripts/install.sh" "${scenario_type}" "${scenario_dir_rel}"
  tar -czf "${output_tgz}" -C "${package_root}" .
  rm -rf "${package_root}"
}

run_profile_export_from_tgz() {
  local tgz_path="$1"
  local output_path="$2"
  local subject_kind="${3:-profile-tgz}"
  local subject_ref="${4:-${tgz_path}}"
  local subject_source="${5:-packaged}"
  local artifact_name="profile.tgz"
  local bundle_root stage_dir has_override_env="false"

  [[ -n "${output_path}" ]] || die 3 "the 'profile export' command requires --output <file|dir>"
  [[ -f "${tgz_path}" ]] || die 3 "tgz package not found: ${tgz_path}"

  export_runtime_init
  stage_dir="$(mktemp -d)"
  bundle_root="${stage_dir}/bundle"
  mkdir -p "${bundle_root}"

  cp "${tgz_path}" "${bundle_root}/${artifact_name}"
  if [[ -n "${OVERRIDE_ENV_PATH}" ]]; then
    [[ -f "${OVERRIDE_ENV_PATH}" ]] || die 4 "override env file not found: ${OVERRIDE_ENV_PATH}"
    cp "${OVERRIDE_ENV_PATH}" "${bundle_root}/override.env"
    has_override_env="true"
  fi

  export_runtime_set_metadata command "profile export"
  export_runtime_set_metadata subject_kind "${subject_kind}"
  export_runtime_set_metadata subject_ref "${subject_ref}"
  export_runtime_set_metadata artifact_name "${artifact_name}"
  export_runtime_set_metadata profile_source "${subject_source}"
  export_runtime_add_env "TELEMETRY_ENABLED" "${TELEMETRY_ENABLED:-false}"
  export_runtime_copy_infra_runtime "${REPO_DIR}" "${bundle_root}"
  export_runtime_write_install_config "${bundle_root}/install-config.env"
  export_runtime_write_manifest "${bundle_root}/manifest.json"
  export_runtime_write_profile_install_script "${bundle_root}/install.sh" "${artifact_name}" "${has_override_env}"
  export_runtime_write_readme "${bundle_root}/README.md" "${subject_ref}" "${artifact_name}"

  if [[ "${output_path}" == *.tgz || "${output_path}" == *.tar.gz ]]; then
    mkdir -p "$(dirname "${output_path}")"
    tar -czf "${output_path}" -C "${stage_dir}" bundle
  else
    rm -rf "${output_path}"
    mkdir -p "$(dirname "${output_path}")"
    cp -R "${bundle_root}" "${output_path}"
  fi

  rm -rf "${stage_dir}"
  log "OK" "Exported profile bundle written to: ${output_path}"
}

run_profile_export_from_source_profile() {
  local profile="$1"
  local output_path="$2"
  local normalized_tgz
  normalized_tgz="$(mktemp -t pk3s-infra-export-profile.XXXXXX.tgz)"
  create_source_profile_tgz "${profile}" "${normalized_tgz}"
  run_profile_export_from_tgz "${normalized_tgz}" "${output_path}" "source-profile" "${profile}" "source-profile"
  rm -f "${normalized_tgz}"
}

profile_input_records() {
  local file="$1"
  awk '
    function emit() {
      if (name != "") {
        print name "|" required "|" sensitive "|" source "|" description
        name=""
      }
    }
    /^spec:/ { in_spec=1; in_inputs=0; next }
    in_spec && /^  inputs:/ { in_inputs=1; next }
    in_inputs && /^  [a-zA-Z]/ { emit(); done=1; exit }
    in_inputs && /^    - name:/ {
      emit()
      name=$3
      required="false"
      sensitive="false"
      source="either"
      description=""
      next
    }
    in_inputs && /^      required:/ { required=$2; next }
    in_inputs && /^      sensitive:/ { sensitive=$2; next }
    in_inputs && /^      source:/ { source=$2; next }
    in_inputs && /^      description:/ {
      description=substr($0, index($0, ":") + 2)
      gsub(/^"/, "", description)
      gsub(/"$/, "", description)
      next
    }
    END { if (!done) emit() }
  ' "${file}"
}

validate_profile_input_metadata() {
  local manifest="$1"
  local record name required sensitive source description
  while IFS= read -r record; do
    [[ -n "${record}" ]] || continue
    IFS='|' read -r name required sensitive source description <<<"${record}"
    [[ -n "${name}" ]] || die 4 "profile package input name is required"
    case "${required}" in
      true|false) ;;
      *) die 4 "profile package input '${name}' has invalid required value: ${required}" ;;
    esac
    case "${sensitive}" in
      true|false) ;;
      *) die 4 "profile package input '${name}' has invalid sensitive value: ${sensitive}" ;;
    esac
    case "${source}" in
      either|package-default|local-override) ;;
      *) die 4 "profile package input '${name}' has invalid source value: ${source}" ;;
    esac
  done < <(profile_input_records "${manifest}")
}

env_file_var_has_value() {
  local env_file="$1"
  local var_name="$2"
  [[ -n "${env_file}" && -f "${env_file}" ]] || return 1
  (
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
    [[ -n "${!var_name:-}" ]]
  )
}

validate_profile_runtime_inputs() {
  local manifest="$1"
  local merged_env="$2"
  local override_env="${3:-}"
  local missing_local_override=()
  local missing_defaults=()
  local record name required sensitive source description

  while IFS= read -r record; do
    [[ -n "${record}" ]] || continue
    IFS='|' read -r name required sensitive source description <<<"${record}"
    [[ "${required}" == "true" ]] || continue
    case "${source}" in
      local-override)
        env_file_var_has_value "${override_env}" "${name}" || missing_local_override+=("${name}")
        ;;
      package-default|either)
        env_file_var_has_value "${merged_env}" "${name}" || missing_defaults+=("${name}")
        ;;
    esac
  done < <(profile_input_records "${manifest}")

  if ((${#missing_local_override[@]} > 0)); then
    die 4 "required packaged profile inputs must be provided through --env-file: ${missing_local_override[*]}"
  fi
  if ((${#missing_defaults[@]} > 0)); then
    die 4 "required packaged profile inputs are missing from package defaults or local overrides: ${missing_defaults[*]}"
  fi
}

extract_tgz_to_temp() {
  local archive="$1"
  [[ -f "${archive}" ]] || die 3 "tgz package not found: ${archive}"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  tar -xzf "${archive}" -C "${tmp_dir}" || die 4 "could not extract tgz package: ${archive}"
  printf '%s\n' "${tmp_dir}"
}

resolve_profile_manifest() {
  local package_root="$1"
  local manifest
  manifest="$(find "${package_root}" -type f -name 'profile.yaml' | head -n1)"
  [[ -n "${manifest}" ]] || die 4 "profile package is missing profile.yaml"
  printf '%s\n' "${manifest}"
}

validate_profile_package() {
  local manifest="$1"
  local profile_name scenario_type engine_type install_script
  profile_name="$(trim_yaml_value "$(profile_yaml_get "${manifest}" "metadata.name")")"
  scenario_type="$(trim_yaml_value "$(profile_yaml_get "${manifest}" "spec.scenario.type")")"
  engine_type="$(trim_yaml_value "$(profile_yaml_get "${manifest}" "spec.engine.type")")"
  install_script="$(trim_yaml_value "$(profile_yaml_get "${manifest}" "spec.execution.installScript")")"

  [[ -n "${profile_name}" ]] || die 4 "profile package metadata.name is required"
  [[ -n "${scenario_type}" ]] || die 4 "profile package spec.scenario.type is required"
  [[ -n "${engine_type}" ]] || die 4 "profile package spec.engine.type is required"
  [[ -n "${install_script}" ]] || die 4 "profile package spec.execution.installScript is required"

  case "${engine_type}" in
    opentofu|ansible|shell) ;;
    *) die 4 "unsupported profile package engine: ${engine_type}" ;;
  esac

  validate_profile_input_metadata "${manifest}"

  printf '%s\n%s\n%s\n%s\n' "${profile_name}" "${scenario_type}" "${engine_type}" "${install_script}"
}

run_validate_profile_package() {
  local tgz_path="$1"
  local tmp_dir manifest metadata profile_name scenario_type engine_type install_script
  tmp_dir="$(extract_tgz_to_temp "${tgz_path}")"
  manifest="$(resolve_profile_manifest "${tmp_dir}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  metadata="$(validate_profile_package "${manifest}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  profile_name="$(printf '%s\n' "${metadata}" | sed -n '1p')"
  scenario_type="$(printf '%s\n' "${metadata}" | sed -n '2p')"
  engine_type="$(printf '%s\n' "${metadata}" | sed -n '3p')"
  install_script="$(printf '%s\n' "${metadata}" | sed -n '4p')"

  log "INFO" "Profile package: ${profile_name}"
  log "INFO" "Scenario: ${scenario_type}"
  log "INFO" "Engine: ${engine_type}"
  log "INFO" "Install script: ${install_script}"
  log "OK" "Profile package validation passed"
  rm -rf "${tmp_dir}"
}

packaged_profile_env_file() {
  local package_root="$1"
  local env_file="${package_root}/profile.env"
  [[ -f "${env_file}" ]] || die 4 "profile package is missing profile.env"
  printf '%s\n' "${env_file}"
}

merged_packaged_profile_env_file() {
  local package_root="$1"
  local override_env="${2:-}"
  local base_env merged_env
  base_env="$(packaged_profile_env_file "${package_root}")" || return $?
  if [[ -z "${override_env}" ]]; then
    printf '%s\n' "${base_env}"
    return 0
  fi
  [[ -f "${override_env}" ]] || die 4 "override env file not found: ${override_env}"
  merged_env="$(mktemp)"
  cat "${base_env}" > "${merged_env}"
  printf '\n' >> "${merged_env}"
  cat "${override_env}" >> "${merged_env}"
  printf '%s\n' "${merged_env}"
}

warn_if_packaged_profile_uses_embedded_env_only() {
  local profile_name="$1"
  local scenario_type="$2"
  local override_env="${3:-}"
  local manifest="${4:-}"

  if [[ -n "${override_env}" ]]; then
    return 0
  fi

  case "${scenario_type}" in
    multipass)
      return 0
      ;;
  esac

  if [[ -n "${manifest}" ]]; then
    while IFS= read -r record; do
      [[ -n "${record}" ]] || continue
      IFS='|' read -r _name _required _sensitive source _description <<<"${record}"
      if [[ "${source}" == "local-override" ]]; then
        break
      fi
    done < <(profile_input_records "${manifest}")
    [[ "${source:-}" == "local-override" ]] || return 0
  fi

  log "WARN" "Running packaged profile '${profile_name}' without local overrides; embedded profile.env defaults will be used as-is."
  log "WARN" "For real cloud and on-prem installs, pass installation-specific values from the invoking machine with --env-file <file>."
}

packaged_profile_scenario_dir() {
  local package_root="$1"
  local scenario_type="$2"
  local rel_dir
  rel_dir="$(scenario_rel_dir "${scenario_type}")" || die 4 "unsupported packaged profile scenario: ${scenario_type}"
  [[ -d "${package_root}/${rel_dir}" ]] || die 4 "profile package scenario directory not found: ${rel_dir}"
  printf '%s\n' "${package_root}/${rel_dir}"
}

profile_state_dir() {
  if [[ -n "${PK3S_PROFILE_STATE_DIR:-}" ]]; then
    printf '%s\n' "${PK3S_PROFILE_STATE_DIR}"
    return 0
  fi
  if [[ -n "${XDG_CACHE_HOME:-}" && -w "${XDG_CACHE_HOME}" ]]; then
    printf '%s\n' "${XDG_CACHE_HOME}/pk3s/profiles"
    return 0
  fi
  if [[ -d "${HOME}/.cache" && -w "${HOME}/.cache" ]]; then
    printf '%s\n' "${HOME}/.cache/pk3s/profiles"
    return 0
  fi
  printf '%s\n' "${TMPDIR:-/tmp}/pk3s/profiles"
}

profile_state_path() {
  local profile_name="$1"
  printf '%s/%s.json\n' "$(profile_state_dir)" "${profile_name}"
}

profile_runtime_state_dir() {
  local profile_name="$1"
  printf '%s/%s.runtime\n' "$(profile_state_dir)" "${profile_name}"
}

copy_if_exists() {
  local source_path="$1"
  local dest_path="$2"
  [[ -e "${source_path}" ]] || return 0
  mkdir -p "$(dirname "${dest_path}")"
  rm -rf "${dest_path}"
  cp -a "${source_path}" "${dest_path}"
}

packaged_profile_runtime_override_keys() {
  cat <<'EOF'
PRODUCTIVE_K3S_SOURCE
PRODUCTIVE_K3S_VERSION
PRODUCTIVE_K3S_RELEASE_REPO
PRODUCTIVE_K3S_REPO
PRODUCTIVE_K3S_CORE_REPO_DIR
PRODUCTIVE_K3S_ADDONS_REPO_DIR
PRODUCTIVE_K3S_STACK_TGZ_URL
PRODUCTIVE_K3S_STACK_REMOTE_PATH
PRODUCTIVE_K3S_ENGINE
PRODUCTIVE_K3S_DISTRO
PRODUCTIVE_K3S_AUTO_APPROVE_PREFLIGHT_WARNINGS
PRODUCTIVE_K3S_AUTO_APPROVE_APPLY_PLAN
TELEMETRY_ENABLED
TELEMETRY_ENDPOINT
TELEMETRY_MARKER
TELEMETRY_BEARER_TOKEN
TELEMETRY_MAX_RETRIES
TELEMETRY_CONNECT_TIMEOUT_SECONDS
TELEMETRY_REQUEST_TIMEOUT_SECONDS
TELEMETRY_OUTBOX_DIR
TELEMETRY_USER_AGENT
TELEMETRY_SESSION_ID
TELEMETRY_PARENT_RUN_ID
TELEMETRY_COMPONENT
EOF
}

capture_packaged_profile_runtime_overrides() {
  local target_path="$1"
  local key
  : > "${target_path}"
  while IFS= read -r key; do
    [[ -n "${key}" ]] || continue
    if [[ ${!key+x} ]]; then
      printf 'export %s=%q\n' "${key}" "${!key}" >> "${target_path}"
    else
      printf 'unset %s\n' "${key}" >> "${target_path}"
    fi
  done < <(packaged_profile_runtime_override_keys)
}

source_packaged_profile_env_with_runtime_overrides() {
  local profile_env="$1"
  local runtime_env="$2"
  set -a
  # shellcheck disable=SC1090
  source "${profile_env}"
  set +a
  # shellcheck disable=SC1090
  source "${runtime_env}"
}

rewrite_packaged_source_profile_install_wrapper_if_needed() {
  local package_root="$1"
  local install_path="$2"
  local scenario_type="$3"
  local rel_dir

  [[ -f "${install_path}" ]] || return 0
  grep -Fq 'PROFILE_ENV="${PACKAGE_ROOT}/profile.env"' "${install_path}" || return 0
  grep -Fq 'exec make -C "${SCENARIO_DIR}" up "$@"' "${install_path}" || return 0

  rel_dir="$(scenario_rel_dir "${scenario_type}")" || return 0
  [[ -d "${package_root}/${rel_dir}" ]] || return 0
  write_source_profile_install_wrapper "${install_path}" "${scenario_type}" "${rel_dir}"
}

rewrite_packaged_multipass_bootstrap_helper_if_needed() {
  local package_root="$1"
  local scenario_type="$2"
  local helper_path

  [[ "${scenario_type}" == "multipass" ]] || return 0
  helper_path="${package_root}/scenarios/local/multipass/scripts/run_bootstrap_session.py"
  [[ -f "${helper_path}" ]] || return 0

  python3 - "${helper_path}" <<'PY'
from pathlib import Path
import re
import sys

helper_path = Path(sys.argv[1])
content = helper_path.read_text(encoding="utf-8")
patched = re.sub(
    r"(?m)^(\s*)rc = 0$",
    r"\1rc = proc.returncode if proc.returncode is not None else 124",
    content,
    count=1,
)
if patched != content:
    helper_path.write_text(patched, encoding="utf-8")
PY
}

persist_profile_state() {
  local profile_name="$1"
  local scenario_dir="$2"
  local cluster_json="${scenario_dir}/generated/cluster.json"
  [[ -f "${cluster_json}" ]] || return 0
  local state_dir state_path
  state_dir="$(profile_state_dir)"
  state_path="$(profile_state_path "${profile_name}")"
  mkdir -p "${state_dir}"
  cp "${cluster_json}" "${state_path}"
  log "INFO" "Persisted profile state: ${state_path}"
}

rewrite_profile_state_ssh_key_path() {
  local profile_name="$1"
  local stable_key_path="$2"
  local state_path tmp_state
  state_path="$(profile_state_path "${profile_name}")"
  [[ -f "${state_path}" ]] || return 0
  tmp_state="$(mktemp)"
  jq --arg key_path "${stable_key_path}" '.ssh.key_path = $key_path' "${state_path}" > "${tmp_state}"
  mv "${tmp_state}" "${state_path}"
}

rewrite_runtime_cluster_ssh_key_path() {
  local runtime_dir="$1"
  local stable_key_path="$2"
  local cluster_json tmp_state
  cluster_json="${runtime_dir}/generated/cluster.json"
  [[ -f "${cluster_json}" ]] || return 0
  tmp_state="$(mktemp)"
  jq --arg key_path "${stable_key_path}" '.ssh.key_path = $key_path' "${cluster_json}" > "${tmp_state}"
  mv "${tmp_state}" "${cluster_json}"
}

persist_profile_runtime_state() {
  local profile_name="$1"
  local scenario_dir="$2"
  local runtime_dir opentofu_dir stable_key_path
  runtime_dir="$(profile_runtime_state_dir "${profile_name}")"
  rm -rf "${runtime_dir}"
  mkdir -p "${runtime_dir}"

  copy_if_exists "${scenario_dir}/generated" "${runtime_dir}/generated"
  opentofu_dir="${scenario_dir}/opentofu"
  if [[ -d "${opentofu_dir}" ]]; then
    mkdir -p "${runtime_dir}/opentofu"
    copy_if_exists "${opentofu_dir}/.terraform" "${runtime_dir}/opentofu/.terraform"
    copy_if_exists "${opentofu_dir}/terraform.tfstate" "${runtime_dir}/opentofu/terraform.tfstate"
    copy_if_exists "${opentofu_dir}/terraform.tfstate.backup" "${runtime_dir}/opentofu/terraform.tfstate.backup"
  fi
  stable_key_path="${runtime_dir}/generated/ssh/id_ed25519"
  if [[ -f "${stable_key_path}" ]]; then
    rewrite_runtime_cluster_ssh_key_path "${runtime_dir}" "${stable_key_path}"
    rewrite_profile_state_ssh_key_path "${profile_name}" "${stable_key_path}"
  fi
  log "INFO" "Persisted profile runtime state: ${runtime_dir}"
}

restore_profile_runtime_state() {
  local profile_name="$1"
  local scenario_dir="$2"
  local runtime_dir opentofu_dir
  runtime_dir="$(profile_runtime_state_dir "${profile_name}")"
  [[ -d "${runtime_dir}" ]] || return 0

  copy_if_exists "${runtime_dir}/generated" "${scenario_dir}/generated"
  opentofu_dir="${scenario_dir}/opentofu"
  if [[ -d "${opentofu_dir}" || -d "${runtime_dir}/opentofu" ]]; then
    mkdir -p "${opentofu_dir}"
    copy_if_exists "${runtime_dir}/opentofu/.terraform" "${opentofu_dir}/.terraform"
    copy_if_exists "${runtime_dir}/opentofu/terraform.tfstate" "${opentofu_dir}/terraform.tfstate"
    copy_if_exists "${runtime_dir}/opentofu/terraform.tfstate.backup" "${opentofu_dir}/terraform.tfstate.backup"
  fi
}

remove_profile_state() {
  local profile_name="$1"
  rm -f "$(profile_state_path "${profile_name}")"
  rm -rf "$(profile_runtime_state_dir "${profile_name}")"
}

run_packaged_profile_make() {
  local package_root="$1"
  local profile_env="$2"
  local scenario_dir="$3"
  local target="$4"
  local make_mode="${5:-normal}"
  local make_bin="${PK3S_PROFILE_MAKE_BIN:-${MAKE_BIN}}"
  local runtime_env
  runtime_env="$(mktemp)"

  local rc=0
  if (
    capture_packaged_profile_runtime_overrides "${runtime_env}"
    source_packaged_profile_env_with_runtime_overrides "${profile_env}" "${runtime_env}"
    cd "${package_root}"
    export REPO_ROOT="${package_root}"
    export PRODUCTIVE_K3S_REPO="${PK3S_PROFILE_PACKAGE_PRODUCTIVE_K3S_REPO:-${package_root}}"
    export PRODUCTIVE_K3S_SOURCE="${PRODUCTIVE_K3S_SOURCE:-remote}"
    if [[ "${make_mode}" == "dry-run" ]]; then
      "${make_bin}" -n -C "${scenario_dir}" "${target}"
    else
      "${make_bin}" -C "${scenario_dir}" "${target}"
    fi
  ); then
    rc=0
  else
    rc=$?
  fi
  rm -f "${runtime_env}"
  return "${rc}"
}

run_install_profile_package() {
  local tgz_path="$1"
  local action="${2:-install}"
  local tmp_dir manifest metadata install_script install_path manifest_dir package_root
  local profile_name scenario_type engine_type scenario_dir profile_env target cleanup_env=0
  tmp_dir="$(extract_tgz_to_temp "${tgz_path}")"
  package_root="${tmp_dir}"
  manifest="$(resolve_profile_manifest "${tmp_dir}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  metadata="$(validate_profile_package "${manifest}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  profile_name="$(printf '%s\n' "${metadata}" | sed -n '1p')"
  scenario_type="$(printf '%s\n' "${metadata}" | sed -n '2p')"
  engine_type="$(printf '%s\n' "${metadata}" | sed -n '3p')"
  install_script="$(printf '%s\n' "${metadata}" | sed -n '4p')"
  manifest_dir="$(dirname "${manifest}")"
  profile_env="$(merged_packaged_profile_env_file "${package_root}" "${OVERRIDE_ENV_PATH}")" || {
    local rc=$?
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  if [[ "${profile_env}" != "${package_root}/profile.env" ]]; then
    cleanup_env=1
    cp "${profile_env}" "${package_root}/profile.env"
    profile_env="${package_root}/profile.env"
  fi
  scenario_dir="$(packaged_profile_scenario_dir "${package_root}" "${scenario_type}")" || {
    local rc=$?
    if [[ "${cleanup_env}" -eq 1 ]]; then rm -f "${profile_env}"; fi
    rm -rf "${tmp_dir}"
    return "${rc}"
  }
  install_path="${manifest_dir}/${install_script}"
  rewrite_packaged_source_profile_install_wrapper_if_needed "${package_root}" "${install_path}" "${scenario_type}"
  rewrite_packaged_multipass_bootstrap_helper_if_needed "${package_root}" "${scenario_type}"
  restore_profile_runtime_state "${profile_name}" "${scenario_dir}"

  case "${action}" in
    install|apply)
      [[ -f "${install_path}" ]] || {
        if [[ "${cleanup_env}" -eq 1 ]]; then rm -f "${profile_env}"; fi
        rm -rf "${tmp_dir}"
        die 4 "profile package install script not found: ${install_script}"
      }
      validate_profile_runtime_inputs "${manifest}" "${profile_env}" "${OVERRIDE_ENV_PATH}"
      warn_if_packaged_profile_uses_embedded_env_only "${profile_name}" "${scenario_type}" "${OVERRIDE_ENV_PATH}" "${manifest}"
      log "INFO" "Executing packaged profile installer: ${install_script}"
      local runtime_env
      runtime_env="$(mktemp)"
      local install_rc=0
      if (
        capture_packaged_profile_runtime_overrides "${runtime_env}"
        source_packaged_profile_env_with_runtime_overrides "${profile_env}" "${runtime_env}"
        cd "${manifest_dir}"
        bash "${install_path}"
      ); then
        install_rc=0
      else
        install_rc=$?
      fi
      rm -f "${runtime_env}"
      (( install_rc == 0 )) || {
        if [[ "${cleanup_env}" -eq 1 ]]; then rm -f "${profile_env}"; fi
        rm -rf "${tmp_dir}"
        return "${install_rc}"
      }
      persist_profile_state "${profile_name}" "${scenario_dir}"
      persist_profile_runtime_state "${profile_name}" "${scenario_dir}"
      ;;
    status)
      validate_profile_runtime_inputs "${manifest}" "${profile_env}" "${OVERRIDE_ENV_PATH}"
      warn_if_packaged_profile_uses_embedded_env_only "${profile_name}" "${scenario_type}" "${OVERRIDE_ENV_PATH}" "${manifest}"
      log "INFO" "Executing packaged profile status via scenario make target"
      run_packaged_profile_make "${package_root}" "${profile_env}" "${scenario_dir}" "status"
      persist_profile_state "${profile_name}" "${scenario_dir}"
      persist_profile_runtime_state "${profile_name}" "${scenario_dir}"
      ;;
    destroy)
      target="$(command_to_target "destroy" "${scenario_type}")" || {
        rm -rf "${tmp_dir}"
        die 2 "unsupported packaged profile command '${action}' for scenario '${scenario_type}'"
      }
      validate_profile_runtime_inputs "${manifest}" "${profile_env}" "${OVERRIDE_ENV_PATH}"
      warn_if_packaged_profile_uses_embedded_env_only "${profile_name}" "${scenario_type}" "${OVERRIDE_ENV_PATH}" "${manifest}"
      log "INFO" "Executing packaged profile destroy via scenario target: ${target}"
      run_packaged_profile_make "${package_root}" "${profile_env}" "${scenario_dir}" "${target}"
      remove_profile_state "${profile_name}"
      ;;
    plan)
      case "${engine_type}" in
        opentofu)
          validate_profile_runtime_inputs "${manifest}" "${profile_env}" "${OVERRIDE_ENV_PATH}"
          warn_if_packaged_profile_uses_embedded_env_only "${profile_name}" "${scenario_type}" "${OVERRIDE_ENV_PATH}" "${manifest}"
          log "INFO" "Executing packaged profile plan through embedded OpenTofu scenario"
          run_opentofu_plan "${scenario_dir}" "${profile_env}"
          persist_profile_runtime_state "${profile_name}" "${scenario_dir}"
          ;;
        ansible|shell)
          target="$(command_to_target "apply" "${scenario_type}")" || {
            rm -rf "${tmp_dir}"
            die 2 "unsupported packaged profile command '${action}' for scenario '${scenario_type}'"
          }
          validate_profile_runtime_inputs "${manifest}" "${profile_env}" "${OVERRIDE_ENV_PATH}"
          warn_if_packaged_profile_uses_embedded_env_only "${profile_name}" "${scenario_type}" "${OVERRIDE_ENV_PATH}" "${manifest}"
          log "INFO" "Executing packaged profile plan via scenario make dry-run"
          run_packaged_profile_make "${package_root}" "${profile_env}" "${scenario_dir}" "${target}" "dry-run"
          ;;
      esac
      ;;
    *)
      rm -rf "${tmp_dir}"
      die 2 "unsupported packaged profile command: ${action}"
      ;;
  esac
  local rc=$?
  if [[ "${cleanup_env}" -eq 1 ]]; then
    rm -f "${profile_env}"
  fi
  rm -rf "${tmp_dir}"
  return "${rc}"
}

run_dev_profile_command() {
  local action="$1"
  [[ -n "${PROFILE_PATH}" ]] || die 3 "the 'dev profile ${action}' command requires --profile-env <file>"
  case "${action}" in
    validate)
      run_validate_profile_only "${PROFILE_PATH}"
      ;;
    export)
      run_profile_export_from_source_profile "${PROFILE_PATH}" "${OUTPUT_PATH}"
      ;;
    plan|apply|destroy|status)
      profile_command_dispatch "${action}" "${PROFILE_PATH}"
      ;;
    *)
      die 2 "unsupported dev profile command: ${action}"
      ;;
  esac
}

if (($# == 0)); then
  usage >&2
  exit 2
fi

PARSED_ARGS=()
while (($# > 0)); do
  case "$1" in
    --profile)
      [[ $# -ge 2 ]] || die 2 "--profile requires a value"
      PROFILE_PATH="$2"
      shift 2
      ;;
    --profile-env)
      [[ $# -ge 2 ]] || die 2 "--profile-env requires a value"
      PROFILE_PATH="$2"
      shift 2
      ;;
    --tgz)
      [[ $# -ge 2 ]] || die 2 "--tgz requires a value"
      TGZ_PATH="$2"
      shift 2
      ;;
    --env-file)
      [[ $# -ge 2 ]] || die 2 "--env-file requires a value"
      OVERRIDE_ENV_PATH="$2"
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || die 2 "--output requires a value"
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --debug)
      GLOBAL_DEBUG=1
      shift
      ;;
    --yes)
      GLOBAL_YES=1
      shift
      ;;
    --dry-run)
      GLOBAL_DRY_RUN=1
      shift
      ;;
    --json)
      GLOBAL_JSON=1
      shift
      ;;
    *)
      PARSED_ARGS+=("$1")
      shift
      ;;
  esac
done
set -- "${PARSED_ARGS[@]}"

if [[ "${GLOBAL_DEBUG}" -eq 1 ]]; then
  set -x
fi

COMMAND="${1:-help}"
RC=0
TELEMETRY_SCENARIO="${PK3S_INFRA_SCENARIO:-}"
if infra_command_emits_telemetry "${1:-help}" "${2:-}"; then
  prepare_telemetry_context
  if [[ -n "${PROFILE_PATH}" && -f "${PROFILE_PATH}" ]]; then
    source_profile "${PROFILE_PATH}"
    TELEMETRY_SCENARIO="${PK3S_INFRA_SCENARIO:-}"
  fi
  if is_truthy "${TELEMETRY_ENABLED:-false}"; then
    write_generic_telemetry_event "infra.command.started" "${COMMAND}" "started" "${TELEMETRY_SCENARIO}"
  fi
fi

case "${COMMAND}" in
  -h|--help|help)
    usage
    ;;
  version)
    if [[ "${GLOBAL_JSON}" -eq 1 ]]; then
      render_bundle_info_json
      exit 0
    fi
    printf '%s\n' "${VERSION}"
    ;;
  bom)
    [[ "${GLOBAL_JSON}" -eq 1 ]] || die 2 "bom requires --json"
    render_bom_json
    ;;
  bundle)
    [[ "${2:-}" == "info" ]] || die 2 "unsupported bundle command: ${2:-}"
    [[ "${GLOBAL_JSON}" -eq 1 ]] || die 2 "bundle info requires --json"
    render_bundle_info_json
    ;;
  doctor)
    run_doctor || RC=$?
    ;;
  list-profiles)
    require_source_surface "list-profiles"
    run_list_profiles || RC=$?
    ;;
  profile)
    case "${2:-}" in
      validate)
        [[ -n "${TGZ_PATH}" ]] || die 3 "the 'profile validate' command requires --tgz <file>"
        run_validate_profile_package "${TGZ_PATH}" || RC=$?
        ;;
      export)
        [[ -n "${TGZ_PATH}" ]] || die 3 "the 'profile export' command requires --tgz <file>"
        run_profile_export_from_tgz "${TGZ_PATH}" "${OUTPUT_PATH}" || RC=$?
        ;;
      install|plan|apply|destroy|status)
        [[ -n "${TGZ_PATH}" ]] || die 3 "the 'profile ${2:-}' command requires --tgz <file>"
        run_install_profile_package "${TGZ_PATH}" "${2:-}" || RC=$?
        ;;
      *)
        die 2 "unsupported profile command: ${2:-}"
        ;;
    esac
    ;;
  dev)
    require_source_surface "dev"
    [[ "${2:-}" == "profile" ]] || die 2 "unsupported dev command: ${2:-}"
    run_dev_profile_command "${3:-}" || RC=$?
    ;;
  validate-profile)
    require_source_surface "${COMMAND}"
    [[ -n "${PROFILE_PATH}" ]] || die 3 "the '${COMMAND}' command requires --profile <file>"
    run_validate_profile_only "${PROFILE_PATH}" || RC=$?
    ;;
  validate|plan|apply|destroy|status)
    require_source_surface "${COMMAND}"
    [[ -n "${PROFILE_PATH}" ]] || die 3 "the '${COMMAND}' command requires --profile <file>"
    profile_command_dispatch "${COMMAND}" "${PROFILE_PATH}" || RC=$?
    ;;
  export)
    require_source_surface "${COMMAND}"
    [[ -n "${PROFILE_PATH}" ]] || die 3 "the '${COMMAND}' command requires --profile <file>"
    run_profile_export_from_source_profile "${PROFILE_PATH}" "${OUTPUT_PATH}" || RC=$?
    ;;
  multipass|onprem|onprem-basic|on-prem|onprem-arm|onprem-basic-arm|on-prem-arm|aws-single-node)
    require_source_surface "${COMMAND}"
    TELEMETRY_SCENARIO="$(resolve_scenario "${COMMAND}")"
    legacy_dispatch "$@" || RC=$?
    ;;
  *)
    die 2 "unsupported command: ${COMMAND}"
    ;;
esac

if infra_command_emits_telemetry "${1:-help}" "${2:-}" && is_truthy "${TELEMETRY_ENABLED:-false}"; then
  if (( RC == 0 )); then
    write_generic_telemetry_event "infra.command.completed" "${COMMAND}" "success" "${TELEMETRY_SCENARIO}"
  else
    write_generic_telemetry_event "infra.command.completed" "${COMMAND}" "failed" "${TELEMETRY_SCENARIO}"
  fi
fi

exit "${RC}"
