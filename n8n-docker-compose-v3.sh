#!/bin/sh
# n8n-setup-ssl.sh  (updated)
# POSIX sh installer:
# - prompts user for domain & public IP
# - verifies DNS resolves to given IP
# - if verified: creates docker-compose with Caddy (auto TLS) + n8n (HTTPS)
# - otherwise: creates docker-compose for HTTP n8n with secure-cookie disabled
# Usage:
#   Interactive: sudo sh n8n-setup-ssl.sh
#   Non-interactive example:
#     sudo N8N_USER=admin N8N_PASS='Pass123' N8N_SECURE_COOKIE=false sh n8n-setup-ssl.sh

set -eu

err() { printf '%s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

# Check docker
if ! command -v docker >/dev/null 2>&1; then
  err "ERROR: docker not found. Install Docker first."
  exit 1
fi

# Choose compose command
DOCKER_COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
else
  err "ERROR: neither 'docker compose' nor 'docker-compose' found. Install Docker Compose."
  exit 2
fi

# Basic vars
DATA_DIR="/n8n/data"
BACKUP_DIR="/n8n/backups"
COMPOSE_DIR="/n8n"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
CADDYFILE="${COMPOSE_DIR}/Caddyfile"
N8N_IMAGE="${N8N_IMAGE:-n8nio/n8n:latest}"
HOST_HTTP_PORT="${HOST_HTTP_PORT:-5678}"  # host port for HTTP-only mode
INTERNAL_N8N_PORT="5678"                  # container internal port (n8n default)

# invoking user (for chown)
if [ "${SUDO_USER:-}" ]; then
  INVOKING_USER="$SUDO_USER"
else
  INVOKING_USER="$(whoami 2>/dev/null || echo root)"
fi

# Read credentials (TTY-safe with env fallback)
N8N_USER_INPUT=""
N8N_PASS_INPUT=""

if [ -t 0 ]; then
  printf '🔑 n8n Basic Auth (recommended)\n'
  printf 'Enter n8n username (default: admin): '
  read N8N_USER_INPUT || true
  printf 'Enter n8n password (hidden, press enter for default "change-me"): '
  stty -echo 2>/dev/null || true
  read N8N_PASS_INPUT || true
  stty echo 2>/dev/null || true
  printf '\n'
fi

# Final credentials (env override > interactive input > default)
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

# Force secure cookie env override allowed
if [ "${N8N_SECURE_COOKIE:-}" = "false" ]; then
  FORCE_SECURE_COOKIE="false"
else
  FORCE_SECURE_COOKIE=""
fi

# Inform user
info ""
info "NOTE: For proper HTTPS + secure cookies you need a domain (e.g. n8n.example.com) pointing to this server's public IP, and ports 80/443 open."
info "If you don't have a domain, script can start n8n in HTTP-only mode and disable secure cookies (for testing)."
info ""

# Continue?
if [ -t 0 ]; then
  printf 'Continue with setup? (y/N): '
  read CONTINUE_ANS || true
  if [ -z "$CONTINUE_ANS" ] || [ "${CONTINUE_ANS%[!yY]*}" != "y" ]; then
    info "Aborting per user choice."
    exit 0
  fi
fi

# Prompt domain and public IP
DOMAIN_INPUT=""
PUBLIC_IP_INPUT=""

if [ -t 0 ]; then
  printf 'Enter your domain name for n8n (leave empty to skip TLS): '
  read DOMAIN_INPUT || true
  printf 'Enter this instance public IP (leave empty to auto-detect): '
  read PUBLIC_IP_INPUT || true
fi

# Auto-detect public IP if empty (best-effort)
if [ -z "$PUBLIC_IP_INPUT" ]; then
  PUBLIC_IP_INPUT="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '')"
fi

# Trim inputs
DOMAIN="$(printf '%s' "$DOMAIN_INPUT" | awk '{$1=$1};1')"
PUBLIC_IP="$(printf '%s' "$PUBLIC_IP_INPUT" | awk '{$1=$1};1')"

info ""
info "Domain: ${DOMAIN:-<none>}"
info "Public IP: ${PUBLIC_IP:-<auto-detect or none>}"
info ""

# If domain provided, ask whether DNS A record created
VERIFY_DNS="no"
if [ -n "$DOMAIN" ]; then
  if [ -t 0 ]; then
    printf 'Have you created/updated the DNS A record for %s pointing to %s? (y/N): ' "$DOMAIN" "${PUBLIC_IP:-<unknown>}"
    read DNS_CONFIRM || true
    if [ -n "$DNS_CONFIRM" ] && [ "${DNS_CONFIRM%[!yY]*}" = "y" ]; then
      VERIFY_DNS="yes"
    fi
  else
    VERIFY_DNS="yes"
  fi
fi

# DNS verification
DNS_MATCH="no"
if [ "$VERIFY_DNS" = "yes" ] && [ -n "$DOMAIN" ]; then
  info "Resolving ${DOMAIN}..."
  RESOLVED_IPS=""
  if command -v getent >/dev/null 2>&1; then
    RESOLVED_IPS="$(getent ahosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | uniq | tr '\n' ' ' | awk '{$1=$1;print}')"
  fi
  if [ -z "$RESOLVED_IPS" ]; then
    if command -v dig >/dev/null 2>&1; then
      RESOLVED_IPS="$(dig +short A "$DOMAIN" 2>/dev/null | tr '\n' ' ' | awk '{$1=$1;print}')"
    elif command -v nslookup >/dev/null 2>&1; then
      RESOLVED_IPS="$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: /{print $2}' | tr '\n' ' ' | awk '{$1=$1;print}')"
    fi
  fi

  info "Resolved IPs: ${RESOLVED_IPS:-<none>}"

  if [ -n "$RESOLVED_IPS" ] && [ -n "$PUBLIC_IP" ]; then
    echo "$RESOLVED_IPS" | tr ' ' '\n' | grep -x "$PUBLIC_IP" >/dev/null 2>&1 && DNS_MATCH="yes" || DNS_MATCH="no"
  elif [ -n "$RESOLVED_IPS" ]; then
    FIRST_RESOLVED="$(printf '%s' "$RESOLVED_IPS" | awk '{print $1}')"
    PUBLIC_IP="$FIRST_RESOLVED"
    DNS_MATCH="yes"
  else
    DNS_MATCH="no"
  fi

  if [ "$DNS_MATCH" = "yes" ]; then
    info "DNS OK: ${DOMAIN} -> ${PUBLIC_IP}"
  else
    err "DNS MISMATCH or resolution failed for ${DOMAIN}."
    if [ -t 0 ]; then
      printf 'Choose: (A) abort, (B) start HTTP-only, (C) attempt TLS anyway [B]: '
      read DNS_CHOICE || true
      case "${DNS_CHOICE:-B}" in
        A|a) info "Aborting."; exit 0 ;;
        C|c) info "Attempting TLS anyway (may fail)";;
        *) info "Proceeding HTTP-only"; DNS_MATCH="no" ;;
      esac
    else
      err "Non-interactive: proceeding HTTP-only."
      DNS_MATCH="no"
    fi
  fi
