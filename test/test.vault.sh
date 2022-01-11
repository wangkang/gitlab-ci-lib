#!/bin/bash
set -eo pipefail
source "../.gitlab-ci.lib.sh"

export CUSTOMER="${VAULT_TEST_CUSTOMER:-missing}"
export ENV_NAME='testing'

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
