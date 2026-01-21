#!/bin/bash

################################################################################
# WireGuard User Query & Management Script
# Description: Interactive tool for managing WireGuard peers and SQLite database
# Usage: sudo ./query_users.sh
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
DB_PATH="/var/lib/ztna/users.db"
WG_CONFIG="/etc/wireguard/wg0.conf"
CLIENT_DIR="/var/lib/ztna/clients"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Check if database exists
if [ ! -f "$DB_PATH" ]; then
    echo -e "${RED}Error: Database not found at $DB_PATH${NC}"
    echo "Run setup_server.sh first to initialize the database"
    exit 1
fi

# Function to print header
print_header() {
    echo ""
    echo -e "${BLUE}========================================"
    echo "$1"
    echo -e "========================================${NC}"
}

# Function to list all peers
list_all_peers() {
    print_header "ALL WIREGUARD PEERS"
    
    echo -e "${CYAN}ID | Username      | Device ID  | Peer IP       | Created At           | Last Seen${NC}"
    echo "---+---------------+------------+---------------+----------------------+----------------------"
    
    sqlite3 -separator ' | ' "$DB_PATH" << EOF
.mode column
SELECT 
    id,
    SUBSTR(username, 1, 13) as username,
    SUBSTR(device_id, 1, 10) as device_id,
    peer_ip,
    created_at,
    COALESCE(last_seen, 'Never') as last_seen
FROM users
ORDER BY id;
EOF
    
    echo ""
    TOTAL=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;")
    echo -e "${GREEN}Total peers: $TOTAL${NC}"
    echo ""
}

# Function to show active connections
show_active_connections() {
    print_header "ACTIVE WIREGUARD CONNECTIONS"
    
    if ! command -v wg &> /dev/null; then
        echo -e "${YELLOW}Warning: wg command not found${NC}"
        echo "WireGuard tools not installed or not in PATH"
        return
    fi
    
    # Get WireGuard status
    WG_OUTPUT=$(wg show wg0 2>/dev/null || echo "")
    
    if [ -z "$WG_OUTPUT" ]; then
        echo -e "${YELLOW}WireGuard interface wg0 not found or not running${NC}"
        echo "Check: sudo wg show"
        return
    fi
    
    echo -e "${CYAN}Peer Public Key (truncated) | Endpoint          | Latest Handshake | Transfer${NC}"
    echo "------------------------------+-------------------+------------------+---------------------------"
    
    # Parse wg show output
    CURRENT_PEER=""
    PEER_ENDPOINT=""
    PEER_HANDSHAKE=""
    PEER_TRANSFER=""
    
    while IFS= read -r line; do
        if [[ $line == peer:* ]]; then
            # Print previous peer if exists
            if [ -n "$CURRENT_PEER" ]; then
                PEER_SHORT="${CURRENT_PEER:0:26}..."
                printf "%-30s| %-17s | %-16s | %s\n" "$PEER_SHORT" "${PEER_ENDPOINT:-N/A}" "${PEER_HANDSHAKE:-Never}" "${PEER_TRANSFER:-0 B}"
            fi
            
            # Start new peer
            CURRENT_PEER=$(echo "$line" | awk '{print $2}')
            PEER_ENDPOINT=""
            PEER_HANDSHAKE=""
            PEER_TRANSFER=""
        elif [[ $line == *endpoint:* ]]; then
            PEER_ENDPOINT=$(echo "$line" | awk '{print $2}')
        elif [[ $line == *"latest handshake"* ]]; then
            PEER_HANDSHAKE=$(echo "$line" | sed 's/.*latest handshake: //')
        elif [[ $line == *"transfer"* ]]; then
            PEER_TRANSFER=$(echo "$line" | sed 's/.*transfer: //')
        fi
    done <<< "$WG_OUTPUT"
    
    # Print last peer
    if [ -n "$CURRENT_PEER" ]; then
        PEER_SHORT="${CURRENT_PEER:0:26}..."
        printf "%-30s| %-17s | %-16s | %s\n" "$PEER_SHORT" "${PEER_ENDPOINT:-N/A}" "${PEER_HANDSHAKE:-Never}" "${PEER_TRANSFER:-0 B}"
    fi
    
    echo ""
}

