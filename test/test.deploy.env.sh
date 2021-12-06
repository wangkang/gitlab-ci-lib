#!/bin/bash
source "test.ssh.init.sh"
#==============================================================================

export ENV_NAME='testing'
do_ssh_add_user_jumper
do_ssh_reset_service

define_common_deploy_env

deploy_env_hook_do() {
  do_print_info "$(do_stack_trace)"
  do_print_info "HELLO: [${HELLO1}]"
  do_print_info "HELLO: [${HELLO2}]"
  do_file_replace "${_compose_env_new:?}" HELLO1 HELLO2
}

deploy_env_dummy_hook_do() {
  do_print_info "$(do_stack_trace)"
  do_print_info "$(pwd)"
}

declare -rx HELLO1='hello1'
declare -rx HELLO2='hello2'
declare -arx DEPLOY_ENV_HOOK_EXPORT=(HELLO1 HELLO2)
do_deploy_env_down 'dummy'
do_deploy_env_up 'dummy'
