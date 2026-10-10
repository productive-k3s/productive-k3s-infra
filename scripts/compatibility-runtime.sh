#!/usr/bin/env bash

pk3s_normalize_semver() {
  printf '%s\n' "${1#v}"
}

pk3s_semver_is_valid() {
  local version
  version="$(pk3s_normalize_semver "${1:-}")"
  [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

pk3s_semver_gte() {
  local left right
  left="$(pk3s_normalize_semver "$1")"
  right="$(pk3s_normalize_semver "$2")"
  [[ "$(printf '%s\n%s\n' "${right}" "${left}" | sort -V | head -n1)" == "${right}" ]]
}

pk3s_semver_lt() {
  local left right
  left="$(pk3s_normalize_semver "$1")"
  right="$(pk3s_normalize_semver "$2")"
  [[ "${left}" != "${right}" ]] && [[ "$(printf '%s\n%s\n' "${left}" "${right}" | sort -V | head -n1)" == "${left}" ]]
}

pk3s_profile_compatibility_value() {
  local manifest="$1"
  local owner="$2"
  local key="$3"
  awk -v owner="${owner}" -v key="${key}" '
    /^spec:/ { in_spec=1; next }
    in_spec && /^  compatibility:/ { in_compat=1; next }
    in_compat && /^    requires:/ { in_requires=1; next }
    in_requires && $0 == "      " owner ":" { in_owner=1; next }
    in_owner && $0 ~ "^        " key ":" { print; exit }
    in_owner && /^      [^[:space:]]/ { exit }
  ' "${manifest}"
}

pk3s_resolve_infra_engine_version() {
  local composite="${PRODUCTIVE_K3S_INFRA_VERSION:-${VERSION:-}}"
  if [[ -n "${PK3S_INFRA_SEMVER:-}" ]]; then
    printf '%s\n' "${PK3S_INFRA_SEMVER}"
  elif [[ "${composite}" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)-v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    printf '%s\n' "${PRODUCTIVE_K3S_INFRA_ENGINE_VERSION:-${composite}}"
  fi
}

pk3s_resolve_bound_core_version() {
  local composite="${PRODUCTIVE_K3S_INFRA_VERSION:-${VERSION:-}}"
  if [[ -n "${PK3S_CORE_SEMVER:-}" ]]; then
    printf '%s\n' "${PK3S_CORE_SEMVER}"
  elif [[ "${composite}" =~ ^v?([0-9]+\.[0-9]+\.[0-9]+)-v?([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
  else
    printf '%s\n' "${PRODUCTIVE_K3S_VERSION:-${PRODUCTIVE_K3S_CORE_VERSION:-}}"
  fi
}

pk3s_validate_version_window() {
  local subject="$1" artifact_version="$2" runtime_name="$3" running_version="$4" min_version="$5" max_version="$6"
  if ! pk3s_semver_is_valid "${min_version}" || ! pk3s_semver_is_valid "${max_version}" || ! pk3s_semver_lt "${min_version}" "${max_version}"; then
    printf 'profile %s %s is incompatible: invalid %s version window [%s, %s)\n' \
      "${subject}" "${artifact_version}" "${runtime_name}" "${min_version:-missing}" "${max_version:-missing}" >&2
    return 4
  fi
  if ! pk3s_semver_is_valid "${running_version}"; then
    printf 'profile %s %s is incompatible: running %s version is not comparable: %s\n' \
      "${subject}" "${artifact_version}" "${runtime_name}" "${running_version:-unknown}" >&2
    return 4
  fi
  if ! pk3s_semver_gte "${running_version}" "${min_version}" || ! pk3s_semver_lt "${running_version}" "${max_version}"; then
    printf 'profile %s %s is incompatible: requires %s >=%s and <%s; running %s %s\n' \
      "${subject}" "${artifact_version}" "${runtime_name}" "${min_version}" "${max_version}" "${runtime_name}" "${running_version}" >&2
    printf 'upgrade Infra/Core or select an older compatible profile version\n' >&2
    return 4
  fi
}

pk3s_validate_profile_compatibility() {
  local manifest="$1" profile_name="$2" profile_version="$3"
  local contract infra_min infra_max core_min core_max running_infra running_core
  contract="$(trim_yaml_value "$(pk3s_profile_compatibility_value "${manifest}" infra contract)")"
  infra_min="$(trim_yaml_value "$(pk3s_profile_compatibility_value "${manifest}" infra minEngineVersion)")"
  infra_max="$(trim_yaml_value "$(pk3s_profile_compatibility_value "${manifest}" infra maxEngineVersionExclusive)")"
  core_min="$(trim_yaml_value "$(pk3s_profile_compatibility_value "${manifest}" core minVersion)")"
  core_max="$(trim_yaml_value "$(pk3s_profile_compatibility_value "${manifest}" core maxVersionExclusive)")"
  running_infra="$(pk3s_resolve_infra_engine_version)"
  running_core="$(pk3s_resolve_bound_core_version)"

  [[ "${contract}" == "profile/v1" ]] || {
    printf 'profile %s %s is incompatible: requires supported Infra contract profile/v1; declared %s\n' \
      "${profile_name}" "${profile_version}" "${contract:-missing}" >&2
    return 4
  }
  pk3s_validate_version_window "${profile_name}" "${profile_version}" Infra "${running_infra}" "${infra_min}" "${infra_max}" || return $?
  pk3s_validate_version_window "${profile_name}" "${profile_version}" Core "${running_core}" "${core_min}" "${core_max}"
}