# Function to remove peer
remove_peer() {
    echo ""
    echo -e "${YELLOW}Enter username to remove:${NC}"
    read -r USERNAME
    
    if [ -z "$USERNAME" ]; then
        echo -e "${RED}Error: Username cannot be empty${NC}"
        return
    fi
    
    # Check if user exists
    USER_EXISTS=$(sqlite3 "$DB_PATH" "SELECT username FROM users WHERE username='$USERNAME';" || echo "")
    
    if [ -z "$USER_EXISTS" ]; then
        echo -e "${RED}Error: Username '$USERNAME' not found${NC}"
        return
    fi
    
    # Get public key for removal from WireGuard config
    PUBLIC_KEY=$(sqlite3 "$DB_PATH" "SELECT public_key FROM users WHERE username='$USERNAME';")
    
    # Confirm removal
    echo ""
    echo -e "${YELLOW}Are you sure you want to remove user '$USERNAME'? (yes/no)${NC}"
    read -r CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo -e "${BLUE}Removal cancelled${NC}"
        return
    fi
    
    echo -e "${YELLOW}Removing peer...${NC}"
    
    # Remove from database
    sqlite3 "$DB_PATH" "DELETE FROM users WHERE username='$USERNAME';"
    echo -e "${GREEN}✓ Removed from database${NC}"
    
    # Remove from WireGuard config
    if [ -f "$WG_CONFIG" ]; then
        # Create temp file without the peer
        sed -i.bak "/# Client: $USERNAME/,/^$/d" "$WG_CONFIG"
        echo -e "${GREEN}✓ Removed from WireGuard config${NC}"
    fi
    
    # Remove client config files
    if [ -f "$CLIENT_DIR/${USERNAME}.conf" ]; then
        rm -f "$CLIENT_DIR/${USERNAME}.conf"
        rm -f "$CLIENT_DIR/${USERNAME}.png"
        echo -e "${GREEN}✓ Removed client config files${NC}"
    fi
    
    # Restart WireGuard
    if docker ps | grep -q wireguard; then
        docker restart wireguard > /dev/null 2>&1
        echo -e "${GREEN}✓ WireGuard container restarted${NC}"
    else
        if command -v wg &> /dev/null; then
            wg syncconf wg0 <(wg-quick strip wg0) 2>/dev/null || true
            echo -e "${GREEN}✓ WireGuard config reloaded${NC}"
        fi
    fi
    
    echo ""
    echo -e "${GREEN}Peer '$USERNAME' removed successfully${NC}"
    echo ""
}

# Function to search user
search_user() {
    echo ""
    echo -e "${YELLOW}Enter username or device ID to search:${NC}"
    read -r SEARCH_TERM
    
    if [ -z "$SEARCH_TERM" ]; then
        echo -e "${RED}Error: Search term cannot be empty${NC}"
        return
    fi
    
    print_header "SEARCH RESULTS"
    
    sqlite3 "$DB_PATH" << EOF
.mode line
SELECT 
    'ID: ' || id,
    'Username: ' || username,
    'Device ID: ' || device_id,
    'Public Key: ' || SUBSTR(public_key, 1, 40) || '...',
    'Peer IP: ' || peer_ip,
    'Created At: ' || created_at,
    'Last Seen: ' || COALESCE(last_seen, 'Never')
FROM users
WHERE username LIKE '%$SEARCH_TERM%' OR device_id LIKE '%$SEARCH_TERM%';
EOF
    
    echo ""
}

# Function to update last seen
update_last_seen() {
    echo ""
    echo -e "${YELLOW}Updating last seen timestamps from WireGuard...${NC}"
    
    if ! command -v wg &> /dev/null; then
        echo -e "${RED}Error: wg command not found${NC}"
        return
    fi
    
    # Get all peers with recent handshakes
    WG_OUTPUT=$(wg show wg0 dump 2>/dev/null | tail -n +2 || echo "")
    
    if [ -z "$WG_OUTPUT" ]; then
        echo -e "${YELLOW}No active WireGuard peers found${NC}"
        return
    fi
    
    UPDATED=0
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    
    while IFS=$'\t' read -r public_key preshared_key endpoint allowed_ips latest_handshake_seconds transfer_rx transfer_tx persistent_keepalive; do
        if [ -n "$public_key" ] && [ "$latest_handshake_seconds" != "0" ]; then
            # Update database
            sqlite3 "$DB_PATH" "UPDATE users SET last_seen='$CURRENT_TIME' WHERE public_key='$public_key';"
            USERNAME=$(sqlite3 "$DB_PATH" "SELECT username FROM users WHERE public_key='$public_key';" || echo "Unknown")
            
            if [ -n "$USERNAME" ] && [ "$USERNAME" != "Unknown" ]; then
                echo -e "${GREEN}✓ Updated: $USERNAME${NC}"
                UPDATED=$((UPDATED + 1))
            fi
        fi
    done <<< "$WG_OUTPUT"
    
    echo ""
    echo -e "${GREEN}Updated $UPDATED peer(s)${NC}"
    echo ""
}

