#!/bin/bash

# Raspberry Pi Zero W Setup Script
# - Installs Tailscale
# - Configures Raspberry Pi 12MP Camera for streaming

set -e  # Exit on error

# Create lock file to prevent re-running
LOCK_FILE="/var/lib/rpi-setup-complete"
if [ -f "$LOCK_FILE" ]; then
    echo "Setup already completed. Remove $LOCK_FILE to run again."
    exit 0
fi

echo "========================================="
echo "Raspberry Pi Zero W Setup Script"
echo "========================================="
echo ""

# Log output to file
exec 1> >(tee -a /var/log/rpi-setup.log)
exec 2>&1

echo "Started at: $(date)"

# Update system first
echo "[1/5] Updating system packages..."
sudo apt-get update -y && sudo apt-get upgrade -y

# Install Tailscale
echo ""
echo "[2/5] Installing Tailscale..."
curl -fsSL https://pkgs.tailscale.com/stable/raspbian/trixie.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/raspbian/trixie.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
sudo apt-get update -y && sudo apt-get install tailscale -y

echo "Tailscale installed successfully!"
echo "You'll need to authenticate Tailscale after this script completes."
echo "Run: sudo tailscale up"

# Install camera dependencies
echo ""
echo "[3/5] Installing camera streaming dependencies..."
sudo apt-get install -y \
    libcamera-apps \
    libcamera-dev \
    ffmpeg \
    v4l-utils

# Install mjpg-streamer for lightweight streaming
echo ""
echo "[4/5] Installing mjpg-streamer..."
sudo apt-get install -y \
    cmake \
    libjpeg-dev \
    gcc \
    g++ \
    make

# Clone and build mjpg-streamer if not already installed
if [ ! -d "/opt/mjpg-streamer" ]; then
    cd /tmp
    git clone https://github.com/jacksonliam/mjpg-streamer.git
    cd mjpg-streamer/mjpg-streamer-experimental
    make
    sudo make install
    sudo mkdir -p /opt/mjpg-streamer
    sudo cp -r . /opt/mjpg-streamer/
    cd ~
fi

# Create camera streaming service
echo ""
echo "[5/5] Creating camera streaming service..."

sudo tee /etc/systemd/system/camera-stream.service > /dev/null <<'EOF'
[Unit]
Description=Camera Streaming Service
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/mjpg-streamer
ExecStart=/usr/bin/libcamera-vid -t 0 --width 1920 --height 1080 --framerate 30 -o - | /usr/local/bin/mjpg_streamer -i "input_stdin.so" -o "output_http.so -w ./www -p 8080"
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable camera-stream.service

echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""

# Create lock file to prevent re-running
sudo touch "$LOCK_FILE"
echo "Setup completed at: $(date)" | sudo tee -a "$LOCK_FILE"

echo "Next steps:"
echo "1. Authenticate Tailscale:"
echo "   sudo tailscale up"
echo ""
echo "2. Start the camera stream:"
echo "   sudo systemctl start camera-stream"
echo ""
echo "3. Check camera stream status:"
echo "   sudo systemctl status camera-stream"
echo ""
echo "4. Access the camera stream at:"
echo "   http://<raspberry-pi-ip>:8080"
echo "   or via Tailscale: http://<tailscale-ip>:8080"
echo ""
echo "Optional: Test camera manually with:"
echo "   libcamera-hello --list-cameras"
echo "   libcamera-vid -t 10000 --width 1920 --height 1080 -o test.h264"
echo ""
echo "========================================="

# Reboot prompt
echo ""
echo "A reboot is recommended. Reboot now? (y/n)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    sudo reboot
fi