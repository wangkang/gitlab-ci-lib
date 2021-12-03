#!/bin/bash
set -eo pipefail
source "../.gitlab-ci.lib.sh"

#==============================================================================
export CUSTOMER='customer'
export ENV_NAME='testing'
export VAULT_URL_GITLAB="${VAULT_URL:?}/gitlab/dummy-service/${CUSTOMER}"
define_common_init
define_common_init_ssh
#==============================================================================
init_ssh_do
do_ssh_add_user_upload
#==============================================================================
export OPTION_DEBUG='no'
export CD_VERSION_TAG='0'
export CI_PROJECT_DIR="${PWD}"
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
