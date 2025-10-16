#!/usr/bin/env bash

set -eu -o pipefail

DIR="$(cd "$(dirname "$0")" ; pwd -P)"

CONFIG_FILE="${CONFIG_DIR:-${HOME}/.borg_backup}"

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

  divider
  echo "writing test data '${backup_id}' to '${BACKUP_TEST_DIR}/data' and execute backup"
  divider_thin

  mkdir -p "${BACKUP_TEST_DIR}"
  echo "${backup_id}" > "${BACKUP_TEST_DIR}/data"
  backup_create "${BACKUP_TEST_DIR}"
  divider

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

function divider() {
  echo "================================================================================"
}

function divider_thin() {
  echo "--------------------------------------------------------------------------------"
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

  divider
  echo "writing config repository '${repository_host}' using ssh key '${ssh_key}' with folders '${backup_folders}' to '${CONFIG_FILE}'"
  divider_thin

  local delimiter=""
  local backup_folders_list=""
  backup_folders=$(echo "${backup_folders}" | tr "," "\n")
  for backup_folder in ${backup_folders}
  do
      cat "${DIR}/bin/backup.template" | sed -e "s/a/${backup_folder}/g"
      backup_folders_list="${backup_folders_list}${delimiter}\"${backup_folder}\""
      if [[ -z "${delimiter}" ]]; then
        delimiter=","
      fi
  done

  jq -n --arg repository_host ${repository_host} --arg ssh_key ${ssh_key} --argjson backup_folders "[${backup_folders_list}]" '{"repository_host":$repository_host,"ssh_key":$ssh_key,"backup_folders": $backup_folders}' | tee ${CONFIG_FILE}
  divider

  #divider
  #echo "installing files into '${HOME}/bin'"
  #divider_thin
  #mkdir -p "${HOME}/bin"
  #cp -v ${DIR}/bin/* ${HOME}/bin
  #divider
}

function task_export {
  local export_dir="${DIR}/export"
  local export_file="${export_dir}/${USER}.ssh.age"
  divider
  echo "exporting ssh key '${SSH_KEY}' to '${export_file}'"
  divider_thin
  mkdir -p "${export_dir}"
  age --encrypt --passphrase -o "${export_file}" ${SSH_KEY}
  divider
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
  *) task_usage ;;
esac