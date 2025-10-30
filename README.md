# Docker Postfix SMTP Relay

A lightweight Postfix SMTP relay container supporting multiple email service providers including Maileroo, Mailtrap, SendGrid, and any generic SMTP server.

## Features

- 🚀 Multi-provider support (Maileroo, Mailtrap, SendGrid, Gmail, Office365, any SMTP)
- 🔒 TLS/SSL encryption
- 🌐 Auto-detects /16 subnet for relay
- 📝 All logs to stderr (`docker logs`)
- 🏥 Built-in health checks
- 🔧 Simple Makefile-based operations

## Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/your-org/docker-postfix.git
cd docker-postfix
cp env.sample .env
nano .env  # Edit with your SMTP provider details
```

### 2. Build and Start

```bash
cd test
make build
make up
```

### 3. Test

```bash
cd test
make test TO=your@email.com
```

## Configuration

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SMTP_SERVER` | Yes | - | SMTP server hostname |
| `SMTP_PORT` | Yes | 587 | SMTP server port |
| `SMTP_USERNAME` | Yes | - | SMTP username |
| `SMTP_PASSWORD` | Yes | - | SMTP password |
| `DOMAIN` | Yes | - | Domain for outgoing mail |
| `SERVER_HOSTNAME` | No | Auto | Server FQDN |
| `TIMEZONE` | No | America/New_York | Timezone |
| `SMTP_NETWORKS` | No | Auto /16 | Additional networks (comma-separated CIDR) |
| `SMTP_LISTEN_PORT` | No | 25 | Port to expose on host |
| `LOCAL_NETWORK` | No | Auto-detected | Override local network CIDR (e.g., 192.168.0.0/16) |
| `DEBUG` | No | no | Enable debug logging |

### Provider Examples

#### Maileroo
```bash
SMTP_SERVER=smtp.maileroo.com
SMTP_PORT=587
SMTP_USERNAME=noreply@example.com
SMTP_PASSWORD=your_password
DOMAIN=example.com
```

#### Mailtrap
```bash
SMTP_SERVER=live.smtp.mailtrap.io
SMTP_PORT=587
SMTP_USERNAME=your_username
SMTP_PASSWORD=your_password
DOMAIN=example.com
```

#### SendGrid
```bash
SMTP_SERVER=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=your_api_key
DOMAIN=example.com
```

**Note**: For SendGrid, username must be `apikey` (literal string).

#### Gmail
```bash
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your_email@gmail.com
SMTP_PASSWORD=your_app_password
DOMAIN=gmail.com
```

## Makefile Commands

All operations are handled through the Makefile in the `test/` directory.

### Setup Commands

```bash
cd test

make build       # Build the Docker image
make up          # Start the container
make down        # Stop the container
make restart     # Restart the container
```

### Monitoring Commands

```bash
make logs        # View logs (follow mode)
make logs-tail   # View last 100 lines
make status      # Show container and Postfix status
make queue       # View mail queue
make health      # Check container health
```

### Maintenance Commands

```bash
make shell       # Open shell in container
make config      # Show Postfix configuration
make test        # Send test email (auto-detects container)
make flush       # Flush mail queue
make check       # Validate Postfix configuration
```

### Cleanup Commands

```bash
make clean       # Remove container and volumes
make clean-all   # Remove everything including images
```

### Advanced Commands

```bash
make debug       # Start with debug mode enabled
make validate    # Validate .env file
make queue-delete # Delete all messages in queue
make stats       # Show real-time container stats
```

### Full Command List

Run `make help` or just `make` to see all available commands:

```bash
cd test
make
```

## Network Configuration

The container automatically allows relay from:
- Localhost (127.0.0.0/8)
- Auto-detected /16 subnet

To add custom networks:
```bash
SMTP_NETWORKS=192.168.1.0/24,10.0.0.0/8
```

## Using with Applications

Configure your application to use the relay:

```yaml
services:
  your-app:
    environment:
      MAIL_HOST: postfix-relay
      MAIL_PORT: 25
    depends_on:
      - postfix
```

Connection details:
- **Host**: `postfix-relay`
- **Port**: `25`
- **Authentication**: Not required for local network

## Testing

### Quick Test (Recommended)

The easiest way to test your Postfix relay:

```bash
cd test
make test TO=recipient@example.com
```

**That's it!** No configuration needed.

### What Gets Auto-Detected?

The test script automatically finds and configures:

