#!/bin/bash

echo "=== AirCore A26 Station Deploy ==="
echo ""

while true; do
    printf "What was the username you chose to be the owner of the HLS directory?: "
    read -r username
    printf "user: $username. Correct? (Y/N) "
    read -r confirm_username
    [[ ""$confirm_username =~ ^[yY]$ ]] && break
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Pulling image..."
docker pull "ghcr.io/$git_user/$git_repo_name:latest"

echo "Starting container..."
docker compose -f "$SCRIPT_DIR/compose.yml" up -d

echo ""
echo "--- Deploy complete ---"
docker compose -f "$SCRIPT_DIR/compose.yml" ps

echo ""
echo "--- Pulling utility scripts ---"

get_asset_url() {
  local name=$1
  curl -s -H "Authorization: token $git_pat" \
    "https://api.github.com/repos/$git_user/$git_repo_name/releases?per_page=50" \
    | jq -r "[.[] | .assets[] | select(.name==\"$name\")][0].url"
}

download_asset() {
  local name=$1
  local dest=$2
  local url
  url=$(get_asset_url "$name")
  sudo curl -sL -H "Authorization: token $git_pat" \
    -H "Accept: application/octet-stream" \
    "$url" -o "$dest"
  sudo chmod +x "$dest"
}

echo "Testing asset resolution..."
url=$(get_asset_url "newsweather")
echo "Resolved URL: $url"

download_asset "gatherer"    /usr/local/bin/gatherer
download_asset "newsweather" /usr/local/bin/newsweather
download_asset "logger"      /usr/local/bin/logger
download_asset "archiver"    /usr/local/bin/archiver

echo "--- writing crontab ---"
crontab -u $username ~/a26-setup-helpers/crontab
