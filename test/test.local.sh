#!/usr/bin/env bash

source "../.gitlab-ci.lib.sh"

set -eo pipefail

define_common_init
declare -rx OPTION_DEBUG='yes'

#==============================================================================

test_print() {
  do_print_trace do_print_trace 1 2 3
  do_print_info  do_print_info  1 2 3
  do_print_warn  do_print_warn  1 2 3
  do_print_debug do_print_debug 1 2 3
  do_print_dash_pair HELLO
  do_print_dash_pair HELLO WORLD
  do_print_dash_pair
  do_print_section
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
  echo "${PWD}/" !(temp*) | do_func_invoke_here do_print_info
}
shopt -u extglob

#==============================================================================

test_print

do_eval_here <<\------
  echo "${PWD}"
  pwd
------
do_print_section do_eval_here

do_func_invoke_here do_print_info 'do_func_invoke_here do_print_info' <<\------
  01 02 03 04 05
  11 12 13 14 15
  21 22 23 24 25
------
do_print_section do_func_invoke_here

shopt -s extglob
test_globbing
shopt -u extglob
do_print_section test_globbing

#test_diff

#define_common_build
#do_build_ci_info 'temp.env'
