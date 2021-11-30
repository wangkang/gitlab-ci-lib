#!/bin/bash

set -eo pipefail

#===============================================================================

define_util_core() {
  do_here() {
    local _func_name="${1}"
    local _input
    _input="$(timeout 2s cat /dev/stdin || true)"
    if [ -n "${_input}" ]; then
      eval "${_func_name:?}" "'${_input}'"
    else
      echo "Warning: empty stdin, ${_func_name}() was cancelled" >&2
    fi
  }
  do_dir_list() {
    local _dir="${1}"
    [ ! -d "${_dir:?}" ] && { return; }
    find "${_dir}" -type f -exec ls -lhA {} +
  }
  do_dir_make() {
    local _dir="${1}"
    local _hint
    [ -d "${_dir:?}" ] && { return; }
    if ! _hint=$(mkdir -p "${_dir}" 2>&1); then
      do_print_warn "[$(whoami)@$(hostname) $(pwd)]$ mkdir -p ${_dir}"
      do_print_warn "${_hint}"
    fi
  }
  do_dir_clean() {
    local _dir="${1}"
    local _hint
    [ ! -d "${_dir:?}" ] && { return; }
    if ! _hint=$(rm -rf "${_dir:?}/"* 2>&1); then
      do_print_warn "[$(whoami)@$(hostname) $(pwd)]$ rm -rf \"${_dir}/\"*"
      do_print_warn "${_hint}"
      do_print_warn "$(find "${_dir}" -type f -exec ls -lhA {} +)"
    fi
  }
  do_diff() {
    printf "\033[0;34m%s\033[0m\n" "# diff '${1:?}' '${2:?}'"
    local _result
    [ ! -f "${1}" ] && touch "${1}"
    [ ! -f "${2}" ] && {
      printf "\033[1;33m%s\033[0m\n" "- diff cancelled: ${2} is not a file"
      set +e
      return 3
    }
    local _status
    set +eo pipefail
    diff --unchanged-line-format='' --old-line-format="- |%2dn| %L" \
      --new-line-format="+ |%2dn| %L" "${1}" "${2}" |
      awk 'BEGIN{FIELDWIDTHS="1"} { if ($1 == "+") {
      printf "\033[0;32m%s\033[0m\n", $0 } else {
      printf "\033[0;31m%s\033[0m\n", $0 } }'
    _status=${PIPESTATUS[0]}
    set -o pipefail
    [ 1 = "${_status}" ] && [ -n "${_result}" ] && {
      echo "${_result}" | awk 'BEGIN{FIELDWIDTHS="1"} { if ($1 == "+") {
      printf "\033[0;32m%s\033[0m\n", $0 } else {
      printf "\033[0;31m%s\033[0m\n", $0 } }'
    }
    return "${_status}"
  }
}

