#!/bin/bash
set -eo pipefail
source "../.gitlab-ci.lib.sh"

define_common_init
declare -rx OPTION_DEBUG='yes'

#==============================================================================

test_print() {
  do_print_trace do_print_trace 1 2 3
  do_print_info do_print_info 1 2 3
  do_print_warn do_print_warn 1 2 3
  do_print_debug do_print_debug 1 2 3
  do_print_dash_pair HELLO
  do_print_dash_pair HELLO WORLD
  do_print_dash_pair
  do_print_section
  do_print_section HELLO
  do_print_section HELLO WORLD
}

test_diff() {
  do_diff '../temp.diff.old.sh' './test.vault.sh'
  local _status="${?}"
  set -e
  case ${_status} in
  0) do_print_trace "- do_diff returned ${_status} (same)" ;;
  1) do_print_trace "- do_diff returned ${_status} (different)" ;;
  2) do_print_trace "- do_diff returned ${_status} (error)" ;;
  *) do_print_trace "- do_diff returned ${_status} (unknown status)" ;;
  esac
}

shopt -s extglob
test_globbing() {
  printf '%s\n' !(abc)
  echo !(temp-*) | do_here do_print_info "${PWD}/"
}
shopt -u extglob

test_print
test_diff

shopt -s extglob
test_globbing
shopt -u extglob

define_common_build
do_build_ci_info 'temp.env'
