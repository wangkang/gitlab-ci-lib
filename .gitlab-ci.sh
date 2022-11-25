#!/bin/bash

define_custom_init() {
  init_first_custom_do() {
    do_print_warn "$(do_stack_trace)" 'TODO ...'
  }
  init_final_custom_do() {
    do_print_warn "$(do_stack_trace)" 'TODO ...'
    env
  }
}

define_custom_build() {
  build_custom_do() {
    do_print_warn "$(do_stack_trace)" 'TODO ...'
  }
}

define_custom_upload() {
  upload_custom_do() {
    do_print_warn "$(do_stack_trace)" 'TODO ...'
  }
}

define_custom_deploy() {
  deploy_custom_do() {
    do_print_warn "$(do_stack_trace)" 'TODO ...'
  }
}

define_custom_verify() {
  verify_custom_do() {
    do_print_warn "$(do_stack_trace)" 'TODO ...'
  }
}
