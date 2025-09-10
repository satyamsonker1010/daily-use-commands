#!/bin/sh
# POSIX sh compatible installer for n8n (docker compose)
# - Safe prompting when interactive (TTY)
# - Accepts env vars for non-interactive runs
# - Checks docker & docker compose availability
# - Creates /n8n data + backups, writes docker-compose.yml, starts service
# Usage:
#   Interactive: sudo sh n8n-install.sh
#   Non-interactive (example):
#     sudo N8N_USER=admin N8N_PASS=Secret123 N8N_SECURE_COOKIE=false sh n8n-install.sh

set -eu

# ----------------------------
# Configuration (change if needed)
# ----------------------------
DATA_DIR="/n8n/data"
BACKUP_DIR="/n8n/backups"
COMPOSE_DIR="/n8n"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
N8N_IMAGE="${N8N_IMAGE:-n8nio/n8n:latest}"
N8N_PORT="${N8N_PORT:-5678}"

# ----------------------------
# Helper: print to stderr
# ----------------------------
err() {
  printf '%s\n' "$*" >&2
}

# ----------------------------
# Detect invoking (real) user
# ----------------------------
if [ "${SUDO_USER:-}" ]; then
  INVOKING_USER="$SUDO_USER"
else
  INVOKING_USER="$(whoami 2>/dev/null || echo root)"
fi

# ----------------------------
# Ensure Docker is present
# ----------------------------
if ! command -v docker >/dev/null 2>&1; then
  err "ERROR: docker not found. Please install Docker first."
  exit 1
fi

# Determine compose command (prefer `docker compose` plugin)
DOCKER_COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
else
  err "ERROR: neither 'docker compose' nor 'docker-compose' found. Install Docker Compose."
  exit 2
fi

# ----------------------------
# Read credentials (TTY-safe) with env var fallbacks
# ----------------------------
# If N8N_USER / N8N_PASS already exported, use them.
# If STDIN is a TTY, prompt the user. Otherwise fall back to env or defaults.

N8N_USER_INPUT=""
N8N_PASS_INPUT=""

if [ -t 0 ]; then
  printf '🔑 Setup n8n Basic Auth (recommended to protect UI)\n'
  printf 'Enter n8n username (default: admin): '
  read N8N_USER_INPUT || true

  # Read password silently
  printf 'Enter n8n password (will be hidden): '
  # disable echo
  stty -echo 2>/dev/null || true
  read N8N_PASS_INPUT || true
  stty echo 2>/dev/null || true
  printf '\n'
fi

# Priorities:
# 1) exported env var (N8N_USER / N8N_PASS)
# 2) interactive input
# 3) sensible default
if [ -n "${N8N_USER:-}" ]; then
  N8N_USER_FINAL="$N8N_USER"
elif [ -n "$N8N_USER_INPUT" ]; then
  N8N_USER_FINAL="$N8N_USER_INPUT"
else
  N8N_USER_FINAL="admin"
fi

if [ -n "${N8N_PASS:-}" ]; then
  N8N_PASS_FINAL="$N8N_PASS"
elif [ -n "$N8N_PASS_INPUT" ]; then
  N8N_PASS_FINAL="$N8N_PASS_INPUT"
else
  N8N_PASS_FINAL="change-me"
fi

# Secure cookie option (default: true)
# Allow overriding with env N8N_SECURE_COOKIE=false
if [ "${N8N_SECURE_COOKIE:-}" = "false" ]; then
  SECURE_COOKIE_VAL="false"
else
  SECURE_COOKIE_VAL="true"
fi

# ----------------------------
# Create directories and set ownership/permissions
# ----------------------------
printf 'Creating directories: %s and %s\n' "$DATA_DIR" "$BACKUP_DIR"
sudo mkdir -p "$DATA_DIR" "$BACKUP_DIR" "$COMPOSE_DIR"
sudo chown -R "${INVOKING_USER}:${INVOKING_USER}" /n8n
sudo chmod 755 /n8n
# Make sure data/backups are writable by invoking user
sudo chown -R "${INVOKING_USER}:${INVOKING_USER}" "$DATA_DIR" "$BACKUP_DIR"
sudo chmod 700 "$DATA_DIR" || true
sudo chmod 700 "$BACKUP_DIR" || true

# ----------------------------
# Write docker-compose.yml
# ----------------------------
printf 'Writing docker-compose.yml to %s\n' "$COMPOSE_FILE"

cat > "$COMPOSE_FILE" <<EOF
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
      - N8N_BASIC_AUTH_USER=${N8N_USER_FINAL}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASS_FINAL}
      - N8N_SECURE_COOKIE=${SECURE_COOKIE_VAL}
      - TZ=Etc/UTC
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
      interval: 1m
      timeout: 10s
      retries: 5
EOF

# Secure the compose file (contains secrets)
sudo chown "${INVOKING_USER}:${INVOKING_USER}" "$COMPOSE_FILE"
sudo chmod 600 "$COMPOSE_FILE"

# ----------------------------
# Start / restart n8n
# ----------------------------
printf 'Starting n8n using: %s\n' "$DOCKER_COMPOSE_CMD"
cd "$COMPOSE_DIR" || exit 1

# Pull image (ignore pull errors)
$DOCKER_COMPOSE_CMD pull || true

# Use down/up to ensure updated env is applied
$DOCKER_COMPOSE_CMD down >/dev/null 2>&1 || true
$DOCKER_COMPOSE_CMD up -d

# ----------------------------
# Final info
# ----------------------------
IP_ADDR="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '127.0.0.1')"
printf '\n-------------------------------------------------\n'
printf '✅ n8n started (image: %s)\n' "$N8N_IMAGE"
printf '🌐 Web UI: http://%s:%s\n' "$IP_ADDR" "$N8N_PORT"
if [ "${SECURE_COOKIE_VAL}" = "true" ]; then
  printf '🔒 Note: n8n sets secure cookies; use HTTPS or set N8N_SECURE_COOKIE=false for testing only.\n'
fi
printf '📂 Data directory: %s\n' "$DATA_DIR"
printf '📂 Backups directory: %s\n' "$BACKUP_DIR"
printf '📄 Compose file: %s\n' "$COMPOSE_FILE"
printf '👉 To view logs: docker logs -f n8n\n'
printf '👉 To view compose status: %s ps\n' "$DOCKER_COMPOSE_CMD"
printf '-------------------------------------------------\n'
