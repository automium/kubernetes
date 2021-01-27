#!/bin/bash

set -e
set -o pipefail

source lib/helpers.sh
source lib/plan.sh

DESTROY_NUMBERS=$(get_destroy_nodes)
for DESTROY_NUMBER in $DESTROY_NUMBERS; do
  # Clean up old interrupted tasks if any
  curl -f -sS -X DELETE "http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.cleanup/${IDENTITY}-${DESTROY_NUMBER}?recurse=yes" > /dev/null

  curl -sS -X PUT http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.cleanup/${IDENTITY}-${DESTROY_NUMBER}/start -d "{ \"name\": \"${IDENTITY}-${DESTROY_NUMBER}\", \"time\": \"$(date +%s)\" }" > /dev/null
  curl -sS -X DELETE http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.cleanup/${IDENTITY}-${DESTROY_NUMBER}/start > /dev/null
  curl -sS -X PUT http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.cleanup/${IDENTITY}-${DESTROY_NUMBER}/ongoing -d "{ \"name\": \"${IDENTITY}-${DESTROY_NUMBER}\", \"time\": \"$(date +%s)\" }" > /dev/null

  echo "$(date +%x\ %H:%M:%S) [START] Destroy instance ${IDENTITY}-${DESTROY_NUMBER}"

  if [ "${PROVISIONER_CONFIG_WAIT_CLEANUP}" == "true" ]; then
    TIMEOUT=${PROVISIONER_CONFIG_WAIT_CLEANUP_TIMEOUT}
    COUNT=0
    echo "$(date +%x\ %H:%M:%S) [START] Cleanup tasks on node ${IDENTITY}-${DESTROY_NUMBER}"
    while [ "$(curl -sS http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.cleanup/${IDENTITY}-${DESTROY_NUMBER}/ongoing)" ]; do
      echo "$(date +%x\ %H:%M:%S) Wait until all cleanup tasks finish on node ${IDENTITY}-${DESTROY_NUMBER}"
      if [ ${COUNT} -ge ${TIMEOUT} ]; then
        echo "$(date +%x\ %H:%M:%S) Timeout reached for cleanup tasks on node ${IDENTITY}-${DESTROY_NUMBER}"
        break
      fi;
      COUNT=$(echo ${COUNT} + 1 | bc)
      sleep 1
    done
    echo "$(date +%x\ %H:%M:%S) [END] Cleanup tasks on node ${IDENTITY}-${DESTROY_NUMBER}"
  fi
done

CREATE_NUMBERS=$(get_create_nodes)
for CREATE_NUMBER in $CREATE_NUMBERS; do
  echo "$(date +%x\ %H:%M:%S) [START] Create instance ${IDENTITY}-${CREATE_NUMBER}"

  curl -sS -X PUT http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.create/${IDENTITY}-${CREATE_NUMBER}/ongoing -d "{ \"name\": \"${IDENTITY}-${CREATE_NUMBER}\", \"time\": \"$(date +%s)\" }" > /dev/null
done

source lib/apply.sh

for DESTROY_NUMBER in $DESTROY_NUMBERS; do
  # Clean up removing task
  curl -sS -X DELETE http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.cleanup/${IDENTITY}-${DESTROY_NUMBER}/ongoing > /dev/null
  curl -sS -X PUT http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.cleanup/${IDENTITY}-${DESTROY_NUMBER}/end -d "{ \"name\": \"${IDENTITY}-${DESTROY_NUMBER}\", \"time\": \"$(date +%s)\" }" > /dev/null
  curl -sS -X DELETE http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.cleanup/${IDENTITY}-${DESTROY_NUMBER}/end > /dev/null
  echo "$(date +%x\ %H:%M:%S) [END] Destroy instance ${IDENTITY}-${DESTROY_NUMBER}"
done

for CREATE_NUMBER in $CREATE_NUMBERS; do
  echo "$(date +%x\ %H:%M:%S) [START] Wait instance ${IDENTITY}-${CREATE_NUMBER}"
  wait_health_ok ${IDENTITY}-${CREATE_NUMBER}

  while [ "$(curl -sS http://${CONSUL}:${CONSUL_PORT}/v1/kv/${CLUSTER_NAME}/.create/${IDENTITY}-${CREATE_NUMBER}/ongoing)" ]; do
    echo "$(date +%x\ %H:%M:%S) Wait until all creating tasks finish on node ${IDENTITY}-${CREATE_NUMBER}"
    sleep 10
  done

  echo "$(date +%x\ %H:%M:%S) [END] Wait instance ${IDENTITY}-${CREATE_NUMBER}"
  echo "$(date +%x\ %H:%M:%S) [END] Create instance ${IDENTITY}-${CREATE_NUMBER}"
done