# Function to export users to CSV
export_to_csv() {
    OUTPUT_FILE="/tmp/wireguard_users_$(date +%Y%m%d_%H%M%S).csv"
    
    print_header "EXPORT TO CSV"
    
    sqlite3 -header -csv "$DB_PATH" "SELECT * FROM users;" > "$OUTPUT_FILE"
    
    echo -e "${GREEN}Exported to: $OUTPUT_FILE${NC}"
    echo ""
    echo "File contents:"
    head -n 5 "$OUTPUT_FILE"
    
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE")
    if [ "$TOTAL_LINES" -gt 6 ]; then
        echo "..."
        echo -e "${BLUE}(showing first 5 rows, total: $((TOTAL_LINES - 1)) users)${NC}"
    fi
    
    echo ""
}

# Function to show database statistics
show_statistics() {
    print_header "DATABASE STATISTICS"
    
    TOTAL_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;")
    ACTIVE_USERS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE last_seen IS NOT NULL;")
    NEVER_CONNECTED=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE last_seen IS NULL;")
    
    echo -e "${CYAN}Total users:${NC}          $TOTAL_USERS"
    echo -e "${GREEN}Active users:${NC}         $ACTIVE_USERS"
    echo -e "${YELLOW}Never connected:${NC}      $NEVER_CONNECTED"
    
    echo ""
    echo -e "${CYAN}Recent activity (last 24 hours):${NC}"
    
    YESTERDAY=$(date -d '24 hours ago' '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -v -24H '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
    RECENT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users WHERE last_seen > '$YESTERDAY';")
    
    echo -e "  Active in last 24h: ${GREEN}$RECENT${NC}"
    
    echo ""
    echo -e "${CYAN}IP allocation:${NC}"
    FIRST_IP=$(sqlite3 "$DB_PATH" "SELECT peer_ip FROM users ORDER BY peer_ip ASC LIMIT 1;" || echo "None")
    LAST_IP=$(sqlite3 "$DB_PATH" "SELECT peer_ip FROM users ORDER BY peer_ip DESC LIMIT 1;" || echo "None")
    
    echo "  First IP:  $FIRST_IP"
    echo "  Last IP:   $LAST_IP"
    echo "  Available: $(( 253 - TOTAL_USERS )) IPs (10.13.13.2 - 10.13.13.254)"
    
    echo ""
}

# Main menu
main_menu() {
    while true; do
        echo ""
        echo -e "${MAGENTA}╔════════════════════════════════════════╗"
        echo "║   WireGuard User Management Menu      ║"
        echo -e "╚════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}1.${NC} List all peers"
        echo -e "${CYAN}2.${NC} Show active connections"
        echo -e "${CYAN}3.${NC} Remove peer"
        echo -e "${CYAN}4.${NC} Search user"
        echo -e "${CYAN}5.${NC} Update last seen timestamps"
        echo -e "${CYAN}6.${NC} Export users to CSV"
        echo -e "${CYAN}7.${NC} Show database statistics"
        echo -e "${CYAN}8.${NC} Exit"
        echo ""
        echo -e "${YELLOW}Enter your choice (1-8):${NC}"
        read -r CHOICE
        
        case $CHOICE in
            1)
                list_all_peers
                ;;
            2)
                show_active_connections
                ;;
            3)
                remove_peer
                ;;
            4)
                search_user
                ;;
            5)
                update_last_seen
                ;;
            6)
                export_to_csv
                ;;
            7)
                show_statistics
                ;;
            8)
                echo ""
                echo -e "${GREEN}Goodbye!${NC}"
                echo ""
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-8.${NC}"
                ;;
        esac
        
        echo -e "${BLUE}Press Enter to continue...${NC}"
        read -r
    done
}

# Run main menu
main_menu
