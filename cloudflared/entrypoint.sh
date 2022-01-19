#!/usr/bin/env bashio

export NO_AUTOUPDATE=true

bashio::log.info "Version: $(/cloudflared --version)"
bashio::log.info "Starting Cloudflared Tunnel..."

# Set the logging level - debug, info, warn, error, fatal
if bashio::config.has_value 'loglevel'; then
    TUNNEL_LOGLEVEL="$(bashio::config 'loglevel')"
    bashio::log.info "Setting log level to $TUNNEL_LOGLEVEL..."
    export TUNNEL_LOGLEVEL
    export TUNNEL_TRANSPORT_LOGLEVEL=$TUNNEL_LOGLEVEL
fi

if ! bashio::config.has_value 'service'; then
    bashio::log.warning "No service set, using default 'http://homeassistant:8123'..."
    TUNNEL_URL="$(bashio::config 'service' || echo 'http://homeassistant:8123')"
else
    TUNNEL_URL="$(bashio::config 'service')"
fi
export TUNNEL_URL
bashio::log.info "Service set to: $TUNNEL_URL"

if ! bashio::config.has_value 'hostname'; then
    bashio::log.warning "No hostname set, using quick tunnel..."
    /cloudflared tunnel
    exit 1
else
    TUNNEL_HOSTNAME="$(bashio::config 'hostname')"
    export TUNNEL_HOSTNAME
fi

# TUNNEL_ORIGIN_CERT="$(bashio::config 'certificate')"
TUNNEL_ORIGIN_CERT="/ssl/cloudflared/cert.pem"
if bashio::config.has_value 'tunnel_name'; then
    TUNNEL_NAME="$(bashio::config 'tunnel_name')"
else
    bashio::log.info "No tunnel name set, using default 'ha-cloudflare'..."
    TUNNEL_NAME="ha-cloudflare"
fi
TUNNEL_CRED_FILE="$(dirname "$TUNNEL_ORIGIN_CERT")/$TUNNEL_NAME.yml"

# Create directories
mkdir -p "/ssl/cloudflared"
mkdir -p "/share/cloudflared"

# Overwrite existing DNS entries
if bashio::config.true 'overwrite_dns'; then
    TUNNEL_FORCE_PROVISIONING_DNS=$(bashio::config 'overwrite_dns')
    bashio::log.info "Setting DNS overwrite to $TUNNEL_FORCE_PROVISIONING_DNS..."
    export TUNNEL_FORCE_PROVISIONING_DNS
fi

# Login if we can't find the certificate
if ! bashio::fs.file_exists "${TUNNEL_ORIGIN_CERT}"; then
    bashio::log.info "Certificate '$TUNNEL_ORIGIN_CERT' doesn't exist..."
    bashio::log.warning "You need to log in to Cloudflare, please follow the link below..."
    if ! /cloudflared login; then
        bashio::log.error "Failed to login to Cloudflare..."
        exit 1
    fi
    # Move the cert to the expected location
    mv -fn /root/.cloudflared/cert.pem "$TUNNEL_ORIGIN_CERT"
fi
export TUNNEL_ORIGIN_CERT

# Create the tunnel if it doesn't exist
if /cloudflared tunnel info "${TUNNEL_NAME}" &>/dev/null; then
    bashio::log.info "Tunnel config exists..."
    /cloudflared tunnel delete -f "${TUNNEL_NAME}"
fi
bashio::log.info "Creating new tunnel config"
rm -rf "${TUNNEL_CRED_FILE}"
if ! /cloudflared tunnel create -o yaml --credentials-file "${TUNNEL_CRED_FILE}" "$TUNNEL_NAME"; then
    bashio::log.error "Failed to create tunnel..."
    exit 1
fi
export TUNNEL_CRED_FILE

bashio::log.info "Creating new tunnel with hostname '${TUNNEL_HOSTNAME}' -> '${TUNNEL_URL}'"
/cloudflared tunnel --name "$TUNNEL_NAME" || bashio::log.error "Error starting Cloudflare tunnel! If errors persist try removing " && exit 1

