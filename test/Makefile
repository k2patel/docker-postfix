.PHONY: help build up down restart logs shell test clean status queue config

# Change to parent directory for docker-compose commands
COMPOSE=cd .. && docker-compose

# Default target
help:
	@echo "Docker Postfix SMTP Relay - Makefile Commands"
	@echo "=============================================="
	@echo ""
	@echo "Setup and Build:"
	@echo "  make build       - Build the Docker image"
	@echo "  make up          - Start the container"
	@echo "  make down        - Stop the container"
	@echo "  make restart     - Restart the container"
	@echo ""
	@echo "Monitoring:"
	@echo "  make logs        - View container logs (follow)"
	@echo "  make logs-tail   - View last 100 lines"
	@echo "  make status      - Show container and Postfix status"
	@echo "  make queue       - View mail queue"
	@echo "  make health      - Check container health"
	@echo ""
	@echo "Maintenance:"
	@echo "  make shell       - Open shell in container"
	@echo "  make config      - Show Postfix configuration"
	@echo "  make test        - Send test email (auto-detects container)"
	@echo "                     Usage: make test TO=user@example.com [FROM=sender@domain.com]"
	@echo "  make flush       - Flush mail queue"
	@echo "  make check       - Check Postfix configuration"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean       - Remove container and volumes"
	@echo "  make clean-all   - Remove everything including images"
	@echo ""
	@echo "Advanced:"
	@echo "  make debug       - Start with debug mode enabled"
	@echo "  make validate    - Validate environment file"
	@echo "  make stats       - Show real-time stats"
	@echo ""

# Build the Docker image
build:
	@echo "Building Docker image..."
	@$(COMPOSE) build

# Start the container
up:
	@echo "Starting Postfix relay..."
	@$(COMPOSE) up -d
	@echo "Waiting for container to be healthy..."
	@sleep 5
	@make status

# Stop the container
down:
	@echo "Stopping Postfix relay..."
	@$(COMPOSE) down

# Restart the container
restart: down up

# View logs
logs:
	@$(COMPOSE) logs -f

# View last 100 lines of logs
logs-tail:
	@$(COMPOSE) logs --tail=100

# Open shell in container
shell:
	@$(COMPOSE) exec postfix bash

# Show container and Postfix status
status:
	@echo "Container Status:"
	@echo "================="
	@docker ps --filter name=postfix-relay --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "Postfix Status:"
	@echo "==============="
	@$(COMPOSE) exec postfix postfix status || echo "Container not running"

# View mail queue
queue:
	@echo "Mail Queue:"
	@echo "==========="
	@$(COMPOSE) exec postfix postqueue -p

# Flush mail queue
flush:
	@echo "Flushing mail queue..."
	@$(COMPOSE) exec postfix postqueue -f
	@echo "Queue flushed"

# View Postfix configuration
config:
	@echo "Postfix Configuration:"
	@echo "====================="
	@$(COMPOSE) exec postfix postconf -n

# Check Postfix configuration
check:
	@echo "Checking Postfix configuration..."
	@$(COMPOSE) exec postfix postfix check
	@$(COMPOSE) exec postfix postconf -c /etc/postfix/
	@echo "Configuration check complete"

# Send test email
test:
	@if [ -z "$(TO)" ]; then \
		echo "Usage: make test TO=recipient@example.com [FROM=sender@domain.com] [SUBJECT='Test Email']"; \
		echo ""; \
		echo "Examples:"; \
		echo "  make test TO=user@example.com"; \
		echo "  make test TO=user@example.com FROM=noreply@mydomain.com"; \
		echo "  make test TO=user@example.com FROM=sender@domain.com SUBJECT='My Test'"; \
		echo ""; \
		echo "Note: Container is auto-detected from docker-postfix-postfix image"; \
		echo "      FROM defaults to noreply@<DOMAIN> if not specified"; \
		exit 1; \
	fi
	@if [ -n "$(CONTAINER)" ]; then \
		./test-email.sh $(CONTAINER) $(TO) $(FROM) $(SUBJECT); \
	else \
		./test-email.sh $(TO) $(FROM) $(SUBJECT); \
	fi

# Validate environment file
validate:
	@echo "Validating .env file..."
	@if [ ! -f ../.env ]; then \
		echo "ERROR: .env file not found. Copy env.sample to .env in parent directory"; \
		exit 1; \
	fi
	@grep -q "SMTP_SERVER=" ../.env || (echo "ERROR: SMTP_SERVER not set" && exit 1)
	@grep -q "SMTP_PORT=" ../.env || (echo "ERROR: SMTP_PORT not set" && exit 1)
	@grep -q "SMTP_USERNAME=" ../.env || (echo "ERROR: SMTP_USERNAME not set" && exit 1)
	@grep -q "SMTP_PASSWORD=" ../.env || (echo "ERROR: SMTP_PASSWORD not set" && exit 1)
	@grep -q "DOMAIN=" ../.env || (echo "ERROR: DOMAIN not set" && exit 1)
	@echo "Environment file validation passed"

# Clean up (remove container and volumes)
clean:
	@echo "Cleaning up containers and volumes..."
	@$(COMPOSE) down -v
	@echo "Cleaning local data directories..."
	@cd .. && rm -rf data logs mail spool
	@echo "Cleanup complete"

# Clean everything including images
clean-all: clean
	@echo "Removing Docker images..."
	@$(COMPOSE) down --rmi all
	@echo "Complete cleanup finished"

# Show queue details
queue-detail:
	@echo "Detailed Queue Information:"
	@echo "=========================="
	@$(COMPOSE) exec postfix sh -c "postqueue -p | tail -n 1"

# Delete all queued messages
queue-delete:
	@echo "WARNING: This will delete ALL messages in the queue!"
	@read -p "Are you sure? (yes/no): " confirm; \
	if [ "$$confirm" = "yes" ]; then \
		$(COMPOSE) exec postfix postsuper -d ALL; \
		echo "All queued messages deleted"; \
	else \
		echo "Cancelled"; \
	fi

# Enable debug mode
debug:
	@echo "Restarting with DEBUG mode enabled..."
	@$(COMPOSE) down
	@cd .. && DEBUG=yes docker-compose up

# Show real-time statistics
stats:
	@docker stats postfix-relay

# Run health check
health:
	@echo "Running health check..."
	@docker inspect postfix-relay --format='{{.State.Health.Status}}' 2>/dev/null || echo "Container not running"
