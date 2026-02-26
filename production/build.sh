#!/bin/bash

set -e

CORES=$(nproc)

echo "=== AirCore A26 Host Installer ==="
echo "Using $CORES cores."
echo ""
echo "WARNING: The server will reboot after this installer completes."
printf "Do you accept that the server will restart after this? (Y/N) "
read -r confirm_reboot
if [[ "$confirm_reboot" =~ ^[yY]$ ]]; then
    auto_shutdown=true
else
    auto_shutdown=false
    echo "No automatic reboot. You MUST reboot manually before starting the station."
fi

echo ""

# HLS directory owner
while true; do
    printf "Username of the HLS directory owner: "
    read -r HLS_OWNER
    printf "HLS owner: $HLS_OWNER. Correct? (Y/N) "
    read -r confirm
    [[ "$confirm" =~ ^[yY]$ ]] && break
done

printf "HLS access token (shared with CDN): "
read -r -s hls_token
echo ""

# CIFS credentials
while true; do
    printf "CIFS username: "
    read -r cifs_user
    printf "CIFS password: "
    read -r -s cifs_password
    echo ""
    printf "CIFS HOST NAME (e.g. u490804.your-storagebox.de): "
    read -r cifs_server
    printf "user: $cifs_user, server: $cifs_server. Correct? (Y/N) "
    read -r cifs_confirm
    [[ "$cifs_confirm" =~ ^[yY]$ ]] && break
done

# GitHub credentials
while true; do
    printf "GitHub username: "
    read -r git_user
    printf "GitHub PAT: "
    read -r -s git_pat
    echo ""
    printf "GitHub user: $git_user. Correct? (Y/N) "
    read -r git_confirm
    [[ "$git_confirm" =~ ^[yY]$ ]] && break
done

echo "$git_pat" | sudo tee -a /etc/environment

echo ""
echo "--- Starting installation ---"

# apt
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-v2 cifs-utils apache2

# HLS directory
sudo mkdir -p /var/www/hls
sudo chown -R 1001:1001 /var/www/hls
sudo touch /var/www/hls/.keep

# Audio log directory
sudo mkdir -p /opt/archive
sudo chown -R 1001:1001 /opt/archive
sudo touch /opt/archive/.keep

# Apache config
sudo cp 000-default.conf /etc/apache2/sites-available/000-default.conf
sudo systemctl reload apache2

# systemd
sudo cp a26-archiver.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable a26-archiver --now

# write to apache envvars
echo "export HLS_TOKEN=$hls_token" | sudo tee -a /etc/apache2/envvars > /dev/null
sudo systemctl reload apache2

# CIFS credentials file
printf "username=%s\npassword=%s\n" "$cifs_user" "$cifs_password" \
    | sudo tee /etc/cifs-credentials > /dev/null
sudo chmod 600 /etc/cifs-credentials

# fstab mounts
sudo mkdir -p /radio /radio-util

FSTAB_RADIO="//${cifs_server}/backup/radio /radio cifs credentials=/etc/cifs-credentials,ro,uid=${HLS_OWNER},gid=${HLS_OWNER},_netdev 0 0"
FSTAB_UTIL="//${cifs_server}/backup /radio-util cifs credentials=/etc/cifs-credentials,ro,uid=${HLS_OWNER},gid=${HLS_OWNER},_netdev 0 0"

grep -q "/radio cifs" /etc/fstab || echo "$FSTAB_RADIO" | sudo tee -a /etc/fstab > /dev/null
grep -q "/radio-util cifs" /etc/fstab || echo "$FSTAB_UTIL" | sudo tee -a /etc/fstab > /dev/null

sudo systemctl daemon-reload
sudo mount /radio
sudo mount /radio-util

sudo usermod -aG docker liq-user

sudo touch /var/log/radio-10.log
sudo chown liq-user:liq-user /var/log/radio-10.log

# Docker login
echo "$git_pat" | docker login ghcr.io -u "$git_user" --password-stdin

echo ""
echo "--- Installation complete ---"

if [ "$auto_shutdown" = true ]; then
    echo "Rebooting in 5 seconds..."
    sleep 5
    sudo reboot
fi
