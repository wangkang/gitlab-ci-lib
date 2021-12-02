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
do_ssh_add_user_jumper
do_ssh_reset_service
#==============================================================================
export OPTION_DEBUG='no'
define_common_deploy_env

deploy_env_hook_do() {
  do_print_info "$(do_stack_trace)"
  do_print_info "$(pwd)"
}

deploy_env_dummy_hook_do() {
  do_print_info "$(do_stack_trace)"
  do_print_info "$(pwd)"
}

do_deploy_env_down 'dummy'
do_deploy_env_up 'dummy'