| Feature | What Happens | Override Option |
|---------|--------------|-----------------|
| **Container Name** | Finds containers using `docker-postfix-postfix` image | Specify as first arg |
| **FROM Address** | Uses `noreply@DOMAIN` from container env | `FROM=email@domain.com` |
| **SMTP Port** | Detects mapped port (e.g., `25` or custom) | N/A (always detected) |
| **Host IP** | Converts `0.0.0.0` → `127.0.0.1` for local testing | N/A (always detected) |
| **Subject** | Defaults to "Test Email from Postfix Relay" | `SUBJECT="Your Subject"` |

**No manual configuration required** - just provide the recipient email!

### Advanced Testing Options

**With custom FROM address:**
```bash
make test TO=user@example.com FROM=noreply@mydomain.com
```

**With custom subject:**
```bash
make test TO=user@example.com FROM=sender@domain.com SUBJECT="My Test Email"
```

**Using the test script directly:**
```bash
./test-email.sh user@example.com
./test-email.sh user@example.com sender@mydomain.com
./test-email.sh user@example.com sender@mydomain.com "Custom Subject"
```

**Manual container specification (if auto-detection fails):**
```bash
./test-email.sh my-container user@example.com sender@domain.com
```

### Test Script Features

The `test-email.sh` script automatically:
- Finds containers using `docker-postfix-postfix` image
- Detects port mapping and converts `0.0.0.0` to `127.0.0.1`
- Uses proper SMTP protocol via sendmail
- Falls back to mail command if needed
- Shows queue status after sending
- Provides colored output for easy reading

### Validation Tests

```bash
cd test
make check       # Validate Postfix configuration
make validate    # Validate .env file
make queue       # View mail queue
make config      # Show current Postfix config
```

## Troubleshooting

### Email Not Received

**1. Check container logs:**
```bash
cd test
make logs-tail   # Last 100 lines
make logs        # Follow in real-time
```

**2. Check mail queue:**
```bash
make queue       # View queued messages
make flush       # Force processing
```

**3. Verify configuration:**
```bash
make config      # Show Postfix config
make check       # Validate config
make validate    # Validate .env file
```

### SMTP Protocol Errors

If you see "improper command pipelining" errors:

**Use the test script** (handles protocol correctly):
```bash
./test-email.sh user@example.com sender@domain.com
```

**Verify FROM domain matches DOMAIN setting:**
```bash
# In .env file
DOMAIN=mydomain.com

# Use matching FROM address
make test TO=user@example.com FROM=noreply@mydomain.com
```

**Check mynetworks configuration:**
```bash
docker exec postfix-relay postconf mynetworks
```

### Container Not Auto-Detected

**1. Verify container is running:**
```bash
docker ps | grep postfix
```

**2. Start the container:**
```bash
cd test
make up
```

**3. Manually specify container:**
```bash
./test-email.sh my-container-name user@example.com
```

### Enable Debug Mode

For detailed SMTP transaction logs:
```bash
cd test
make debug
```

### Emails Stuck in Queue

```bash
cd test
make queue          # View queue
make flush          # Force processing
make queue-delete   # Delete all (with confirmation)
```

### Network Configuration Issues

**Override auto-detected network:**
```bash
# In .env file
LOCAL_NETWORK=192.168.1.0/24
```

**Add additional networks:**
```bash
SMTP_NETWORKS=10.0.0.0/8,172.16.0.0/12
```

### Container Health Issues

```bash
cd test
make status      # Check status
make health      # Check health status
make restart     # Restart container
make down        # Stop container
make up          # Start fresh
```

## Examples

### Testing Examples

**Simple test with Gmail:**
```bash
cd test
make test TO=youraddress@gmail.com
# FROM will auto-detect from DOMAIN in .env
```

**Test with custom FROM and subject:**
```bash
make test TO=client@example.com FROM=support@mycompany.com SUBJECT="Production Test"
```

**Test from command line:**
```bash
./test-email.sh user@example.com noreply@mydomain.com "Hello World"
```

**Verify email was sent:**
```bash
make queue       # Should show empty queue if sent
make logs-tail   # Check for "status=sent"
```

### Basic Workflow

```bash
# Initial setup
cd docker-postfix
cp env.sample .env
nano .env

# Build and start
cd test
make build
make up

# Check status
make status
make logs

# Test email delivery
make test TO=your@email.com

# Stop
make down
```

### Development Workflow

```bash
cd test

# Start with debug
make debug

# Check logs in another terminal
make logs

# Restart after changes
make restart

# Clean up
make clean
```

### Monitoring Workflow

```bash
cd test

# Check everything
make status
make health
make queue
make logs-tail

# Continuous monitoring
make logs
```

## Security

- Store credentials in `.env` (never commit to git)
- Limit relay to trusted networks only
- TLS automatically enabled for known providers
- Use app-specific passwords for Gmail

## License

MIT License - See [LICENSE](LICENSE) file for details.

## Support

For issues and questions, please open an issue on GitHub.