# if ! bashio::config.has_value 'config'; then
#     CONF_FILE="/share/cloudflared/conf.yml"
#     # Create the config file
#     bashio::log.info "Creating config file '${CONF_FILE}'..."
#     echo "" > "$CONF_FILE"
#     # echo "url: '$(bashio::config 'service')'" > "$CONF_FILE"
#     TUNNEL_URL="$(bashio::config 'service')"
#     export TUNNEL_URL
#     echo "tunnel: '${TUNNEL_NAME}'" >> "$CONF_FILE"
#     echo "credential-file: '${TUNNEL_CRED_FILE}'" >> "$CONF_FILE"
#     # Create the route
#     # if /cloudflared tunnel route dns "${TUNNEL_NAME}" "${EXTERNAL_SUBDOMAIN}"; then
#     #     bashio::log.info "Created route '${EXTERNAL_SUBDOMAIN}' on '${TUNNEL_NAME}' tunnel"
#     # elif /cloudflared tunnel route dns "${TUNNEL_NAME}" "${EXTERNAL_SUBDOMAIN}" 2>&1 | grep -q 'already exists'; then
#     #     bashio::log.info "Route '${EXTERNAL_SUBDOMAIN}' on '${TUNNEL_NAME}' tunnel already exists"
#     # else
#     #     bashio::log.error "Failed to create route '${EXTERNAL_SUBDOMAIN}' on '${TUNNEL_NAME}' tunnel"
#     # fi

#     if existing_tunnel=$(cloudflared tunnel route dns "${TUNNEL_NAME}" "${EXTERNAL_SUBDOMAIN}" 2>&1); then
#         bashio::log.info "Created route '${EXTERNAL_SUBDOMAIN}' on '${TUNNEL_NAME}' tunnel"
#     elif echo "$existing_tunnel" | grep -q 'already exists'; then
#         bashio::log.info "Route '${EXTERNAL_SUBDOMAIN}' on '${TUNNEL_NAME}' tunnel already exists"
#     else
#         bashio::log.error "Failed to create route '${EXTERNAL_SUBDOMAIN}' on '${TUNNEL_NAME}' tunnel"
#         exit 1
#     fi
#     # Create the config file
#     # bashio::log.info "Creating config file: ${CONF_FILE}"
#     # # Ingress rules, see https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/configuration/ingress
#     # if ! bashio::config.has_value 'ingress'; then
#     #     bashio::log.error "No config provided and no ingress rules defined"
#     #     exit 1
#     # fi
#     # # echo bashio::config "myarray" > "${CONF_FILE}"
#     # echo "ingress:" > "$CONF_FILE"
#     # for rule in $(bashio::config "ingress|keys"); do
#     #     service=$(bashio::config "ingress[${rule}].service")
#     #     if ! bashio::config.exists "ingress[${rule}].hostname"  || bashio::config.is_empty "ingress[${rule}].hostname"; then
#     #         bashio::log.info "Configuring service only: ${service}"
#     #         echo "  - service: ${service}" >> "$CONF_FILE"
#     #     else
#     #         hostname=$(bashio::config "ingress[${rule}].hostname")
#     #         bashio::log.info "Configuring hostname: ${hostname} -> ${service}"
#     #         echo "  - hostname: ${hostname}" >> "$CONF_FILE"
#     #         echo "    service: ${service}" >> "$CONF_FILE"
#     #         # Create the route
#     #         if /cloudflared tunnel route dns "${TUNNEL_NAME}" "${hostname}"; then
#     #             bashio::log.info "Created route: ${hostname} -> ${service}"
#     #         else
#     #             bashio::log.error "Failed to create route: ${hostname} -> ${service}"
#     #         fi
#     #     fi
#     # done
# # else
# #     if bashio::config.exists "$CONF_FILE"; then
# #         bashio::log.info "Using config file: ${CONF_FILE}"
# #         CONF_FILE="$(bashio::config 'config')"
# #     else
# #         bashio::log.error "Can't load config file: ${CONF_FILE}"
# #         exit 1
# #     fi
# fi

