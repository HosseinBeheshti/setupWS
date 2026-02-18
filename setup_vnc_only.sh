#!/bin/bash

# Exit on any error
set -e

# --- Colors ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- Helper Functions ---
print_message() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Load Configuration ---
print_message "Loading configuration from workstation.env..."
ENV_FILE="./workstation.env"
if [[ ! -f "$ENV_FILE" ]]; then
    print_error "Configuration file not found: $ENV_FILE"
    exit 1
fi
source "$ENV_FILE"
print_message "Configuration loaded successfully."

# --- Check if running as root ---
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

# --- VNC User Setup Function ---
setup_vnc_user() {
    local USERNAME=$1
    local PASSWORD=$2
    local DISPLAY_NUM=$3
    local RESOLUTION=$4
    local PORT=$5

    print_message "--- Setting up VNC for user '$USERNAME' on port $PORT (display :$DISPLAY_NUM) ---"

    # 1. Create user if not exists
    if ! id "$USERNAME" &>/dev/null; then
        useradd -m -s /bin/bash "$USERNAME"
        print_message "User '$USERNAME' created."
    fi
    printf '%s:%s\n' "$USERNAME" "$PASSWORD" | chpasswd
    usermod -aG sudo "$USERNAME"
    print_message "User '$USERNAME' configured with password and sudo privileges."

    # 2. Configure VNC for the user
    sudo -u "$USERNAME" bash <<EOFSU
mkdir -p ~/.vnc
printf '%s' '$PASSWORD' | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd

cat > ~/.vnc/xstartup << 'XSTART'
#!/bin/sh
# This script is executed by the VNC server when a desktop session starts.
# It launches the XFCE desktop environment.
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
[ -r \\\$HOME/.Xresources ] && xrdb \\\$HOME/.Xresources
exec startxfce4
XSTART

chmod +x ~/.vnc/xstartup

# --- VNC Initialization ---
# Forcefully kill any existing VNC server for this display to ensure a clean state.
vncserver -kill :$DISPLAY_NUM >/dev/null 2>&1 || true
sleep 1

# Initialize the VNC server once to create necessary files.
vncserver -rfbport $PORT :$DISPLAY_NUM

# Wait a moment for the server to create its PID file before killing it.
sleep 2

# Kill the temporary server. The systemd service will manage the permanent one.
vncserver -kill :$DISPLAY_NUM >/dev/null 2>&1 || true
EOFSU
    print_message "VNC configured for user '$USERNAME'."

    # 3. Create systemd service file for the user
    print_message "Creating systemd service for '$USERNAME'..."
    cat > /etc/systemd/system/vncserver-$USERNAME@.service << EOF
[Unit]
Description=TigerVNC server for user $USERNAME
After=syslog.target network.target

[Service]
Type=simple
User=$USERNAME
Group=$USERNAME
WorkingDirectory=/home/$USERNAME

ExecStartPre=-/usr/bin/vncserver -kill :%i > /dev/null 2>&1
ExecStart=/usr/bin/vncserver -fg -depth 24 -geometry $RESOLUTION -localhost no -rfbport $PORT :%i
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # 4. Enable and start the service
    systemctl daemon-reload
    systemctl enable vncserver-$USERNAME@$DISPLAY_NUM.service
    systemctl restart vncserver-$USERNAME@$DISPLAY_NUM.service
    print_message "VNC service for '$USERNAME' enabled and started."

    # Add a check to see if the service is active
    sleep 3 # Give the service a moment to stabilize
    if ! systemctl is-active --quiet vncserver-$USERNAME@$DISPLAY_NUM.service; then
        print_error "VNC service for '$USERNAME' failed to start. Please check the logs with:"
        echo "journalctl -xeu vncserver-$USERNAME@$DISPLAY_NUM.service"
        exit 1
    fi
}

# --- Main Script ---

print_message "=== Starting VNC Server Setup ==="

# Note: Required packages are installed by setup_ws.sh
# Note: Firewall rules are configured by setup_ws.sh

# Parse VNC users and setup each user
print_message "Setting up VNC users from configuration..."
if [[ -z "$VNC_USER_COUNT" ]]; then
    print_error "VNC_USER_COUNT not defined in $ENV_FILE"
    exit 1
fi

# Loop through each user based on VNC_USER_COUNT
for ((i=1; i<=VNC_USER_COUNT; i++)); do
    # Get user variables dynamically
    username_var="VNCUSER${i}_USERNAME"
    password_var="VNCUSER${i}_PASSWORD"
    display_var="VNCUSER${i}_DISPLAY"
    resolution_var="VNCUSER${i}_RESOLUTION"
    port_var="VNCUSER${i}_PORT"
    
    username="${!username_var}"
    password="${!password_var}"
    display="${!display_var}"
    resolution="${!resolution_var}"
    port="${!port_var}"
    
    if [[ -z "$username" || -z "$password" || -z "$display" || -z "$resolution" || -z "$port" ]]; then
        print_warning "Skipping user $i: incomplete configuration"
        continue
    fi
    
    setup_vnc_user "$username" "$password" "$display" "$resolution" "$port"
done

# --- Add VNC users to docker group if Docker is installed ---
if command -v docker &> /dev/null; then
    print_message "Adding VNC users to docker group..."
    for ((i=1; i<=VNC_USER_COUNT; i++)); do
        username_var="VNCUSER${i}_USERNAME"
        username="${!username_var}"
        if [[ -n "$username" ]]; then
            usermod -aG docker "$username" 2>/dev/null || true
            print_message "  Added $username to docker group"
        fi
    done
fi

# Final Information
IP_ADDRESS="$VPS_PUBLIC_IP"
print_message "=== VNC Server Setup Complete ==="
echo -e "-----------------------------------------------------"
echo -e "${YELLOW}VNC User Connection Details:${NC}"
echo ""

for ((i=1; i<=VNC_USER_COUNT; i++)); do
    username_var="VNCUSER${i}_USERNAME"
    password_var="VNCUSER${i}_PASSWORD"
    display_var="VNCUSER${i}_DISPLAY"
    resolution_var="VNCUSER${i}_RESOLUTION"
    port_var="VNCUSER${i}_PORT"
    
    username="${!username_var}"
    password="${!password_var}"
    display="${!display_var}"
    resolution="${!resolution_var}"
    port="${!port_var}"
    
    if [[ -n "$username" ]]; then
        echo -e "  ${GREEN}User:${NC}       $username"
        echo -e "  ${GREEN}Password:${NC}   $password"
        echo -e "  ${GREEN}Address:${NC}    $IP_ADDRESS:$port (Display :$display)"
        echo -e "  ${GREEN}Resolution:${NC} $resolution"
        echo ""
    fi
done

echo -e "-----------------------------------------------------"
echo -e "To check service status for a user, run:"
echo -e "  systemctl status vncserver-<username>@<display>.service"
echo -e "-----------------------------------------------------"

exit 0
