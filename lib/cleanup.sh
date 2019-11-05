#!/bin/bash

if [ "$DEBUG" = "true" ]; then
  set -x
  cat config.tf
fi

# Define all config.tf vars as bash vars
eval $(
cat << EOC | json2hcl -reverse | python3 -c '
import sys, json
for i in json.load(sys.stdin)["variable"]:
  for key, value in i.items():
    print("export " + key + "=\"" + str(i[key][0]["default"]) + "\"")
'
${config}
EOC
)

if [ "$cluster_name" ]; then
  identity=$${cluster_name}-$${name}
  export identity
else
  identity=$${name}
  export identity
fi

node_exist() {
  curl -s "http://$${consul}:$${consul_port}/v1/agent/members" | jq ".[] | select(.Name==\"$${identity}-$${_NUMBER}\") | select(.Status!=3)"
}

while [ "$(node_exist)" ]; do
  echo "$(date +%x\ %H:%M:%S) Deregister node from consul"
  curl -sS -X PUT "http://$${consul}:$${consul_port}/v1/agent/force-leave/$${identity}-$${_NUMBER}" > /dev/null
  curl -sS -X PUT "http://$${consul}:$${consul_port}/v1/catalog/deregister?dc=$${consul_datacenter}" --data \{\"Datacenter\":\"$${consul_datacenter}\",\"Node\":\"$${identity}-$${_NUMBER}\"\} > /dev/null
  sleep 1
done

if [ "$quantity" = "0" ]; then
  echo "$(date +%x\ %H:%M:%S) Is the last node so clean up everything"
  # Remove consul keys
  curl -sS -X DELETE "http://$${consul}:$${consul_port}/v1/kv/$${cluster_name}/$${identity}?recurse=yes" > /dev/null

  # Cleanup all cluster if last group
  cluster_group_kv=$(curl -H "Accept: application/json" -Ss http://$${consul}:$${consul_port}/v1/kv/$${cluster_name}?recurse=yes)
  if [ "$?" != "0" ]; then
    echo "$(date +%x\ %H:%M:%S) Curl error in cluster_group_kv"
    exit 1
  fi

  cluster_group_exists=$(echo $${cluster_group_kv} | jq '.[].Key' | egrep ".*/.*/.*" | grep -v "/\.deploy/" | grep -v "/\.cleanup/" | wc -l)
  if [ "$cluster_group_exists" = "0" ]; then
    echo "$(date +%x\ %H:%M:%S) Is the last group so clean up everything"
    # Remove cluster consul keys
    curl -sS -X DELETE "http://$${consul}:$${consul_port}/v1/kv/$${cluster_name}?recurse=yes" > /dev/null
  fi
fi

exit 0
