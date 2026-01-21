#!/bin/bash

################################################################################
# ZTNA Backup Script
# Description: Automated backup of ZTNA infrastructure components
# Usage: sudo ./backup_ztna.sh
# Cron: 0 2 * * * /path/to/backup_ztna.sh
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BACKUP_DIR="${BACKUP_DIR:-/var/lib/ztna/backups}"
DB_PATH="${DB_PATH:-/var/lib/ztna/users.db}"
WG_CONFIG_DIR="/etc/wireguard"
CF_CONFIG_DIR="/etc/cloudflare"
CLIENT_DIR="/var/lib/ztna/clients"
RETENTION_DAYS=30  # Keep backups for 30 days

# Timestamp for backup file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="ztna-backup-${TIMESTAMP}"
TEMP_DIR="/tmp/${BACKUP_NAME}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

echo -e "${BLUE}========================================"
echo "ZTNA Backup Script"
echo "======================================${NC}"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Create temp directory
mkdir -p "$TEMP_DIR"
echo -e "${YELLOW}Creating backup: ${BACKUP_NAME}${NC}"

# Function to backup with error handling
backup_item() {
    local source="$1"
    local dest="$2"
    local description="$3"
    
    if [ -e "$source" ]; then
        mkdir -p "$(dirname "$TEMP_DIR/$dest")"
        cp -r "$source" "$TEMP_DIR/$dest" 2>/dev/null || {
            echo -e "${YELLOW}Warning: Could not backup $description${NC}"
            return 1
        }
        echo -e "${GREEN}✓${NC} Backed up: $description"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} Skipped (not found): $description"
        return 1
    fi
}

# Backup SQLite database
echo ""
echo -e "${BLUE}Backing up database...${NC}"
if [ -f "$DB_PATH" ]; then
    mkdir -p "$TEMP_DIR/var/lib/ztna"
    sqlite3 "$DB_PATH" ".backup '$TEMP_DIR/var/lib/ztna/users.db'" 2>/dev/null || {
        cp "$DB_PATH" "$TEMP_DIR/var/lib/ztna/users.db"
    }
    echo -e "${GREEN}✓${NC} Database backed up"
    
    # Export to SQL for easy restoration
    sqlite3 "$DB_PATH" .dump > "$TEMP_DIR/var/lib/ztna/users.sql"
    echo -e "${GREEN}✓${NC} Database dumped to SQL"
else
    echo -e "${YELLOW}⚠${NC} Database not found: $DB_PATH"
fi

# Backup WireGuard configuration
echo ""
echo -e "${BLUE}Backing up WireGuard configuration...${NC}"
backup_item "$WG_CONFIG_DIR/wg0.conf" "etc/wireguard/wg0.conf" "WireGuard config"
backup_item "$WG_CONFIG_DIR/server_private.key" "etc/wireguard/server_private.key" "WireGuard server private key"
backup_item "$WG_CONFIG_DIR/server_public.key" "etc/wireguard/server_public.key" "WireGuard server public key"

