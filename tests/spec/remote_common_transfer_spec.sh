# shellcheck shell=bash disable=SC2016
Describe 'remote-cluster transfer and release helpers'
  COMMON="$SHELLSPEC_PROJECT_ROOT/ansible/roles/remote_cluster/files/common.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-remote-common-lib.sh"

  It 'formats remote_exec with ssh args and target'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      SSH_USER=ubuntu
      SSH_PORT=2222
      SSH_KEY_PATH=/tmp/id_ed25519
      SSH_EXTRA_OPTS="-o LogLevel=ERROR"
      ssh() { printf "%s\n" "$*"; }
      remote_exec 10.0.0.10 "echo hello"'
    The status should equal 0
    The output should include 'BatchMode=yes'
    The output should include 'StrictHostKeyChecking=accept-new'
    The output should include 'ConnectTimeout=10'
    The output should include '2222'
    The output should include '/tmp/id_ed25519'
    The output should include 'ubuntu@10.0.0.10'
    The output should include 'bash -lc'
  End

  It 'formats remote_exec_tty with forced tty'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      SSH_USER=ubuntu
      SSH_PORT=22
      ssh() { printf "%s\n" "$*"; }
      remote_exec_tty 10.0.0.11 "hostname"'
    The status should equal 0
    The output should include '-tt'
    The output should include 'ubuntu@10.0.0.11'
  End

  It 'formats scp transfers with ssh options'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      SSH_USER=ubuntu
      SSH_PORT=2200
      SSH_KEY_PATH=/tmp/id_ed25519
      SSH_EXTRA_OPTS="-o LogLevel=ERROR"
      scp() { printf "%s\n" "$*"; }
      scp_to ./bundle.tgz 10.0.0.12 /srv/bundle.tgz'
    The status should equal 0
    The output should include 'BatchMode=yes'
    The output should include 'StrictHostKeyChecking=accept-new'
    The output should include 'ConnectTimeout=10'
    The output should include '2200'
    The output should include '/tmp/id_ed25519'
    The output should include './bundle.tgz'
    The output should include 'ubuntu@10.0.0.12:/srv/bundle.tgz'
  End

  It 'reuses an existing local k3sup binary'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      k3sup() { :; }
      ensure_local_k3sup
      printf "%s" "$K3SUP_BIN"'
    The status should equal 0
    The output should include 'k3sup'
  End

  It 'installs k3sup under the user bin when sudo is unavailable'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      tmpbin="$(mktemp -d)"
      work="$(mktemp -d)"
      home_dir="$(mktemp -d)"
      cat >"${tmpbin}/curl" <<EOF
#!/usr/bin/env bash
cat <<'\''SCRIPT'\'' > k3sup
#!/usr/bin/env bash
echo installed-k3sup
SCRIPT
chmod +x k3sup
EOF
      cat >"${tmpbin}/sudo" <<EOF
#!/usr/bin/env bash
exit 1
EOF
      cat >"${tmpbin}/install" <<EOF
#!/usr/bin/env bash
cp "\$1" "\$2"
EOF
      chmod +x "${tmpbin}/curl" "${tmpbin}/sudo" "${tmpbin}/install"
      export PATH="${tmpbin}:$PATH"
      export HOME="${home_dir}"
      mktemp() { /usr/bin/mktemp -d "${work}/tmp.XXXXXX"; }
      ensure_local_k3sup
      printf "%s|%s" "$K3SUP_BIN" "$PATH"'
    The status should equal 0
    The output should include '/.local/bin/k3sup'
    The output should include '/.local/bin:'
  End

  It 'builds the controller-side k3sup join command'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      SSH_USER=ubuntu
      SSH_PORT=2222
      SSH_KEY_PATH=/tmp/id_ed25519
      log() { :; }
      tmpdir="$(mktemp -d)"
      cmd_log="${tmpdir}/k3sup"
      cat >"${cmd_log}" <<'\''EOF'\''
#!/usr/bin/env bash
printf "%s\n" "$*"
EOF
      chmod +x "${cmd_log}"
      ensure_local_k3sup() { K3SUP_BIN="${cmd_log}"; }
      k3sup_controller_join_agent 10.0.0.20 10.0.0.10 root'
    The status should equal 0
    The output should include 'join'
    The output should include '--ip 10.0.0.20'
    The output should include '--server-ip 10.0.0.10'
    The output should include '--server-user root'
    The output should include '--ssh-key /tmp/id_ed25519'
    The output should include '--ssh-port 2222'
  End

  It 'resolves release tags from explicit versions and local mode'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      PRODUCTIVE_K3S_SOURCE=remote
      PRODUCTIVE_K3S_VERSION=v0.9.1
      printf "%s|" "$(resolve_productive_k3s_release_tag)"
      PRODUCTIVE_K3S_SOURCE=local
      PRODUCTIVE_K3S_VERSION=""
      printf "%s" "$(resolve_productive_k3s_release_tag)"'
    The status should equal 0
    The output should equal '0.9.1|local'
  End

  It 'downloads and validates a productive-k3s remote bundle'
    When run /usr/bin/bash "$RUNNER" "$COMMON" '
      tmpdir="$(mktemp -d)"
      destination="${tmpdir}/bundle.tgz"
      PRODUCTIVE_K3S_RELEASE_REPO=productive-k3s/productive-k3s-core
      productive_k3s_release_json() {
        cat <<EOF
{"assets":[
  {"name":"productive-k3s-core-0.9.1.tar.gz","browser_download_url":"https://example.test/bundle.tgz"},
  {"name":"productive-k3s-core-0.9.1.tar.gz.sha256","browser_download_url":"https://example.test/bundle.tgz.sha256"}
]}
EOF
      }
      curl() {
        if [[ "$2" == "https://example.test/bundle.tgz" ]]; then
          printf "bundle" >"$4"
        else
          printf "abc123  %s\n" "${destination}" >"$4"
        fi
      }
      sha256sum() { printf "%s\n" "bundle checksum ok"; }
      validate_productive_k3s_bundle_archive() { printf "validated:%s" "$1"; }
      download_productive_k3s_release_bundle "${destination}" 0.9.1'
    The status should equal 0
    The output should include 'Downloading productive-k3s-core release 0.9.1 from productive-k3s/productive-k3s-core'
    The output should include 'bundle checksum ok'
    The output should include 'validated:'
  End
End
