#!/bin/bash
set -euo pipefail
# -e → script fail hote hi exit
# -u → unset variables use hote hi error
# -o pipefail → pipeline me koi bhi command fail ho to pura script fail

# ---------------------------
# install-n8n-docker-compose.sh
# Creates root-level dirs, writes docker-compose.yml and starts n8n
# ---------------------------

# Variables (paths)
DATA_DIR="/n8n/data"                # workflows, credentials, executions
BACKUP_DIR="/n8n/backups"           # backup storage
COMPOSE_DIR="/n8n"                  # where docker-compose.yml will live
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
N8N_IMAGE="n8nio/n8n:latest"        # official n8n image
N8N_PORT=5678                       # web UI port
USER_TO_OWN="${SUDO_USER:-$(whoami)}"   # sudo caller or current user

# ---------------------------
# Step 1) Prompt for Basic Auth
# ---------------------------
echo "🔑 Setup n8n Basic Auth (to protect web UI)"
read -p "Enter n8n username (default: admin): " N8N_USER
read -s -p "Enter n8n password: " N8N_PASS
echo ""   # new line after hidden input

# Defaults if user pressed enter
N8N_USER=${N8N_USER:-admin}

# ---------------------------
# Step 2) Create directories
# ---------------------------
sudo mkdir -p "${DATA_DIR}"         # create /n8n/data if not exists
sudo mkdir -p "${BACKUP_DIR}"       # create /n8n/backups if not exists
sudo mkdir -p "${COMPOSE_DIR}"      # create /n8n if not exists
sudo chown -R "${USER_TO_OWN}:${USER_TO_OWN}" /n8n   # give ownership to user
sudo chmod 755 /n8n                 # directory readable/executable by all

# ---------------------------
# Step 3) Write docker-compose.yml
# ---------------------------
cat > "${COMPOSE_FILE}" <<YML
version: "3.8"

services:
  n8n:
    image: ${N8N_IMAGE}
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${N8N_PORT}:5678"
    volumes:
      - ${DATA_DIR}:/home/node/.n8n
      - ${BACKUP_DIR}:/backups
    environment:
      - N8N_PORT=${N8N_PORT}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASS}
      - TZ=Etc/UTC
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 1m
      timeout: 10s
      retries: 5
YML

# secure file
sudo chown "${USER_TO_OWN}:${USER_TO_OWN}" "${COMPOSE_FILE}"
sudo chmod 600 "${COMPOSE_FILE}"   # sensitive (password inside)

# ---------------------------
# Step 4) Start n8n with Docker Compose
# ---------------------------
cd "${COMPOSE_DIR}"
if docker compose version >/dev/null 2>&1; then
  docker compose pull || true
  docker compose up -d
elif command -v docker-compose >/dev/null 2>&1; then
  docker-compose pull || true
  docker-compose up -d
else
  echo "❌ ERROR: Docker Compose not installed."
  exit 2
fi

# ---------------------------
# Step 5) Print info
# ---------------------------
echo "-------------------------------------------------"
echo "✅ n8n started (image: ${N8N_IMAGE})"
echo "🌐 Web UI: http://$(hostname -I | awk '{print $1}'):${N8N_PORT}"
echo "📂 Data directory: ${DATA_DIR}"
echo "📂 Backups directory: ${BACKUP_DIR}"
echo "📄 Compose file: ${COMPOSE_FILE}"
echo "👉 To view logs: docker logs -f n8n"
echo "👉 To view compose status: docker compose ps"
echo "-------------------------------------------------"
