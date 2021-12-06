#!/bin/bash
source "test.ssh.init.sh"
#==============================================================================

do_ssh_add_user_upload
do_ssh_add_user_jumper
do_ssh_reset_service

do_print_hello() {
  do_print_trace "$(do_stack_trace)" "${1}"
}
do_print_hello_alice() {
  for i in "${@}"; do
    do_print_hello "${i}"
  done
  do_print_hello 'alice'
}
_statement="
  $(declare -f do_stack_trace)
  $(declare -f do_print_trace)
  $(declare -f do_print_hello_alice)
  do_print_hello_alice
"

echo '----------------------------------------'
{
  _command="${_statement}"
  printf -v _command '%s\n%s' "$(declare -f do_print_colorful)" "${_command}"
  printf -v _command '%s\n%s' "$(declare -f do_print_info)" "${_command}"
  printf -v _command '%s\n%s' "$(declare -f do_print_hello)" "${_command}"
  (echo "${_command}" | ssh -T "${JUMPER_USER_HOST}" -- /bin/bash -eo pipefail -s -) &
  (echo "${_command}" | ssh -o ConnectTimeout=3 -T "${JUMPER_USER_HOST}" -- \
    ssh -o ConnectTimeout=3 -T "${SERVICE_USER_HOST}" -- /bin/bash -eo pipefail -s -) &
  (eval "${_statement}")
  wait
}
echo '----------------------------------------'
do_ssh_export do_print_colorful do_print_trace do_print_hello
{
  (do_ssh_jumper_exec "${_statement}") &
  (do_ssh_server_exec "${_statement}") &
  (eval "${_statement}")
  wait
}
echo '----------------------------------------'
{
  (do_ssh_jumper_invoke do_print_hello_alice "$(whoami)" 'bob') &
  (do_ssh_server_invoke do_print_hello_alice "$(whoami)" 'carl') &
  (eval do_print_hello_alice "$(whoami)" 'deny')
  wait
}
echo '----------------------------------------'
do_ssh_export_clear

export OPTION_DEBUG='no'
do_ssh_export do_print_colorful do_print_warn do_print_trace
do_ssh_export do_print_hello do_print_hello_alice do_dir_make do_dir_list
do_ssh_exec_here "${UPLOAD_USER_HOST:?}" "${SERVICE_USER_HOST:?}" <<\------
  do_print_hello_alice
  do_dir_make "abc"
  do_dir_list "abc"
  pwd
------
do_ssh_export_clear