declare -ax SSH_EXPORT_FUN=('do_print_debug')
declare -ax SSH_EXPORT_VAR=('OPTION_DEBUG' 'SSH_EXPORT_VAR' 'SSH_EXPORT_FUN')
define_util_ssh() {
  do_ssh_export() {
    for i in "${@}"; do
      local _name="${i}"
      if [ "$(type -t "${_name}")" = 'function' ]; then
        if [[ "${SSH_EXPORT_FUN[*]}" =~ ${_name} ]]; then return; fi
        SSH_EXPORT_FUN+=("${_name}")
      else
        if [ -z "${!_name}" ]; then
          echo "## $(whoami)@$(hostname): not a function/variable name '${_name}'" >&2
          continue
        else
          if [[ "${SSH_EXPORT_VAR[*]}" =~ ${_name} ]]; then return; fi
          SSH_EXPORT_VAR+=("${_name}")
        fi
      fi
    done
  }
  do_ssh_export_clear() {
    SSH_EXPORT_FUN=('do_print_debug')
    SSH_EXPORT_VAR=('OPTION_DEBUG' 'SSH_EXPORT_VAR' 'SSH_EXPORT_FUN')
  }
  do_ssh_invoke() {
    local _ssh="${1}"
    local _func_name="${2}"
    do_ssh_export "${_func_name:?}"
    do_ssh_exec "${_ssh:?}" "${@:2}"
  }
  do_ssh_exec_chain() {
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
    for i in "${SSH_EXPORT_VAR[@]}"; do
      printf -v _command '%s\n%s' "$(declare -p "${i}")" "${_command}"
    done
    for i in "${SSH_EXPORT_FUN[@]}"; do
      printf -v _command '%s\n%s' "$(declare -f "${i}")" "${_command}"
    done
    local _hint
    _hint="[$(date)] --> ${_ssh:?}"
    printf -v _command '%s\n%s' "## BEGIN: ${_hint}" "${_command}"
    printf -v _command '%s\n%s' "${_command}" "## END: ${_hint}"
    do_print_debug "${_command}"
    echo "${_command}" | ${_ssh} -- /bin/bash -eo pipefail -s -
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
    UPLOAD_USER_HOST="${UPLOAD_SSH_USER}@${UPLOAD_SSH_HOST}"
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
    JUMPER_USER_HOST="${DEPLOY_SSH_USER}@${JUMPER_SSH_HOST}"
    UPLOAD_SSH_USER="${UPLOAD_SSH_USER:=${JUMPER_SSH_USER:-${SSH_USER:?}}}"
  }
  do_ssh_add_user() {
    do_print_info "# ${FUNCNAME[*]}"
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
    _uid=$($_ssh "${_user_host}" 'id') && do_print_info "SSH ADD USER OK ($_uid)"
    local _status="${?}"
    if [ 0 = ${_status} ]; then
      if [[ ! "${ADDED_USER_HOST[*]}" =~ ${_user_host} ]]; then
        ADDED_USER_HOST+=("${_user_host}")
      fi
    fi
    do_print_info 'SSH ADD USER DONE' "ssh exit with status ${_status}"
  }
  do_ssh_reset_service() {
    SERVICE_USER="$(_service_ssh_variable 'SERVICE_SSH_USER')"
    do_print_dash_pair 'SERVICE_USER' "${SERVICE_USER}"
    SERVICE_HOST="$(_service_ssh_variable 'SERVICE_SSH_HOST')"
    do_print_dash_pair 'SERVICE_HOST' "${SERVICE_HOST}"
    SERVICE_USER_HOST="${SERVICE_USER:?}@${SERVICE_HOST:?}"
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
      declare -p "${_name}"
    fi
  }
  _ssh_add_key() {
    echo "${1:?}" | tr -d '\r' | ssh-add - >/dev/null
    #do_print_info "# ssh-add $?"
  }
  _ssh_add_known() {
    echo "${1:?}" >>~/'.ssh/known_hosts'
  }
  _ssh_agent_init() {
    if [ -z "$(command -v ssh-agent)" ]; then
      do_print_warn 'Error: ssh-agent is not installed'
      exit 120
    fi
    if [ -z "$(command -v ssh-add)" ]; then
      do_print_warn 'Error: ssh-add is not installed'
      exit 120
    fi
    eval "$(ssh-agent -s)" &>/dev/null
    do_print_info "- ssh-agent status code ${?}"
    mkdir -p ~/.ssh
    touch ~/.ssh/known_hosts
    chmod 644 ~/'.ssh/known_hosts'
    chmod 700 ~/'.ssh'
  }
}

define_util_vault() {
  do_vault_bash_inject() {
    local _url="${1}"
    local _func="${2}"
    if [ -z "${_url}" ]; then
      return
    fi
    do_print_info "# ${2} ${FUNCNAME[*]}"
    if [ "$(type -t "${_func:?}")" != function ]; then
      do_print_warn "- Function '${_func}' is undefined"
      return
    fi
    do_print_info "- fetch from vault: ${_url}"
    local _command
    _command="$(eval "${_func}" "${_url}" "${VAULT_TOKEN:?}")"
    local _line_count
    _line_count=$(echo "${_command}" | wc -l | xargs)
    do_print_debug "${_command}"
    do_print_info "- fetch from vault: ${_line_count} lines"
    eval "${_command}"
  }
  do_vault_check() {
    if [ -z "$(command -v jq)" ]; then
      return 2
    fi
    if [ -z "$(command -v curl)" ]; then
      return 1
    fi
    return 0
  }
  do_vault_with_ssh() {
    local _local_func_name="${1}"
    do_ssh_export do_vault_check do_vault_fetch_local
    local _user_host=${UPLOAD_USER_HOST:-${JUMPER_USER_HOST:-${SSH_USER_HOST}}}
    do_ssh_invoke "${_user_host:?}" "${_local_func_name:?}" "${*:2}" 2>/dev/null
  }
  do_vault_fetch_env_file() { do_vault_with_ssh_or_local "${FUNCNAME[0]}" "${@}"; }
  do_vault_fetch_env_file_local() {
    local _url="${1}"
    local _token="${2}"
    local _jq_cmd='.data | to_entries[] | "\(.key)=\(.value)"'
    do_vault_fetch_local "${_url:?}" "${_token:?}" "${_jq_cmd}"
  }
  do_vault_fetch_bash_env() { do_vault_with_ssh_or_local "${FUNCNAME[0]}" "${@}"; }
  do_vault_fetch_bash_env_local() {
    local _url="${1}"
    local _token="${2}"
    local _jq_cmd=$'.data | to_entries[] | "export \(.key)=$\'\(.value)\'"'
    do_vault_fetch_local "${_url:?}" "${_token:?}" "${_jq_cmd}"
  }
  do_vault_fetch_bash_file() { do_vault_fetch_with_key "${@}" 'BASH_FILE'; }
  do_vault_fetch_with_key() { do_vault_with_ssh_or_local "${FUNCNAME[0]}" "${@}"; }
  do_vault_fetch_with_key_local() {
    local _url="${1}"
    local _token="${2}"
    local _key="${3}"
    local _jq_cmd=".data.${_key}"
    do_vault_fetch_local "${_url:?}" "${_token:?}" "${_jq_cmd}"
  }
  do_vault_with_ssh_or_local() {
    local _func_name="${1}_local"
    if ! do_vault_check; then
      do_vault_with_ssh "${_func_name:?}" "${*:2}"
      do_ssh_export_clear
    else
      eval "${_func_name:?}" "${*:2}"
    fi
  }
  do_vault_fetch_local() {
    local _url="${1}"
    local _token="${2}"
    local _jq_cmd="${3}"
    local _value
    printf '%s\n' "## fetch from vault: ${_url:?} .data.${_key:-"*"} -- $(whoami)@$(hostname)"
    if ! do_vault_check; then return; fi
    _value=$(jq -r "${_jq_cmd:?}" <<<"$(curl --max-time 5 -s "${_url}" -H "X-Vault-Token: ${_token:?}")" 2>/dev/null)
    local _status="${?}"
    if [ '0' = "${_status}" ] && [ -n "${_value}" ] && [ 'null' != "${_value}" ]; then
      printf '%s\n' "${_value}"
    fi
    printf '%s\n' "## fetch from vault exit status ${_status}"
  }
}

