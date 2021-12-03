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
export CD_VERSION_TAG='1.0.x'
export VERSION_BUILDING='1.0.x_13140'
define_common_deploy
#==============================================================================

deploy_env_hook_do() {
  do_print_warn "$(do_stack_trace)"
  #do_deploy_vault_env "${SERVICE_GROUP:?}/${CUSTOMER:?}-env"
  #do_deploy_vault_env "${SERVICE_NAME:?}/${CUSTOMER:?}-env"
}
deploy_env_dummy_hook_do() {
  do_print_warn "$(do_stack_trace)"
}
deploy_dummy_alpine_patch_hook_do() {
  do_print_warn "$(do_stack_trace)"
  #do_deploy_vault_patch
}
deploy_custom_do() {
  do_deploy_env_down 'dummy'
  do_deploy 'dummy-alpine'
  do_deploy_env_up 'dummy'
}
deploy_custom_do

#==============================================================================
define_common_verify

verify_custom_do() {
  do_verify 'dummy-alpine' 'dummy'
}
verify_custom_do
