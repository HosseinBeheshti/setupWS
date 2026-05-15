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
    # Enable lingering so systemd-logind creates /run/user/UID/ at boot (needed by dconf/D-Bus in VNC)
    loginctl enable-linger "$USERNAME" 2>/dev/null || true
    print_message "User '$USERNAME' configured with password and sudo privileges."

    # 2. Set VNC password (must run as user for vncpasswd)
    sudo -u "$USERNAME" bash <<EOFSU
mkdir -p ~/.vnc
printf '%s' '$PASSWORD' | vncpasswd -f > ~/.vnc/passwd
chmod 600 ~/.vnc/passwd
EOFSU

    # 3. Write crash-hardened xstartup as root (avoids nested heredoc escaping issues)
    print_message "Writing crash-hardened xstartup for '$USERNAME'..."
    mkdir -p "/home/${USERNAME}/.vnc"
    cat > "/home/${USERNAME}/.vnc/xstartup" << 'XSTART'
#!/bin/sh
# VNC xstartup — minimal, clean startup for TigerVNC + XFCE
# On crash: xstartup exits → Xtigervnc exits → systemd restarts the whole
# service cleanly. Do NOT use a restart loop inside xstartup — it accumulates
# zombie processes, leaks D-Bus sockets, and causes memory exhaustion.

# Ensure sane working directory (VNC may inherit the setup script's cwd)
cd "$HOME" || cd /tmp

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

export XDG_SESSION_TYPE=x11

# XDG_RUNTIME_DIR is required by dconf, D-Bus, PulseAudio, gvfsd.
# systemd-logind only creates it for PAM sessions; VNC needs it explicitly.
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    sudo mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null
    sudo chown "$(id -u):$(id -g)" "$XDG_RUNTIME_DIR" 2>/dev/null
    sudo chmod 0700 "$XDG_RUNTIME_DIR" 2>/dev/null
fi
# Fallback if /run/user still doesn't exist
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/tmp/xdg-runtime-$(id -u)"
    mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"
fi

# Load Xresources if present
[ -r "$HOME/.Xresources" ] && xrdb "$HOME/.Xresources"

# Start a fresh D-Bus session bus
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS

# Clear stale sessions that may restore a broken state
rm -rf "$HOME/.cache/sessions"

# Disable compositing (no GPU in VNC)
if command -v xfconf-query >/dev/null 2>&1; then
    xfconf-query -c xfwm4 -p /general/use_compositing -s false 2>/dev/null || true
fi

# Start PulseAudio if available
if command -v pulseaudio >/dev/null 2>&1; then
    pulseaudio --kill 2>/dev/null || true
    pulseaudio --start --exit-idle-time=-1 2>/dev/null || true
fi

# Launch XFCE — exec replaces this shell so PID 1 of the VNC session is
# startxfce4. When XFCE exits (crash or logout), the VNC server exits
# and systemd performs a clean restart with fresh D-Bus, fresh env, etc.
exec startxfce4
XSTART
    chmod +x "/home/${USERNAME}/.vnc/xstartup"
    chown "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.vnc/xstartup"

    # 4. Remove packages that fatally crash in VNC (no LightDM/logind/DPMS)
    print_message "Removing VNC-incompatible packages..."
    apt-get remove -y light-locker xfce4-screensaver xiccd xfce4-power-manager 2>/dev/null || true

    # 5. Pre-create autostart overrides before first session start
    print_message "Applying autostart overrides for '$USERNAME'..."
    local AUTOSTART_DIR="/home/${USERNAME}/.config/autostart"
    mkdir -p "$AUTOSTART_DIR"
    for desktop_file in light-locker xiccd xfce4-notifyd xfce4-power-manager xfce4-screensaver; do
        cat > "${AUTOSTART_DIR}/${desktop_file}.desktop" << 'EOF'
