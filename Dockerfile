#Postfix relay
FROM docker.io/library/alpine:latest

#     Variables for Labels:
ARG VENDOR="k2patel"
ARG COMPONENT="postfix-relay"
ARG BUILD_DATE
ARG GIT_REPO
ARG VCS_REF
ARG VERSION="1"
ARG NAME="dockerized-${COMPONENT}"
ARG DESCRIPTION="dockerized environment."
ARG DOCUMENTATION="https://git.k2patel.in"
ARG AUTHOR="k2patel<k2patel@live.com>"
ARG LICENSE="MIT"
#     END Variables

#########################################
LABEL org.label-schema.build-date="${BUILD_DATE}" \
        org.label-schema.name="${NAME}" \
        org.label-schema.description="${DESCRIPTION}" \
        org.label-schema.vcs-ref="${VCS_REF}" \
        org.label-schema.vcs-url="${GIT_REPO}" \
        org.label-schema.url="${GIT_REPO}" \
        org.label-schema.vendor="${VENDOR}" \
        org.label-schema.version="${VERSION}" \
        org.label-schema.usage="${DOCUMENTATION}"

LABEL   org.opencontainers.image.created="${BUILD_DATE}" \
        org.opencontainers.image.url="${GIT_REPO}" \
        org.opencontainers.image.source="${GIT_REPO}" \
        org.opencontainers.image.version="${VERSION}" \
        org.opencontainers.image.revision="${VCS_REF}" \
        org.opencontainers.image.vendor="${VENDOR}" \
        org.opencontainers.image.title="${NAME}" \
        org.opencontainers.image.description="${DESCRIPTION}" \
        org.opencontainers.image.documentation="${DOCUMENTATION}" \
        org.opencontainers.image.authors="${AUTHOR}" \
        org.opencontainers.image.licenses="${LICENSE}"
#########################################

ENV TIMEZONE=${TIMEZONE}
ENV SMTP_SERVER=${SMTP_SERVER}
ENV SERVER_HOSTNAME=${SERVER_HOSTNAME}
ENV SMTP_PORT=${SMTP_PORT}
ENV DOMAIN=${DOMAIN}
ENV SMTP_USERNAME=${SMTP_USERNAME}
ENV SMTP_PASSWORD=${SMTP_PASSWORD}

# Intall Needed Package
RUN apk add --no-cache postfix libsasl supervisor ca-certificates bash rsyslog cyrus-sasl

#Configure nodaemon mode for supervisord
RUN sed -i -e "s/^nodaemon=false/nodaemon=true/" /etc/supervisord.conf
#Change postfix to listen on all the interface
RUN sed -i -e 's/inet_interfaces = localhost/inet_interfaces = all/g' /etc/postfix/main.cf

COPY etc/ /etc/
VOLUME ["/var/log", "/var/mail", "/var/spool/postfix"]
COPY run.sh /
RUN chmod +x /run.sh
RUN newaliases

EXPOSE 25

ENTRYPOINT /usr/bin/supervisord -c /etc/supervisor/supervisord.conf

