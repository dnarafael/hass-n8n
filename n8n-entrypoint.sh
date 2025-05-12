#!/bin/bash

export N8N_SECURE_COOKIE=false
export N8N_HIRING_BANNER_ENABLED=false
export N8N_PERSONALIZATION_ENABLED=false
export N8N_VERSION_NOTIFICATIONS_ENABLED=false
export N8N_RUNNERS_ENABLED=true
export N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true

CONFIG_PATH="/data/options.json"
export GENERIC_TIMEZONE="$(jq --raw-output '.timezone // empty' $CONFIG_PATH)"
export N8N_PROTOCOL="$(jq --raw-output '.protocol // empty' $CONFIG_PATH)"
export N8N_SSL_CERT="/ssl/$(jq --raw-output '.certfile // empty' $CONFIG_PATH)"
export N8N_SSL_KEY="/ssl/$(jq --raw-output '.keyfile // empty' $CONFIG_PATH)"
export N8N_CMD_LINE="$(jq --raw-output '.cmd_line_args // empty' $CONFIG_PATH)"

#####################
## USER PARAMETERS ##
#####################

# Extract the values from env_vars_list
values=$(jq -r '.env_vars_list | .[]' "$CONFIG_PATH")

IFS=$'\n' read -r -d '' -a array <<< "$values"

for element in "${array[@]}"
do
    if [[ "$element" == *"="* ]]; then
        key="${element%%=*}"
        value="${element#*=}"
    else
        key="${element%%:*}"
        value="${element#*:}"
    fi

    key="$(echo "$key" | xargs | tr -d '\r\n')"
    value="$(echo "$value" | xargs | tr -d '\r\n')"

    if [[ -n "$key" ]]; then
        export "$key"="$value"
        echo "exported $key=$value"
    fi
done

# Install any external packages requested
if [ -n "${NODE_FUNCTION_ALLOW_EXTERNAL}" ]; then
    echo "Installing external packages..."
    IFS=',' read -r -a packages <<< "${NODE_FUNCTION_ALLOW_EXTERNAL}"
    for package in "${packages[@]}"
    do
        echo "Installing ${package}..."
        npm install -g "${package}"
    done
fi

DATA_DIRECTORY_PATH="/data/n8n"

mkdir -p "${DATA_DIRECTORY_PATH}/.n8n/.cache"
chmod -R 755 "${DATA_DIRECTORY_PATH}"

echo "🔍 Verificando existência do banco de dados do n8n..."
if [ -f "${DATA_DIRECTORY_PATH}/.n8n/database.sqlite" ]; then
    echo "✅ Banco de dados encontrado em ${DATA_DIRECTORY_PATH}/.n8n/database.sqlite"
else
    echo "⚠️ Banco de dados não encontrado. O n8n irá criar um novo na primeira execução."
fi

export N8N_USER_FOLDER="${DATA_DIRECTORY_PATH}"

# Garantir que diretório do user folder exista
if [ ! -d "${N8N_USER_FOLDER}" ]; then
    mkdir -p "${N8N_USER_FOLDER}"
fi

echo "N8N_USER_FOLDER: ${N8N_USER_FOLDER}"

INFO=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" http://supervisor/info)
INFO=${INFO:-'{}'}
echo "Fetched Info from Supervisor: ${INFO}"

CONFIG=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" http://supervisor/core/api/config)
CONFIG=${CONFIG:-'{}'}
echo "Fetched Config from Supervisor: ${CONFIG}"

ADDON_INFO=$(curl -s -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" http://supervisor/addons/self/info)
ADDON_INFO=${ADDON_INFO:-'{}'}
echo "Fetched Add-on Info from Supervisor: ${ADDON_INFO}"

INGRESS_PATH=$(echo "$ADDON_INFO" | jq -r '.data.ingress_url // "/"')
echo "Extracted Ingress Path from Supervisor: ${INGRESS_PATH}"

LOCAL_HA_PORT=$(echo "$CONFIG" | jq -r '.port // "8123"')
LOCAL_HA_HOSTNAME=$(echo "$INFO" | jq -r '.data.hostname // "localhost"')
LOCAL_N8N_URL="http://$LOCAL_HA_HOSTNAME:5690"
echo "Local Home Assistant n8n URL: ${LOCAL_N8N_URL}"

EXTERNAL_N8N_URL=${EXTERNAL_URL:-$(echo "$CONFIG" | jq -r ".external_url // \"$LOCAL_N8N_URL\"")}
EXTERNAL_HA_HOSTNAME=$(echo "$EXTERNAL_N8N_URL" | sed -e "s/https\?:\/\///" | cut -d':' -f1)
echo "External Home Assistant n8n URL: ${EXTERNAL_N8N_URL}"

export N8N_PATH=${N8N_PATH:-"${INGRESS_PATH}"}
export N8N_EDITOR_BASE_URL=${N8N_EDITOR_BASE_URL:-"${EXTERNAL_N8N_URL}${N8N_PATH}"}
export WEBHOOK_URL=${WEBHOOK_URL:-"http://${LOCAL_HA_HOSTNAME}:8081"}

echo "N8N_PATH: ${N8N_PATH}"
echo "N8N_EDITOR_BASE_URL: ${N8N_EDITOR_BASE_URL}"
echo "WEBHOOK_URL: ${WEBHOOK_URL}"

###########
## START ##
###########

if [ "$#" -gt 0 ]; then
    exec n8n --userFolder="${N8N_USER_FOLDER}" ${N8N_CMD_LINE}
else
    exec n8n --userFolder="${N8N_USER_FOLDER}"
fi
