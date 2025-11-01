#!/bin/bash

set -e

# Redirect all output to stderr for docker logs
exec 1>&2

echo "========================================"
echo "Postfix SMTP Relay Configuration"
echo "========================================"

[ "${DEBUG}" == "yes" ] && set -x

# Set timezone
if [ -n "${TIMEZONE}" ]; then
    echo "Setting timezone to: ${TIMEZONE}"
    cp /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
    echo "${TIMEZONE}" > /etc/timezone
fi

# Initialize postfix directories (Alpine-specific)
# Postfix on Alpine doesn't use post-install in the same way
# The directories are already created during package installation

function add_config_value() {
  local key=${1}
  local value=${2}
  local config_file=${3:-/etc/postfix/main.cf}
  [ "${key}" == "" ] && echo "ERROR: No key set !!" && exit 1
  [ "${value}" == "" ] && echo "ERROR: No value set !!" && exit 1

  echo "  Setting: ${key} = ${value}"
  postconf -e "${key} = ${value}"
}

# Validate required environment variables
[ -z "${SMTP_SERVER}" ] && echo "ERROR: SMTP_SERVER is not set" && exit 1
[ -z "${SMTP_PORT}" ] && echo "ERROR: SMTP_PORT is not set" && exit 1
[ -z "${SMTP_USERNAME}" ] && echo "ERROR: SMTP_USERNAME is not set" && exit 1
[ -z "${SMTP_PASSWORD}" ] && echo "ERROR: SMTP_PASSWORD is not set" && exit 1

# Detect SMTP provider and set defaults
SMTP_PROVIDER="generic"
if [[ "${SMTP_SERVER}" == *"mailtrap.io"* ]]; then
    SMTP_PROVIDER="mailtrap"
    echo "Detected provider: Mailtrap"
elif [[ "${SMTP_SERVER}" == *"sendgrid"* ]]; then
    SMTP_PROVIDER="sendgrid"
    echo "Detected provider: SendGrid"
elif [[ "${SMTP_SERVER}" == *"maileroo"* ]]; then
    SMTP_PROVIDER="maileroo"
    echo "Detected provider: Maileroo"
else
    echo "Using generic SMTP provider: ${SMTP_SERVER}"
fi

