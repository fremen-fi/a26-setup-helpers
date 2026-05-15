#!/bin/bash

set -euo pipefail

echo "=== AirCore A26 Station Deploy ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo cp "$SCRIPT_DIR/radio" /etc/logrotate.d/radio

sudo mkdir -p /var/log/radio-10
sudo touch /var/log/radio-10/radio-10.log
sudo chown -R 1001:1001 /var/log/radio-10

sudo groupadd -r aircore-edge 2>/dev/null || true
sudo useradd -r -g aircore-edge -s /usr/sbin/nologin -M -d /var/cache/aircore-edge aircore-edge 2>/dev/null || true

sudo mkdir -p /var/lib/aircore-edge /tmp/aircore-edge
sudo chown aircore-edge:aircore-edge /var/lib/aircore-edge /tmp/aircore-edge

while true; do
    printf "What was the username you chose to be the owner of the HLS directory?: "
    read -r username
    printf "user: $username. Correct? (Y/N) "
    read -r confirm_username
    [[ "$confirm_username" =~ ^[yY]$ ]] && break
done

while true; do
    printf "GitHub username: "
    read -r git_user
    printf "GitHub repo name (without slashes): "
    read -r git_repo_name
    printf "user: $git_user, repo: $git_repo_name. Correct? (Y/N) "
    read -r confirm
    [[ "$confirm" =~ ^[yY]$ ]] && break
done

while true; do
    printf "GitHub PAT: "
    read -r -s git_pat
    echo ""
    [[ -n "$git_pat" ]] && break
    echo "PAT cannot be empty."
done

RADIO_IMAGE="ghcr.io/$git_user/$git_repo_name:latest"
export RADIO_IMAGE

echo "Logging in to ghcr.io..."
echo "$git_pat" | docker login ghcr.io -u "$git_user" --password-stdin

echo "Pulling image..."
docker pull "$RADIO_IMAGE"

echo "Starting container..."
docker compose -f "$SCRIPT_DIR/compose.yml" up -d

echo ""
echo "--- Deploy complete ---"
docker compose -f "$SCRIPT_DIR/compose.yml" ps

echo ""
echo "--- Pulling utility scripts ---"

get_asset_url() {
  local name=$1
  local response
  response=$(curl -sS -H "Authorization: token $git_pat" \
    "https://api.github.com/repos/$git_user/$git_repo_name/releases?per_page=50")
  if ! echo "$response" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "ERROR: GitHub API did not return a releases array. Response:" >&2
    echo "$response" >&2
    return 1
  fi
  echo "$response" | jq -r "[.[] | .assets[]? | select(.name==\"$name\")][0].url"
}

download_asset() {
  local name=$1
  local dest=$2
  local url
  url=$(get_asset_url "$name")
  if [[ -z "$url" || "$url" == "null" ]]; then
    echo "ERROR: could not resolve asset URL for '$name'" >&2
    return 1
  fi
  local tmp
  tmp=$(sudo mktemp "${dest}.XXXXXX")
  sudo curl -fsSL -H "Authorization: token $git_pat" \
    -H "Accept: application/octet-stream" \
    "$url" -o "$tmp"
  sudo chmod +x "$tmp"
  sudo mv -f "$tmp" "$dest"
}

echo "Testing asset resolution..."
url=$(get_asset_url "newsweather")
echo "Resolved URL: $url"

download_asset "archiver"    /usr/local/bin/archiver

echo "--- downloading audio_bridge ---"
sudo curl -fsSL \
    "https://frm-sw-storage.s3.rbx.io.cloud.ovh.net/ac-edge/audio_bridge" \
    -o /usr/local/bin/audio_bridge
sudo chmod +x /usr/local/bin/audio_bridge

echo "--- installing systemd units ---"
sudo cp "$SCRIPT_DIR/../aircore-edge-bridge.service" /etc/systemd/system/aircore-edge-bridge.service
sudo systemctl daemon-reload

echo "--- writing crontab ---"
crontab -u $username ~/a26-setup-helpers/crontab

echo "--- starting systemd services ---"
sudo systemctl enable a26-archiver --now
sudo systemctl restart a26-archiver
sudo systemctl enable aircore-edge-bridge --now
sudo systemctl restart aircore-edge-bridge
