#!/usr/bin/env bash

pk3s_env_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

pk3s_env_decode_value() {
  local raw="$1"
  local source_path="$2"
  local line_number="$3"
  local value

  value="$(pk3s_env_trim "${raw}")"
  if [[ "${value}" == \$\(* || "${value}" == *\`* || "${value}" == \<\(* || "${value}" == \>\(* ]]; then
    printf 'unsafe executable syntax in env file %s at line %s\n' "${source_path}" "${line_number}" >&2
    return 1
  fi

  if [[ "${value}" == \"* || "${value}" == \'* ]]; then
    local quote="${value:0:1}"
    [[ ${#value} -ge 2 && "${value: -1}" == "${quote}" ]] || {
      printf 'unterminated quoted value in env file %s at line %s\n' "${source_path}" "${line_number}" >&2
      return 1
    }
    value="${value:1:${#value}-2}"
  else
    local decoded="" index char
    for ((index = 0; index < ${#value}; index++)); do
      char="${value:index:1}"
      if [[ "${char}" == "\\" && $((index + 1)) -lt ${#value} ]]; then
        index=$((index + 1))
        decoded+="${value:index:1}"
      else
        decoded+="${char}"
      fi
    done
    value="${decoded}"
  fi

  case "${value}" in
    '$HOME') value="${HOME}" ;;
    '$HOME/'*) value="${HOME}/${value#\$HOME/}" ;;
    '${HOME}') value="${HOME}" ;;
    '${HOME}/'*) value="${HOME}/${value#\$\{HOME\}/}" ;;
  esac

  printf '%s' "${value}"
}

pk3s_env_load_file() {
  local source_path="$1"
  local line line_number=0 key raw value

  [[ -f "${source_path}" ]] || {
    printf 'env file not found: %s\n' "${source_path}" >&2
    return 1
  }

  while IFS= read -r line || [[ -n "${line}" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"
    line="$(pk3s_env_trim "${line}")"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    if [[ "${line}" == export[[:space:]]* ]]; then
      line="$(pk3s_env_trim "${line#export}")"
    fi
    [[ "${line}" == *=* ]] || {
      printf 'expected KEY=VALUE in env file %s at line %s\n' "${source_path}" "${line_number}" >&2
      return 1
    }
    key="$(pk3s_env_trim "${line%%=*}")"
    raw="${line#*=}"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
      printf 'invalid variable name in env file %s at line %s: %s\n' "${source_path}" "${line_number}" "${key}" >&2
      return 1
    }
    value="$(pk3s_env_decode_value "${raw}" "${source_path}" "${line_number}")" || return $?
    printf -v "${key}" '%s' "${value}"
    export "${key}"
  done < "${source_path}"
}

pk3s_env_normalize_files() {
  local target_path="$1"
  shift
  local source_path line line_number key raw value
  local -a keys=()
  local -A values=()
  local -A seen=()

  for source_path in "$@"; do
    [[ -f "${source_path}" ]] || {
      printf 'env file not found: %s\n' "${source_path}" >&2
      return 1
    }
    line_number=0
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line_number=$((line_number + 1))
      line="${line%$'\r'}"
      line="$(pk3s_env_trim "${line}")"
      [[ -z "${line}" || "${line}" == \#* ]] && continue
      if [[ "${line}" == export[[:space:]]* ]]; then
        line="$(pk3s_env_trim "${line#export}")"
      fi
      [[ "${line}" == *=* ]] || {
        printf 'expected KEY=VALUE in env file %s at line %s\n' "${source_path}" "${line_number}" >&2
        return 1
      }
      key="$(pk3s_env_trim "${line%%=*}")"
      raw="${line#*=}"
      [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
        printf 'invalid variable name in env file %s at line %s: %s\n' "${source_path}" "${line_number}" "${key}" >&2
        return 1
      }
      value="$(pk3s_env_decode_value "${raw}" "${source_path}" "${line_number}")" || return $?
      if [[ -z "${seen[${key}]+x}" ]]; then
        keys+=("${key}")
        seen["${key}"]=1
      fi
      values["${key}"]="${value}"
    done < "${source_path}"
  done

  : > "${target_path}"
  chmod 600 "${target_path}"
  for key in "${keys[@]}"; do
    printf 'export %s=%q\n' "${key}" "${values[${key}]}" >> "${target_path}"
  done
}