# Get local network subnet - allow override via environment variable
if [ -z "${LOCAL_NETWORK}" ]; then
    # Auto-detect and use /16 by default
    LOCAL_NETWORK=$(ip route | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+' | head -1 | awk '{print $1}')
    if [ -z "$LOCAL_NETWORK" ]; then
        LOCAL_IP=$(hostname -i | grep -E -o '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1)
        if [ -n "$LOCAL_IP" ]; then
            # Extract first two octets for /16 network
            NETWORK_PREFIX=$(echo $LOCAL_IP | cut -d. -f1-2)
            LOCAL_NETWORK="${NETWORK_PREFIX}.0.0/16"
        else
            LOCAL_NETWORK="172.16.0.0/16"
        fi
    fi
    echo "Auto-detected local network: ${LOCAL_NETWORK}"
else
    echo "Using provided LOCAL_NETWORK: ${LOCAL_NETWORK}"
fi

# Build mynetworks - always include localhost and detected local network
nets="127.0.0.0/8, [::1]/128, ${LOCAL_NETWORK}"

# Add custom networks if specified
if [ ! -z "${SMTP_NETWORKS}" ]; then
    echo "Adding custom networks..."
    for i in $(sed 's/,/ /g' <<<$SMTP_NETWORKS); do
        if grep -Eq "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}" <<<$i ; then
            nets="${nets}, $i"
            echo "  Added network: $i"
        else
            echo "  WARNING: $i is not in proper IPv4 subnet format. Ignoring."
        fi
    done
fi

echo ""
echo "Allowed networks: ${nets}"
echo ""

# Set hostname and domain defaults
SERVER_HOSTNAME_DEFAULT=$(hostname -f)
DOMAIN_DEFAULT=$(hostname -d)

# Use provided values or defaults
SERVER_HOSTNAME=${SERVER_HOSTNAME:-${SERVER_HOSTNAME_DEFAULT}}
DOMAIN=${DOMAIN:-${DOMAIN_DEFAULT}}

echo "Configuring Postfix..."
echo "----------------------------------------"

# Basic configuration
add_config_value "myhostname" "${SERVER_HOSTNAME}"
add_config_value "mydomain" "${DOMAIN}"
add_config_value "mydestination" '$myhostname'
add_config_value "myorigin" '$mydomain'
add_config_value "mynetworks" "${nets}"
add_config_value "inet_interfaces" "all"
add_config_value "inet_protocols" "ipv4"

# Relay configuration
add_config_value "relayhost" "[${SMTP_SERVER}]:${SMTP_PORT}"
add_config_value "relay_domains" "*"

# SASL Authentication
add_config_value "smtp_sasl_auth_enable" "yes"
add_config_value "smtp_sasl_password_maps" "lmdb:/etc/postfix/sasl_passwd"
add_config_value "smtp_sasl_security_options" "noanonymous"
add_config_value "smtp_sasl_tls_security_options" "noanonymous"
add_config_value "smtp_sasl_mechanism_filter" "plain, login"

# TLS configuration
if [ "${SMTP_PROVIDER}" == "sendgrid" ] || [ "${SMTP_PROVIDER}" == "mailtrap" ] || [ "${SMTP_PROVIDER}" == "maileroo" ]; then
    add_config_value "smtp_use_tls" "yes"
    add_config_value "smtp_tls_security_level" "encrypt"
    add_config_value "smtp_tls_CAfile" "/etc/ssl/certs/ca-certificates.crt"
    add_config_value "smtp_tls_session_cache_database" "lmdb:\${data_directory}/smtp_scache"
    add_config_value "smtp_tls_loglevel" "1"
else
    add_config_value "smtp_tls_security_level" "may"
fi

# Size limits
add_config_value "header_size_limit" "4096000"
add_config_value "mailbox_size_limit" "0"
add_config_value "message_size_limit" "52428800"
add_config_value "recipient_delimiter" "+"

# Relay restrictions
add_config_value "smtpd_relay_restrictions" "permit_mynetworks, reject_unauth_destination"
add_config_value "smtpd_recipient_restrictions" "permit_mynetworks, reject_unauth_destination"
add_config_value "smtpd_sasl_local_domain" "${DOMAIN}"

# Logging configuration - send logs to stdout/stderr
add_config_value "maillog_file" "/dev/stdout"
add_config_value "maillog_file_prefixes" "/var, /dev"

# Queue settings
add_config_value "maximal_queue_lifetime" "1d"
add_config_value "bounce_queue_lifetime" "1d"
add_config_value "queue_run_delay" "300s"
add_config_value "minimal_backoff_time" "300s"
add_config_value "maximal_backoff_time" "4000s"

# Debug settings (enable if DEBUG=yes)
if [ "${DEBUG}" == "yes" ]; then
    add_config_value "debug_peer_level" "2"
fi

echo "----------------------------------------"
echo ""

# Create SASL password file
echo "Configuring SASL authentication..."
echo "[${SMTP_SERVER}]:${SMTP_PORT} ${SMTP_USERNAME}:${SMTP_PASSWORD}" > /etc/postfix/sasl_passwd
chmod 600 /etc/postfix/sasl_passwd
postmap /etc/postfix/sasl_passwd
# Set permissions on the generated database file (may have different extensions)
chmod 600 /etc/postfix/sasl_passwd.* 2>/dev/null || true
echo "  SASL credentials configured for ${SMTP_SERVER}:${SMTP_PORT}"
echo ""

# Set header tag if specified
if [ ! -z "${SMTP_HEADER_TAG}" ]; then
    echo "Setting SMTP header tag: ${SMTP_HEADER_TAG}"
    postconf -e "header_checks = regexp:/etc/postfix/header_tag"
    echo -e "/^MIME-Version:/i PREPEND RelayTag: $SMTP_HEADER_TAG\n/^Content-Transfer-Encoding:/i PREPEND RelayTag: $SMTP_HEADER_TAG" > /etc/postfix/header_tag
    echo ""
fi

# Clean up old PID file if mounting /var/spool/postfix
echo "Cleaning up old PID files..."
rm -f /var/spool/postfix/pid/master.pid

# Validate postfix configuration
echo "Validating Postfix configuration..."
postconf -c /etc/postfix/

if [[ $? != 0 ]]; then
  echo ""
  echo "========================================"
  echo "ERROR: Postfix configuration error!"
  echo "========================================"
  exit 1
fi

echo ""
echo "========================================"
echo "Postfix configuration completed successfully"
echo "========================================"
echo "Provider: ${SMTP_PROVIDER}"
echo "Relay host: ${SMTP_SERVER}:${SMTP_PORT}"
echo "Hostname: ${SERVER_HOSTNAME}"
echo "Domain: ${DOMAIN}"
echo "Networks: ${nets}"
echo "========================================"
echo ""

# Start postfix in foreground mode
echo "Starting Postfix in foreground mode..."
echo ""

# Run postfix in foreground - this will handle all logging to stdout/stderr
exec postfix start-fg
