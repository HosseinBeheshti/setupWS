#!/bin/bash
# OpenConnect VPN User Management Script
# Usage: ./manage_ocserv.sh [add|remove|list|disable|enable] [username]

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

OCPASSWD_FILE="/etc/ocserv/ocpasswd"

# Check root privileges
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root"
   exit 1
fi

# Check if ocserv is installed
if ! command -v ocpasswd &> /dev/null; then
    print_error "ocserv is not installed. Run ./setup_ocserv.sh first"
    exit 1
fi

# Show usage
show_usage() {
    echo "OpenConnect VPN User Management"
    echo ""
    echo "Usage: $0 <command> [username]"
    echo ""
    echo "Commands:"
    echo "  add <username>       - Add a new VPN user"
    echo "  remove <username>    - Remove a VPN user"
    echo "  disable <username>   - Disable a VPN user (keeps in database)"
    echo "  enable <username>    - Enable a disabled VPN user"
    echo "  list                 - List all VPN users"
    echo "  passwd <username>    - Change user password"
    echo ""
    echo "Examples:"
    echo "  $0 add john"
    echo "  $0 remove john"
    echo "  $0 list"
    exit 1
}

# Add user
add_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        print_error "Username is required"
        show_usage
    fi
    
    # Check if user already exists
    if [[ -f "$OCPASSWD_FILE" ]] && grep -q "^${username}:" "$OCPASSWD_FILE"; then
        print_error "User '$username' already exists"
        exit 1
    fi
    
    print_message "Creating VPN user: $username"
    
    # Create user with ocpasswd (will prompt for password)
    ocpasswd -c "$OCPASSWD_FILE" "$username"
    
    if [[ $? -eq 0 ]]; then
        print_message "✓ User '$username' created successfully"
        
        # Show connection info
        source "./workstation.env" 2>/dev/null || true
        if [[ -n "$OCSERV_HOSTNAME" && "$OCSERV_HOSTNAME" != "<vpn.yourdomain.com>" ]]; then
            echo ""
            print_message "Connection details:"
            echo -e "  Server: ${GREEN}${OCSERV_HOSTNAME}:${OCSERV_PORT:-443}${NC}"
            echo -e "  Username: ${GREEN}$username${NC}"
            echo -e "  Password: ${GREEN}(as entered above)${NC}"
        fi
    else
        print_error "Failed to create user '$username'"
        exit 1
    fi
}

# Remove user
remove_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        print_error "Username is required"
        show_usage
    fi
    
    # Check if user exists
    if [[ ! -f "$OCPASSWD_FILE" ]] || ! grep -q "^${username}:" "$OCPASSWD_FILE"; then
        print_error "User '$username' does not exist"
        exit 1
    fi
    
    print_warning "Removing VPN user: $username"
    
    # Remove user from password file
    ocpasswd -c "$OCPASSWD_FILE" -d "$username"
    
    if [[ $? -eq 0 ]]; then
        print_message "✓ User '$username' removed successfully"
        
        # Disconnect active sessions
        print_message "Disconnecting active sessions for user '$username'..."
        pkill -u "$username" ocserv 2>/dev/null || true
        
        # Show user count
        if [[ -f "$OCPASSWD_FILE" ]]; then
            user_count=$(grep -c "^" "$OCPASSWD_FILE" || echo "0")
            print_message "Total VPN users: $user_count"
        fi
    else
        print_error "Failed to remove user '$username'"
        exit 1
    fi
}

# Disable user (lock account)
disable_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        print_error "Username is required"
        show_usage
    fi
    
    # Check if user exists
    if [[ ! -f "$OCPASSWD_FILE" ]] || ! grep -q "^${username}:" "$OCPASSWD_FILE"; then
        print_error "User '$username' does not exist"
        exit 1
    fi
    
    print_message "Disabling VPN user: $username"
    
    # Lock the account by prefixing with '!'
    ocpasswd -c "$OCPASSWD_FILE" -l "$username"
    
    if [[ $? -eq 0 ]]; then
        print_message "✓ User '$username' disabled successfully"
        
        # Disconnect active sessions
        print_message "Disconnecting active sessions for user '$username'..."
        pkill -u "$username" ocserv 2>/dev/null || true
    else
        print_error "Failed to disable user '$username'"
        exit 1
    fi
}

# Enable user (unlock account)
enable_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        print_error "Username is required"
        show_usage
    fi
    
    # Check if user exists
    if [[ ! -f "$OCPASSWD_FILE" ]] || ! grep -q "^${username}:" "$OCPASSWD_FILE"; then
        print_error "User '$username' does not exist"
        exit 1
    fi
    
    print_message "Enabling VPN user: $username"
    
    # Unlock the account
    ocpasswd -c "$OCPASSWD_FILE" -u "$username"
    
    if [[ $? -eq 0 ]]; then
        print_message "✓ User '$username' enabled successfully"
    else
        print_error "Failed to enable user '$username'"
        exit 1
    fi
}

# Change password
change_password() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        print_error "Username is required"
        show_usage
    fi
    
    # Check if user exists
    if [[ ! -f "$OCPASSWD_FILE" ]] || ! grep -q "^${username}:" "$OCPASSWD_FILE"; then
        print_error "User '$username' does not exist"
        exit 1
    fi
    
    print_message "Changing password for VPN user: $username"
    
    # Change password
    ocpasswd -c "$OCPASSWD_FILE" "$username"
    
    if [[ $? -eq 0 ]]; then
        print_message "✓ Password changed for user '$username'"
    else
        print_error "Failed to change password for '$username'"
        exit 1
    fi
}

# List users
list_users() {
    if [[ ! -f "$OCPASSWD_FILE" ]]; then
        print_warning "No VPN users configured yet"
        echo ""
        echo "To add a user, run: $0 add <username>"
        exit 0
    fi
    
    print_message "VPN Users:"
    echo ""
    
    local count=0
    while IFS=: read -r username hash; do
        ((count++))
        # Check if locked (disabled)
        if [[ "$hash" == \!* ]]; then
            echo -e "  ${count}. ${YELLOW}${username}${NC} (disabled)"
        else
            echo -e "  ${count}. ${GREEN}${username}${NC}"
        fi
    done < "$OCPASSWD_FILE"
    
    echo ""
    print_message "Total users: $count"
    
    # Show active connections
    if command -v occtl &> /dev/null && systemctl is-active --quiet ocserv; then
        echo ""
        print_message "Active connections:"
        occtl show users 2>/dev/null || echo "  No active connections"
    fi
}

# Main
case "${1:-}" in
    add)
        add_user "$2"
        ;;
    remove|delete)
        remove_user "$2"
        ;;
    disable|lock)
        disable_user "$2"
        ;;
    enable|unlock)
        enable_user "$2"
        ;;
    list|ls)
        list_users
        ;;
    passwd|password)
        change_password "$2"
        ;;
    *)
        show_usage
        ;;
esac

exit 0
