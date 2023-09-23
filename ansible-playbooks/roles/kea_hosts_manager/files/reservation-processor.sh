#!/bin/bash

# To be used with Ansible shell module

set -e

# Function to extract MAC address from Kea reservations output and create a new json structure
function extract_mac_address_from_kea_reservations {
  local LOCAL_JSON_DATA="$1"
  local LOCAL_SUBNET_ID="$2"
  echo "$LOCAL_JSON_DATA" | jq -M -c --argjson subnet_id "$LOCAL_SUBNET_ID" '[.[0].arguments.hosts[] | { "hw-address": .["hw-address"], "subnet-id": $subnet_id }]'
}

#Function that returns IP MAC reservations from Kea's database
function get_kea_reservations {
  local LOCAL_URL=$1
  local LOCAL_SERVICE=$2
  local LOCAL_SUBNET_ID=$3
  local LOCAL_USERNAME=$4
  local LOCAL_PASSWORD=$5
  local LOCAL_PAYLOAD="{
    \"command\": \"reservation-get-all\",
    \"service\": [ \"$LOCAL_SERVICE\" ],
    \"arguments\": { \"subnet-id\": $LOCAL_SUBNET_ID }
  }"
  # Get response with HTTP status code
  local LOCAL_RESPOSE=$(
    curl -s \
      -w "%{http_code}" \
      -u "$LOCAL_USERNAME:$LOCAL_PASSWORD" \
      -H "Content-Type: application/json" \
      -d "$LOCAL_PAYLOAD" \
      "$LOCAL_URL"
  )
  # Separate HTTP status code from the response
  local LOCAL_RESPOSE_CODE=${LOCAL_RESPOSE: -3}
  # Separate the actual reponse from the response by removing the status code
  local LOCAL_RESPOSE_BODY=${LOCAL_RESPOSE:0:${#LOCAL_RESPOSE}-3}

  # If response is valid, extract MAC addresses and create MAC <-> Subnet bindings
  if [ "$LOCAL_RESPOSE_CODE" -eq 200 ]; then
    if [ -n "$LOCAL_RESPOSE_BODY" ]; then
      local EXTRACTED_MAC_SUBNET_BINDINGS=$(extract_mac_address_from_kea_reservations "$LOCAL_RESPOSE_BODY" "$LOCAL_SUBNET_ID")
      echo ${EXTRACTED_MAC_SUBNET_BINDINGS}
    else
      echo "Empty or invalid response from server."
      exit 1
    fi
  else
    echo "Failed to fetch data. HTTP status code: $LOCAL_RESPOSE_CODE"
    exit 1
  fi
}

# The following function is a ChatGPT improved version which is only using
# jq to get missing reservations rather than using the "for" and "if" blocks
# for comparision.
function extract_mac_addresses_not_present_in_sot {
  local LOCAL_URL=$1
  local LOCAL_SERVICE=$2
  local LOCAL_USERNAME=$3
  local LOCAL_PASSWORD=$4
  local LOCAL_SOT_SUBNET_ID=$(echo "${SOT_FROM_ANSIBLE}" | jq -M '.[0].subnet_id')
  local LOCAL_EXISTING_RESERVATIONS="$(get_kea_reservations ${LOCAL_URL} ${LOCAL_SERVICE} ${LOCAL_SOT_SUBNET_ID} ${LOCAL_USERNAME} ${LOCAL_PASSWORD})"

  # Extract hw-address from LOCAL_EXISTING_RESERVATIONS, compare it with hw-address in SOT_FROM_ANSIBLE
  # If it doesn't exist in SOT_FROM_ANSIBLE, construct the JSON directly
  LOCAL_MISSING_RESERVATIONS_JSON=$(echo "$LOCAL_EXISTING_RESERVATIONS" | jq -c --argjson sot_subnet_id "$LOCAL_SOT_SUBNET_ID" --argjson sot "${SOT_FROM_ANSIBLE}" \
    'map(select(.["hw-address"] as $hw_address | $sot[0].reservations | map(.["hw-address"] | ascii_downcase) | index($hw_address | ascii_downcase) | not) | { "hw-address": .["hw-address"], "subnet-id": $sot_subnet_id })')

  echo "${LOCAL_MISSING_RESERVATIONS_JSON}"
}

ARGS_LIST=(
  "get-all-reservations"
  "list-deletable-reservations"
  "subnet-id:"
  "kea-ctrl-agent-proto:"
  "kea-ctrl-agent-host:"
  "kea-ctrl-agent-port:"
  "kea-ctrl-agent-username:"
  "kea-ctrl-agent-password:"
  "kea-ctrl-agent-service-name:"
  "source-of-truth:"
)

OPTIONS=$(getopt -o '' --longoptions "$(printf "%s," "${ARGS_LIST[@]}")" --name "$(basename "$0")" -- "$@")

eval set -- "$OPTIONS"

while true; do
  case "$1" in
    --get-all-reservations)
      GET_ALL_RESERVATIONS=true
      shift
      ;;
    --list-deletable-reservations)
      LIST_DELETABLE_RESERVATIONS=true
      EXPECT_SOT=true
      shift
      ;;
    --subnet-id)
      SUBNET_ID="$2"
      shift 2
      ;;
    --kea-ctrl-agent-proto)
      KEA_CTRL_AGENT_PROTO="$2"
      shift 2
      ;;
    --kea-ctrl-agent-host)
      KEA_CTRL_AGENT_HOST="$2"
      shift 2
      ;;
    --kea-ctrl-agent-port)
      KEA_CTRL_AGENT_PORT="$2"
      shift 2
      ;;
    --kea-ctrl-agent-username)
      KEA_CTRL_AGENT_USERNAME="$2"
      shift 2
      ;;
    --kea-ctrl-agent-password)
      KEA_CTRL_AGENT_PASSWORD="$2"
      shift 2
      ;;
    --kea-ctrl-agent-service-name)
      KEA_CTRL_AGENT_SERVICE_NAME="$2"
      shift 2
      ;;
    --source-of-truth) # This will be passed by Ansible as a json
      if [ "$EXPECT_SOT" = true ]; then
        SOT_FROM_ANSIBLE_PROVIDED=true
        SOT_FROM_ANSIBLE=$2
      else
        echo "Error: --source-of-truth must be set for an operation that requires it"
        exit 1
      fi
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Invalid option: $1"
      exit 1
      ;;
  esac
