#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments flexibly
# Supports: recipient [from] [subject]
# Or: container recipient [from] [subject]
CONTAINER_NAME=""
RECIPIENT=""
FROM_EMAIL=""
SUBJECT="Test Email from Postfix Relay"

# Check if first argument looks like an email
if [[ "$1" =~ @.*\. ]]; then
    # First arg is email - it's the recipient
    RECIPIENT="${1}"
    FROM_EMAIL="${2}"
    SUBJECT="${3:-Test Email from Postfix Relay}"
else
    # First arg is not email - assume it's container name
    if [ -n "$1" ]; then
        CONTAINER_NAME="${1}"
        RECIPIENT="${2}"
        FROM_EMAIL="${3}"
        SUBJECT="${4:-Test Email from Postfix Relay}"
    fi
fi

# Function to print colored messages
print_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

print_success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

print_info() {
    echo -e "${YELLOW}INFO: $1${NC}"
}

# Show usage if recipient is not provided
if [ -z "$RECIPIENT" ]; then
    echo "Usage: $0 RECIPIENT_EMAIL [FROM_EMAIL] [SUBJECT]"
    echo "   or: $0 CONTAINER_NAME RECIPIENT_EMAIL [FROM_EMAIL] [SUBJECT]"
    echo ""
    echo "Arguments:"
    echo "  RECIPIENT_EMAIL  - Email address to send test email to (required)"
    echo "  FROM_EMAIL       - From email address (optional, default: noreply@<domain>)"
    echo "  SUBJECT          - Email subject (default: 'Test Email from Postfix Relay')"
    echo "  CONTAINER_NAME   - Docker container name (optional, auto-detected)"
    echo ""
    echo "Examples:"
    echo "  $0 user@example.com"
    echo "  $0 user@example.com sender@mydomain.com"
    echo "  $0 user@example.com sender@mydomain.com 'My Test Email'"
    echo "  $0 my-postfix user@example.com sender@mydomain.com"
    echo ""
    exit 1
fi

# Auto-detect container name if not provided
if [ -z "$CONTAINER_NAME" ]; then
    print_info "Auto-detecting container..."

    # Try to find container by image name pattern
    CONTAINER_NAME=$(docker ps --filter "ancestor=docker-postfix-postfix" --format '{{.Names}}' | head -n 1)

    # Fallback: try common naming patterns
    if [ -z "$CONTAINER_NAME" ]; then
        CONTAINER_NAME=$(docker ps --filter "name=postfix" --format '{{.Names}}' | head -n 1)
    fi

    if [ -z "$CONTAINER_NAME" ]; then
        print_error "Could not auto-detect container. Please specify container name."
        echo ""
        echo "Available containers:"
        docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"
        echo ""
        echo "Usage: $0 CONTAINER_NAME RECIPIENT_EMAIL"
        exit 1
    fi

    print_success "Detected container: ${CONTAINER_NAME}"
fi

# Check if container exists
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    print_error "Container '${CONTAINER_NAME}' is not running"
    echo ""
    echo "Available containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    exit 1
fi

print_info "Container: ${CONTAINER_NAME}"

# Get the port mapping for the container
PORT_MAPPING=$(docker port "${CONTAINER_NAME}" 25 2>/dev/null | head -n 1)

if [ -z "$PORT_MAPPING" ]; then
    print_error "Could not determine port mapping for container '${CONTAINER_NAME}'"
    exit 1
fi

# Extract host and port from mapping (format: 0.0.0.0:25 or 127.0.0.1:25)
HOST=$(echo "$PORT_MAPPING" | cut -d: -f1)
PORT=$(echo "$PORT_MAPPING" | cut -d: -f2)

# Convert 0.0.0.0 to 127.0.0.1 for local communication
if [ "$HOST" = "0.0.0.0" ]; then
    HOST="127.0.0.1"
fi

# Set default FROM email if not provided
if [ -z "$FROM_EMAIL" ]; then
    # Try to get domain from container environment or use hostname
    DOMAIN=$(docker exec "$CONTAINER_NAME" printenv DOMAIN 2>/dev/null || echo "relay.local")
    FROM_EMAIL="noreply@${DOMAIN}"
fi

print_info "SMTP Server: ${HOST}:${PORT}"
print_info "From: ${FROM_EMAIL}"
print_info "Recipient: ${RECIPIENT}"
print_info "Subject: ${SUBJECT}"
echo ""

# Generate email body with timestamp
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S %Z")
EMAIL_BODY="This is a test email sent from the Postfix SMTP relay.

Container: ${CONTAINER_NAME}
Sent at: ${TIMESTAMP}
SMTP Server: ${HOST}:${PORT}

If you received this email, your Postfix relay is working correctly!

---
Automated test email"

print_info "Sending test email..."
echo ""

# Method 1: Try using sendmail directly (most reliable for Postfix)
print_info "Attempting to send via sendmail..."

SENDMAIL_OUTPUT=$(docker exec -i "$CONTAINER_NAME" sendmail -v -f "$FROM_EMAIL" "$RECIPIENT" 2>&1 << EOFMAIL
From: ${FROM_EMAIL}
To: ${RECIPIENT}
Subject: ${SUBJECT}

${EMAIL_BODY}
EOFMAIL
)
SENDMAIL_EXIT=$?

if [ $SENDMAIL_EXIT -eq 0 ]; then
    print_success "Email queued successfully via sendmail"
    echo "$SENDMAIL_OUTPUT" | grep -i "queued\|sent" || true
else
    print_error "Sendmail method failed"
    echo "Output: $SENDMAIL_OUTPUT"
    echo ""

    # Method 2: Try using mailx/mail command
    print_info "Trying alternative method using mail command..."

    MAIL_OUTPUT=$(docker exec "$CONTAINER_NAME" sh -c "
        echo '${EMAIL_BODY}' | mail -v -s '${SUBJECT}' -r '${FROM_EMAIL}' '${RECIPIENT}' 2>&1
    ")
    MAIL_EXIT=$?

    if [ $MAIL_EXIT -eq 0 ]; then
        print_success "Email queued successfully via mail command"
    else
        print_error "Mail command failed"
        echo "Output: $MAIL_OUTPUT"
        echo ""
        print_info "Check container logs for more details:"
        echo "  docker logs $CONTAINER_NAME"
        exit 1
    fi
fi

echo ""
print_info "Checking mail queue..."
docker exec "$CONTAINER_NAME" postqueue -p 2>/dev/null || echo "Queue check not available"

echo ""
print_success "Test complete! Check the recipient mailbox for the test email."
echo ""
print_info "You can monitor the logs with:"
echo "  docker logs -f ${CONTAINER_NAME}"
echo ""