define_util_print() {
  do_print_variable() {
    local _prefix="${1}"
    local _name="${2:?}"
    local _suffix="${3}"
    local _name3="${_prefix}${_name}$_suffix"
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
      printf "#---- ${_color}%s-- %s${_clear}\n" 'DEBUG BEGIN --' "${FUNCNAME[*]:1:${_n}}"
      printf "%s\n" "${@}" | awk '{printf "#%3d| \033[0;35m%s\033[0m\n", NR, $0}'
      printf "#---- ${_color}%s-- %s${_clear}\n" 'DEBUG END ----' "${FUNCNAME[*]:1:${_n}}"
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
  do_func_invoke() {
    local _func_name="${1}"
    if [ "$(type -t "${_func_name:?}")" != function ]; then
      do_print_info "# $_func_name is absent as a function"
    else
      do_print_info "# $_func_name"
      eval "${@}"
    fi
  }
  init_first_do() {
    do_func_invoke 'init_first_custom_do'
    do_print_section 'INIT ALL BEGIN'
    _init_env_var
    _init_version_tag
    do_print_dash_pair
  }
  init_final_do() {
    do_func_invoke 'init_final_custom_do'
    do_print_section 'INIT ALL DONE!' && echo ''
  }
  init_inject_env_bash_do() {
    _reset_injection_vault_url 'env'
    do_vault_bash_inject "${INJECTION_VAULT_URL}" 'do_vault_fetch_bash_env'
  }
  init_inject_ci_bash_do() {
    _reset_injection_vault_url 'ci'
    do_vault_bash_inject "${INJECTION_VAULT_URL}" 'do_vault_fetch_bash_file'
  }
  init_inject_cd_bash_do() {
    _reset_injection_vault_url 'cd'
    do_vault_bash_inject "${INJECTION_VAULT_URL}" 'do_vault_fetch_bash_file'
  }
  _reset_injection_vault_url() {
    local _type="${1}"
    if [ -n "${VAULT_URL_GITLAB}" ]; then
      INJECTION_VAULT_URL="${VAULT_URL_GITLAB}-${_type:?}"
      return
    fi
    INJECTION_VAULT_URL=''
    if [ -z "${CI_PROJECT_NAME}" ]; then
      do_print_info "- Abort vault injection: 'CI_PROJECT_NAME' is absent"
      return
    fi
    if [ -z "${CUSTOMER}" ]; then
      do_print_info "- Abort vault injection: 'CUSTOMER' is absent"
      return
    fi
    if [ -z "${VAULT_URL}" ]; then
      do_print_info "- Abort vault injection: 'VAULT_URL' is absent"
      return
    fi
    if [ -z "${VAULT_TOKEN}" ]; then
      do_print_info "- Abort vault injection: 'VAULT_TOKEN' is absent"
      return
    fi
    INJECTION_VAULT_URL="${VAULT_URL}/gitlab/${CI_PROJECT_NAME}/${CUSTOMER}-${_type:?}"
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
    VERSION_BUILDING="${CD_VERSION_TAG:?}_${CI_PIPELINE_ID:?}"
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
    _ssh_agent_init
    do_ssh_add_user_default
    init_inject_env_bash_do
  }
}

#===============================================================================

define_common_build() {
  do_build_ci_info() {
    local _template_file="${1}"
    local _sed='sed -i -e'
    do_print_info 'BUILD CI/CD INFO' "${_template_file:?}"
    $_sed "s|#CD_ENVIRONMENT|${ENV_NAME:?}|g" "$_template_file"
    $_sed "s|#CD_VERSION_TAG|${CD_VERSION_TAG:?}|g" "$_template_file"
    $_sed "s|#CI_COMMIT_TAG|${CI_COMMIT_TAG}|g" "$_template_file"
    $_sed "s|#CI_PIPELINE_ID|${CI_PIPELINE_ID}|g" "$_template_file"
    $_sed "s|#CI_JOB_ID|${CI_JOB_ID}|g" "$_template_file"
    $_sed "s|#CI_COMMIT_REF_NAME|${CI_COMMIT_REF_NAME}|g" "$_template_file"
    $_sed "s|#CI_COMMIT_SHA|${CI_COMMIT_SHA}|g" "$_template_file"
    $_sed "s|#CI_COMMIT_SHORT_SHA|${CI_COMMIT_SHORT_SHA}|g" "$_template_file"
    $_sed "s|#CI_COMMIT_TITLE|${CI_COMMIT_TITLE}|g" "$_template_file"
    do_print_info 'BUILD CI/CD INFO DONE'
  }
} # define_common_build

#===============================================================================

define_common_upload() {
  do_upload() {
    do_print_info 'UPLOAD SERVICE'
    SERVICE_NAME="${1}"
    SERVICE_GROUP="${2}"
    UPLOAD_REMOTE_DIR="/home/${UPLOAD_SSH_USER:?}/${SERVICE_GROUP:?}/${SERVICE_NAME:?}-${CD_VERSION_TAG:?}"
    do_print_dash_pair 'RUNNER_LOCATION' "$(whoami)@$(hostname):${RUNNER_LOCAL_DIR:?}"
    do_print_dash_pair 'REMOTE_LOCATION' "${UPLOAD_USER_HOST:?}:${UPLOAD_REMOTE_DIR}"
    find "${RUNNER_LOCAL_DIR}" -type d -exec chmod 774 {} +
    find "${RUNNER_LOCAL_DIR}" -type f -exec chmod 660 {} +
    find "${RUNNER_LOCAL_DIR}" -type f -exec ls -lhA {} +
    do_print_info 'UPLOAD   ' "$(date +'%T')"
    local _dir="${UPLOAD_REMOTE_DIR:?}"
    local _scp="scp -rpC -o StrictHostKeyChecking=no"
    do_ssh_export do_print_warn do_dir_make do_dir_clean
    do_ssh_upload_invoke upload_clean_dir_do "${_dir}"
    do_ssh_export_clear
    if ! $_scp "${RUNNER_LOCAL_DIR}/"* "${UPLOAD_USER_HOST:?}:${UPLOAD_REMOTE_DIR}/"; then
      do_print_warn 'UPLOAD FAILED'
      exit 120
    else
      do_print_info 'UPLOAD OK' "$(date +'%T')"
      do_ssh_export do_dir_list
      do_ssh_upload_invoke upload_cd_version_file_do "${_dir}" "${VERSION_BUILDING:?}"
      do_ssh_export_clear
    fi
    do_upload_cleanup_local
    do_print_info 'UPLOAD SERVICE DONE'
  }
  do_upload_cleanup_local() {
    do_print_info 'UPLOAD CLEANUP LOCAL'
    RUNNER_LOCAL_DIR="${CI_PROJECT_DIR:?}/tmp/upload"
    mkdir -p "${RUNNER_LOCAL_DIR:?}"
    rm -rf "${RUNNER_LOCAL_DIR:?}/"* && do_print_info 'UPLOAD CLEANUP LOCAL OK'
  }
  upload_clean_dir_do() {
    do_dir_clean "${1}"
    do_dir_make "${1}"
  }
  upload_cd_version_file_do() {
    local _dir="${1}"
    local _version="${2}"
    cd "${_dir:?}" && touch ./CD_VERSION &&
      echo "${_version:?}" >./CD_VERSION && chmod 640 ./CD_VERSION
    do_dir_list "${_dir}"
  }
} # define_common_upload

#===============================================================================

define_common_service() {
  do_on_jumper_host() {
    if [ -n "${1}" ]; then do_on_jumper_host_1="${1}"; fi
    # shellcheck disable=SC2029
    ssh "${JUMPER_USER_HOST:?}" "${do_on_jumper_host_1:?}"
  }
  do_on_deploy_host() {
    if [ -n "${1}" ]; then do_on_deploy_host_1="${1}"; fi
    # shellcheck disable=SC2029
    ssh "${JUMPER_USER_HOST:?}" "ssh \"${SERVICE_USER_HOST:?}\" $'${do_on_deploy_host_1:?}'"
  }
  do_cat_running_version() {
    do_on_deploy_host "
      if [ 1 = \$($_container_cmd ps -a | grep '${SERVICE_NAME}' | wc -l || echo 0) ]; then
        $_container_cmd exec ${SERVICE_NAME} cat ${CONTAINER_WORK_DIR}/CD_VERSION 2>/dev/null || echo 0
      else echo 0; fi "
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
    do_ssh_export SERVICE_NAME
    do_ssh_export SERVICE_DIR
    do_ssh_export do_print_trace
    do_ssh_server_invoke _service_info_print "${_container_cmd:?}" &&
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
    _service_vault_reset
    SERVICE_UPLOAD_DIR="/home/${UPLOAD_SSH_USER:?}/${SERVICE_GROUP}/${SERVICE_NAME}-${CD_VERSION_TAG:?}"
    UPLOAD_LOCATION="${UPLOAD_SSH_USER}@${JUMPER_SSH_HOST}:${SERVICE_UPLOAD_DIR}"
    do_print_dash_pair 'UPLOAD_LOCATION' "${UPLOAD_LOCATION}"
    [ -z "${CONTAINER_WORK_DIR}" ] && CONTAINER_WORK_DIR="/home/${SERVICE_USER}"
    _service_reset_status
    _service_check_version
  }
  _service_info_print() {
    local _container_cmd="${1:?}"
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
  _service_vault_reset() {
    SERVICE_VAULT_TOKEN="$(_service_vault_variable 'VAULT_TOKEN_RUNTIME')"
    [ -z "${SERVICE_VAULT_TOKEN}" ] && SERVICE_VAULT_TOKEN="${VAULT_TOKEN}"
    SERVICE_VAULT_URL="$(_service_vault_variable 'VAULT_URL_RUNTIME')"
    [ -z "${SERVICE_VAULT_URL}" ] && SERVICE_VAULT_URL="${VAULT_URL}"
    SERVICE_VAULT_URL="${SERVICE_VAULT_URL}/runtime"
    do_print_dash_pair 'SERVICE_VAULT_URL' "${SERVICE_VAULT_URL}"
  }
  _service_vault_variable() {
    local _prefix=''
    [ -n "${CUSTOMER}" ] && _prefix="$(echo "${CUSTOMER}" | tr '[:lower:]' '[:upper:]')_"
    local _suffix=''
    [ -n "${ENV_NAME}" ] && _suffix="_$(echo "${ENV_NAME}" | tr '[:lower:]' '[:upper:]')"
    do_print_variable "${_prefix//-/_}" "${1:?}" "${_suffix}"
  }
  _service_reset_status() {
    do_print_dash_pair 'Runtime Variables'
    SERVICE_HOST_UID=$(do_on_deploy_host 'id')
    do_print_dash_pair 'SERVICE_HOST_UID' "${SERVICE_HOST_UID}"
    IS_PODMAN_HOST=$(do_on_deploy_host 'if ! command -v podman-compose &>/dev/null; then echo no; else echo yes; fi')
    do_print_dash_pair 'IS_PODMAN_HOST' "${IS_PODMAN_HOST}"
    if [ 'yes' = "${IS_PODMAN_HOST}" ]; then
      _container_cmd='sudo podman'
    else _container_cmd='docker'; fi
  }
  _service_check_version() {
    _cd_version_file=${SERVICE_UPLOAD_DIR}/CD_VERSION
    VERSION_DEPLOYING=$(do_on_jumper_host "cat $_cd_version_file 2>/dev/null || echo 0")
    if [ 'yes' = "${OPTION_FORCE_DEPLOY}" ]; then
      VERSION_BUILDING="${VERSION_DEPLOYING:=1}"
    fi
    do_print_dash_pair 'VERSION_BUILDING' "${VERSION_BUILDING:?}"
    do_print_dash_pair 'VERSION_DEPLOYING' "${VERSION_DEPLOYING}"
    VERSION_RUNNING=$(do_on_deploy_host "$_container_cmd exec ${SERVICE_NAME} \
    cat ${CONTAINER_WORK_DIR:?}/CD_VERSION 2>/dev/null || echo 0")
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
  do_deploy() {
    do_print_info 'DEPLOY SERVICE'
    SERVICE_NAME="${1:-${SERVICE_NAME:?}}"
    SERVICE_GROUP="${2:-${SERVICE_GROUP:?}}"
    SERVICE_NAME_LOWER="$(echo "${SERVICE_NAME:?}" | tr '[:upper:]' '[:lower:]' | tr '-' '_')"
    SERVICE_GROUP_LOWER="$(echo "${SERVICE_GROUP:?}" | tr '[:upper:]' '[:lower:]' | tr '-' '_')"
    service_common_do
    if [ "${VERSION_BUILDING:?}" != "${VERSION_DEPLOYING:?}" ]; then
      do_print_info 'DEPLOY SERVICE REJECTED' "# package version is not ${VERSION_BUILDING}"
      return
    fi
    do_func_invoke deploy_patch_hook_do
    do_func_invoke "deploy_${SERVICE_NAME_LOWER}_patch_hook_do"
    _deploy_init
    _deploy_env
    _deploy_service
    do_print_info 'DEPLOY SERVICE DONE'
    do_inspect_container
  }
  do_deploy_vault_env() {
    do_print_info "# ${FUNCNAME[*]}"
    local _path="${1}"
    local _code
    [ -z "${_path}" ] && _path="${SERVICE_GROUP:?}/${CUSTOMER:?}-env"
    local _url="${SERVICE_VAULT_URL:?}/${_path}"
    do_print_info "- fetch from vault: ${_url}"
    _code="$(do_vault_fetch_env_file "${_url}" "${SERVICE_VAULT_TOKEN:?}")"
    local _line_count
    _line_count=$(echo "${_code}" | wc -l | xargs)
    do_print_info "- fetch from vault: ${_line_count} lines"
    do_ssh_server_exec "printf '%s\n' '${_code}' >>'${DEPLOY_ENV_SRC:?}'"
  }
  do_deploy_vault_patch() {
    do_print_info "# ${FUNCNAME[0]}"
    local _file_path="${1}"
    local _type="${2:-etc}"
    local _content_key="${_file_path:?}"
    #_content_key="$(printf '%s' "${_file_path:?}" | tr '-' '_' | tr '.' '_')"
    _content_key="${_content_key//./_}"
    _content_key="${_content_key//-/_}"
    local _url="${VAULT_URL}/gitlab/${CI_PROJECT_NAME:?}/${CUSTOMER:?}-${_type}"
    local _remote_dir="${SERVICE_UPLOAD_DIR:?}/${_type}"
    local _remote_path="${_remote_dir}/${_file_path}"
    do_print_info "- fetch from ${_url} ## ${_content_key:?}"
    do_print_info "- fetch to ${UPLOAD_SSH_USER}@${JUMPER_SSH_HOST}:${_remote_path}"
    local _file_content
    _file_content="$(do_vault_fetch_with_key "${_url}" "${VAULT_TOKEN:?}" "${_content_key}")"
    if [ -z "${_file_content}" ]; then
      do_print_warn '- fetched nothing'
      return 0
    fi
    printf -v _file_content '"%q"' "${_file_content}"
    do_on_jumper_host "
    if [ ! -f ${_remote_path} ]; then touch ${_remote_path} && chmod 660 ${_remote_path}; fi
    printf '%s\n' \"${_file_content}\" >'${_remote_path}'
    ls -lh '${_remote_dir}'
    "
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
    do_on_jumper_host "mkdir -p ${_remote_dir}"
    do_print_info 'UPLOAD PATCH FROM' "${_local_dir}/*"
    do_print_info 'UPLOAD PATCH TO' "${_remote_dir}/"
    if ! $_scp "${_local_dir}/"* "${_remote_dir}/"; then
      do_print_warn 'UPLOAD PATCH FAILED'
    else
      do_print_info 'UPLOAD PATCH OK' "$(date +'%T')"
    fi
  }
  _deploy_init() {
    if [ 'yes' = "${IS_PODMAN_HOST}" ]; then
      _compose_env_name='container-compose.env'
      _compose_yml_name='container-compose.yml'
      _compose_cmd="sudo podman-compose -f $_compose_yml_name"
    else
      _compose_env_name='docker-compose.env'
      _compose_yml_name='docker-compose.yml'
      _compose_cmd="docker-compose -f $_compose_yml_name --compatibility"
    fi
    _scp="scp -rpC -o StrictHostKeyChecking=no"
    SERVICE_DEPLOY_DIR="${SERVICE_DIR}-${CD_VERSION_TAG:?}"
    DEPLOY_ENV_SRC="${SERVICE_DEPLOY_DIR}/env/$_compose_env_name"
    DEPLOY_YML_SRC="${SERVICE_DEPLOY_DIR}/env/$_compose_yml_name"
  }
  DECLARE_DO_TRACE=$(printf '%s' "do_trace() { \
    if   [ \$# -gt 1 ]; then printf \"\033[0;34m%s\033[0m %s\n\" \"\$1\" \"\$2\"; \
    elif [ \$# -gt 0 ]; then printf \"\033[0;34m%s\033[0m\n\"    \"\$1\";         \
    else printf \"\"; fi }; " | tr -s ' ')
  _deploy_env() {
    local _local_dir="${SERVICE_UPLOAD_DIR:?}/env"
    local _remote_dir="${SERVICE_DEPLOY_DIR:?}/env"
    local _u_ssh="ssh ${JUMPER_USER_HOST:?}"
    local _d_ssh="ssh ${SERVICE_USER_HOST:?}"
    CONTAINER_VERSION_MOUNT="- ./${SERVICE_NAME}/CD_VERSION:\${CONTAINER_WORK_DIR}/CD_VERSION:ro"
    CONTAINER_ENTRYPOINT_MOUNT="- ./${SERVICE_NAME}/bin/${SERVICE_NAME}.sh:/usr/local/bin/${SERVICE_NAME}:ro"
    $_u_ssh "
    ${DECLARE_DO_TRACE}
    if [ ! -d '$_local_dir' ]; then
      do_trace '### Not a directory: $_local_dir'
      exit 0
    fi
    do_trace '# find $_local_dir'
    find  '$_local_dir' -type f -exec ls -lhA {} +
    $_d_ssh 'mkdir -p $_remote_dir'
    do_trace '# scp  $_local_dir'
    $_scp '$_local_dir/'* ${SERVICE_USER_HOST}:$_remote_dir/
    $_d_ssh $'
      ${DECLARE_DO_TRACE}
      do_trace \'- replace ${DEPLOY_ENV_SRC}\'
      [ -f \'${DEPLOY_ENV_SRC}\' ] && {
        _eth0_ipv4=\$(/usr/sbin/ifconfig eth0 | grep \'inet \'| awk \'{print \$2}\')
        sed -i -e \'s|#CONTAINER_WORK_DIR|${CONTAINER_WORK_DIR}|g\'   ${DEPLOY_ENV_SRC}
        sed -i -e \"s|#VAULT_URL|${SERVICE_VAULT_URL}|g\"             ${DEPLOY_ENV_SRC}
        sed -i -e \"s|#VAULT_TOKEN|${SERVICE_VAULT_TOKEN}|g\"         ${DEPLOY_ENV_SRC}
        sed -i -e \"s|#DEPLOY_CUSTOMER|${CUSTOMER:?}|g\"              ${DEPLOY_ENV_SRC}
        sed -i -e \'s|#DEPLOY_ENV_NAME|${ENV_NAME:?}|g\'              ${DEPLOY_ENV_SRC}
        sed -i -e \"s|#DEPLOY_HOST_IP|\$_eth0_ipv4|g\"                ${DEPLOY_ENV_SRC}
      }
      do_trace \'- replace ${DEPLOY_YML_SRC}\'
      [ -f \'${DEPLOY_YML_SRC}\' ] && {
        sed -i -e \'s|#CONTAINER_VERSION_MOUNT|${CONTAINER_VERSION_MOUNT:?}|g\'       ${DEPLOY_YML_SRC}
        sed -i -e \'s|#CONTAINER_ENTRYPOINT_MOUNT|${CONTAINER_ENTRYPOINT_MOUNT:?}|g\' ${DEPLOY_YML_SRC}
      }
      do_trace \'# find $_remote_dir\'
      find \'$_remote_dir\' -type f -exec ls -lhA {} +
    ' "
    do_func_invoke deploy_env_hook_do
    do_func_invoke "deploy_${SERVICE_GROUP_LOWER}_env_hook_do"
    do_func_invoke "deploy_${SERVICE_NAME_LOWER}_env_hook_do"
  }
  _deploy_env_diff() {
    DECLARE_DO_DIFF="do_diff() {                                         \
      printf \'\033[0;34m%s\033[0m\n\' \"# diff \${1:?} \${2:?}\";       \
      diff --unchanged-line-format=\'\'                                  \
      --old-line-format=\"\033[0;31m- |%dn| %L\033[0m\"                  \
      --new-line-format=\"\033[0;32m+ |%dn| %L\033[0m\" \"\$1\" \"\$2\"; \
    }; "
    _diff_result=$(
      do_on_deploy_host "
      ${DECLARE_DO_TRACE}
      ${DECLARE_DO_DIFF}
      _new='${DEPLOY_ENV_SRC:?}'
      _old='${SERVICE_GROUP_DIR}/.env'
      if [ ! -f \"\$_old\" ]; then touch \"\$_old\"; fi
      do_diff \"\$_old\" \"\$_new\"
      _env_changed=\$?
      _new='${DEPLOY_YML_SRC:?}'
      _old='${SERVICE_GROUP_DIR}/$_compose_yml_name'
      if [ ! -f \"\$_old\" ]; then touch \"\$_old\"; fi
      do_diff \"\$_old\" \"\$_new\"
      _yml_changed=\$?
      do_trace \"# diff result: env(\$_env_changed) yml(\$_yml_changed)\"
      if [ 1 = \$_env_changed ] || [ 1 = \$_yml_changed ];
      then echo 'yes';
      else echo ' no'; fi "
    )
    echo "${_diff_result:0:${#_diff_result}-3}"
    ENV_CHANGED=$(echo "${_diff_result: -3}" | xargs)
    do_print_dash_pair 'ENV_CHANGED' "${ENV_CHANGED}"
  }
  _deploy_service() {
    DECLARE_DO_CHECK_CONTAINER="do_check_container() {   \
      if [ 1 = \$($_container_cmd ps -a | grep \'${SERVICE_NAME}\' | wc -l || echo 0) ]; then \
        _container_created=\'yes\';      \
      else _container_created=\'no\'; fi \
    }; "
    _deploy_env_diff
    ENV_BACKUP_NAME="backup.$(date +'%Y%m%d.%H%M%S')"
    do_print_dash_pair 'ENV_BACKUP_NAME' "${ENV_BACKUP_NAME}"
    local _u_ssh="ssh ${JUMPER_USER_HOST}"
    local _d_ssh="ssh ${SERVICE_USER_HOST}"
    local _local_dir="${SERVICE_UPLOAD_DIR}"
    local _remote_dir="${SERVICE_DEPLOY_DIR}"
    local _container_stop_cmd="$_container_cmd stop"
    local _rsync_cmd='rsync -avr'
    $_u_ssh "
    $_d_ssh $'
      ${DECLARE_DO_TRACE}
      ${DECLARE_DO_CHECK_CONTAINER}
      do_backup() {
        cd $_remote_dir/..
        echo \"\$(cat \${1}) -- \${1}\" >> ./${ENV_BACKUP_NAME}/service_versions
      };
      do_check_container
      if [ \'yes\' != \"\$_container_created\" ]; then
        exit 0
      fi
      if [ \'yes\' != \'${ENV_CHANGED:?}\' ]; then
        do_trace \'# $_container_cmd stop\'
        $_container_stop_cmd ${SERVICE_NAME}
        do_trace \"# $_container_cmd stop exited with status \$?\"
      else
        cd $_remote_dir/..
        mkdir -p ./${ENV_BACKUP_NAME}
        touch ./${ENV_BACKUP_NAME}/service_versions
        do_trace \'# do_backup\'
        export -f do_backup
        find \'$_remote_dir\' -type f -name \'CD_VERSION\' -exec bash -c \'do_backup \"\$0\"\' {} \;
        do_trace \'# do_backup done\'
        do_trace \'# $_compose_cmd down\'
        $_compose_cmd down
        do_trace \"# $_compose_cmd down exited with status \$?\"
        mv ./$_compose_yml_name ./${ENV_BACKUP_NAME}/
        mv ./.env ./${ENV_BACKUP_NAME}/$_compose_env_name
      fi
    '
    ${DECLARE_DO_TRACE}
    do_trace '# find $_local_dir'
    cd '$_local_dir'
    find '$_local_dir' -type f -exec ls -lhA {} +
    do_trace '# $_rsync_cmd --exclude env/* $_local_dir/ ${SERVICE_USER_HOST:?}:$_remote_dir'
    $_rsync_cmd --exclude 'env/*' '$_local_dir/' '${SERVICE_USER_HOST:?}:$_remote_dir'
    $_d_ssh $'
      ${DECLARE_DO_TRACE}
      ${DECLARE_DO_CHECK_CONTAINER}
      [ -d \'$_remote_dir/native\' ] && chmod 600 \'$_remote_dir/native/\'*
      [ -d \'$_remote_dir/bin\' ] && chmod 700 \'$_remote_dir/bin/\'*
      [ -d \'$_remote_dir/env\' ] && chmod 600 \'$_remote_dir/env/\'*
      [ -d \'$_remote_dir/etc\' ] && chmod 600 \'$_remote_dir/etc/\'*
      [ -d \'$_remote_dir/lib\' ] && chmod 600 \'$_remote_dir/lib/\'*
      [ -d \'$_remote_dir/log\' ] && chmod 640 \'$_remote_dir/log/\'*
      [ -d \'$_remote_dir/log\' ] && chmod 750 \'$_remote_dir/log\'
      [ -d \'$_remote_dir/tmp\' ] && chmod 750 \'$_remote_dir/tmp\'
      do_trace \'# find $_remote_dir\'
      find    \'$_remote_dir\' -type f -exec ls -lhA {} +
      ln -sfn \'$_remote_dir\' \'$_remote_dir/CD_LINK\'
      mv -Tf  \'$_remote_dir/CD_LINK\' ${SERVICE_DIR:?} && {
        do_check_container
        if [ \'yes\' != \'${ENV_CHANGED}\' ] && [ \'yes\' = \"\$_container_created\" ]; then
          do_trace \'# $_container_cmd start\'
          $_container_cmd start ${SERVICE_NAME}
          do_trace \"# $_container_cmd start exited with status \$?\"
        else
          cd $_remote_dir/..
          cp --preserve $_remote_dir/env/$_compose_env_name ./.env
          cp --preserve $_remote_dir/env/$_compose_yml_name ./
          do_trace \'# $_compose_cmd up -d\'
          $_compose_cmd up -d
          do_trace \"# $_compose_cmd up -d exited with status \$?\"
        fi
      }
    ' "
    _deploy_write_log
  }
  _deploy_write_log() {
    do_print_info 'WRITE DEPLOY LOG'
    local _now
    _now=$(date +'%Y-%m-%d %T %Z')
    local _log_line="[$_now] [${VERSION_DEPLOYING}] [${CI_JOB_STAGE} ${CI_JOB_NAME}] [${CI_PIPELINE_ID} ${CI_JOB_ID}]"
    local _log_file="${SERVICE_DIR:?}/CD_VERSION_LOG"
    do_on_deploy_host "
      if [ ! -f $_log_file ]; then
        touch $_log_file && chmod 640 $_log_file
      fi
      echo $_log_line >> $_log_file
      tail -3 $_log_file
      _lines=\$(cat $_log_file | wc -l)
      if [ \$_lines -gt 200 ]; then
        echo \"\$(tail -200 $_log_file)\" > $_log_file
      fi
    " && do_print_info 'WRITE DEPLOY LOG OK'
  }
} # define_common_deploy

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
