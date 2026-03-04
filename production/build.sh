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

# Grafana Cloud credentials (for Prometheus remote_write)
while true; do
    printf "Grafana Cloud remote_write username: "
    read -r grafana_user
    printf "Grafana Cloud remote_write API key: "
    read -r -s grafana_key
    echo ""
    printf "Grafana user: $grafana_user. Correct? (Y/N) "
    read -r grafana_confirm
    [[ "$grafana_confirm" =~ ^[yY]$ ]] && break
done

printf "Server label (e.g. audio-server-hel1-2): "
read -r server_label

echo "git_pat=$git_pat" | sudo tee -a /etc/environment

echo ""
echo "--- Starting installation ---"

# apt
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose-v2 cifs-utils apache2 jq

# HLS directory
sudo mkdir -p /var/www/hls
sudo touch /var/www/hls/.keep
sudo chown -R 1001:1001 /var/www/hls

# Audio log directory
sudo mkdir -p /opt/archive
sudo touch /opt/archive/.keep
sudo chown -R 1001:1001 /opt/archive

# Apache config
sudo cp 000-default.conf /etc/apache2/sites-available/000-default.conf
sudo systemctl reload apache2

# systemd
sudo cp a26-archiver.service /etc/systemd/system/
sudo systemctl daemon-reload

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

# Prometheus
PROM_VERSION="3.2.1"
PROM_ARCH="linux-amd64"
PROM_TAR="prometheus-${PROM_VERSION}.${PROM_ARCH}.tar.gz"
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/${PROM_TAR}" -O /tmp/${PROM_TAR}
tar xzf /tmp/${PROM_TAR} -C /tmp

sudo mkdir -p /opt/prometheus/rules
sudo cp /tmp/prometheus-${PROM_VERSION}.${PROM_ARCH}/prometheus /opt/prometheus/
sudo cp /tmp/prometheus-${PROM_VERSION}.${PROM_ARCH}/promtool /opt/prometheus/
rm -rf /tmp/prometheus-${PROM_VERSION}* /tmp/${PROM_TAR}

sudo useradd --system --no-create-home --shell /usr/sbin/nologin prometheus || true
sudo chown -R prometheus:prometheus /opt/prometheus

cat <<EOF | sudo tee /opt/prometheus/prometheus.yml > /dev/null
global:
  scrape_interval: 15s
rule_files:
  - "rules/lufs.yml"
remote_write:
  - url: https://prometheus-prod-39-prod-eu-north-0.grafana.net/api/prom/push
    basic_auth:
      username: "${grafana_user}"
      password: "${grafana_key}"
    write_relabel_configs:
      # Only send critical audio metrics for alerting
      - source_labels: [__name__]
        regex: 'liquidsoap_output_lufs_1h_avg|liquidsoap_output_lufs_24h_avg|liquidsoap_output_lufs_7d_avg|liquidsoap_output_lufs_3s|liquidsoap_dead_air.*|up|liquidsoap_rms_db'
        action: keep
      # Add server identification
      - target_label: server
        replacement: '${server_label}'
      - target_label: environment
        replacement: 'production'
scrape_configs:
  # Fast scraping for audio metrics (LUFS + RMS)
  - job_name: 'liquidsoap_audio'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 10s
    metric_relabel_configs:
      - source_labels: ['__name__']
        regex: 'liquidsoap_output_lufs_3s|liquidsoap_rms_db|liquidsoap_dead_air.*'
        action: keep
  # Normal scraping for other metrics
  - job_name: 'liquidsoap_other'
    static_configs:
      - targets: ['localhost:9090']
    scrape_interval: 30s
    metric_relabel_configs:
      - source_labels: ['__name__']
        regex: 'liquidsoap_output_lufs_3s|liquidsoap_rms_db|liquidsoap_dead_air.*'
        action: drop
  # Catchup metrics
  - job_name: 'liquidsoap_catchup'
    static_configs:
      - targets: ['localhost:9093']
    scrape_interval: 15s
  # Playlist position metrics
  - job_name: 'playlist_positions'
    static_configs:
      - targets: ['localhost:9094']
    scrape_interval: 15s
  # RSS feed health monitoring
  - job_name: 'feed_health'
    static_configs:
      - targets: ['localhost:9095']
    scrape_interval: 60s
  # Content validation monitoring
  - job_name: 'content_validation'
    static_configs:
      - targets: ['localhost:9096']
    scrape_interval: 30s
EOF

cat <<'RULES_EOF' | sudo tee /opt/prometheus/rules/lufs.yml > /dev/null
groups:
  - name: lufs_processing
    interval: 30s
    rules:
      # Clean LUFS metric (filters out NaN, infinite, and extreme values)
      - record: liquidsoap_output_lufs_clean
        expr: |
          liquidsoap_output_lufs_3s{job="liquidsoap_audio"}
          and on() (
            liquidsoap_output_lufs_3s{job="liquidsoap_audio"} == liquidsoap_output_lufs_3s{job="liquidsoap_audio"}
          )
          and on() (
            liquidsoap_output_lufs_3s{job="liquidsoap_audio"} > -100
          )
          and on() (
            liquidsoap_output_lufs_3s{job="liquidsoap_audio"} < 50
          )
      # 1 hour rolling average
      - record: liquidsoap_output_lufs_1h_avg
        expr: avg_over_time(liquidsoap_output_lufs_clean[1h])
      # 24 hour rolling average
      - record: liquidsoap_output_lufs_24h_avg
        expr: avg_over_time(liquidsoap_output_lufs_clean[24h])
      # 7 day rolling average for long-term trends
      - record: liquidsoap_output_lufs_7d_avg
        expr: avg_over_time(liquidsoap_output_lufs_clean[7d])
RULES_EOF

sudo chown -R prometheus:prometheus /opt/prometheus

cat <<'SERVICE_EOF' | sudo tee /etc/systemd/system/prometheus.service > /dev/null
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/opt/prometheus/prometheus \
    --config.file=/opt/prometheus/prometheus.yml \
    --storage.tsdb.path=/opt/prometheus/data \
    --storage.tsdb.retention.time=30d
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE_EOF

sudo systemctl daemon-reload
sudo systemctl enable prometheus

sudo usermod -aG docker liq-user

sudo touch /var/log/radio-10.log
sudo chown 1001:1001 /var/log/radio-10.log

# Docker login
echo "$git_pat" | docker login ghcr.io -u "$git_user" --password-stdin

echo ""
echo "--- Installation complete ---"

if [ "$auto_shutdown" = true ]; then
    echo "Rebooting in 5 seconds..."
    sleep 5
    sudo reboot
fi
