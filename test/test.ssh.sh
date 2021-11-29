#!/bin/bash
set -eo pipefail
source "../.gitlab-ci.lib.sh"

#==============================================================================
export VAULT_URL_GITLAB="${VAULT_URL:?}/gitlab/dummy-service/customer"
define_common_init
#==============================================================================
define_common_init_ssh
init_ssh_do
do_ssh_add_user_upload
do_ssh_add_user_jumper
do_ssh_reset_service
declare -rx OPTION_DEBUG='no'
#==============================================================================

do_print_hello() {
  do_print_info "$(whoami)@$(hostname):" "${1}"
}
do_print_hello_alice() {
  for i in "${@}"; do
    do_print_hello "${i}"
  done
  do_print_hello 'alice'
}

do_ssh_export do_print_info
do_ssh_export do_print_hello

_statement="
  $(declare -f do_print_hello_alice)
  do_print_hello_alice
"

echo '----------------------------------------'
{
  _command="${_statement}"
  printf -v _command '%s\n%s' "$(declare -f do_print_info)" "${_command}"
  printf -v _command '%s\n%s' "$(declare -f do_print_hello)" "${_command}"
  (echo "${_command}" | ssh -T "${JUMPER_USER_HOST}" -- /bin/bash -eo pipefail -s -) &
  (echo "${_command}" | ssh -o ConnectTimeout=3 -T "${JUMPER_USER_HOST}" -- \
    ssh -o ConnectTimeout=3 -T "${SERVICE_USER_HOST}" -- /bin/bash -eo pipefail -s -) &
  (eval "${_statement}")
  wait
}
echo '----------------------------------------'
{
  (do_exec_on_jumper "${_statement}") &
  (do_exec_on_server "${_statement}") &
  (eval "${_statement}")
  wait
}
echo '----------------------------------------'
{
  (do_invoke_on_jumper do_print_hello_alice "$(whoami)" 'bob') &
  (do_invoke_on_server do_print_hello_alice "$(whoami)" 'carl') &
  (eval do_print_hello_alice "$(whoami)" 'deny')
  wait
}
echo '----------------------------------------'

do_ssh_export_clear

do_ssh_export do_print_warn
do_ssh_export do_dir_make
do_ssh_export do_dir_clean

do_here do_ssh_exec_upload <<\-----
  do_dir_clean abc
  do_dir_make  abc
  pwd
  echo "$(whoami)"
-----
