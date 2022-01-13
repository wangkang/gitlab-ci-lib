#!/bin/bash

set -eo pipefail

#===============================================================================

define_util_core() {
  do_nothing() { :; }
  do_stack_trace() {
    printf '%s --> %s' "$(whoami)@$(hostname)" "$(echo -n "${FUNCNAME[*]:1} " | tac -s ' ')"
  }
  do_here() {
    local _func_name="${1}"
    local _input
    _input="$(timeout 2s cat /dev/stdin || true)"
    _input=$(printf '%s' "${_input}" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')
    do_func_invoke "${_func_name:?}" "${*:2}" "${_input}"
  }
  do_func_invoke() {
    local _func_name="${1}"
    if [ "$(type -t "${_func_name:?}")" != function ]; then
      do_print_trace "# $_func_name is an absent function"
    else eval "${@}"; fi
  }
  do_dir_list() {
    do_print_trace "$(do_stack_trace)" "$(date +'%T')"
    local _dir="${1}"
    [ ! -d "${_dir:?}" ] && { return; }
    find "${_dir}" -type f -exec ls -lhA {} +
  }
  do_dir_make() {
    local _dir="${1}"
    [ -d "${_dir:?}" ] && return
    local _mode="${2:-700}"
    local _hint
    if ! _hint=$(mkdir -p "${_dir}" && chmod "${_mode}" "${_dir}" 2>&1); then
      do_print_warn "$(do_stack_trace) $ mkdir -p ${_dir}"
      do_print_warn "${_hint}"
    fi
  }
  do_dir_clean() {
    local _dir="${1}"
    local _make="${2}"
    local _hint
    [ ! -d "${_dir:?}" ] && {
      if [ 'make' = "${_make}" ]; then
        do_dir_make "${_dir}" "${@:3}"
      else return; fi
    }
    if ! _hint=$(rm -rf "${_dir:?}/"* 2>&1); then
      do_print_warn "$(do_stack_trace) $ rm -rf \"${_dir}/\"*"
      do_print_warn "${_hint}"
      do_print_warn "$(find "${_dir}" -type f -exec ls -lhA {} +)"
    fi
  }
  do_dir_chmod() {
    do_print_trace "$(do_stack_trace)"
    local _dir="${1}"
    [ ! -d "${_dir:?}" ] && return
    cd "${_dir}"
    [ -d "./bin" ] && chmod 700 "./bin/"*
    [ -d "./env" ] && chmod 600 "./env/"*
    [ -d "./etc" ] && chmod 600 "./etc/"*
    [ -d "./lib" ] && chmod 600 "./lib/"*
    [ -d "./log" ] && chmod 640 "./log/"*
    [ -d "./log" ] && chmod 750 "./log"
    [ -d "./tmp" ] && chmod 750 "./tmp"
    [ -d "./native" ] && chmod 600 "./native/"*
    chmod o-r,o-w,o-x,g-w './'*
  }
  do_dir_scp() {
    local _local_dir="${1}"
    local _remote_dir="${2}"
    local _user_host="${3}"
    local _hook_do="${4}"
    do_ssh_export_clear
    do_ssh_export do_print_trace do_print_warn do_print_colorful
    do_ssh_invoke "$(do_ssh_exec_chain "${_user_host:?}")" do_dir_make "'${_remote_dir}'"
    local _status="${?}"
    [ ! ${_status} ] && return ${_status}
    do_dir_list "${_local_dir:?}"
    if ! scp -rpC -o StrictHostKeyChecking=no "${_local_dir}/"* "${_user_host}:${_remote_dir:?}/"; then
      do_print_warn "scp to ${_user_host}:${_remote_dir:?}/ failed"
      return 9
    else
      do_print_trace "scp to ${_user_host} (ok)" "$(date +'%T')"
      if [ "$(type -t "${_hook_do}")" = function ]; then
        do_ssh_export_clear
        do_ssh_export do_print_trace do_print_colorful do_dir_list do_dir_chmod _remote_dir
        do_ssh_invoke "$(do_ssh_exec_chain "${_user_host:?}")" "${_hook_do}" "${*:5}"
        do_ssh_export_clear
      fi
      local _status="${?}"
      [ ! ${_status} ] && return ${_status}
    fi
    do_ssh_export_clear
  }
  do_diff() {
    printf "\033[0;34m%s\033[0m\n" "# ${FUNCNAME[0]} '${1:?}' '${2:?}'"
    [ ! -f "${1}" ] && touch "${1}" && chmod 600 "${1}" && ls -lh "${1}"
    local _status
    set +e +o pipefail
    diff --unchanged-line-format='' \
      --old-line-format="- |%2dn| %L" \
      --new-line-format="+ |%2dn| %L" "${1}" "${2}" |
      awk 'BEGIN{FIELDWIDTHS="1"} { if ($1 == "+") {
      printf "\033[0;32m%s\033[0m\n", $0 } else {
      printf "\033[0;31m%s\033[0m\n", $0 } }'
    _status=${PIPESTATUS[0]}
    set -o pipefail
    return "${_status}"
  }
  do_file_replace() {
    local _path="${1}"
    [ ! -f "${_path:?}" ] && {
      echo "$(do_stack_trace): Not a file '${_path:?}'" >&2
      return
    }
    for name in "${@:2}"; do
      sed -i -e "s|#${name}|${!name}|g" "${_path}"
    done
  }
  do_write_file() {
    local _path="${1}"
    local _file_content="${2}"
    [ ! -f "${_path:?}" ] && touch "${_path}" && chmod 660 "${_path}"
    ls -lh "${_path}"
    printf '%s\n' "${_file_content:?}" >"${_path}"
    ls -lh "${_path}"
  }
  do_write_log_file() {
    do_print_trace "$(do_stack_trace)"
    local _path="${1}"
    local _line="${*:2}"
    _line="[$(date +'%Y-%m-%d %T %Z')] ${_line:?}"
    [ ! -f "${_path:?}" ] && touch "${_path}" && chmod 640 "${_path}"
    echo "${_line}" >>"${_path}"
    tail -3 "${_path}"
    local _lines
    _lines=$(wc -l <"${_path}" | xargs)
    [ "${_lines}" -gt 220 ] && tail -200 "${_path}" >"${_path}.tmp" &&
      mv -f "${_path}.tmp" "${_path}"
  }
}

declare -ax SSH_EXPORT_FUN=()
declare -ax SSH_EXPORT_VAR=()

