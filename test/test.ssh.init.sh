#!/bin/bash
set -eo pipefail
source "../.gitlab-ci.lib.sh"

export OPTION_DEBUG='no'
export CUSTOMER="${VAULT_TEST_CUSTOMER:-missing}"
export ENV_NAME='testing'
export CI_PROJECT_NAME='dummy-service'
define_common_init
define_common_init_ssh
init_ssh_do
