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
