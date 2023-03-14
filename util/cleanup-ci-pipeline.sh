#!/bin/bash
set -eo pipefail

## https://docs.gitlab.com/15.9/ee/api/rest/

declare -xr GITLAB_API_URL="${GITLAB_API_URL:-https://gitlab.com/api/v4}"
declare -xr HEADER_TOKEN="PRIVATE-TOKEN: ${GITLAB_API_TOKEN:?}"
declare -xr GITLAB_PROJECT_ID="${GITLAB_PROJECT_ID:-${1}}"
declare -xr PER_PAGE=${GITLAB_PIPELINE_RESERVED_PAGES:-15}
declare -xr RESERVED_PAGES=${GITLAB_PIPELINE_RESERVED_PAGES:-20}

echo "GITLAB_API_URL    :" "${GITLAB_API_URL}"
echo "GITLAB_PROJECT_ID :" "${GITLAB_PROJECT_ID}"
echo "PER_PAGE          :" "${PER_PAGE}"
echo "RESERVED_PAGES    :" "${RESERVED_PAGES}"

cleanup_ci_pipeline() {
  local _url="${GITLAB_API_URL}/projects?per_page=100&sort=asc"
  while IFS='' read -r _project_id; do
    echo "cleanup_ci_pipeline -> delete_pipeline_project <${_project_id:?}>"
    delete_pipeline_project "${_project_id:?}"
  done < <(curl -s --header "${HEADER_TOKEN:?}" "${_url}" | jq -r '.[] .id')
}

delete_pipeline_project() {
  local _project_id="${1}"
  local _url="${GITLAB_API_URL}/projects/${_project_id:?}/pipelines?per_page=${PER_PAGE:?}"
  while IFS=':' read -r key value; do
    # remove leading whitespace characters
    value="${value#"${value%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    value="${value%"${value##*[![:space:]]}"}"
    key=$(echo "${key}" | tr '[:upper:]' '[:lower:]')
    case "${key}" in
    'x-total') _total_item="$value" ;;
    'x-total-pages') _total_page="$value" ;;
    *) ;;
    esac
  done < <(curl -s --header "${HEADER_TOKEN:?}" -I -X HEAD "${_url}")
  echo "Project:<$_project_id> Pipelines:[$_total_item] Pages:[$_total_page]"
  if [ "$_total_page" -gt "${RESERVED_PAGES:?}" ]; then
    delete_pipeline_page "${_project_id:?}" "$_total_page"
  else
    echo "Project:<$_project_id> Canceled"
  fi
}

delete_pipeline_page() {
  local _project_id="${1}"
  local _page="${2}"
  local _url="${GITLAB_API_URL}/projects/${_project_id:?}/pipelines?sort=desc&per_page=${PER_PAGE:?}&page=${_page:?}"
  local _array=()
  while IFS='' read -r _pipeline_id; do
    _array=("${_pipeline_id}" "${_array[@]}")
  done < <(curl -s --header "${HEADER_TOKEN:?}" "$_url" | jq -r '.[] .id')
  for _pipeline_id in "${_array[@]}"; do
    local _pipeline_url="${GITLAB_API_URL}/projects/${_project_id:?}/pipelines/${_pipeline_id}"
    echo "Deleting: ${_pipeline_url}"
    (curl -s --header "${HEADER_TOKEN:?}" --request "DELETE" "${_pipeline_url}") &
  done
  wait
  delete_pipeline_project "${_project_id:?}"
}

if [ -z "${GITLAB_PROJECT_ID}" ]; then
  cleanup_ci_pipeline
else
  delete_pipeline_project "${GITLAB_PROJECT_ID}"
fi

## 2023-03-14