fi

# Prepare directories
info "Preparing directories..."
sudo mkdir -p "$DATA_DIR" "$BACKUP_DIR" "$COMPOSE_DIR"
sudo chown -R "${INVOKING_USER}:${INVOKING_USER}" /n8n
sudo chmod 755 /n8n
sudo chown -R "${INVOKING_USER}:${INVOKING_USER}" "$DATA_DIR" "$BACKUP_DIR"
sudo chmod 700 "$DATA_DIR" || true
sudo chmod 700 "$BACKUP_DIR" || true

# If DNS matched and domain provided -> TLS mode with Caddy
if [ "$DNS_MATCH" = "yes" ] && [ -n "$DOMAIN" ]; then
  info "Writing compose with Caddy (auto TLS)..."

  # Compose: n8n configured to generate HTTPS URLs (host=DOMAIN, protocol=https, port=443)
  cat > "$COMPOSE_FILE" <<EOF
version: "3.8"

services:
  n8n:
    image: ${N8N_IMAGE}
    container_name: n8n
    restart: unless-stopped
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER_FINAL}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASS_FINAL}
      - N8N_HOST=${DOMAIN}
      - N8N_PROTOCOL=https
      - N8N_PORT=443
      - WEBHOOK_TUNNEL_URL=https://${DOMAIN}
    volumes:
      - ${DATA_DIR}:/home/node/.n8n
      - ${BACKUP_DIR}:/backups
    expose:
      - "${INTERNAL_N8N_PORT}"

  caddy:
    image: caddy:2
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ${COMPOSE_DIR}/Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config

