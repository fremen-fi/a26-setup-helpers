#!/bin/bash

set -e

echo "=== AirCore A26 Station Deploy ==="
echo ""

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

sudo curl -L -H "Authorization: token $git_pat" \
  "https://github.com/$git_user/$git_repo_name/releases/latest/download/gatherer" \
  -o /usr/local/bin/gatherer
sudo chmod +x /usr/local/bin/gatherer

sudo curl -L -H "Authorization: token $git_pat" \
  "https://github.com/$git_user/$git_repo_name/releases/latest/download/newsweather" \
  -o /usr/local/bin/newsweather
sudo chmod +x /usr/local/bin/newsweather

sudo curl -L -H "Authorization: token $git_pat" \
  "https://github.com/$git_user/$git_repo_name/releases/latest/download/logger" \
  -o /usr/local/bin/logger
sudo chmod +x /usr/local/bin/logger

sudo curl -L -H "Authorization: token $git_pat" \
  "https://github.com/$git_user/$git_repo_name/releases/latest/download/archiver" \
  -o /usr/local/bin/archiver
sudo chmod +x /usr/local/bin/archiver

echo "--- writing crontab ---"
crontab -u liq-user ~/a26-setup-helpers/crontab
