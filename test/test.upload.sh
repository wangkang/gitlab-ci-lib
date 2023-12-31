#!/bin/bash
source "test.ssh.init.sh"
#==============================================================================

export CD_VERSION_TAG='0'
export CI_PROJECT_DIR="${PWD}"

do_ssh_add_user_upload
define_common_upload

upload_custom_do() {
  do_print_info "$(do_stack_trace)"
  do_upload_cleanup_local
  upload_dummy_env
  upload_dummy_alpine
}

upload_dummy_env() {
  local _dir="${RUNNER_LOCAL_DIR:?}"
  do_dir_make "${_dir}"
  echo "hello" >"${_dir}/temp.txt"
  do_upload_env 'dummy'
}

upload_dummy_alpine() {
  local _dir="${RUNNER_LOCAL_DIR:?}/etc"
  do_dir_make "${_dir}"
  echo "hello" >"${_dir}/temp.txt"
  do_upload 'dummy-alpine' 'dummy'
}

upload_custom_do
