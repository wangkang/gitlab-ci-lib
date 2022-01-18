#!/bin/bash
set -eo pipefail
do_vault_login() {
  if [ -n "${VAULT_TOKEN}" ]; then
    printf '%s' "${VAULT_TOKEN}"
    return
  fi
  echo "# vault login: '${VAULT_URL}' -- $(date)" >&2
  if [ -z "$(command -v jq)" ]; then
    echo '##jq is not installed' >&2
    return
  fi
  if [ -z "${VAULT_URL}" ]; then
    echo "##env variable 'VAULT_URL' is absent" >&2
    return
  fi
  if [ -z "${VAULT_USER}" ]; then
    echo "##env variable 'VAULT_USER' is absent" >&2
    return
  fi
  if [ -z "${VAULT_PASS}" ]; then
    echo "# env variable 'VAULT_PASS' is absent" >&2
    if [ -z "${VAULT_PASS_SYS}" ]; then
      echo "##env variable 'VAULT_PASS_SYS' is absent" >&2
      return
    fi
  fi
  _json="{\"password\":\"${VAULT_PASS:-${VAULT_PASS_SYS:?}}\"}"
  _url_login="${VAULT_URL:?}/auth/userpass/login/${VAULT_USER:?}"
  _token=$(curl -s --max-time 5 --request POST "${_url_login}" --data "${_json}" | jq -r '.auth.client_token')
  if [ -z "${_token}" ]; then
    echo '##vault login failed' >&2
    return
  fi
  export VAULT_TOKEN="${_token}"
  echo "# vault login token: '$(echo "${_token}" | cut -c 1-8) *** ***'" >&2
  printf '%s' "${_token}"
}
do_vault_fetch() {
  _path0="${1}"
  if [ '/' = "$(echo "${_path0:?}" | cut -c 1)" ]; then
    _path="${_path0}"
  else
    # shellcheck disable=SC2153
    _path="${VAULT_PATH}/${_path0}"
  fi
  [ '/' != "$(echo "${_path}" | cut -c 1)" ] && _path="/${_path}"
  _token="$(do_vault_login)"
  if [ -z "${_token}" ]; then return; fi
  _from_url="${VAULT_URL:?}${_path}"
  echo "# vault fetch: ${_from_url:?} -- $(date)" >&2
  set +e
  curl -s --max-time 5 "${_from_url:?}" -H "X-Vault-Token: ${_token:?}" 2>/dev/null
  echo "# vault fetch exit status $?" >&2
  set -e
}
do_vault_export() {
  echo "# vault export path: '${1}' -- $(date)"
  _jq_cmd=$'.data.data|select(.!=null)|to_entries[]|"export \(.key)=$\'\(.value)\';"'
  _code="$(do_vault_fetch "${1}" | jq -r "${_jq_cmd}")"
  echo "# vault export ${#_code} char(s)"
  if [ -n "${_code}" ]; then eval "${_code}"; fi
  echo "# vault export finished -- $(date)"
}
