#!/usr/bin/env bash

set -eu -o pipefail

DIR="$(cd "$(dirname "$0")" ; pwd -P)"

CONFIG_FILE="${CONFIG_DIR:-${HOME}/.borg_backup.json}"

BACKUP_TEST_DIR="${HOME}/backup-test"
SSH_KEY="${SSH_KEY:-${HOME}/.ssh/id_rsa}"

function task_test {
  # create a testbed docker container that has the same user and homedir like the current user
  (
    cd "${DIR}/test"
    docker build \
      --build-arg USER_NAME=${USER} \
      --build-arg USER_HOME=${HOME} \
      -t bootstrap-testbed:${USER} \
      .
  )

  local backup_id="$(uuidgen)"
  source "${DIR}/bin/backup"

  divider_header "writing test data '${backup_id}' to '${BACKUP_TEST_DIR}/data' and execute backup"

  mkdir -p "${BACKUP_TEST_DIR}"
  echo "${backup_id}" > "${BACKUP_TEST_DIR}/data"
  backup_create "${BACKUP_TEST_DIR}"

  divider_footer

  rm -rf "${BACKUP_TEST_DIR}"
  (
    cd /
    backup_extract "${BACKUP_TEST_DIR}"
  )

  if [[ "${backup_id}" != "$(cat ${BACKUP_TEST_DIR}/data)" ]]; then
    echo "restore failed"
    exit 1
  fi
}

function divider_header() {
  echo "================================================================================"
  echo $@
  echo "--------------------------------------------------------------------------------"
}

function divider_footer() {
  echo "================================================================================"
  echo
}

function backup_template() {
  cat << EOF
#!/usr/bin/env bash

set -eu

DIR="\$( cd "\$(dirname "\$0")" ; pwd -P )"
source "\${DIR}/backup"

backup_create "${1:-}"
EOF
}

function task_init {
  local repository_host="${1:-}"

  if [[ -z "${repository_host}" ]]; then
    echo -e "please provide a valid borg ssh repository host\n\ndo init ssh://<user>@<host>:<port> ~/.ssh/id_rsa folder1,folder1"
    exit 1
  fi

  local ssh_key="${2:-}"
  if [[ ! -f ${ssh_key} ]]; then
    echo -e "ssh key '${ssh_key}' not found\n\ndo init ssh://<user>@<host>:<port> ~/.ssh/id_rsa folder1,folder1"
    exit 1
  fi

  local backup_folders="${3:-}"
  if [[ -z "${backup_folders}" ]]; then
    echo -e "please provide a comma seperated list of backup folders\\n\\ndo init ssh://<user>@<host>:<port> ~/.ssh/id_rsa folder1,folder1"
    exit 1
  fi

  divider_header  "writing config repository '${repository_host}' using ssh key '${ssh_key}' with folders '${backup_folders}' to '${CONFIG_FILE}'"

  local delimiter=""
  local backup_folders_list=""
  backup_folders=$(echo "${backup_folders}" | tr "," "\n")
  for backup_folder in ${backup_folders}
  do
      backup_folders_list="${backup_folders_list}${delimiter}\"${backup_folder}\""
      if [[ -z "${delimiter}" ]]; then
        delimiter=","
      fi
  done

  jq -n --arg repository_host ${repository_host} --arg ssh_key ${ssh_key} --argjson backup_folders "[${backup_folders_list}]" '{"repository_host":$repository_host,"ssh_key":$ssh_key,"backup_folders": $backup_folders}' | tee ${CONFIG_FILE}
  divider_footer

  divider_header  "writing backup commands to '${HOME}/bin'"

  mkdir -p "${HOME}/bin"
  cp "${DIR}/bin/backup" "${HOME}/bin/backup"
  cp "${DIR}/bin/backup.exclude" "${HOME}/bin/backup.exclude"
  for backup_folder in ${backup_folders}
  do
      local backup_command="${HOME}/bin/backup-$(echo ${backup_folder#/} | tr '\/' '-' | tr '\.' '-')"
      echo "writing backup command '${backup_command}'"
      backup_template "${backup_folder}" > ${backup_command}
      chmod +x ${backup_command}
  done
  divider_footer
}

function ensure_age() {
  if ! which age &> /dev/null; then
    echo "'age' not found, please install (https://github.com/FiloSottile/age)"
    exit 1
  fi
}

function task_export {

  ensure_age

  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "config '${CONFIG_FILE}' not found, please run init first"
    exit 1
  fi

  local export_dir="${DIR}/export"
  rm -rf "${export_dir}" || true
  mkdir -p "${export_dir}"

  local ssh_file="${export_dir}/ssh_key.age"

  divider_header "exporting ssh key '${SSH_KEY}' to '${ssh_file}'"
  age --encrypt --passphrase -o "${ssh_file}" ${SSH_KEY}
  cp ${CONFIG_FILE} "${export_dir}/config"
  divider_footer

  local export_file="${USER}-export.tar"
  divider_header "creating export '${export_file}'"
  (
    cd "${export_dir}"
    tar -cvf ${export_file} *
  )
  divider_footer

  echo "created export, for disaster recovery run './do import ${export_file}'"
}

function task_import {
  local export_file="${1:-}"

  if [[ ! -f ${export_file} ]]; then
    echo -e "export file '${export_file}' not found"
    exit 1
  fi

  echo "importing backup config from '${export_file}'"
  echo
  ensure_age

  divider_header "extracting config to '${CONFIG_FILE}'"
  tar -xf ${export_file} "config" --to-stdout > ${CONFIG_FILE}
  divider_footer

  local ssh_key="$(cat ${CONFIG_FILE} | jq -r .ssh_key)"
  divider_header "extracting ssh key to '${ssh_key}'"

  if [[ -f ${ssh_key} ]]; then
    echo "ssh key '${ssh_key}' already exists"
    exit 1
  fi
  tar -xf ${export_file} "ssh_key.age" --to-stdout | age --decrypt > ${ssh_key}
  divider_footer
}

function task_usage {
  echo "Usage: $0 ..."
  exit 1
}

ARG=${1:-}
shift || true

case ${ARG} in
  init) task_init $@ ;;
  test) task_test ;;
  export) task_export ;;
  import) task_import $@ ;;
  *) task_usage ;;
esac