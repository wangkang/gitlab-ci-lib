#!/bin/bash
set -eo pipefail
source "../.gitlab-ci.lib.sh"

define_common_init
declare -rx OPTION_DEBUG='yes'

#==============================================================================

do_print_trace do_print_trace 1 2 3
do_print_info do_print_info 1 2 3
do_print_warn do_print_warn 1 2 3
do_print_debug do_print_debug 1 2 3
do_print_dash_pair
do_print_dash_pair HELLO
do_print_dash_pair HELLO WORLD
do_print_section
do_print_section HELLO
do_print_section HELLO WORLD
