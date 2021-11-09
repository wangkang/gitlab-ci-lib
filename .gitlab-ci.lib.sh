#!/bin/bash

set -e

#===============================================================================

build_job_do() {
  do_print_section 'BUILD JOB BEGIN'
  do_func_invoke "build_custom_do"
  do_print_section 'BUILD JOB DONE!' && echo ''
}
upload_job_do() {
  do_print_section 'UPLOAD JOB BEGIN'
  do_upload_cleanup_local
  do_func_invoke "upload_custom_do"
  do_print_section 'UPLOAD JOB DONE!' && echo ''
}
deploy_job_do() {
  do_print_section 'DEPLOY JOB BEGIN'
  do_func_invoke "deploy_custom_do"
  do_func_invoke "deploy_${ENV_NAME:?}_do"
  do_print_section 'DEPLOY JOB DONE!' && echo ''
}
verify_job_do() {
  do_print_section 'VERIFY JOB BEGIN'
  do_func_invoke "verify_custom_do"
  do_func_invoke "verify_${ENV_NAME:?}_do"
  do_print_section 'VERIFY JOB DONE!' && echo ''
}

#===============================================================================

declare_init_common() {
  do_func_invoke() {
    [ -n "${1}" ] && _func_name="${1}"
    if [[ $(type -t "${_func_name:?}") != function ]]; then
      do_print_info "# $_func_name is absent as a function"
    else
      do_print_info "# $_func_name"
      eval "$_func_name"
    fi
  }
  do_print_info() {
    if [ $# -gt 1 ]; then
      printf '\033[0;36m%s\033[0m %s\n' "$1" "$2"
    elif [ $# -gt 0 ]; then
      printf '\033[0;36m%s\033[0m\n' "$1"
    else printf ''; fi
  }
  do_print_warn() {
    if [ $# -gt 1 ]; then
      printf '\033[1;33m%s\033[0m %s\n' "$1" "$2"
    elif [ $# -gt 0 ]; then
      printf '\033[1;33m%s\033[0m\n' "$1"
    else printf ''; fi
  }
  do_print_dash_pair() {
    if [ -z "${SHORT_LINE}" ]; then
      SHORT_LINE='------------------------------'
    fi
    if [ $# -gt 1 ]; then
      key=${1:?} && val=${2}
      printf '\033[0;32m%s\033[0m \033[1;30m%s\033[0m [\033[0;32m%s\033[0m]\n' \
        "${key}" "${SHORT_LINE:${#key}}" "${val}"
    elif [ $# -gt 0 ]; then
      printf '\033[1;30m%s\033[0m\n' "${SHORT_LINE}-- ${1}"
    else
      printf '\033[1;30m%s\033[0m\n' "${SHORT_LINE}${SHORT_LINE}"
    fi
  }
  do_print_section() {
    if [ -z "${LONG_LINE}" ]; then
      LONG_LINE='===================================================================================================='
    fi
    if [ $# -gt 0 ]; then
      printf '\033[1;36m%s %s\033[0m %s\n' "${1}" "${LONG_LINE:${#1}}" "$(date +'%Y-%m-%d %T %Z')"
    else
      printf '\033[1;30m%s\033[0m\n' "${SHORT_LINE}--------------------"
    fi
  }
  init_first_do() {
    do_func_invoke 'init_first_custom_do'
    do_print_section 'INIT ALL BEGIN'
    _print_env_var
    _init_version_tag
    do_print_dash_pair
  }
  init_final_do() {
    do_func_invoke 'init_final_custom_do'
    do_print_section 'INIT ALL DONE!' && echo ''
  }
  _print_env_var() {
    do_print_dash_pair 'CI_COMMIT_REF_NAME' "${CI_COMMIT_REF_NAME}"
    do_print_dash_pair 'ENV_NAME' "${ENV_NAME:?}"
    do_print_dash_pair 'GIT_CHECKOUT' "${GIT_CHECKOUT}"
  }
  _init_ci_tag() {
    [[ -z "${CI_COMMIT_TAG}" ]] && CI_COMMIT_TAG=${CI_COMMIT_SHORT_SHA}
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
}

declare_init_ssh_common() {
  do_ssh_add_user() {
    _user_host="${ARG_SSH_USER:?}@${ARG_SSH_HOST:?}"
    do_print_info "SSH ADD USER $_user_host"
    if [ "$_user_host" = "${SSH_USER_HOST}" ]; then
      do_print_info 'SSH ADD USER OK (is default)'
      return
    fi
    [ -n "${ARG_SSH_KNOWN_HOSTS}" ] && _ssh_add_known "${ARG_SSH_KNOWN_HOSTS}"
    [ -n "${ARG_SSH_PRIVATE_KEY}" ] && _ssh_add_key "${ARG_SSH_PRIVATE_KEY}"
    # shellcheck disable=SC2086
    _uid=$(ssh ${SSH_DEBUG_OPTIONS} "$_user_host" 'id') && (
      do_print_info "SSH ADD USER OK $_uid"
    )
  }
  init_ssh_do() {
    _pri_line=$(echo "${SSH_PRIVATE_KEY}" | tr -d '\n')
    do_print_dash_pair 'Gitlab Custom Variables (ssh)'
    do_print_dash_pair 'SSH_HOST' "${SSH_HOST}"
    do_print_dash_pair 'SSH_PRIVATE_KEY' "${_pri_line:0:60} **"
    do_print_dash_pair 'SSH_KNOWN_HOSTS' "${SSH_KNOWN_HOSTS:0:60} **"
    _ssh_agent_init
    _ssh_default_user
  }
  _ssh_default_user() {
    if [[ -z "${SSH_USER}" && -n "${SSH_USER_PREFIX}" ]]; then
      SSH_USER="${SSH_USER_PREFIX}-${ENV_NAME:?}"
    fi
    ARG_SSH_USER=${SSH_USER:?}
    ARG_SSH_HOST="${SSH_HOST:?}"
    ARG_SSH_KNOWN_HOSTS="${SSH_KNOWN_HOSTS:?}"
    ARG_SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:?}"
    do_ssh_add_user
    SSH_USER_HOST="${SSH_USER}@${SSH_HOST}"
  }
  _ssh_add_key() {
    do_print_info "# ssh-add"
    echo "${1:?}" | tr -d '\r' | ssh-add - >/dev/null
    do_print_info "# ssh-add $?"
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
    do_print_info "# ssh-agent"
    eval "$(ssh-agent -s)"
    do_print_info "# ssh-agent $?"
    mkdir -p ~/.ssh
    touch ~/.ssh/known_hosts
    chmod 644 ~/'.ssh/known_hosts'
    chmod 700 ~/'.ssh'
  }
}

#===============================================================================

declare_build_common() {
  do_build_ci_info() {
    [ -n "${1}" ] && _template_file="${1}"
    do_print_info 'BUILD CI/CD INFO' "${_template_file:?}"
    sed -i -e "s|#CD_ENVIRONMENT|${ENV_NAME:?}|g" "$_template_file"
    sed -i -e "s|#CD_VERSION_TAG|${CD_VERSION_TAG:?}|g" "$_template_file"
    sed -i -e "s|#CI_COMMIT_TAG|${CI_COMMIT_TAG}|g" "$_template_file"
    sed -i -e "s|#CI_PIPELINE_ID|${CI_PIPELINE_ID}|g" "$_template_file"
    sed -i -e "s|#CI_JOB_ID|${CI_JOB_ID}|g" "$_template_file"
    sed -i -e "s|#CI_COMMIT_REF_NAME|${CI_COMMIT_REF_NAME}|g" "$_template_file"
    sed -i -e "s|#CI_COMMIT_SHA|${CI_COMMIT_SHA}|g" "$_template_file"
    sed -i -e "s|#CI_COMMIT_SHORT_SHA|${CI_COMMIT_SHORT_SHA}|g" "$_template_file"
    sed -i -e "s|#CI_COMMIT_TITLE|${CI_COMMIT_TITLE}|g" "$_template_file"
    do_print_info 'BUILD CI/CD INFO DONE'
  }
}

#===============================================================================

declare_upload_common() {
  do_upload() {
    _upload_init_ssh
    UPLOAD_USER_HOST="${ARG_SSH_USER}@${ARG_SSH_HOST}"
    do_print_info 'UPLOAD SERVICE'
    [ -n "${1}" ] && SERVICE_NAME="${1}"
    [ -n "${2}" ] && SERVICE_GROUP="${2}"
    RUNNER_USER_HOST="$(whoami)@$(hostname)"
    UPLOAD_REMOTE_DIR="/home/${UPLOAD_SSH_USER:?}/${SERVICE_GROUP:?}/${SERVICE_NAME:?}-${CD_VERSION_TAG:?}"
    do_print_dash_pair 'SERVICE_GROUP' "${SERVICE_GROUP}"
    do_print_dash_pair 'SERVICE_NAME' "${SERVICE_NAME}"
    do_print_dash_pair 'RUNNER_USER_HOST' "${RUNNER_USER_HOST}"
    do_print_dash_pair 'RUNNER_LOCAL_DIR' "${RUNNER_LOCAL_DIR}"
    do_print_dash_pair 'UPLOAD_USER_HOST' "${UPLOAD_USER_HOST}"
    do_print_dash_pair 'UPLOAD_REMOTE_DIR' "${UPLOAD_REMOTE_DIR}"
    find "${RUNNER_LOCAL_DIR:?}" -type f -exec ls -lhA {} +
    do_print_info 'UPLOAD   ' "$(date +'%T')"
    _ssh="ssh ${UPLOAD_USER_HOST}"
    _scp="scp -rpC -o StrictHostKeyChecking=no"
    $_ssh "mkdir -p ${UPLOAD_REMOTE_DIR}" || (
      do_print_warn 'mkdir fail'
      print_warn_do
      exit 120
    )
    _upload_cleanup_remote
    if ! $_scp "${RUNNER_LOCAL_DIR}"/* "${UPLOAD_USER_HOST:?}:${UPLOAD_REMOTE_DIR}/"; then
      do_print_warn 'UPLOAD FAILED'
      exit 120
    else
      do_print_info 'UPLOAD OK' "$(date +'%T')"
    fi
    $_ssh "cd ${UPLOAD_REMOTE_DIR}           \
      && touch ./CD_VERSION                  \
      && echo ${VERSION_BUILDING:?} > ./CD_VERSION \
      && find . -type d -exec chmod 750 {} + \
      && find . -type f -exec chmod 640 {} + \
      && find ${UPLOAD_REMOTE_DIR} -type f -exec ls -lhA {} + \
    " || (
      do_print_warn 'UPLOAD REMOTE JOB FAILED'
      print_warn_do
    )
    do_upload_cleanup_local
    do_print_info 'UPLOAD SERVICE DONE'
  }
  do_upload_cleanup_local() {
    do_print_info 'UPLOAD CLEANUP LOCAL'
    RUNNER_LOCAL_DIR="${CI_PROJECT_DIR:?}/tmp/upload"
    mkdir -p "${RUNNER_LOCAL_DIR:?}"
    rm -rf "${RUNNER_LOCAL_DIR:?}/"* && do_print_info 'UPLOAD CLEANUP LOCAL OK'
  }
  _upload_cleanup_remote() {
    do_print_info 'UPLOAD CLEANUP REMOTE'
    $_ssh "rm -rf '${UPLOAD_REMOTE_DIR:?}'/*" && do_print_info 'UPLOAD CLEANUP REMOTE OK'
  }
  _upload_init_ssh() {
    ARG_SSH_USER="${UPLOAD_SSH_USER:=${SSH_USER:?}}"
    ARG_SSH_PRIVATE_KEY="${UPLOAD_SSH_PRIVATE_KEY:=${SSH_PRIVATE_KEY}}"
    ARG_SSH_HOST="${JUMPER_SSH_HOST:=${SSH_HOST:?}}"
    ARG_SSH_KNOWN_HOSTS="${JUMPER_SSH_KNOWN_HOSTS:=${SSH_KNOWN_HOSTS}}"
    do_ssh_add_user
  }
}

#===============================================================================

declare_service_common() {
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
    if [[ "$_vr" && "$_vr" != '0' && "$_vr" != "${VERSION_RUNNING_NOW}" ]]; then
      do_print_dash_pair 'VERSION_STOPPED' "${VERSION_RUNNING}"
    fi
    do_on_deploy_host "
    do_trace() {
      if   [ \$# -gt 1 ]; then printf \"\033[0;34m%s\033[0m %s\n\" \"\$1\" \"\$2\";
      elif [ \$# -gt 0 ]; then printf \"\033[0;34m%s\033[0m\n\"    \"\$1\";
      else printf \"\"; fi
    }
    do_trace \'*** Currently deployed version:\'
    cat \'${SERVICE_DIR:?}/CD_VERSION\'
    do_trace \'*** Recent deployment log\'
    tail -n5 \'${SERVICE_DIR}/CD_VERSION_LOG\'
    if [ 1 = \$($_container_cmd ps -a | grep \'${SERVICE_NAME}\' | wc -l || echo 0) ]; then
      do_trace \'*** Container State:\'
      $_container_cmd inspect --type=container --format=\'{{json .State}}\' \'${SERVICE_NAME}\'
    else
      do_trace \'### Container is not created:\' \"${SERVICE_NAME}\"
    fi " && do_print_info "INSPECT OK [${SERVICE_LOCATION}]"
  }
  service_common_do() {
    do_print_dash_pair 'Required Arguments'
    do_print_dash_pair 'SERVICE_NAME' "${SERVICE_NAME:?}"
    do_print_dash_pair 'SERVICE_GROUP' "${SERVICE_GROUP:?}"
    _service_init_user_host
    _service_init_ssh
    JUMPER_USER_HOST="${ARG_SSH_USER}@${ARG_SSH_HOST}"
    UPLOAD_SSH_USER="${UPLOAD_SSH_USER:=${ARG_SSH_USER:-${SSH_USER:?}}}"
    do_print_dash_pair 'Common Variables'
    SERVICE_USER_HOST="${SERVICE_USER:?}@${SERVICE_HOST:?}"
    SERVICE_GROUP_DIR="/home/${SERVICE_USER}/${SERVICE_GROUP}"
    SERVICE_DIR="${SERVICE_GROUP_DIR}/${SERVICE_NAME}"
    SERVICE_LOCATION="${SERVICE_USER_HOST}:${SERVICE_DIR}"
    do_print_dash_pair 'SERVICE_LOCATION' "${SERVICE_LOCATION}"
    SERVICE_UPLOAD_DIR="/home/${UPLOAD_SSH_USER:?}/${SERVICE_GROUP}/${SERVICE_NAME}-${CD_VERSION_TAG:?}"
    UPLOAD_LOCATION="${JUMPER_USER_HOST}:${SERVICE_UPLOAD_DIR}"
    do_print_dash_pair 'UPLOAD_LOCATION' "${UPLOAD_LOCATION}"
    [ '' = "${CONTAINER_WORK_DIR}" ] && CONTAINER_WORK_DIR="/home/${SERVICE_USER}"
    _service_reset_status
    _service_check_version
  }
  _service_init_user_host() {
    ENV_SUFFIX_UPPER="_$(echo "${ENV_NAME}" | tr '[:lower:]' '[:upper:]')"
    _user_var_name="SERVICE_USER${ENV_SUFFIX_UPPER:?}"
    SERVICE_USER="${SERVICE_USER:-${SERVICE_SSH_USER:-${!_user_var_name}}}"
    do_print_dash_pair 'SERVICE_USER' "${SERVICE_USER}"
    _host_var_name="SERVICE_HOST${ENV_SUFFIX_UPPER:?}"
    SERVICE_HOST="${SERVICE_HOST:-${SERVICE_SSH_HOST:-${!_host_var_name}}}"
    do_print_dash_pair 'SERVICE_HOST' "${SERVICE_HOST}"
  }
  _service_init_ssh() {
    ARG_SSH_USER="${JUMPER_SSH_USER:=${SSH_USER:?}}"
    ARG_SSH_PRIVATE_KEY="${JUMPER_SSH_PRIVATE_KEY:-${SSH_PRIVATE_KEY}}"
    ARG_SSH_HOST="${JUMPER_SSH_HOST:=${SSH_HOST:?}}"
    ARG_SSH_KNOWN_HOSTS="${JUMPER_SSH_KNOWN_HOSTS:-${SSH_KNOWN_HOSTS}}"
    do_ssh_add_user
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
    do_print_dash_pair 'VERSION_BUILDING' "${VERSION_BUILDING:?}"
    VERSION_DEPLOYING=$(do_on_jumper_host "cat $_cd_version_file 2>/dev/null || echo 0")
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
} # declare_service_common

#===============================================================================

declare_verify_common() {
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

declare_deploy_common() {
  do_deploy() {
    do_print_info 'DEPLOY SERVICE'
    SERVICE_NAME="${1:-${SERVICE_NAME:?}}"
    SERVICE_GROUP="${2:-${SERVICE_GROUP:?}}"
    service_common_do
    if [ "${VERSION_BUILDING:?}" != "${VERSION_DEPLOYING:?}" ]; then
      do_print_info 'DEPLOY SERVICE REJECTED' "# package version is not ${VERSION_BUILDING}"
      return
    fi
    _deploy_init
    _deploy_env
    _deploy_service
    _deploy_write_log
    do_print_info 'DEPLOY SERVICE DONE'
    do_inspect_container
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
    _scp="scp -Cr -o StrictHostKeyChecking=no"
    SERVICE_DEPLOY_DIR="${SERVICE_DIR}-${CD_VERSION_TAG:?}"
    DEPLOY_ENV_SRC="${SERVICE_DEPLOY_DIR}/env/$_compose_env_name"
    DEPLOY_YML_SRC="${SERVICE_DEPLOY_DIR}/env/$_compose_yml_name"
  }
  DECLARE_DO_TRACE="do_trace() {                                                  \
    if   [ \$# -gt 1 ]; then printf \"\033[0;34m%s\033[0m %s\n\" \"\$1\" \"\$2\"; \
    elif [ \$# -gt 0 ]; then printf \"\033[0;34m%s\033[0m\n\"    \"\$1\";         \
    else printf \"\"; fi                                                          \
  }; "
  _deploy_env() {
    local _local_dir="${SERVICE_UPLOAD_DIR:?}/env"
    local _remote_dir="${SERVICE_DEPLOY_DIR:?}/env"
    local _u_ssh="ssh ${JUMPER_USER_HOST:?}"
    local _d_ssh="ssh ${SERVICE_USER_HOST:?}"
    CONTAINER_VERSION_MOUNT="- ./${SERVICE_NAME}/CD_VERSION:\${CONTAINER_WORK_DIR}/CD_VERSION:ro"
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
      [ -f \'${DEPLOY_ENV_SRC}\' ] && (
        _eth0_ipv4=\$(/usr/sbin/ifconfig eth0 | grep \'inet \'| awk \'{print \$2}\')
        sed -i -e \'s|#DEPLOY_ENV_NAME|${ENV_NAME:?}|g\'              ${DEPLOY_ENV_SRC}
        sed -i -e \"s|#DEPLOY_HOST_IP|\$_eth0_ipv4|g\"                ${DEPLOY_ENV_SRC}
        sed -i -e \'s|#CONTAINER_WORK_DIR|${CONTAINER_WORK_DIR:?}|g\' ${DEPLOY_ENV_SRC}
      )
      [ -f \'${DEPLOY_YML_SRC}\' ] && (
        sed -i -e \'s|#CONTAINER_VERSION_MOUNT|${CONTAINER_VERSION_MOUNT:?}|g\' ${DEPLOY_YML_SRC}
      )
      do_trace \'# find $_remote_dir\'
      find \'$_remote_dir\' -type f -exec ls -lhA {} +
    ' "
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
      if [[ 1 = \$_env_changed || 1 = \$_yml_changed ]];
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
    mv '$_local_dir/env' '$_local_dir/.env'
    find '$_local_dir' -type f -exec ls -lhA {} +
    $_scp '$_local_dir/'* \"${SERVICE_USER_HOST:?}:$_remote_dir/\"
    $_d_ssh $'
      ${DECLARE_DO_TRACE}
      ${DECLARE_DO_CHECK_CONTAINER}
      do_trace \'# find $_remote_dir\'
      find    \'$_remote_dir\' -type f -exec ls -lhA {} +
      ln -sfn \'$_remote_dir\' \'$_remote_dir/CD_LINK\'
      mv -Tf  \'$_remote_dir/CD_LINK\' ${SERVICE_DIR:?} && (
        [ -d \'$_remote_dir/bin\' ] && chmod u+x \'$_remote_dir/bin/\'*
        do_check_container
        if [[ \'yes\' != \'${ENV_CHANGED}\' && \'yes\' = \"\$_container_created\" ]]; then
          do_trace \'# $_container_cmd start\'
          $_container_cmd start ${SERVICE_NAME}
          do_trace \"# $_container_cmd start exited with status \$?\"
        else
          cd $_remote_dir/..
          mv $_remote_dir/env/$_compose_yml_name ./
          mv $_remote_dir/env/$_compose_env_name ./.env
          do_trace \'# $_compose_cmd up -d\'
          $_compose_cmd up -d
          do_trace \"# $_compose_cmd up -d exited with status \$?\"
        fi
      )
    '
    mv '$_local_dir/.env' '$_local_dir/env'
    "
  }
  _deploy_write_log() {
    do_print_info 'WRITE DEPLOY LOG'
    _job_tag="${CI_JOB_STAGE} ${CI_JOB_NAME} ${CI_JOB_ID}"
    _now=$(date +'%Y-%m-%d %T %Z')
    _log_line="[$_now] [${CI_COMMIT_SHORT_SHA}] [${CI_PIPELINE_ID}] [${CD_VERSION_TAG}] [$_job_tag]"
    _log_file="${SERVICE_DIR:?}/CD_VERSION_LOG"
    do_on_deploy_host "
      touch $_log_file              && \
      echo $_log_line >> $_log_file && \
      tail -n30 $_log_file          && \
      chmod 640 $_log_file
    " && do_print_info 'WRITE DEPLOY LOG OK'
  }
} # declare_deploy_common

#===============================================================================