volumes:
  caddy_data:
  caddy_config:
EOF

  # Write Caddyfile (reverse-proxy to internal port)
  cat > "$CADDYFILE" <<EOF
${DOMAIN} {
  reverse_proxy n8n:${INTERNAL_N8N_PORT}
  encode zstd gzip
}
EOF

  # Ownership & perms
  sudo chown "${INVOKING_USER}:${INVOKING_USER}" "$COMPOSE_FILE" "$CADDYFILE"
  sudo chmod 600 "$COMPOSE_FILE" "$CADDYFILE"

  # Start stack
  info "Bringing up stack (this will let Caddy request TLS certificates)."
  cd "$COMPOSE_DIR" || exit 1
  $DOCKER_COMPOSE_CMD pull || true
  $DOCKER_COMPOSE_CMD down >/dev/null 2>&1 || true
  $DOCKER_COMPOSE_CMD up -d

  info "If certificate issuance fails, check DNS and ports 80/443 (firewall)."
  info "Open: https://${DOMAIN}"

else
  info "Writing HTTP-only docker-compose (N8N_SECURE_COOKIE=false to avoid cookie warning)."

  # Use explicit host port from HOST_HTTP_PORT variable
  # Force secure cookie to false (either env override or default false here)
  if [ "${FORCE_SECURE_COOKIE:-}" = "false" ]; then
    SEC_COOK_VAL="false"
  else
    SEC_COOK_VAL="false"
  fi

  cat > "$COMPOSE_FILE" <<EOF
version: "3.8"

services:
  n8n:
    image: ${N8N_IMAGE}
    container_name: n8n
    restart: unless-stopped
    ports:
      - "${HOST_HTTP_PORT}:${INTERNAL_N8N_PORT}"
    volumes:
      - ${DATA_DIR}:/home/node/.n8n
      - ${BACKUP_DIR}:/backups
    environment:
      - N8N_PORT=${INTERNAL_N8N_PORT}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER_FINAL}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASS_FINAL}
      - N8N_SECURE_COOKIE=${SEC_COOK_VAL}
      - TZ=Etc/UTC
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${INTERNAL_N8N_PORT}/healthz"]
      interval: 1m
      timeout: 10s
      retries: 5
EOF

  sudo chown "${INVOKING_USER}:${INVOKING_USER}" "$COMPOSE_FILE"
  sudo chmod 600 "$COMPOSE_FILE"

  info "Starting n8n (HTTP-only)..."
  cd "$COMPOSE_DIR" || exit 1
  $DOCKER_COMPOSE_CMD pull || true
  $DOCKER_COMPOSE_CMD down >/dev/null 2>&1 || true
  $DOCKER_COMPOSE_CMD up -d

  info "n8n is available at: http://$(hostname -I | awk '{print $1}'):${HOST_HTTP_PORT}"
fi

info ""
info "Completed. Check logs: docker logs -f n8n"
info "Check compose status: ${DOCKER_COMPOSE_CMD} ps"
