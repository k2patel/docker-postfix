FROM docker.io/library/alpine:3.19

# Variables for Labels
ARG VENDOR="your-org"
ARG COMPONENT="postfix-relay"
ARG BUILD_DATE
ARG GIT_REPO="https://github.com/your-org/docker-postfix"
ARG VCS_REF
ARG VERSION="2.0"
ARG NAME="dockerized-${COMPONENT}"
ARG DESCRIPTION="Postfix SMTP relay supporting multiple providers (Maileroo, Mailtrap, SendGrid)"
ARG DOCUMENTATION="https://github.com/your-org/docker-postfix"
ARG AUTHOR="Your Name <your-email@example.com>"
ARG LICENSE="MIT"

# Labels
LABEL org.label-schema.build-date="${BUILD_DATE}" \
    org.label-schema.name="${NAME}" \
    org.label-schema.description="${DESCRIPTION}" \
    org.label-schema.vcs-ref="${VCS_REF}" \
    org.label-schema.vcs-url="${GIT_REPO}" \
    org.label-schema.vendor="${VENDOR}" \
    org.label-schema.version="${VERSION}"

# Install required packages
RUN apk add --no-cache \
    postfix \
    postfix-pcre \
    cyrus-sasl \
    cyrus-sasl-login \
    libsasl \
    ca-certificates \
    bash \
    tzdata \
    mailx

# Create necessary directories
RUN mkdir -p /var/spool/postfix /etc/postfix/sasl

# Copy entrypoint script
COPY run.sh /run.sh
RUN chmod +x /run.sh

# Initialize postfix
RUN newaliases

# Expose SMTP port
EXPOSE 25

# Volumes for persistence
VOLUME ["/var/spool/postfix"]

# Health check
HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=40s \
    CMD postfix status || exit 1

# Run postfix in foreground
ENTRYPOINT ["/run.sh"]
