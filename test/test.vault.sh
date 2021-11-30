#!/bin/bash
set -eo pipefail

#==============================================================================
export VAULT_URL_GITLAB="${VAULT_URL:?}/gitlab/dummy-service/customer"
source "../.gitlab-ci.lib.sh"
define_common_init
define_common_init_ssh
init_ssh_do
#==============================================================================
init_inject_ci_bash_do
init_inject_cd_bash_do
do_ssh_add_user_jumper
do_ssh_reset_service
export OPTION_DEBUG='no'
#==============================================================================

test_invoke() {
  local _func_name="${1:?}"
  do_print_info "# ${1} \$2_${2}"
  eval "${@}"
}
test_func() {
  local _func_name="${1:?}"
  local _url="${VAULT_URL_GITLAB}-secret"
  (test_invoke do_ssh_jumper_invoke "${_func_name}" "${_url}" "${VAULT_TOKEN:?}" "${*:2}") &
  (test_invoke do_ssh_server_invoke "${_func_name}" "${_url}" "${VAULT_TOKEN:?}" "${*:2}") &
  (test_invoke "${_func_name}" "${_url}" "${VAULT_TOKEN:?}" "${*:2}")
  wait
}
{
  do_ssh_export do_vault_check
  do_ssh_export do_vault_fetch_local

  test_func do_vault_fetch_bash_env_local
  test_func do_vault_fetch_env_file_local
  test_func do_vault_fetch_with_key_local 'ESCAPE_HELL'
}