# Backup client configurations
echo ""
echo -e "${BLUE}Backing up client configurations...${NC}"
if [ -d "$CLIENT_DIR" ] && [ "$(ls -A $CLIENT_DIR 2>/dev/null)" ]; then
    mkdir -p "$TEMP_DIR/var/lib/ztna/clients"
    cp -r "$CLIENT_DIR"/* "$TEMP_DIR/var/lib/ztna/clients/" 2>/dev/null
    CLIENT_COUNT=$(ls -1 "$CLIENT_DIR"/*.conf 2>/dev/null | wc -l)
    echo -e "${GREEN}✓${NC} Backed up $CLIENT_COUNT client configs"
else
    echo -e "${YELLOW}⚠${NC} No client configs found"
fi

# Backup Cloudflare configuration
echo ""
echo -e "${BLUE}Backing up Cloudflare configuration...${NC}"
if [ -d "$CF_CONFIG_DIR" ] && [ "$(ls -A $CF_CONFIG_DIR 2>/dev/null)" ]; then
    mkdir -p "$TEMP_DIR/etc/cloudflare"
    cp -r "$CF_CONFIG_DIR"/* "$TEMP_DIR/etc/cloudflare/" 2>/dev/null
    echo -e "${GREEN}✓${NC} Cloudflare config backed up"
else
    echo -e "${YELLOW}⚠${NC} No Cloudflare config found"
fi

# Backup Docker Compose file
echo ""
echo -e "${BLUE}Backing up Docker configuration...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
backup_item "$SCRIPT_DIR/docker-compose-ztna.yml" "docker-compose-ztna.yml" "Docker Compose file"

# Backup environment configuration
backup_item "$SCRIPT_DIR/workstation.env" "workstation.env" "Environment configuration"

# Backup management scripts
echo ""
echo -e "${BLUE}Backing up management scripts...${NC}"
backup_item "$SCRIPT_DIR/add_wg_peer.sh" "add_wg_peer.sh" "WireGuard provisioning script"
backup_item "$SCRIPT_DIR/query_users.sh" "query_users.sh" "User query script"
backup_item "$SCRIPT_DIR/backup_ztna.sh" "backup_ztna.sh" "Backup script"

# Create backup metadata
echo ""
echo -e "${BLUE}Creating backup metadata...${NC}"
cat > "$TEMP_DIR/backup_info.txt" << EOF
ZTNA Backup Information
=======================
Backup Name: ${BACKUP_NAME}
Backup Date: $(date '+%Y-%m-%d %H:%M:%S')
Hostname: $(hostname)
VPS IP: $(hostname -I | awk '{print $1}')

Components Backed Up:
- SQLite Database: $([ -f "$TEMP_DIR/var/lib/ztna/users.db" ] && echo "Yes" || echo "No")
- WireGuard Config: $([ -f "$TEMP_DIR/etc/wireguard/wg0.conf" ] && echo "Yes" || echo "No")
- Client Configs: $(ls -1 "$TEMP_DIR/var/lib/ztna/clients"/*.conf 2>/dev/null | wc -l) files
- Cloudflare Config: $([ -d "$TEMP_DIR/etc/cloudflare" ] && echo "Yes" || echo "No")
- Docker Compose: $([ -f "$TEMP_DIR/docker-compose-ztna.yml" ] && echo "Yes" || echo "No")
- Environment File: $([ -f "$TEMP_DIR/workstation.env" ] && echo "Yes" || echo "No")

System Information:
- OS: $(lsb_release -d 2>/dev/null | cut -f2 || uname -s)
- Kernel: $(uname -r)
- Docker Version: $(docker --version 2>/dev/null || echo "Not installed")

User Statistics:
$(sqlite3 "$DB_PATH" "SELECT COUNT(*) || ' total users' FROM users;" 2>/dev/null || echo "Database not accessible")
$(sqlite3 "$DB_PATH" "SELECT COUNT(*) || ' active users (connected at least once)' FROM users WHERE last_seen IS NOT NULL;" 2>/dev/null || echo "")

Restoration Instructions:
1. Extract backup: tar -xzf ${BACKUP_NAME}.tar.gz
2. Stop services: docker-compose -f docker-compose-ztna.yml down
3. Restore database: cp backup/var/lib/ztna/users.db /var/lib/ztna/
4. Restore configs: cp -r backup/etc/wireguard/* /etc/wireguard/
5. Restart services: docker-compose -f docker-compose-ztna.yml up -d
EOF

echo -e "${GREEN}✓${NC} Metadata created"

# Create compressed archive
echo ""
echo -e "${BLUE}Compressing backup...${NC}"
mkdir -p "$BACKUP_DIR"
cd /tmp
tar -czf "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}/" 2>/dev/null

if [ $? -eq 0 ]; then
    BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | cut -f1)
    echo -e "${GREEN}✓${NC} Backup compressed: ${BACKUP_SIZE}"
    
    # Calculate checksum
    CHECKSUM=$(sha256sum "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" | awk '{print $1}')
    echo "$CHECKSUM  ${BACKUP_NAME}.tar.gz" > "${BACKUP_DIR}/${BACKUP_NAME}.sha256"
    echo -e "${GREEN}✓${NC} Checksum: ${CHECKSUM:0:16}..."
else
    echo -e "${RED}✗${NC} Failed to compress backup"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# Cleanup temp directory
rm -rf "$TEMP_DIR"
echo -e "${GREEN}✓${NC} Temporary files cleaned up"

# Remove old backups
echo ""
echo -e "${BLUE}Cleaning old backups (retention: ${RETENTION_DAYS} days)...${NC}"
OLD_BACKUPS=$(find "$BACKUP_DIR" -name "ztna-backup-*.tar.gz" -mtime +${RETENTION_DAYS} 2>/dev/null)
OLD_COUNT=0

if [ -n "$OLD_BACKUPS" ]; then
    while IFS= read -r backup_file; do
        rm -f "$backup_file"
        rm -f "${backup_file%.tar.gz}.sha256"
        OLD_COUNT=$((OLD_COUNT + 1))
        echo -e "${YELLOW}✓${NC} Removed: $(basename "$backup_file")"
    done <<< "$OLD_BACKUPS"
    echo -e "${GREEN}Removed $OLD_COUNT old backup(s)${NC}"
else
    echo -e "${GREEN}No old backups to remove${NC}"
fi

# Display backup summary
echo ""
echo -e "${BLUE}========================================"
echo "Backup Summary"
echo -e "========================================${NC}"
echo -e "Backup file: ${GREEN}${BACKUP_DIR}/${BACKUP_NAME}.tar.gz${NC}"
echo -e "Backup size: ${GREEN}${BACKUP_SIZE}${NC}"
echo -e "Checksum:    ${GREEN}${CHECKSUM:0:32}...${NC}"
echo ""

# List all backups
BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/ztna-backup-*.tar.gz 2>/dev/null | wc -l)
echo -e "Total backups in ${BACKUP_DIR}: ${GREEN}${BACKUP_COUNT}${NC}"

if [ "$BACKUP_COUNT" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Recent backups:${NC}"
    ls -lht "$BACKUP_DIR"/ztna-backup-*.tar.gz 2>/dev/null | head -5 | awk '{print "  " $9 "  (" $5 ", " $6 " " $7 " " $8 ")"}'
fi

echo ""
echo -e "${GREEN}========================================"
echo "Backup completed successfully!"
echo -e "========================================${NC}"

# Optional: Remote backup sync
# Uncomment and configure one of these methods:

# Option 1: rsync to remote server
# echo ""
# echo -e "${BLUE}Syncing to remote server...${NC}"
# rsync -avz --delete "$BACKUP_DIR/" user@backup-server:/backups/vps-ztna/
# echo -e "${GREEN}✓${NC} Remote sync completed"

# Option 2: rclone to cloud storage (S3, Backblaze B2, Cloudflare R2)
# echo ""
# echo -e "${BLUE}Uploading to cloud storage...${NC}"
# rclone sync "$BACKUP_DIR/" remote:vps-ztna-backups/
# echo -e "${GREEN}✓${NC} Cloud upload completed"

# Option 3: scp to specific server
# echo ""
# echo -e "${BLUE}Copying to backup server...${NC}"
# scp "${BACKUP_DIR}/${BACKUP_NAME}.tar.gz" user@backup-server:/backups/
# echo -e "${GREEN}✓${NC} Backup copied to remote server"

exit 0
