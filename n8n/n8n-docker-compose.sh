#!/bin/sh
set -eu
# -e → exit on error
# -u → exit on unset variable

# ---------------------------
# install-n8n-docker-compose.sh (POSIX sh version)
# ---------------------------

# Variables (paths)
DATA_DIR="/n8n/data"
BACKUP_DIR="/n8n/backups"
COMPOSE_DIR="/n8n"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
N8N_IMAGE="n8nio/n8n:latest"
N8N_PORT=5678

# Get current user who invoked (fallback to whoami if not sudo)
if [ -n "${SUDO_USER:-}" ]; then
  USER_TO_OWN="$SUDO_USER"
else
  USER_TO_OWN="$(whoami)"
fi

# ---------------------------
# Step 1) Prompt for Basic Auth
# ---------------------------
echo "🔑 Setup n8n Basic Auth (to protect web UI)"
printf "Enter n8n username (default: admin): "
read N8N_USER_INPUT
printf "Enter n8n password: "
stty -echo
read N8N_PASS_INPUT
stty echo
echo ""

# Defaults
if [ -z "$N8N_USER_INPUT" ]; then
  N8N_USER="admin"
else
  N8N_USER="$N8N_USER_INPUT"
fi

if [ -z "$N8N_PASS_INPUT" ]; then
  N8N_PASS="change-me"
else
  N8N_PASS="$N8N_PASS_INPUT"
fi

# ---------------------------
# Step 2) Create directories
# ---------------------------
sudo mkdir -p "$DATA_DIR"
sudo mkdir -p "$BACKUP_DIR"
sudo mkdir -p "$COMPOSE_DIR"
sudo chown -R "$USER_TO_OWN:$USER_TO_OWN" /n8n
sudo chmod 755 /n8n

# ---------------------------
# Step 3) Write docker-compose.yml
# ---------------------------
cat > "$COMPOSE_FILE" <<YML
version: "3.8"

services:
  n8n:
    image: $N8N_IMAGE
    container_name: n8n
    restart: unless-stopped
    ports:
      - "$N8N_PORT:5678"
    volumes:
      - $DATA_DIR:/home/node/.n8n
      - $BACKUP_DIR:/backups
    environment:
      - N8N_PORT=$N8N_PORT
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
      - TZ=Etc/UTC
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 1m
      timeout: 10s
      retries: 5
YML

sudo chown "$USER_TO_OWN:$USER_TO_OWN" "$COMPOSE_FILE"
sudo chmod 600 "$COMPOSE_FILE"

# ---------------------------
# Step 4) Start n8n with Docker Compose
# ---------------------------
cd "$COMPOSE_DIR"
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
IP_ADDR="$(hostname -I | awk '{print $1}')"
echo "-------------------------------------------------"
echo "✅ n8n started (image: $N8N_IMAGE)"
echo "🌐 Web UI: http://$IP_ADDR:$N8N_PORT"
echo "📂 Data directory: $DATA_DIR"
echo "📂 Backups directory: $BACKUP_DIR"
echo "📄 Compose file: $COMPOSE_FILE"
echo "👉 To view logs: docker logs -f n8n"
echo "👉 To view compose status: docker compose ps"
echo "-------------------------------------------------"
