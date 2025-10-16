#!/usr/bin/env bash

set -eu -o pipefail

DIR="$(cd "$(dirname "$0")" ; pwd -P)"

BACKUP_TEST_DIR="${HOME}/backup_test"

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

  mkdir -p "${BACKUP_TEST_DIR}"


  local backup_id="$(uuidgen)"

  mkdir -p "${BACKUP_TEST_DIR}/backup"
  echo "${backup_id}" > "${BACKUP_TEST_DIR}/data"

  source "${DIR}/bin/backup"
  backup_create "${BACKUP_TEST_DIR}/backup"
  backup_latest "${BACKUP_TEST_DIR}/backup"

  #(
  #  cd  "${TEMP_DIR}/restore"
  #  backup_extract "${TEMP_DIR}/backup" --strip-components 6
  #)
}

function task_install {
  mkdir -p "${HOME}/bin"
  cp -v "${DIR}/bin/*" -p "${HOME}/bin"
}

function task_usage {
  echo "Usage: $0 ..."
  exit 1
}

ARG=${1:-}
shift || true

case ${ARG} in
  test) task_test ;;
  install) task_install ;;
  *) task_usage ;;
esac