done

# Expect input or assume defaults
: ${KEA_CTRL_AGENT_PROTO:=http}
: ${KEA_CTRL_AGENT_HOST:=127.0.0.1}
: ${KEA_CTRL_AGENT_PORT:=8084}
: ${KEA_CTRL_AGENT_USERNAME:=admin}
: ${KEA_CTRL_AGENT_PASSWORD:=admin}
: ${KEA_CTRL_AGENT_SERVICE_NAME:=dhcp4}

# Set Kea URL
KEA_CTRL_AGENT_URL="$KEA_CTRL_AGENT_PROTO://$KEA_CTRL_AGENT_HOST:$KEA_CTRL_AGENT_PORT/"


if [ "$GET_ALL_RESERVATIONS" = true ]; then
  if [ -z "$SUBNET_ID" ]; then
    echo -e "Error: --subnet-id must be provided when --get-all-reservations is used"
    exit 1
  fi
  KEA_RESERVATIONS=$(get_kea_reservations ${KEA_CTRL_AGENT_URL} ${KEA_CTRL_AGENT_SERVICE_NAME} ${SUBNET_ID} ${KEA_CTRL_AGENT_USERNAME} ${KEA_CTRL_AGENT_PASSWORD})
  echo ${KEA_RESERVATIONS}
fi

if [ "$SOT_FROM_ANSIBLE_PROVIDED" = true ]; then
  if [ "$LIST_DELETABLE_RESERVATIONS" = true ]; then
    MISSING_RESERVATIONS=$(extract_mac_addresses_not_present_in_sot ${KEA_CTRL_AGENT_URL} ${KEA_CTRL_AGENT_SERVICE_NAME} ${KEA_CTRL_AGENT_USERNAME} ${KEA_CTRL_AGENT_PASSWORD})
    echo ${MISSING_RESERVATIONS}
  fi
fi