[Desktop Entry]
Hidden=true
EOF
    done
    chown -R "${USERNAME}:${USERNAME}" "$AUTOSTART_DIR"

    # 6. Pre-configure xfce4-session (disable save/restore to prevent crash loops)
    print_message "Configuring xfce4-session for '$USERNAME'..."
    local XFCE_SESSION_DIR="/home/${USERNAME}/.config/xfce4/xfconf/xfce-perchannel-xml"
    mkdir -p "$XFCE_SESSION_DIR"
    cat > "${XFCE_SESSION_DIR}/xfce4-session.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-session" version="1.0">
  <property name="general" type="empty">
    <property name="SaveOnExit" type="bool" value="false"/>
    <property name="AutoSave" type="bool" value="false"/>
  </property>
  <property name="startup" type="empty">
    <property name="use_failsafe_settings" type="bool" value="false"/>
  </property>
  <property name="compat" type="empty">
    <property name="LaunchGnomeServices" type="bool" value="false"/>
  </property>
</channel>
EOF
    chown -R "${USERNAME}:${USERNAME}" "/home/${USERNAME}/.config/xfce4"

    # 7. Create XDG_RUNTIME_DIR for this user (required by D-Bus, dconf, gvfsd)
    print_message "Creating XDG_RUNTIME_DIR for '$USERNAME'..."
    local USER_UID
    USER_UID=$(id -u "$USERNAME")
    local USER_GID
    USER_GID=$(id -g "$USERNAME")
    mkdir -p "/run/user/${USER_UID}"
    chown "${USER_UID}:${USER_GID}" "/run/user/${USER_UID}"
    chmod 0700 "/run/user/${USER_UID}"

    # 8. Clean stale X lock files and any leftover VNC processes
    print_message "Cleaning stale X lock files for display :${DISPLAY_NUM}..."
    pkill -u "${USERNAME}" -f "Xtigervnc.*:${DISPLAY_NUM}" 2>/dev/null || true
    pkill -u "${USERNAME}" -f "Xvnc.*:${DISPLAY_NUM}"      2>/dev/null || true
    pkill -u "${USERNAME}" -f "vncserver.*:${DISPLAY_NUM}"  2>/dev/null || true
    rm -f "/tmp/.X${DISPLAY_NUM}-lock"
    rm -f "/tmp/.X11-unix/X${DISPLAY_NUM}"
    sleep 1

    # 9. Initialize VNC server once to create necessary runtime files, then stop it
    sudo -u "${USERNAME}" bash <<EOFSU
vncserver -rfbport $PORT :$DISPLAY_NUM
sleep 2
vncserver -kill :$DISPLAY_NUM >/dev/null 2>&1 || true
EOFSU
    print_message "VNC configured for user '$USERNAME'."

    # 10. Create systemd service file
    print_message "Creating systemd service for '$USERNAME'..."
    cat > /etc/systemd/system/vncserver-${USERNAME}@.service << EOF
[Unit]
Description=TigerVNC server for user ${USERNAME}
After=syslog.target network.target

[Service]
Type=forking
User=${USERNAME}
Group=${USERNAME}
WorkingDirectory=/home/${USERNAME}

ExecStartPre=-/usr/bin/vncserver -kill :%i
ExecStart=/usr/bin/vncserver -depth 24 -geometry ${RESOLUTION} -localhost no -rfbport ${PORT} :%i
ExecStop=/usr/bin/vncserver -kill :%i
Restart=on-failure
RestartSec=10
TimeoutStartSec=120
KillMode=mixed
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF

    # 11. Enable and start the service
    systemctl daemon-reload
    systemctl enable vncserver-${USERNAME}@${DISPLAY_NUM}.service
    systemctl restart vncserver-${USERNAME}@${DISPLAY_NUM}.service
    print_message "VNC service for '${USERNAME}' enabled and started."

    sleep 3
    if ! systemctl is-active --quiet vncserver-${USERNAME}@${DISPLAY_NUM}.service; then
        print_error "VNC service for '${USERNAME}' failed to start. Check logs:"
        echo "journalctl -xeu vncserver-${USERNAME}@${DISPLAY_NUM}.service"
        exit 1
    fi
}

# --- Main Script ---

print_message "=== Starting VNC Server Setup ==="

# Note: Packages and firewall rules are managed by setup_ws.sh when run as part of it.
# When run standalone, ensure tigervnc-standalone-server, xfce4, xfce4-goodies,
# and dbus-x11 are already installed.

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
IP_ADDRESS="${VPS_PUBLIC_IP:-$(hostname -I | awk '{print $1}')}"
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

exit 0
