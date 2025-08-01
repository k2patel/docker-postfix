#!/bin/bash

[ "${DEBUG}" == "yes" ] && set -x

/usr/lib/postfix/post-install meta_directory=/etc/postfix create-missing
/usr/lib/postfix/master

function add_config_value() {
  local key=${1}
  local value=${2}
  local config_file=${3:-/etc/postfix/main.cf}
  [ "${key}" == "" ] && echo "ERROR: No key set !!" && exit 1
  [ "${value}" == "" ] && echo "ERROR: No value set !!" && exit 1

  echo "Setting configuration option ${key} with value: ${value}"
 postconf -e "${key} = ${value}"
}

[ -z "${SMTP_SERVER}" ] && echo "SMTP_SERVER is not set" && exit 1
[ -z "${SMTP_PORT}" ] && echo "SMTP_PORT is not set" && exit 1
[ -z "${SMTP_USERNAME}" ] && echo "SMTP_USERNAME is not set" && exit 1
[ -z "${SMTP_PASSWORD}" ] && echo "SMTP_PASSWORD is not set" && exit 1

#Check for subnet restrictions
nets='127.0.0.1, 172.0.0.0/8, 10.0.0.0/8, 192.168.0.0/16'
if [ ! -z "${SMTP_NETWORKS}" ]; then
        for i in $(sed 's/,/\ /g' <<<$SMTP_NETWORKS); do
                if grep -Eq "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}" <<<$i ; then
                        nets+=", $i"
                else
                        echo "$i is not in proper IPv4 subnet format. Ignoring."
                fi
        done
fi

# Set needed config options
add_config_value "myhostname" ${SERVER_HOSTNAME}
add_config_value "mydomain" ${DOMAIN}
add_config_value "mydestination" '$myhostname'
add_config_value "myorigin" '$mydomain'
add_config_value "relayhost" "[${SMTP_SERVER}]:${SMTP_PORT}"
add_config_value "smtp_sasl_auth_enable" "yes"
add_config_value "smtp_sasl_password_maps" "lmdb:/etc/postfix/sasl_passwd"
add_config_value "smtp_sasl_security_options" "noanonymous"
add_config_value "smtp_sasl_tls_security_options" "noanonymous"
add_config_value "smtp_tls_security_level" "encrypt"
add_config_value "header_size_limit" "4096000"
add_config_value "smtpd_sasl_local_domain" ${DOMAIN}
add_config_value "smtpd_recipient_restrictions" "permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination"
add_config_value "mailbox_size_limit" "256000000"

# Create sasl_passwd file with auth credentials
if [ ! -f /etc/postfix/sasl_passwd ]; then
  grep -q "${SMTP_SERVER}" /etc/postfix/sasl_passwd  > /dev/null 2>&1
  if [ $? -gt 0 ]; then
    echo "Adding SASL authentication configuration"
    echo "[${SMTP_SERVER}]:${SMTP_PORT} ${SMTP_USERNAME}:${SMTP_PASSWORD}" >> /etc/postfix/sasl_passwd
    postmap /etc/postfix/sasl_passwd
  fi
fi

#Set header tag  
if [ ! -z "${SMTP_HEADER_TAG}" ]; then
  postconf -e "header_checks = regexp:/etc/postfix/header_tag"
  echo -e "/^MIME-Version:/i PREPEND RelayTag: $SMTP_HEADER_TAG\n/^Content-Transfer-Encoding:/i PREPEND RelayTag: $SMTP_HEADER_TAG" > /etc/postfix/header_tag
  echo "Setting configuration option SMTP_HEADER_TAG with value: ${SMTP_HEADER_TAG}"
fi


add_config_value "mynetworks" "${nets}"

#Start services

# If host mounting /var/spool/postfix, we need to delete old pid file before
# starting services
rm -f /var/spool/postfix/pid/master.pid

postconf -c /etc/postfix/

if [[ $? != 0 ]]; then
  echo "Postfix configuration error, refusing to start."
  exit 1
else
  postfix -c /etc/postfix/ start
  sleep 126144000
fi

ENTERYPOINT /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
