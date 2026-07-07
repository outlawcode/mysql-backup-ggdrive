#!/bin/bash
# Script to install mygdrive-backup via curl

echo "Installing mygdrive-backup..."

GITHUB_RAW_URL="https://raw.githubusercontent.com/outlawcode/mysql-backup-ggdrive/main/backup.sh"

if ! command -v rclone &> /dev/null; then
    echo "Rclone is not installed. Downloading and installing rclone..."
    curl https://rclone.org/install.sh | sudo bash
    if [ $? -eq 0 ]; then
        echo "[OK] Rclone installed successfully."
    else
        echo "[ERROR] Failed to install rclone. Please install it manually."
        exit 1
    fi
else
    echo "[OK] Rclone is already installed."
fi

echo "Downloading mygdrive-backup source code from GitHub..."
sudo curl -sL "$GITHUB_RAW_URL" -o /usr/local/bin/mygdrive-backup

if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to download source code from $GITHUB_RAW_URL. Please verify the URL."
    exit 1
fi

sudo chmod +x /usr/local/bin/mygdrive-backup

echo "=================================================="
echo "[OK] Installation completed successfully!"
echo "You can now use the command: mygdrive-backup"
echo "Just run 'mygdrive-backup' and the tool will guide you through the setup!"
echo "=================================================="
