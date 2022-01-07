#!/bin/bash
set -eo pipefail

declare -rx GITLAB_API_URL="${GITLAB_API_URL:?}"
declare -rx HEADER_TOKEN="PRIVATE-TOKEN: ${GITLAB_API_TOKEN:?}"
declare -rx RESERVED_PAGES=${GITLAB_PIPELINE_RESERVED_PAGES:-15}

cleanup_ci_pipeline() {
  local _url="${GITLAB_API_URL}/projects?per_page=100&sort=asc"
  shopt -s extglob
  while IFS='' read -r _project_id; do
    delete_pipeline_project "${_project_id:?}"
  done < <(curl -s --header "${HEADER_TOKEN:?}" "${_url}" | jq -r '.[] .id')
}

delete_pipeline_project() {
  local _project_id="${1}"
  local _url="${GITLAB_API_URL}/projects/${_project_id:?}/pipelines?sort=asc"
  while IFS=':' read -r key value; do
    value=${value##+([[:space:]])}
    value=${value%%+([[:space:]])}
    case "$key" in
    'X-Total') _total_item="$value" ;;
    'X-Total-Pages') _total_page="$value" ;;
    *) ;;
    esac
  done < <(curl -s --header "${HEADER_TOKEN:?}" -I -X HEAD "${_url}")
  echo "Project:<$_project_id> Pipelines:[$_total_item] Pages:[$_total_page]"
  if [ "$_total_page" -gt "${RESERVED_PAGES:?}" ]; then
    delete_pipeline_page "${_project_id:?}" "$_total_page"
  fi
}

delete_pipeline_page() {
  local _project_id="${1}"
  local _page="${2}"
  local _url="${GITLAB_API_URL}/projects/${_project_id:?}/pipelines?page=${_page:?}"
  local _array=()
  while IFS='' read -r _pipeline_id; do
    _array+=("$_line")
  done < <(curl -s --header "${HEADER_TOKEN:?}" "$_url" | jq -r '.[] .id')
  for _pipeline_id in "${_array[@]}"; do
    local _pipeline_url="${GITLAB_API_URL}/projects/${_project_id:?}/pipelines/${_pipeline_id}"
    echo "Deleting: ${_pipeline_url}"
    (curl -s --header "${HEADER_TOKEN:?}" --request "DELETE" "${_pipeline_url}") &
  done
  wait
  delete_pipeline_project "${_project_id:?}"
}

cleanup_ci_pipeline
