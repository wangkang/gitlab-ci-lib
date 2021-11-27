#!/bin/bash

define_custom_init() {
  init_first_custom_do() {
    do_print_warn "# ${FUNCNAME[*]} TODO ..."
  }
  init_final_custom_do() {
    do_print_warn "# ${FUNCNAME[*]} TODO ..."
  }
}

define_custom_build() {
  build_custom_do() {
    do_print_warn "# ${FUNCNAME[*]} TODO ..."
  }
}

define_custom_upload() {
  upload_custom_do() {
    do_print_warn "# ${FUNCNAME[*]} TODO ..."
  }
}

define_custom_deploy() {
  deploy_custom_do() {
    do_print_warn "# ${FUNCNAME[*]} TODO ..."
  }
}

define_custom_verify() {
  verify_custom_do() {
    do_print_warn "# ${FUNCNAME[*]} TODO ..."
  }
}
