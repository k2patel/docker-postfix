#!/bin/bash

# Postfix SMTP Relay Test Script
# This script validates the Postfix relay configuration and sends test emails

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

# Check if .env file exists
check_env() {
    print_header "Checking Environment Configuration"

    if [ ! -f .env ]; then
        print_error ".env file not found"
        print_info "Copy env.sample to .env and configure it"
        exit 1
    fi
    print_success ".env file found"

    # Source the .env file
    source .env

    # Check required variables
    local required_vars=("SMTP_SERVER" "SMTP_PORT" "SMTP_USERNAME" "SMTP_PASSWORD" "DOMAIN")
    local missing_vars=0

    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            print_error "$var is not set"
            missing_vars=$((missing_vars + 1))
        else
            print_success "$var is set"
        fi
    done

    if [ $missing_vars -gt 0 ]; then
        print_error "$missing_vars required variable(s) missing"
        exit 1
    fi

    print_info "Provider: $SMTP_SERVER:$SMTP_PORT"
    print_info "Domain: $DOMAIN"
}

# Check if Docker is running
check_docker() {
    print_header "Checking Docker"

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        exit 1
    fi
    print_success "Docker is installed"

    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    print_success "Docker daemon is running"

    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed"
        exit 1
    fi
    print_success "Docker Compose is installed"
}

# Check container status
check_container() {
    print_header "Checking Container Status"

    if ! docker ps --filter name=postfix-relay --format '{{.Names}}' | grep -q postfix-relay; then
        print_warning "Container is not running"
        print_info "Starting container..."
        docker-compose up -d
        sleep 10
    fi

    if docker ps --filter name=postfix-relay --format '{{.Names}}' | grep -q postfix-relay; then
        print_success "Container is running"
    else
        print_error "Failed to start container"
        exit 1
    fi

    # Check health status
    health_status=$(docker inspect postfix-relay --format='{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    if [ "$health_status" = "healthy" ]; then
        print_success "Container is healthy"
    elif [ "$health_status" = "starting" ]; then
        print_warning "Container is starting..."
        print_info "Waiting for health check..."
        sleep 10
    else
        print_warning "Health status: $health_status"
    fi
}

# Check Postfix status
check_postfix() {
    print_header "Checking Postfix Status"

    if docker exec postfix-relay postfix status &> /dev/null; then
        print_success "Postfix is running"
    else
        print_error "Postfix is not running"
        print_info "Checking logs..."
        docker logs --tail 50 postfix-relay
        exit 1
    fi
}

# Check network connectivity
check_network() {
    print_header "Checking Network Connectivity"

    source .env

    # Check if nc (netcat) is available in container
    if docker exec postfix-relay which nc &> /dev/null; then
        if docker exec postfix-relay nc -zv ${SMTP_SERVER} ${SMTP_PORT} 2>&1 | grep -q succeeded; then
            print_success "Can connect to ${SMTP_SERVER}:${SMTP_PORT}"
        else
            print_error "Cannot connect to ${SMTP_SERVER}:${SMTP_PORT}"
            print_info "Check firewall and network settings"
        fi
    else
        print_warning "netcat not available, skipping connectivity test"
    fi
}

# Check Postfix configuration
check_config() {
    print_header "Validating Postfix Configuration"

    if docker exec postfix-relay postfix check 2>&1 | grep -q error; then
        print_error "Postfix configuration has errors"
        docker exec postfix-relay postfix check
        exit 1
    else
        print_success "Postfix configuration is valid"
    fi

    # Show key configuration
    print_info "Key Configuration Values:"
    docker exec postfix-relay postconf -n | grep -E "^(myhostname|mydomain|relayhost|mynetworks)" | while read line; do
        echo "  $line"
    done
}

# Check mail queue
check_queue() {
    print_header "Checking Mail Queue"

    queue_output=$(docker exec postfix-relay postqueue -p)

    if echo "$queue_output" | grep -q "Mail queue is empty"; then
        print_success "Mail queue is empty"
    else
        print_warning "Mail queue has messages:"
        echo "$queue_output"
    fi
}

# Send test email
send_test_email() {
    print_header "Sending Test Email"

    if [ -z "$1" ]; then
        read -p "Enter recipient email address: " recipient
    else
        recipient="$1"
    fi

    if [ -z "$recipient" ]; then
        print_error "No recipient provided"
        return 1
    fi

    # Validate email format
    if ! echo "$recipient" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
        print_error "Invalid email address format"
        return 1
    fi

    print_info "Sending test email to: $recipient"

    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    hostname=$(docker exec postfix-relay hostname)

    test_message="Test email from Postfix SMTP Relay

Timestamp: $timestamp
Hostname: $hostname
Container: postfix-relay

If you receive this email, your Postfix relay is working correctly!
"

    if docker exec postfix-relay sh -c "echo '$test_message' | mail -s 'Postfix Relay Test - $timestamp' $recipient" 2>&1; then
        print_success "Test email sent to $recipient"
        print_info "Check the mail queue and logs:"
        echo ""
        docker exec postfix-relay postqueue -p
    else
        print_error "Failed to send test email"
        return 1
    fi
}

# Show logs
show_logs() {
    print_header "Recent Logs"
    docker logs --tail 50 postfix-relay
}

# Full test suite
run_full_test() {
    print_header "Running Full Test Suite"

    check_env
    check_docker
    check_container
    check_postfix
    check_network
    check_config
    check_queue

    print_header "Test Summary"
    print_success "All checks passed!"
    print_info "Container is ready to relay emails"

    echo ""
    read -p "Do you want to send a test email? (y/n): " send_test
    if [ "$send_test" = "y" ] || [ "$send_test" = "Y" ]; then
        send_test_email
    fi
}

# Main menu
show_menu() {
    echo ""
    echo -e "${BLUE}Postfix SMTP Relay Test Menu${NC}"
    echo "================================"
    echo "1) Run full test suite"
    echo "2) Check environment"
    echo "3) Check container status"
    echo "4) Check Postfix configuration"
    echo "5) Check mail queue"
    echo "6) Send test email"
    echo "7) Show logs"
    echo "8) Exit"
    echo ""
    read -p "Select option: " option

    case $option in
        1) run_full_test ;;
        2) check_env ;;
        3) check_container && check_postfix ;;
        4) check_config ;;
        5) check_queue ;;
        6) send_test_email ;;
        7) show_logs ;;
        8) exit 0 ;;
        *) print_error "Invalid option"; show_menu ;;
    esac
}

# Parse command line arguments
if [ $# -eq 0 ]; then
    # No arguments, show menu
    show_menu
else
    case "$1" in
        --full|-f)
            run_full_test
            ;;
        --email|-e)
            if [ -n "$2" ]; then
                send_test_email "$2"
            else
                send_test_email
            fi
            ;;
        --check|-c)
            check_env
            check_docker
            check_container
            check_postfix
            check_config
            ;;
        --logs|-l)
            show_logs
            ;;
        --queue|-q)
            check_queue
            ;;
        --help|-h)
            echo "Postfix SMTP Relay Test Script"
            echo ""
            echo "Usage: $0 [option] [arguments]"
            echo ""
            echo "Options:"
            echo "  -f, --full              Run full test suite"
            echo "  -c, --check             Run configuration checks"
            echo "  -e, --email [address]   Send test email"
            echo "  -q, --queue             Check mail queue"
            echo "  -l, --logs              Show recent logs"
            echo "  -h, --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                              # Interactive menu"
            echo "  $0 --full                       # Run all tests"
            echo "  $0 --email user@example.com     # Send test email"
            echo "  $0 --check                      # Check configuration"
            echo ""
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
fi
