#!/bin/bash
# Script to install mygdrive-backup via curl

echo "Installing mygdrive-backup..."

GITHUB_RAW_URL="https://raw.githubusercontent.com/outlawcode/mysql-backup-ggdrive/main/backup.sh"

if ! command -v rclone &> /dev/null; then
    echo "Rclone is not installed. Downloading and installing rclone..."
    curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
    unzip -q rclone-current-linux-amd64.zip
    cd rclone-*-linux-amd64
    sudo cp rclone /usr/bin/
    sudo chown root:root /usr/bin/rclone
    sudo chmod 755 /usr/bin/rclone
    cd ..
    rm -rf rclone-*-linux-amd64*
    echo "[OK] Rclone installed successfully."
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
echo "Please run 'rclone config' to connect to Google Drive before using the tool."
echo "=================================================="
