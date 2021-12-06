#!/bin/bash
source "test.ssh.init.sh"
#==============================================================================

export ENV_NAME='testing'
do_ssh_add_user_jumper
do_ssh_reset_service

export CD_VERSION_TAG='1.0.x'
export VERSION_BUILDING='1.0.x_13172'
define_common_deploy

#==============================================================================

deploy_env_hook_do() {
  do_print_warn "$(do_stack_trace)"
}
deploy_env_dummy_hook_do() {
  do_print_warn "$(do_stack_trace)"
}
deploy_dummy_alpine_hook_do() {
  do_print_warn "$(do_stack_trace)"
  do_deploy_vault_patch "test.patch.yml"
  do_ssh_export do_print_colorful do_print_warn do_dir_make SERVICE_DEPLOY_DIR
  do_ssh_server_invoke do_dir_clean $'${SERVICE_DEPLOY_DIR}/tmp' make
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
