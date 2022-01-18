#!/bin/bash
set -eo pipefail

export CUSTOMER="${VAULT_TEST_CUSTOMER:-missing}"
export ENV_NAME='testing'

test_vault_gitlab_ci_lib() {
  echo '# ----- test_vault_gitlab_ci_lib -----'
  define_common_init
  define_util_vault
  do_vault_service_env_file 'dummy-env'
  do_vault_service_patch_file 'dummy-alpine-etc' 'config.yml'
  export CI_PROJECT_NAME='dummy-service'
  export OPTION_DEBUG='yes'
  init_inject_env_bash_do
  init_inject_ci_bash_do
  init_inject_cd_bash_do
  export OPTION_DEBUG='no'
}
. "../.gitlab-ci.lib.sh"
test_vault_gitlab_ci_lib

test_vault_injection() {
  echo '# ----- test_vault_injection begin -----'
  echo '# ----- do_vault_login -----'
  # shellcheck disable=SC2155
  export VAULT_TOKEN="$(do_vault_login)"
  [ -z "${VAULT_TOKEN}" ] && exit 0
  echo '# ----- do_vault_fetch -----'
  do_vault_fetch "dummy-env"
  # Do not reuse VAULT_TOKEN: VAULT_TOKEN=''
  echo '# ----- do_vault_export -----'
  do_vault_export "dummy-env"
  echo '# ----- test_vault_injection end -----'
}
export VAULT_PATH="${CUSTOMER}-${ENV_NAME}/data/service"
. "../util/vault-injection.sh"
test_vault_injection