define_util_ssh() {
  do_ssh_export_clear() {
    SSH_EXPORT_FUN=(do_stack_trace do_print_debug)
    SSH_EXPORT_VAR=(SSH_EXPORT_VAR SSH_EXPORT_FUN)
  }
  do_ssh_export_clear
  do_ssh_export() {
    for i in "${@}"; do
      local _name="${i}"
      if [ "$(type -t "${_name}")" = 'function' ]; then
        if [[ "${SSH_EXPORT_FUN[*]}" =~ ${_name} ]]; then return; fi
        SSH_EXPORT_FUN+=("${_name}")
      else
        if [ -z "${!_name}" ]; then
          echo "## $(do_stack_trace) : not a function/variable name '${_name}'" >&2
          continue
        else
          if [[ "${SSH_EXPORT_VAR[*]}" =~ ${_name} ]]; then return; fi
          SSH_EXPORT_VAR+=("${_name}")
        fi
      fi
    done
  }
  do_ssh_invoke() {
    local _ssh="${1}"
    local _func_name="${2}"
    do_ssh_export "${_func_name:?}"
    do_ssh_exec "${_ssh:?}" "${@:2}"
  }
  do_ssh_exec_chain() {
    if [ 1 -gt ${#@} ]; then return; fi
    local _ssh='ssh -o ConnectTimeout=3 -T'
    local _chain
    printf -v _chain '%s %s' "${_ssh}" "${1:?}"
    for i in "${@:2}"; do
      printf -v _chain '%s -- %s %s' "${_chain}" "${_ssh}" "${i}"
    done
    printf '%s' "${_chain}"
  }
  do_ssh_exec() {
    local _ssh="${1}"
    local _command="${*:2}"
    if [ -n "${OPTION_DEBUG}" ]; then
      printf -v _command '%s\n%s' "$(declare -p OPTION_DEBUG)" "${_command}"
    fi
    for i in "${SSH_EXPORT_VAR[@]}"; do
      printf -v _command '%s\n%s' "$(declare -p "${i}")" "${_command}"
    done
    for i in "${SSH_EXPORT_FUN[@]}"; do
      printf -v _command '%s\n%s' "$(declare -f "${i}")" "${_command}"
    done
    do_print_debug "${_command} | ${_ssh:?} -- /bin/bash -eo pipefail -s -"
    set +e
    /bin/echo "${_command}" | ${_ssh} -- /bin/bash -eo pipefail -s -
  }
  do_ssh_exec_here() {
    _ssh="$(do_ssh_exec_chain "${@}")"
    _input="$(timeout 2s cat /dev/stdin || true)"
    _input=$(printf '%s' "${_input}" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "${_input}" ]; then
      _input=$(printf '%s\n%s' "## From stdin (here documents ...)" "${_input}")
      do_ssh_exec "${_ssh}" "${_input}"
    else
      printf '%s %s\n' "Empty stdin, canceled." "$(echo -n "${FUNCNAME[*]} " | tac -s ' ')" >&2
    fi
  }
  do_ssh_add_user_default() {
    eval "$(_ssh_user_declare)"
    ARG_SSH_USER="${SSH_USER}"
    ARG_SSH_HOST="${SSH_HOST}"
    ARG_SSH_KNOWN_HOSTS="${SSH_KNOWN_HOSTS}"
    ARG_SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY}"
    do_ssh_add_user
    SSH_USER_HOST="${SSH_USER}@${SSH_HOST}"
  }
  do_ssh_add_user_upload() {
    eval "$(_ssh_user_declare)"
    eval "$(_ssh_user_declare 'UPLOAD')"
    ARG_SSH_USER="${UPLOAD_SSH_USER:=${SSH_USER:?}}"
    ARG_SSH_PRIVATE_KEY="${UPLOAD_SSH_PRIVATE_KEY:=${SSH_PRIVATE_KEY}}"
    ARG_SSH_HOST="${UPLOAD_SSH_HOST:=${JUMPER_SSH_HOST:-${SSH_HOST:?}}}"
    ARG_SSH_KNOWN_HOSTS="${UPLOAD_SSH_KNOWN_HOSTS:=${JUMPER_SSH_KNOWN_HOSTS:-${SSH_KNOWN_HOSTS}}}"
    do_ssh_add_user
    UPLOAD_USER="${UPLOAD_SSH_USER}"
    UPLOAD_USER_HOST="${UPLOAD_USER}@${UPLOAD_SSH_HOST}"
  }
  do_ssh_add_user_jumper() {
    eval "$(_ssh_user_declare)"
    eval "$(_ssh_user_declare 'UPLOAD')"
    eval "$(_ssh_user_declare 'DEPLOY')"
    ARG_SSH_USER="${DEPLOY_SSH_USER:=${UPLOAD_SSH_USER:=${SSH_USER:?}}}"
    ARG_SSH_PRIVATE_KEY="${DEPLOY_SSH_PRIVATE_KEY:-${UPLOAD_SSH_PRIVATE_KEY:-${SSH_PRIVATE_KEY}}}"
    ARG_SSH_HOST="${JUMPER_SSH_HOST:=${SSH_HOST:?}}"
    ARG_SSH_KNOWN_HOSTS="${JUMPER_SSH_KNOWN_HOSTS:=${SSH_KNOWN_HOSTS}}"
    do_ssh_add_user
    UPLOAD_USER="${UPLOAD_SSH_USER:-${ARG_SSH_USER}}"
    JUMPER_USER_HOST="${DEPLOY_SSH_USER}@${JUMPER_SSH_HOST}"
  }
  do_ssh_agent_init() {
    do_print_info "$(do_stack_trace)"
    if [ -z "$(command -v ssh-agent)" ]; then
      do_print_warn 'Error: ssh-agent is not installed'
      exit 120
    fi
    if [ -z "$(command -v ssh-add)" ]; then
      do_print_warn 'Error: ssh-add is not installed'
      exit 120
    fi
    set +e
    eval "$(ssh-agent -s)" &>/dev/null
    do_print_info "- ssh-agent status code ${?}"
    set -e
    mkdir -p ~/.ssh
    touch ~/.ssh/known_hosts
    chmod 644 ~/'.ssh/known_hosts'
    chmod 700 ~/'.ssh'
  }
  do_ssh_add_user() {
    do_print_info "$(do_stack_trace)"
    local _user_host="${ARG_SSH_USER}@${ARG_SSH_HOST}"
    if [ -z "${ARG_SSH_USER}" ]; then
      do_print_info 'SSH ADD USER ABORT (ARG_SSH_USER is absent)'
      return
    fi
    if [ -z "${ARG_SSH_HOST}" ]; then
      do_print_info 'SSH ADD USER ABORT (ARG_SSH_HOST is absent)'
      return
    fi
    if [ "$_user_host" = "${SSH_USER_HOST}" ]; then
      do_print_info "SSH ADD USER OK (${_user_host} is default user)"
      return
    fi
    if [[ "${ADDED_USER_HOST[*]}" =~ ${_user_host} ]]; then
      do_print_info "SSH ADD USER OK (${_user_host} has already been added)"
      return
    fi
    do_print_info "SSH ADD USER [${_user_host}]"
    do_print_dash_pair 'SSH_USER_HOST' "${_user_host}"
    [ -n "${ARG_SSH_KNOWN_HOSTS}" ] && do_print_dash_pair 'SSH_KNOWN_HOSTS' "${ARG_SSH_KNOWN_HOSTS:0:60}**"
    [ -n "${ARG_SSH_PRIVATE_KEY}" ] && {
      local _pri_line
      _pri_line=$(echo "${ARG_SSH_PRIVATE_KEY}" | tr -d '\n')
      do_print_dash_pair 'SSH_PRIVATE_KEY' "${_pri_line:0:60}**"
    }
    [ -n "${ARG_SSH_KNOWN_HOSTS}" ] && _ssh_add_known "${ARG_SSH_KNOWN_HOSTS}"
    [ -n "${ARG_SSH_PRIVATE_KEY}" ] && _ssh_add_key "${ARG_SSH_PRIVATE_KEY}"
    local _uid='-1'
    local _ssh="ssh -o ConnectTimeout=3 -T ${SSH_DEBUG_OPTIONS}"
    set +e
    _uid=$($_ssh "${_user_host}" 'id') && do_print_info "SSH ADD USER OK ($_uid)"
    local _status="${?}"
    set -e
    if [ 0 = ${_status} ]; then
      if [[ ! "${ADDED_USER_HOST[*]}" =~ ${_user_host} ]]; then
        ADDED_USER_HOST+=("${_user_host}")
      fi
    fi
    do_print_info 'SSH ADD USER DONE' "ssh exit with status ${_status}"
  }
  do_ssh_reset_service() {
    [ -z "${SERVICE_SSH_USER}" ] && SERVICE_SSH_USER="${CUSTOMER}"
    SERVICE_USER="$(_service_ssh_variable 'SERVICE_SSH_USER')"
    do_print_dash_pair 'SERVICE_USER' "${SERVICE_USER}"
    SERVICE_HOST="$(_service_ssh_variable 'SERVICE_SSH_HOST')"
    do_print_dash_pair 'SERVICE_HOST' "${SERVICE_HOST}"
    set +e
    SERVICE_USER_HOST="${SERVICE_USER}@${SERVICE_HOST}"
    [ -z "${CONTAINER_WORK_DIR}" ] && CONTAINER_WORK_DIR="/home/${SERVICE_USER}"
    set -e
  }
  _service_ssh_variable() {
    local _prefix=''
    [ -n "${SERVICE_GROUP}" ] && _prefix="$(echo "${SERVICE_GROUP}" | tr '[:lower:]' '[:upper:]')_"
    local _suffix=''
    [ -n "${ENV_NAME}" ] && _suffix="_$(echo "${ENV_NAME}" | tr '[:lower:]' '[:upper:]')"
    do_print_variable "${_prefix//-/_}" "${1:?}" "${_suffix}"
  }
  _ssh_user_declare() {
    if [ -n "${1}" ]; then local _prefix="${1}_"; else local _prefix=""; fi
    local _full_name="${_prefix}SSH_USER_PREFIX"
    local _value="${!_full_name}"
    if [ -n "${_value}" ]; then
      if [ -n "${ENV_NAME}" ]; then local _value="${_value}-${ENV_NAME}"; fi
      local _name="${_prefix}SSH_USER"
      declare -x "${_name}"="${_value}"
      echo "declare -x \"${_name}\"=\"${_value}\""
      declare -p "${_name}"
    fi
  }
  _ssh_add_key() {
    set +e
    echo "${1:?}" | tr -d '\r' | ssh-add - >/dev/null
    do_print_info "# ssh-add exit with status ${?}"
    set -e
  }
  _ssh_add_known() {
    echo "${1:?}" >>~/'.ssh/known_hosts'
  }
}

define_util_vault() {
  do_vault_service_login() {
    if [ -n "${SERVICE_VAULT_TOKEN}" ]; then return; fi
    init_service_vault_do
    if [ -z "${SERVICE_VAULT_URL}" ]; then
      do_print_info "- Abort vault login: '(SERVICE_)VAULT_URL' is absent"
      return
    fi
    if [ -z "${SERVICE_VAULT_USER}" ]; then
      do_print_info "- Abort vault login: '(SERVICE_)VAULT_USER' is absent"
      return
    fi
    if [ -z "${SERVICE_VAULT_PASS}" ]; then
      do_print_info "- Abort vault login: '(SERVICE_)VAULT_PASS' is absent"
      return
    fi
    do_print_info "# do_vault_service_login url:'${SERVICE_VAULT_URL}' user:'${SERVICE_VAULT_USER}'"
    SERVICE_VAULT_TOKEN=$(do_vault_login "${SERVICE_VAULT_URL}" "${SERVICE_VAULT_USER}" "${SERVICE_VAULT_PASS}")
    if [ -z "${SERVICE_VAULT_TOKEN}" ] || [ 'null' = "${SERVICE_VAULT_TOKEN}" ]; then
      SERVICE_VAULT_TOKEN=''
      do_print_warn "# do_vault_service_login failed" >&2
    fi
  }
  do_vault_project_login() {
    if [ -n "${PROJECT_VAULT_TOKEN}" ]; then return; fi
    init_project_vault_do
    if [ -z "${PROJECT_VAULT_URL}" ]; then
      do_print_info "- Abort vault login: '(PROJECT_)VAULT_URL' is absent"
      return
    fi
    if [ -z "${PROJECT_VAULT_USER}" ]; then
      do_print_info "- Abort vault login: '(PROJECT_)VAULT_USER' is absent"
      return
    fi
    if [ -z "${PROJECT_VAULT_PASS}" ]; then
      do_print_info "- Abort vault login: '(PROJECT_)VAULT_PASS' is absent"
      return
    fi
    do_print_info "# do_vault_project_login url:'${PROJECT_VAULT_URL}' user:'${PROJECT_VAULT_USER}'"
    PROJECT_VAULT_TOKEN=$(do_vault_login "${PROJECT_VAULT_URL}" "${PROJECT_VAULT_USER}" "${PROJECT_VAULT_PASS}")
    if [ -z "${PROJECT_VAULT_TOKEN}" ] || [ 'null' = "${PROJECT_VAULT_TOKEN}" ]; then
      PROJECT_VAULT_TOKEN=''
      do_print_warn "- do_vault_project_login failed"
    fi
  }
  do_vault_service_env_file() {
    do_print_info "$(do_stack_trace)"
    local _path="${1}"
    [ -z "${_path}" ] && _path="${SERVICE_GROUP:?}-env"
    do_vault_service_login
    if [ -z "${SERVICE_VAULT_TOKEN}" ]; then return; fi
    local _url="${SERVICE_VAULT_URL:?}/${SERVICE_VAULT_PATH:?}/${_path}"
    do_vault_fetch_env_file "${_url}" "${SERVICE_VAULT_TOKEN}"
  }
  do_vault_service_patch_file() {
    do_print_info "$(do_stack_trace)"
    local _path="${1}"
    local _file_name="${2}"
    local _content_key="${_file_name:?}"
    _content_key="${_content_key//./_}"
    _content_key="${_content_key//-/_}"
    do_vault_service_login
    if [ -z "${SERVICE_VAULT_TOKEN}" ]; then return; fi
    local _url="${SERVICE_VAULT_URL:?}/${SERVICE_VAULT_PATH:?}/${_path:?}"
    do_vault_fetch_with_key "${_url}" "${SERVICE_VAULT_TOKEN:?}" "${_content_key}"
  }
  do_vault_login() { do_vault_with_ssh_or_local "${FUNCNAME[0]}" "${@}"; }
  do_vault_login_local() {
    local _url="${1}"
    local _user="${2}"
    local _pass="${3}"
    local _jq_cmd='.auth.client_token'
    _url="${_url:?}/auth/userpass/login/${_user:?}"
    _json="{\"password\": \"${_pass:?}\"}"
    jq -r "${_jq_cmd}" <<<"$(curl --max-time 5 -s --request POST "${_url}" --data "${_json}")"
  }
  do_vault_fetch_env_file() { do_vault_with_ssh_or_local "${FUNCNAME[0]}" "${@}"; }
  do_vault_fetch_env_file_local() {
    local _url="${1}"
    local _token="${2}"
    local _jq_cmd='.data.data|select(.!=null)|to_entries[]|"\(.key)=\(.value)"'
    do_vault_fetch_local "${_url:?}" "${_token:?}" "${_jq_cmd}"
  }
  do_vault_fetch_bash_env() { do_vault_with_ssh_or_local "${FUNCNAME[0]}" "${@}"; }
  do_vault_fetch_bash_env_local() {
    local _url="${1}"
    local _token="${2}"
    local _jq_cmd=$'.data.data|select(.!=null)|to_entries[]|"export \(.key)=$\'\(.value)\'"'
    do_vault_fetch_local "${_url:?}" "${_token:?}" "${_jq_cmd}"
  }
  do_vault_fetch_bash_file() { do_vault_fetch_with_key "${@}" 'BASH'; }
  do_vault_fetch_with_key() { do_vault_with_ssh_or_local "${FUNCNAME[0]}" "${@}"; }
  do_vault_fetch_with_key_local() {
    local _url="${1}"
    local _token="${2}"
    local _key="${3}"
    local _jq_cmd=".data.data.${_key:?}"
    do_vault_fetch_local "${_url:?}" "${_token:?}" "${_jq_cmd}"
  }
  do_vault_with_ssh() {
    local _local_func_name="${1}"
    do_ssh_export do_print_colorful do_print_trace do_vault_check do_vault_fetch_local
    local _user_host=${UPLOAD_USER_HOST:-${JUMPER_USER_HOST:-${SSH_USER_HOST}}}
    do_ssh_invoke "$(do_ssh_exec_chain "${_user_host:?}")" "${_local_func_name:?}" "${*:2}"
  }
  do_vault_with_ssh_or_local() {
    local _func_name="${1}_local"
    set +e
    if do_vault_check; then
      eval "${_func_name:?}" "${*:2}"
    else
      if [ "$(type -t do_ssh_export)" != function ]; then
        do_print_info "$(do_stack_trace) 'do_ssh_export' is absent" >&2
        return
      fi
      do_vault_with_ssh "${_func_name:?}" "${*:2}"
      do_ssh_export_clear
    fi
    set -e
  }
  do_vault_check() {
    if [ -z "$(command -v jq)" ]; then return 2; fi
    if [ -z "$(command -v curl)" ]; then return 1; fi
    return 0
  }
  do_vault_fetch_local() {
    local _url="${1}"
    local _token="${2}"
    local _jq_cmd="${3}"
    local _value
    set +e
    #do_print_trace "$(do_stack_trace)" >&2
    do_print_trace "- fetch from ${_url:?} ${_jq_cmd:?}" >&2
    if ! do_vault_check; then return; fi
    _value=$(jq -r "${_jq_cmd:?}" <<<"$(curl --max-time 5 -s "${_url}" -H "X-Vault-Token: ${_token:?}")")
    local _status="${?}"
    set -e
    if [ '0' = "${_status}" ] && [ -n "${_value}" ] && [ 'null' != "${_value}" ]; then
      printf '%s\n' "${_value}"
    fi
    do_print_trace "- fetch from vault exit status ${_status}" >&2
  }
  do_vault_bash_inject() {
    local _url="${1}"
    local _func="${2}"
    if [ -z "${_url}" ]; then return; fi
    if [ "$(type -t "${_func:?}")" != function ]; then
      do_print_warn "- Function '${_func}' is undefined"
      return
    fi
    do_vault_project_login
    if [ -z "${PROJECT_VAULT_TOKEN}" ]; then return; fi
    local _command
    _command="$(eval "${_func}" "${_url}" "${PROJECT_VAULT_TOKEN:?}")"
    do_print_debug "${_command}"
    local _line_count
    _line_count=$(echo "${_command}" | wc -l | xargs)
    do_print_info "- fetch from vault ${_line_count} line(s)"
    eval "${_command}"
  }
}

define_util_print() {
  do_print_variable() {
    local _prefix="${1}"
    local _name="${2:?}"
    local _suffix="${3}"
    local _name3="${_prefix}${_name}${_suffix}"
    local _name2="${_prefix}${_name}"
    local _name1="${_name}${_suffix}"
    local _name0="${_name}"
    local _value=${!_name3:-${!_name2:-${!_name1:-${!_name0}}}}
    printf '%s' "$(echo "${_value}" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  }
  do_print_trace() { do_print_colorful '0;34' "${@}"; }
  do_print_info() { do_print_colorful '0;36' "${@}"; }
  do_print_warn() { do_print_colorful '1;33' "${@}"; }
  do_print_colorful() {
    if [ ! ${#} -gt 1 ]; then return; fi
    local _color="\033[${1}m"
    local _clear='\033[0m'
    local _head
    _head="$(echo "${2}" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ ${#} -gt 2 ]; then
      if [ -z "${_head}" ]; then
        printf "${_color}%s${_clear}\n" "${*:3}"
      else
        printf "${_color}%s${_clear} %s\n" "${_head}" "${*:3}"
      fi
    else
      printf "${_color}%s${_clear}\n" "${_head}"
    fi
  }
  do_print_debug() {
    local _enabled=${OPTION_DEBUG:='no'}
    if [ 'yes' != "${_enabled}" ]; then return 0; fi
    local _color='\033[0;35m'
    local _clear='\033[0m'
    if [ ${#} -gt 0 ]; then
      local _n=$((${#FUNCNAME[@]} - 2))
      local _stack
      _stack="$(whoami)@$(hostname) --> $(echo -n "${FUNCNAME[*]:1:${_n}} " | tac -s ' ')"
      printf "#---- ${_color}%s-- %s${_clear}\n" 'DEBUG BEGIN --' "${_stack}" >&2
      printf "%s\n" "${@}" | awk '{printf "#%3d| \033[0;35m%s\033[0m\n", NR, $0}' >&2
      printf "#---- ${_color}%s-- %s${_clear}\n" 'DEBUG END ----' "${_stack}" >&2
    fi
  }
  do_print_dash_pair() {
    if [ -z "${SHORT_LINE}" ]; then
      declare -x SHORT_LINE='------------------------------'
    fi
    local _clear='\033[0m'
    local _color='\033[0;32m'
    local _dark='\033[1;30m'
    if [ ${#} -gt 1 ]; then
      key=${1} && val=${2}
      printf "${_color}%s${_clear} ${_dark}%s${_clear} [${_color}%s${_clear}]\n" \
        "${key:?}" "${SHORT_LINE:${#key}}" "${val}"
    elif [ ${#} -gt 0 ]; then
      printf "${_dark}%s${_clear}\n" "${SHORT_LINE}-- ${1}"
    else
      printf "${_dark}%s${_clear}\n" "${SHORT_LINE}${SHORT_LINE}"
    fi
  }
  do_print_section() {
    if [ -z "${LONG_LINE}" ]; then
      LONG_LINE='========================================================================================='
    fi
    local _clear='\033[0m'
    local _color='\033[1;36m'
    local _title
    if [ ${#} -gt 0 ]; then
      _title="$(echo "${*}" | sed -e 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      if [ -n "${_title}" ]; then
        printf "${_color}%s %s %s${_clear}\n" "${_title}" "${LONG_LINE:${#_title}}" "$(date +'%Y-%m-%d %T %Z')"
        return
      fi
    fi
    printf "${_color}%s %s${_clear}\n" "=${LONG_LINE}" "$(date +'%Y-%m-%d %T %Z')"
  }
}

#===============================================================================

define_common_init() {
  define_util_core
  define_util_print
  define_util_vault
  define_common_ci_job
  init_first_do() {
    do_func_invoke 'init_first_custom_do'
    do_print_section 'INIT ALL BEGIN'
    _init_env_var
    _init_version_tag
  }
  init_final_do() {
    do_func_invoke 'init_final_custom_do'
    do_print_section 'INIT ALL DONE!' && echo ''
  }
  init_project_vault_do() {
    local _prefix='PROJECT_'
    local _suffix
    [ -n "${ENV_NAME}" ] && _suffix="_$(echo "${ENV_NAME}" | tr '[:lower:]' '[:upper:]')"
    PROJECT_VAULT_USER="$(do_print_variable "${_prefix}" 'VAULT_USER' "${_suffix}")"
    PROJECT_VAULT_PASS="$(do_print_variable "${_prefix}" 'VAULT_PASS' "${_suffix}")"
    PROJECT_VAULT_URL="$(do_print_variable "${_prefix}" 'VAULT_URL' "${_suffix}")"
    PROJECT_VAULT_PATH="${CUSTOMER:?}-${ENV_NAME:?}/data/project"
  }
  init_service_vault_do() {
    local _prefix='SERVICE_'
    local _suffix
    [ -n "${ENV_NAME}" ] && _suffix="_$(echo "${ENV_NAME}" | tr '[:lower:]' '[:upper:]')"
    SERVICE_VAULT_USER="$(do_print_variable "${_prefix}" 'VAULT_USER' "${_suffix}")"
    SERVICE_VAULT_PASS="$(do_print_variable "${_prefix}" 'VAULT_PASS' "${_suffix}")"
    SERVICE_VAULT_URL="$(do_print_variable "${_prefix}" 'VAULT_URL' "${_suffix}")"
    SERVICE_VAULT_PATH="${CUSTOMER:?}-${ENV_NAME:?}/data/service"
  }
  init_inject_env_bash_do() {
    if [ -z "${CUSTOMER}" ]; then
      do_print_info "- Abort vault injection: 'CUSTOMER' is absent"
      return
    fi
    local _path="${VAULT_PATH_ENV:-"${CI_PROJECT_NAME}/gitlab-env"}"
    _reset_injection_vault_url "${_path}"
    #export OPTION_DEBUG='yes'
    do_vault_bash_inject "${INJECTION_VAULT_URL}" 'do_vault_fetch_bash_env'
    #export OPTION_DEBUG='no'
  }
  init_inject_ci_bash_do() {
    local _path="${VAULT_PATH_CI:-"${CI_PROJECT_NAME}/gitlab-ci"}"
    _reset_injection_vault_url "${_path}"
    do_vault_bash_inject "${INJECTION_VAULT_URL}" 'do_vault_fetch_bash_file'
  }
  init_inject_cd_bash_do() {
    local _path="${VAULT_PATH_CD:-"${CI_PROJECT_NAME}/gitlab-cd"}"
    _reset_injection_vault_url "${_path}"
    do_vault_bash_inject "${INJECTION_VAULT_URL}" 'do_vault_fetch_bash_file'
  }
  _reset_injection_vault_url() {
    local _path="${1}"
    do_vault_project_login
    if [ -n "${PROJECT_VAULT_URL}" ]; then
      INJECTION_VAULT_URL="${PROJECT_VAULT_URL}/${PROJECT_VAULT_PATH:?}/${_path:?}"
    fi
  }
  _init_env_var() {
    CUSTOMER=${CUSTOMER:-${CUSTOMER_NAME:-none}}
    ENV_NAME=${ENV_NAME:-none}
    do_print_dash_pair 'CUSTOMER' "${CUSTOMER}"
    do_print_dash_pair 'ENV_NAME' "${ENV_NAME}"
    do_print_dash_pair 'CI_COMMIT_REF_NAME' "${CI_COMMIT_REF_NAME}"
  }
  _init_ci_tag() {
    [ -z "${CI_COMMIT_TAG}" ] && CI_COMMIT_TAG=${CI_COMMIT_SHORT_SHA}
    if [ -z "${CI_COMMIT_TAG}" ]; then
      do_print_warn "Error: CI_COMMIT_TAG is empty"
      exit 120
    fi
    do_print_dash_pair 'CI_COMMIT_TAG' "${CI_COMMIT_TAG}"
  }
  _init_version_tag() {
    _init_ci_tag
    if [ "${CI_COMMIT_REF_NAME}" = "${CI_COMMIT_TAG}" ]; then
      CD_VERSION_TAG="${CI_COMMIT_TAG}"
    else
      parts=()
      saved_ifs="$IFS"
      IFS='/' read -ra parts <<<"${CI_COMMIT_REF_NAME}"
      parts_len=${#parts[@]}
      if [ "${parts_len}" -gt 1 ]; then
        parts=("${parts[@]:1}")
        parts+=('x')
        IFS='.'
        CD_VERSION_TAG="${parts[*]}"
      else CD_VERSION_TAG=''; fi
      IFS="${saved_ifs}"
    fi
    if [ -z "${CD_VERSION_TAG}" ]; then CD_VERSION_TAG='0.0.x'; fi
    VERSION_BUILDING="${CD_VERSION_TAG:?}_${CI_PIPELINE_IID:-CI_PIPELINE_ID:?}"
    do_print_dash_pair 'VERSION_BUILDING' "${VERSION_BUILDING}"
  }
} # define_common_init

#===============================================================================

define_common_init_ssh() {
  declare -xa ADDED_USER_HOST=()
  define_util_ssh
  do_ssh_upload_invoke() { do_ssh_invoke "$(do_ssh_exec_chain "${UPLOAD_USER_HOST:?}")" "${@}"; }
  do_ssh_jumper_invoke() { do_ssh_invoke "$(do_ssh_exec_chain "${JUMPER_USER_HOST:?}")" "${@}"; }
  do_ssh_server_invoke() { do_ssh_invoke "$(do_ssh_exec_chain "${JUMPER_USER_HOST:?}" "${SERVICE_USER_HOST:?}")" "${@}"; }
  do_ssh_upload_exec() { do_ssh_exec "$(do_ssh_exec_chain "${UPLOAD_USER_HOST:?}")" "${@}"; }
  do_ssh_jumper_exec() { do_ssh_exec "$(do_ssh_exec_chain "${JUMPER_USER_HOST:?}")" "${@}"; }
  do_ssh_server_exec() { do_ssh_exec "$(do_ssh_exec_chain "${JUMPER_USER_HOST:?}" "${SERVICE_USER_HOST:?}")" "${@}"; }
  init_ssh_do() {
    do_ssh_agent_init
    do_ssh_add_user_default
    init_inject_env_bash_do
  }
}

define_common_build() {
  do_build_ci_info() {
    local _template_file="${1}"
    do_print_info 'BUILD CI/CD INFO' "${_template_file:?}"
    # shellcheck disable=SC2034
    local CD_ENVIRONMENT="${ENV_NAME:-none}"
    do_file_replace "${_template_file}" CD_ENVIRONMENT CD_VERSION_TAG \
      CI_COMMIT_TAG CI_PIPELINE_IID CI_PIPELINE_ID CI_JOB_ID CI_COMMIT_REF_NAME CI_COMMIT_SHA CI_COMMIT_SHORT_SHA
    do_print_info 'BUILD CI/CD INFO DONE'
  }
}

define_common_upload() {
  do_upload_cleanup_local() {
    do_print_info 'UPLOAD CLEANUP LOCAL'
    RUNNER_LOCAL_DIR="${CI_PROJECT_DIR:?}/temp-upload"
    do_dir_clean "${RUNNER_LOCAL_DIR}" make && do_print_info 'UPLOAD CLEANUP LOCAL OK'
  }
  do_upload() {
    do_print_info 'UPLOAD SERVICE' "[${2}::${1}]"
    SERVICE_NAME="${1:-${SERVICE_NAME:?}}"
    SERVICE_GROUP="${2:-${SERVICE_GROUP:?}}"
    [ -z "${RUNNER_LOCAL_DIR}" ] && do_upload_cleanup_local
    local _local_dir="${RUNNER_LOCAL_DIR:?}"
    local _remote_dir="/home/${UPLOAD_USER:?}/${SERVICE_GROUP:?}/${SERVICE_NAME:?}-${CD_VERSION_TAG:?}"
    upload_cd_version_file_do "${_local_dir}" "${VERSION_BUILDING:-0}"
    upload_scp_do "${_local_dir}" "${_remote_dir}"
    do_print_info 'UPLOAD SERVICE DONE' "[${2}::${1}]"
  }
  do_upload_env() {
    do_print_info 'UPLOAD SERVICE ENV' "[${1}]"
    SERVICE_GROUP="${1:-${SERVICE_GROUP:?}}"
    [ -z "${RUNNER_LOCAL_DIR}" ] && do_upload_cleanup_local
    local _local_dir="${RUNNER_LOCAL_DIR:?}"
    local _remote_dir="/home/${UPLOAD_USER:?}/${SERVICE_GROUP:?}/env-deploy"
    upload_scp_do "${_local_dir}" "${_remote_dir}"
    do_print_info 'UPLOAD SERVICE ENV DONE' "[${1}]"
  }
  do_upload_copy_dir() {
    local _link='cp --preserve --recursive --link'
    local service=${1}
    local service_group=${2}
    local _dir="${CI_PROJECT_DIR:?}/deploy/${service_group:?}"
    local _env_dir="${_dir}/env-deploy"
    local _service_dir="${_dir}/${service:?}"
    set +e
    [ -d "${_env_dir}" ] && {
      $_link "${_env_dir}/"* "${RUNNER_LOCAL_DIR}/"
      do_upload_env "${service_group}"
    }
    [ -d "${_service_dir}" ] && {
      $_link "${_service_dir}/"* "${RUNNER_LOCAL_DIR:?}/"
    }
    set -e
  }
  do_upload_copy_file() {
    local _link='cp --preserve --recursive --link'
    local _file_type="${1}"
    local _file_path="${2}"
    local _file_path="${CI_PROJECT_DIR:?}/${_file_path:?}"
    ls -lh "${_file_path}"
    [ -f '/usr/bin/file' ] && do_print_info "$(/usr/bin/file "${_file_path}")"
    mkdir -p "${RUNNER_LOCAL_DIR:?}/${_file_type:?}"
    $_link "${_file_path}" "${RUNNER_LOCAL_DIR}/${_file_type}/"
  }
  upload_scp_do() {
    local _local_dir="${1}"
    local _remote_dir="${2}"
    do_print_dash_pair 'RUNNER_LOCATION' "$(whoami)@$(hostname):${_local_dir:?}"
    do_print_dash_pair 'REMOTE_LOCATION' "${UPLOAD_USER_HOST:?}:${_remote_dir:?}"
    do_ssh_export_clear
    do_ssh_export do_print_colorful do_print_warn do_print_trace do_dir_make
    do_ssh_upload_invoke do_dir_clean "'${_remote_dir}'" make
    do_ssh_export_clear
    do_dir_scp "${_local_dir}" "${_remote_dir}" "${UPLOAD_USER_HOST:?}" upload_scp_hook_do
    do_upload_cleanup_local
  }
  upload_scp_hook_do() {
    find "${_remote_dir:?}" -type d -exec chmod 774 {} +
    find "${_remote_dir:?}" -type f -exec chmod 660 {} +
    do_dir_list "${_remote_dir:?}"
  }
  upload_cd_version_file_do() {
    local _dir="${1}"
    local _version="${2}"
    local _path="${_dir:?}/CD_VERSION"
    touch "${_path}" && echo "${_version:?}" >"${_path}" && chmod 640 "${_path}"
  }
} # define_common_upload

#===============================================================================

define_common_service() {
  do_cat_running_version() {
    local _command
    _command=$(printf '%s' "if \
    [ 1 = \$($_container_cmd ps -a | grep '${SERVICE_NAME}' | wc -l || echo 0) ]; then
      $_container_cmd exec ${SERVICE_NAME} cat ${CONTAINER_WORK_DIR}/CD_VERSION 2>/dev/null || echo 0
    else echo 0; fi" | tr -s ' ')
    do_ssh_server_exec "${_command}"
  }
  do_inspect_container() {
    do_print_info "INSPECT [${SERVICE_LOCATION}]"
    do_print_dash_pair 'VERSION_BUILDING' "${VERSION_BUILDING}"
    do_print_dash_pair 'VERSION_DEPLOYING' "${VERSION_DEPLOYING}"
    local VERSION_RUNNING_NOW
    VERSION_RUNNING_NOW=$(do_cat_running_version)
    do_print_dash_pair 'VERSION_RUNNING_NOW' "${VERSION_RUNNING_NOW}"
    local _vr="${VERSION_RUNNING}"
    if [ -n "$_vr" ] && [ "$_vr" != '0' ] && [ "$_vr" != "${VERSION_RUNNING_NOW}" ]; then
      do_print_dash_pair 'VERSION_STOPPED' "${VERSION_RUNNING}"
    fi
    do_ssh_export SERVICE_NAME SERVICE_DIR
    do_ssh_export do_print_colorful do_print_trace
    do_ssh_server_invoke service_info_print_do "${_container_cmd:?}" &&
      do_print_info "INSPECT OK [${SERVICE_LOCATION}]"
    do_ssh_export_clear
  }
  service_common_do() {
    do_ssh_reset_service
    do_print_dash_pair 'Required Arguments'
    do_print_dash_pair 'SERVICE_NAME' "${SERVICE_NAME:?}"
    do_print_dash_pair 'SERVICE_GROUP' "${SERVICE_GROUP:?}"
    do_print_dash_pair 'Common Variables'
    SERVICE_GROUP_DIR="/home/${SERVICE_USER}/${SERVICE_GROUP}"
    SERVICE_DIR="${SERVICE_GROUP_DIR}/${SERVICE_NAME}"
    SERVICE_LOCATION="${SERVICE_USER_HOST:?}:${SERVICE_DIR}"
    do_print_dash_pair 'SERVICE_LOCATION' "${SERVICE_LOCATION}"
    SERVICE_UPLOAD_DIR="/home/${UPLOAD_USER:?}/${SERVICE_GROUP}/${SERVICE_NAME}-${CD_VERSION_TAG:?}"
    SERVICE_DEPLOY_DIR="${SERVICE_DIR}-${CD_VERSION_TAG}"
    UPLOAD_LOCATION="${UPLOAD_USER}@${JUMPER_SSH_HOST}:${SERVICE_UPLOAD_DIR}"
    do_print_dash_pair 'UPLOAD_LOCATION' "${UPLOAD_LOCATION}"
    _service_reset_status
    _service_check_version
  }
  service_info_print_do() {
    do_print_trace "*** $(do_stack_trace)"
    local _container_cmd="${*:?}"
    do_print_trace '*** Currently deployed version:'
    cat "${SERVICE_DIR:?}/CD_VERSION"
    do_print_trace '*** Recent deployment log'
    tail -10 "${SERVICE_DIR}/CD_VERSION_LOG"
    if [ 1 = "$($_container_cmd ps -a | grep -c "${SERVICE_NAME:?}" || echo 0)" ]; then
      do_print_trace '*** Container State:'
      $_container_cmd inspect --type=container --format='{{json .State}}' "${SERVICE_NAME}"
    else
      do_print_trace '### Container is not created:' "${SERVICE_NAME}"
    fi
  }
  service_container_exist_do() {
    local _service_name="${1}"
    local _container_cmd="${2}"
    if [ 1 = "$(${_container_cmd:?} ps -a | grep -c "${_service_name:?}" || echo 0)" ]; then
      printf 'yes'
    else printf 'no'; fi
  }
  service_container_stop_do() {
    do_print_trace "$(do_stack_trace)"
    local _service_name="${1}"
    local _container_cmd="${2}"
    if [ 1 = "$(${_container_cmd:?} ps -a | grep -c "${_service_name:?}" || echo 0)" ]; then
      ${_container_cmd} stop "${_service_name}"
      return ${?}
    fi
    return 0
  }
  _service_reset_status() {
    do_print_dash_pair 'Runtime Variables'
    SERVICE_HOST_UID=$(do_ssh_server_exec 'id')
    do_print_dash_pair 'SERVICE_HOST_UID' "${SERVICE_HOST_UID}"
    IS_PODMAN_HOST=$(do_ssh_server_exec \
      'if ! command -v podman-compose &>/dev/null; then echo no; else echo yes; fi')
    do_print_dash_pair 'IS_PODMAN_HOST' "${IS_PODMAN_HOST}"
    if [ 'yes' = "${IS_PODMAN_HOST}" ]; then
      _container_cmd='sudo podman'
    else _container_cmd='docker'; fi
  }
  _service_check_version() {
    _cd_version_file=${SERVICE_UPLOAD_DIR}/CD_VERSION
    VERSION_DEPLOYING=$(do_ssh_jumper_exec "cat ${_cd_version_file:?} || echo 0")
    if [ 'yes' = "${OPTION_FORCE_DEPLOY}" ]; then
      VERSION_BUILDING="${VERSION_DEPLOYING:=1}"
    fi
    do_print_dash_pair 'VERSION_BUILDING' "${VERSION_BUILDING:?}"
    do_print_dash_pair 'VERSION_DEPLOYING' "${VERSION_DEPLOYING}"
    VERSION_RUNNING=$(do_ssh_server_exec "\
    $_container_cmd exec ${SERVICE_NAME} cat ${CONTAINER_WORK_DIR:?}/CD_VERSION || echo 0")
    do_print_dash_pair 'VERSION_RUNNING' "${VERSION_RUNNING}"
    if [ '0' = "${VERSION_DEPLOYING}" ]; then
      do_print_warn "Check this file: ${JUMPER_USER_HOST}:$_cd_version_file"
      exit 120
    fi
    if [ '0' = "${VERSION_RUNNING}" ]; then
      do_print_warn "Service '${SERVICE_NAME}-${VERSION_BUILDING}' is not running"
    fi
    if [ "${VERSION_BUILDING}" != "${VERSION_DEPLOYING}" ]; then
      do_print_warn "Service '${SERVICE_NAME}-${VERSION_BUILDING}' is not uploaded or has been replaced"
    fi
    if [ "${VERSION_BUILDING}" = "${VERSION_RUNNING}" ]; then
      do_print_info "Service '${SERVICE_NAME}-${VERSION_BUILDING}' is already running"
    fi
  }
} # define_common_service

#===============================================================================

define_common_verify() {
  define_common_service
  do_verify() {
    do_print_info 'VERIFY SERVICE'
    [ -n "${1}" ] && SERVICE_NAME="${1}"
    [ -n "${2}" ] && SERVICE_GROUP="${2}"
    service_common_do
    if [ "${VERSION_RUNNING}" != "${VERSION_DEPLOYING}" ]; then
      do_print_warn "Service '${SERVICE_NAME}-${VERSION_DEPLOYING}' was uploaded but not deployed"
    fi
    if [ "${VERSION_RUNNING:?}" = "${VERSION_BUILDING:?}" ]; then
      do_print_info 'VERIFY SERVICE OK'
    else
      if [ '0' = "${VERSION_RUNNING}" ]; then exit 119; fi
    fi
    do_print_info 'VERIFY SERVICE DONE'
    do_inspect_container
  }
}

define_common_deploy() {
  define_common_deploy_env
  do_deploy() {
    do_print_info 'DEPLOY SERVICE'
    SERVICE_NAME="${1:-${SERVICE_NAME:?}}"
    SERVICE_GROUP="${2:-${SERVICE_GROUP:?}}"
    SERVICE_NAME_LOWER="$(echo "${SERVICE_NAME:?}" | tr '[:upper:]' '[:lower:]' | tr '-' '_')"
    service_common_do
    if [ "${VERSION_BUILDING:?}" != "${VERSION_DEPLOYING:?}" ]; then
      do_print_info 'DEPLOY SERVICE REJECTED' "# package version is not ${VERSION_BUILDING}"
      return
    fi
    if [ 'yes' = "${IS_PODMAN_HOST}" ]; then
      _compose_env_name='container-compose.env'
    else _compose_env_name='docker-compose.env'; fi
    do_ssh_export_clear
    do_func_invoke deploy_custom_hook_do
    do_ssh_export_clear
    do_func_invoke "deploy_${SERVICE_NAME_LOWER}_hook_do"
    do_ssh_export_clear
    deploy_service_jumper_do
    do_print_info 'DEPLOY SERVICE DONE'
  }
  do_deploy_vault_env() {
    do_print_info "$(do_stack_trace)"
    local _code
    _code=$(do_vault_service_env_fetch "${1}")
    local _line_count
    _line_count=$(echo "${_code}" | wc -l | xargs)
    do_print_info "- fetch from vault: ${_line_count} lines"
    do_ssh_server_exec "printf '%s\n' '${_code}' >>'${_compose_env_new:?}'"
  }
  do_deploy_vault_patch() {
    do_print_info "$(do_stack_trace)"
    local _vault_path="${1}"
    local _file_name="${2}"
    local _type="${3:-etc}"
    local _file_content
    _file_content="$(do_vault_service_patch_file "${_vault_path:?}-${_type}" "${_file_name:?}")"
    if [ -z "${_file_content}" ]; then
      do_print_warn '- fetched nothing'
      return 0
    fi
    local _remote_path="${SERVICE_UPLOAD_DIR:?}/${_type}/${_file_name}"
    do_print_info "- fetch to ${UPLOAD_USER}@${JUMPER_SSH_HOST}:${_remote_path}"
    do_deploy_write_file "${_remote_path}" "${_file_content}"
  }
  do_deploy_write_file() {
    _file_content="${2}"
    printf -v _file_content '%q' "${_file_content:?}"
    do_ssh_jumper_invoke do_write_file "${1}" "${_file_content}"
    do_ssh_export_clear
  }
  do_deploy_patch() {
    local _dir_name=${1:?}
    local _service_dir="${SERVICE_GROUP:?}/${SERVICE_NAME:?}/${_dir_name}"
    local _local_dir="${CI_PROJECT_DIR:?}/${_service_dir}"
    if [ ! -d "$_local_dir" ]; then
      do_print_warn "'$_local_dir' is not a directory"
      return
    fi
    local _scp="scp -rpC -o StrictHostKeyChecking=no"
    local _remote_dir="${UPLOAD_LOCATION}/${_dir_name}"
    do_ssh_server_exec "mkdir -p ${_remote_dir}"
    do_print_info 'UPLOAD PATCH FROM' "${_local_dir}/*"
    do_print_info 'UPLOAD PATCH TO' "${_remote_dir}/"
    if ! $_scp "${_local_dir}/"* "${_remote_dir}/"; then
      do_print_warn 'UPLOAD PATCH FAILED'
    else
      do_print_info 'UPLOAD PATCH OK' "$(date +'%T')"
    fi
  }
  deploy_service_jumper_do() {
    local _cd_log_line="[${VERSION_DEPLOYING}] [${CI_JOB_STAGE} ${CI_JOB_NAME}] [${CI_PIPELINE_IID:-CI_PIPELINE_ID} ${CI_JOB_ID}]"
    do_ssh_export_clear
    do_ssh_export do_print_trace do_print_warn do_print_colorful
    do_ssh_export do_dir_make do_dir_list do_dir_chmod do_dir_scp do_write_log_file
    do_ssh_export do_ssh_invoke do_ssh_exec do_ssh_exec_chain do_ssh_export do_ssh_export_clear
    do_ssh_export service_container_stop_do
    do_ssh_export SERVICE_NAME SERVICE_USER_HOST SERVICE_UPLOAD_DIR SERVICE_DEPLOY_DIR SERVICE_DIR
    do_ssh_export _container_cmd _cd_log_line
    do_ssh_jumper_invoke deploy_service_do
    do_ssh_export_clear
  }
  deploy_service_do() {
    do_print_trace "$(do_stack_trace)"
    do_ssh_export_clear
    do_ssh_export do_print_trace do_print_warn do_print_colorful
    do_ssh_invoke "$(do_ssh_exec_chain "${SERVICE_USER_HOST:?}")" \
      service_container_stop_do "'${SERVICE_NAME:?}'" "'${_container_cmd}'"
    local _status=${?}
    set -e
    do_ssh_export_clear
    local _head='# service_container_stop_do exit with status'
    case ${_status} in
    0) do_print_trace "${_head} ${_status} (ok)" ;;
    *) do_print_warn "${_head} ${_status} (unknown status)" ;;
    esac
    [ 0 != ${_status} ] && return ${_status}
    do_dir_scp_hook() {
      do_dir_chmod "${_remote_dir}"
      ln -sfn "${_remote_dir}" "${_remote_dir}/CD_LINK"
      do_dir_list "${_remote_dir}"
      mv -Tf "${_remote_dir}/CD_LINK" "${1:?}"
    }
    export -f do_dir_scp_hook
    set +e
    do_dir_scp "${SERVICE_UPLOAD_DIR:?}" "${SERVICE_DEPLOY_DIR:?}" "${SERVICE_USER_HOST:?}" 'do_dir_scp_hook' "${SERVICE_DIR:?}"
    local _status=${?}
    set -e
    local _head='# do_dir_scp exit with status'
    case ${_status} in
    0) do_print_trace "${_head} ${_status} (ok)" ;;
    *) do_print_trace "${_head} ${_status} (unknown status)" ;;
    esac
    [ 0 = ${_status} ] && {
      do_print_trace 'WRITE DEPLOY LOG'
      local _path="${SERVICE_DEPLOY_DIR:?}/CD_VERSION_LOG"
      do_ssh_export_clear
      do_ssh_export do_print_trace do_print_warn do_print_colorful
      do_ssh_invoke "$(do_ssh_exec_chain "${SERVICE_USER_HOST:?}")" do_write_log_file "'${_path}'" "'${_cd_log_line:?}'"
      local _status=${?}
      set -e
      case ${_status} in
      0) do_print_trace 'WRITE DEPLOY LOG OK' ;;
      *) do_print_warn "WRITE DEPLOY LOG FAILED ${_status} (unknown status)" ;;
      esac
      do_ssh_export_clear
    }
  }
} # define_common_deploy

define_common_deploy_env() {
  define_common_service
  do_deploy_env_down() {
    do_print_info 'DEPLOY SERVICE GROUP DOWN' "[${1}]"
    SERVICE_GROUP="${1:-${SERVICE_GROUP}}"
    do_ssh_reset_service
    do_print_dash_pair 'SERVICE_GROUP' "${SERVICE_GROUP:?}"
    do_print_dash_pair 'UPLOAD_USER' "${UPLOAD_USER:?}"
    SERVICE_GROUP_DIR="/home/${SERVICE_USER:?}/${SERVICE_GROUP:?}"
    ENV_DEPLOY_DIR="${SERVICE_GROUP_DIR}/env-deploy"
    local _local_dir="/home/${UPLOAD_USER}/${SERVICE_GROUP}/env-deploy"
    local _remote_dir="${ENV_DEPLOY_DIR}"
    deploy_env_jumper_do "${_local_dir}" "${_remote_dir}"
    deploy_env_down_server_do "${_remote_dir}"
    do_print_info 'DEPLOY SERVICE GROUP DOWN DONE' "[${1}]"
  }
  do_deploy_env_up() {
    do_print_info 'DEPLOY SERVICE GROUP UP' "[${1}]"
    SERVICE_GROUP="${1:-${SERVICE_GROUP}}"
    SERVICE_GROUP_DIR="/home/${SERVICE_USER:?}/${SERVICE_GROUP:?}"
    ENV_DEPLOY_DIR="${SERVICE_GROUP_DIR}/env-deploy"
    do_ssh_reset_service
    do_ssh_export_clear
    do_ssh_export do_print_trace do_print_warn do_print_colorful deploy_env_reset_do
    do_ssh_export SERVICE_GROUP_DIR ENV_DEPLOY_DIR
    do_ssh_server_invoke deploy_env_up_do
    local _status="${?}"
    set -e
    do_ssh_export_clear
    local _head='# deploy_env_up_do exit with status'
    case ${_status} in
    0) do_print_trace "${_head} ${_status} (ok)" ;;
    *) do_print_trace "${_head} ${_status} (unknown status)" ;;
    esac
    do_print_info 'DEPLOY SERVICE GROUP UP DONE' "[${1}]"
  }
  deploy_env_up_do() {
    do_print_trace "$(do_stack_trace)"
    cd "${SERVICE_GROUP_DIR:?}"
    deploy_env_reset_do
    do_print_trace "# ${_compose_cmd:?} up -d"
    ${_compose_cmd} up -d
  }
  deploy_env_reset_do() {
    if ! command -v podman-compose &>/dev/null; then
      _compose_env_name='docker-compose.env'
      _compose_yml_name='docker-compose.yml'
      #_compose_cmd="docker-compose -f $_compose_yml_name --compatibility"
      _compose_cmd="docker-compose"
    else
      _compose_env_name='container-compose.env'
      _compose_yml_name='container-compose.yml'
      _compose_cmd="sudo podman-compose -f $_compose_yml_name"
    fi
    _compose_env_old="${SERVICE_GROUP_DIR:?}/.env"
    _compose_yml_old="${SERVICE_GROUP_DIR:?}/${_compose_yml_name}"
    _compose_env_new="${ENV_DEPLOY_DIR:?}/${_compose_env_name}"
    _compose_yml_new="${ENV_DEPLOY_DIR:?}/${_compose_yml_name}"
  }
  deploy_env_jumper_do() {
    do_ssh_export_clear
    do_ssh_export do_print_trace do_print_warn do_print_colorful
    do_ssh_export do_dir_make do_dir_list do_dir_chmod do_dir_scp
    do_ssh_export do_ssh_invoke do_ssh_exec do_ssh_exec_chain do_ssh_export do_ssh_export_clear
    do_ssh_export SERVICE_USER_HOST _remote_dir
    do_ssh_jumper_invoke deploy_env_do "${_local_dir}" "${_remote_dir}"
    local _status="${?}"
    set -e
    do_ssh_export_clear
    local _head='# deploy_env_do exit with status'
    case ${_status} in
    0) do_print_trace "${_head} ${_status} (ok)" ;;
    9) do_print_trace "${_head} ${_status} (local dir is absent)" ;;
    *) do_print_trace "${_head} ${_status} (unknown status)" ;;
    esac
  }
  deploy_env_do() {
    local _local_dir="${1}"
    [ ! -d "${_local_dir:?}" ] && {
      do_print_warn "'${_local_dir}' is absent"
      return 9
    }
    do_dir_scp_hook() {
      chmod 600 "${_remote_dir}"/*
      do_dir_list "${_remote_dir}"
    }
    export -f do_dir_scp_hook
    do_dir_scp "${_local_dir:?}" "${_remote_dir:?}" "${SERVICE_USER_HOST:?}" 'do_dir_scp_hook'
    return 0
  }
  deploy_env_down_server_do() {
    local _remote_dir="${1}"
    local _service_group_lower
    local _service_group_lower
    _service_group_lower="$(echo "${SERVICE_GROUP}" | tr '[:upper:]' '[:lower:]' | tr '-' '_')"
    set +e
    do_ssh_export_clear
    for i in ${DEPLOY_ENV_HOOK_EXPORT[*]}; do do_ssh_export "${i}"; done
    do_ssh_export do_print_trace do_print_info do_print_warn do_print_colorful do_func_invoke
    do_ssh_export do_file_replace do_diff
    do_ssh_export deploy_env_reset_do deploy_env_diff_do deploy_env_replace_do deploy_env_backup_do
    do_ssh_export CUSTOMER ENV_NAME CONTAINER_WORK_DIR _remote_dir _service_group_lower
    do_ssh_export SERVICE_GROUP SERVICE_GROUP_DIR ENV_DEPLOY_DIR
    init_service_vault_do
    do_ssh_export SERVICE_VAULT_USER SERVICE_VAULT_PASS SERVICE_VAULT_URL SERVICE_VAULT_PATH
    local _func_name="deploy_env_hook_do"
    if [ "$(type -t "${_func_name}")" = 'function' ]; then
      do_ssh_export "${_func_name}"
    fi
    local _func_name="deploy_env_${_service_group_lower}_hook_do"
    if [ "$(type -t "${_func_name}")" = 'function' ]; then
      do_ssh_export "${_func_name}"
    fi
    do_ssh_server_invoke deploy_env_down_do
    local _status="${?}"
    set -e
    do_ssh_export_clear
    local _head='# deploy_env_down_do exit with status'
    case ${_status} in
    0) do_print_trace "${_head} ${_status} (ok)" ;;
    *) do_print_trace "${_head} ${_status} (unknown status)" ;;
    esac
  }
  deploy_env_down_do() {
    deploy_env_reset_do
    local _is_first
    if [ -f "${_compose_yml_old:?}" ]; then
      _is_first='no'
    else _is_first='yes'; fi
    deploy_env_replace_do "${_compose_env_new}"
    cd "${SERVICE_GROUP_DIR:?}"
    do_func_invoke deploy_env_hook_do
    do_func_invoke "deploy_env_${_service_group_lower}_hook_do"
    deploy_env_diff_do
    do_print_trace "# diff result: env(${ENV_CHANGED}) yml(${YML_CHANGED})"
    if [ 0 != "${YML_CHANGED}" ] && [ 1 != "${YML_CHANGED}" ]; then
      do_print_warn "# ${FUNCNAME[0]} cancelled: exception"
      return
    fi
    if [ 0 != "${ENV_CHANGED}" ] && [ 1 != "${ENV_CHANGED}" ]; then
      do_print_warn "# ${FUNCNAME[0]} cancelled: exception"
      return
    fi
    if [ 0 = "${ENV_CHANGED}" ] && [ 0 = "${YML_CHANGED}" ]; then
      do_print_trace "# ${FUNCNAME[0]} cancelled: not changed"
      return
    fi
    local _cp="cp --preserve -f"
    if [ 'yes' = "${_is_first}" ]; then
      do_print_trace "# ${FUNCNAME[0]}: first deployment"
      ${_cp} "${_compose_yml_new:?}" "${_compose_yml_old:?}"
      [ -f "${_compose_env_new:?}" ] && ${_cp} "${_compose_env_new:?}" "${_compose_env_old:?}"
      return
    fi
    if [ 1 = "${ENV_CHANGED}" ] || [ 1 = "${YML_CHANGED}" ]; then
      do_print_trace "# ${_compose_cmd:?} down"
      ${_compose_cmd} down
      local _status=${?}
      do_print_trace "# ${_compose_cmd} down exited with status ${_status}"
      [ ${_status} ] && {
        ENV_BACKUP_DIR="${SERVICE_GROUP_DIR:?}/env-backup/$(date +'%Y%m%d.%H%M%S')"
        deploy_env_backup_do
        ${_cp} "${_compose_yml_new:?}" "${_compose_yml_old:?}"
        [ -f "${_compose_env_new:?}" ] && ${_cp} "${_compose_env_new:?}" "${_compose_env_old:?}"
      }
    fi
  }
  deploy_env_diff_do() {
    do_print_trace "$(do_stack_trace)"
    do_diff "${_compose_env_old}" "${_compose_env_new}"
    ENV_CHANGED="${?}"
    do_diff "${_compose_yml_old}" "${_compose_yml_new}"
    YML_CHANGED="${?}"
    set -e
  }
  deploy_env_replace_do() {
    do_print_trace "$(do_stack_trace)" "[${1}]"
    local _path="${1}"
    [ ! -f "${_path}" ] && {
      do_print_warn "$(do_stack_trace) '${_path:?}' failed: No such file"
      return 0
    }
    declare -rx DEPLOY_ENV_NAME="${ENV_NAME}"
    declare -rx DEPLOY_CUSTOMER="${CUSTOMER}"
    declare -x DEPLOY_HOST_IP='127.0.0.1'
    DEPLOY_HOST_IP=$(/usr/sbin/ifconfig eth0 | grep 'inet ' | awk '{print $2}')
    do_file_replace "${_path:?}" CONTAINER_WORK_DIR DEPLOY_CUSTOMER DEPLOY_HOST_IP DEPLOY_ENV_NAME
    sed -i -e "s|#VAULT_USER|${SERVICE_VAULT_USER}|g" "${_path}"
    sed -i -e "s|#VAULT_PASS|${SERVICE_VAULT_PASS}|g" "${_path}"
    sed -i -e "s|#VAULT_URL|${SERVICE_VAULT_URL}|g" "${_path}"
    sed -i -e "s|#VAULT_PATH|${SERVICE_VAULT_PATH}|g" "${_path}"
  }
  deploy_env_backup_do() {
    do_print_trace "# ${FUNCNAME[0]}"
    mkdir -p "${ENV_BACKUP_DIR:?}"
    local _path="${_compose_yml_old:?}"
    [ ! -f "${_path}" ] && return
    cd "${SERVICE_GROUP_DIR:?}"
    cp --preserve "${_path}" "${ENV_BACKUP_DIR}/${_compose_yml_name}"
    local _path="${_compose_env_old:?}"
    [ -f "${_path}" ] && cp --preserve "${_path}" "${ENV_BACKUP_DIR}/${_compose_env_name:?}"
    find . -type l -ls >"${ENV_BACKUP_DIR}/cd_version_linked"
    backup_cd_version() {
      cd "${SERVICE_GROUP_DIR:?}"
      echo "$(cat "${1}") -- ${1}" >>"${ENV_BACKUP_DIR}/cd_version_all"
    }
    export -f backup_cd_version
    export SERVICE_GROUP_DIR
    export ENV_BACKUP_DIR
    touch "${ENV_BACKUP_DIR}/cd_version_all"
    find "${SERVICE_GROUP_DIR}" -type f -name 'CD_VERSION' -exec bash -c 'backup_cd_version "$0"' {} \;
  }
} # define_common_deploy_env

#===============================================================================

define_common_ci_job() {
  build_job_do() {
    do_print_section 'BUILD JOB BEGIN'
    do_func_invoke "build_custom_do"
    do_print_section 'BUILD JOB DONE!' && echo ''
  }
  upload_job_do() {
    do_print_section 'UPLOAD JOB BEGIN'
    do_ssh_add_user_upload
    do_upload_cleanup_local
    do_func_invoke "upload_custom_do"
    do_print_section 'UPLOAD JOB DONE!' && echo ''
  }
  deploy_job_do() {
    do_print_section 'DEPLOY JOB BEGIN'
    do_ssh_add_user_jumper
    do_func_invoke "deploy_custom_do"
    do_func_invoke "deploy_${ENV_NAME:?}_do"
    do_print_section 'DEPLOY JOB DONE!' && echo ''
  }
  verify_job_do() {
    do_print_section 'VERIFY JOB BEGIN'
    do_ssh_add_user_jumper
    do_func_invoke "verify_custom_do"
    do_func_invoke "verify_${ENV_NAME:?}_do"
    do_print_section 'VERIFY JOB DONE!' && echo ''
  }
} # define_common_job

#===============================================================================
# end of file: .gitlab-ci.lib.sh
