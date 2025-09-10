#!/bin/sh
# n8n-setup-ssl.sh
# POSIX sh installer that:
# - prompts user for domain & public IP
# - verifies DNS resolves to given IP
# - if verified: creates docker-compose with Caddy (auto TLS) + n8n (HTTPS)
# - if not verified or user chooses: creates docker-compose for HTTP n8n with secure-cookie disabled
# Usage (interactive):
#   sudo sh n8n-setup-ssl.sh
# Non-interactive example (no prompts):
#   sudo N8N_USER=admin N8N_PASS='Pass123' N8N_SECURE_COOKIE=false sh n8n-setup-ssl.sh

set -eu

# ---------- helper ----------
err() { printf '%s\n' "$*" >&2; }
info() { printf '%s\n' "$*"; }

# ---------- check docker ----------
if ! command -v docker >/dev/null 2>&1; then
  err "ERROR: docker not found. Install Docker first."
  exit 1
fi

# prefer `docker compose` plugin, fallback to docker-compose binary
DOCKER_COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
else
  err "ERROR: neither 'docker compose' nor 'docker-compose' found. Install Docker Compose."
  exit 2
fi

# ---------- basic vars ----------
DATA_DIR="/n8n/data"
BACKUP_DIR="/n8n/backups"
COMPOSE_DIR="/n8n"
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
CADDYFILE="${COMPOSE_DIR}/Caddyfile"
N8N_IMAGE="${N8N_IMAGE:-n8nio/n8n:latest}"
N8N_PORT="${N8N_PORT:-5678}"

# invoking user (for chown)
if [ "${SUDO_USER:-}" ]; then
  INVOKING_USER="$SUDO_USER"
else
  INVOKING_USER="$(whoami 2>/dev/null || echo root)"
fi

# ---------- read credentials (tty-safe with env fallback) ----------
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

# Final values (env override > interactive input > default)
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

# N8N_SECURE_COOKIE env optional override; default behavior uses secure cookie when TLS is enabled
# If user passes N8N_SECURE_COOKIE=false as env, honor it
if [ "${N8N_SECURE_COOKIE:-}" = "false" ]; then
  FORCE_SECURE_COOKIE="false"
else
  FORCE_SECURE_COOKIE=""
fi

# ---------- Inform user about domain requirement ----------
info ""
info "IMPORTANT: n8n sets secure cookies when running with secure settings."
info "If you plan to use HTTPS (recommended), provide a domain name that points to this server's public IP."
info "If you don't have a domain now, the script can still start n8n without TLS and disable secure-cookie (for testing)."
info ""

# ---------- Ask user if they want to continue ----------
if [ -t 0 ]; then
  printf 'Continue with setup? (y/N): '
  read CONTINUE_ANS || true
  if [ -z "$CONTINUE_ANS" ] || [ "${CONTINUE_ANS%[!yY]*}" != "y" ]; then
    info "Aborting per user choice."
    exit 0
  fi
fi

# ---------- Prompt for domain and public IP ----------
DOMAIN_INPUT=""
PUBLIC_IP_INPUT=""

if [ -t 0 ]; then
  printf 'Enter your domain name (e.g. n8n.example.com). Leave empty to skip TLS and run HTTP-only: '
  read DOMAIN_INPUT || true
  printf 'Enter this instance public IP (e.g. 203.0.113.10). Leave empty to auto-detect: '
  read PUBLIC_IP_INPUT || true
fi

# Auto-detect public IP if not provided (best-effort using hostname -I)
if [ -z "$PUBLIC_IP_INPUT" ]; then
  PUBLIC_IP_INPUT="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '')"
fi

# sanitize domain (trim)
DOMAIN="$(printf '%s' "$DOMAIN_INPUT" | awk '{$1=$1};1')"
PUBLIC_IP="$(printf '%s' "$PUBLIC_IP_INPUT" | awk '{$1=$1};1')"

info ""
info "Domain: ${DOMAIN:-<none>}"
info "Public IP: ${PUBLIC_IP:-<auto-detect or none>}"
info ""

# ---------- If domain provided, ask user to confirm DNS record saved ----------
VERIFY_DNS="no"
if [ -n "$DOMAIN" ]; then
  if [ -t 0 ]; then
    printf 'Have you created/updated the DNS A record for %s pointing to %s? (y/N): ' "$DOMAIN" "${PUBLIC_IP:-<unknown>}"
    read DNS_CONFIRM || true
    if [ -n "$DNS_CONFIRM" ] && [ "${DNS_CONFIRM%[!yY]*}" = "y" ]; then
      VERIFY_DNS="yes"
    fi
  else
    # non-interactive: assume user already set DNS if domain provided
    VERIFY_DNS="yes"
  fi
fi

# ---------- DNS verification (if requested) ----------
DNS_MATCH="no"
if [ "$VERIFY_DNS" = "yes" ] && [ -n "$DOMAIN" ]; then
  info "Verifying DNS for ${DOMAIN}..."
  # Try getent ahosts (POSIX-friendly)
  RESOLVED_IPS=""
  if command -v getent >/dev/null 2>&1; then
    RESOLVED_IPS="$(getent ahosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | uniq | tr '\n' ' ' | awk '{$1=$1;print}')"
  fi
  # fallback to nslookup or dig if getent didn't return
  if [ -z "$RESOLVED_IPS" ]; then
    if command -v nslookup >/dev/null 2>&1; then
      RESOLVED_IPS="$(nslookup "$DOMAIN" 2>/dev/null | awk '/^Address: /{print $2}' | tr '\n' ' ' | awk '{$1=$1;print}')"
    elif command -v dig >/dev/null 2>&1; then
      RESOLVED_IPS="$(dig +short A "$DOMAIN" 2>/dev/null | tr '\n' ' ' | awk '{$1=$1;print}')"
    fi
  fi

  info "Resolved IPs: ${RESOLVED_IPS:-<none>}"

  if [ -n "$RESOLVED_IPS" ] && [ -n "$PUBLIC_IP" ]; then
    # check if PUBLIC_IP appears in resolved list
    echo "$RESOLVED_IPS" | tr ' ' '\n' | grep -x "$PUBLIC_IP" >/dev/null 2>&1 && DNS_MATCH="yes" || DNS_MATCH="no"
  elif [ -n "$RESOLVED_IPS" ]; then
    # no public IP provided; attempt to use first resolved IP as match
    FIRST_RESOLVED="$(printf '%s' "$RESOLVED_IPS" | awk '{print $1}')"
    PUBLIC_IP="$FIRST_RESOLVED"
    DNS_MATCH="yes"
  else
    DNS_MATCH="no"
  fi

  if [ "$DNS_MATCH" = "yes" ]; then
    info "DNS OK: ${DOMAIN} resolves to ${PUBLIC_IP}"
  else
    err "DNS MISMATCH: ${DOMAIN} does not resolve to ${PUBLIC_IP} (or resolution failed)."
    if [ -t 0 ]; then
      printf 'Do you want to (A) abort setup, (B) continue and start n8n without TLS, or (C) continue anyway attempting TLS? [A/B/C] (default B): '
      read DNS_CHOICE || true
      case "${DNS_CHOICE:-B}" in
        A|a) info "Aborting as requested."; exit 0 ;;
        C|c) info "Proceeding to attempt TLS (may fail if DNS isn't correct)." ;;
        *) info "Proceeding to start n8n without TLS and disabling secure-cookie."; DNS_MATCH="no" ;;
      esac
    else
      # non-interactive default: proceed without TLS
      err "Non-interactive: proceeding without TLS."
      DNS_MATCH="no"
    fi
  fi
fi

# ---------- Prepare directories ----------
info "Preparing directories..."
sudo mkdir -p "$DATA_DIR" "$BACKUP_DIR" "$COMPOSE_DIR"
sudo chown -R "${INVOKING_USER}:${INVOKING_USER}" /n8n
sudo chmod 755 /n8n
sudo chown -R "${INVOKING_USER}:${INVOKING_USER}" "$DATA_DIR" "$BACKUP_DIR"
sudo chmod 700 "$DATA_DIR" || true
sudo chmod 700 "$BACKUP_DIR" || true

# ---------- Write docker-compose and (if TLS) Caddyfile ----------
if [ "$DNS_MATCH" = "yes" ] && [ -n "$DOMAIN" ]; then
  info "Writing docker-compose.yml with Caddy (Auto TLS) and Caddyfile..."

  # Docker compose with Caddy reverse proxy for HTTPS and n8n configured for HTTPS
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
      - N8N_WEBHOOK_TUNNEL_URL=https://${DOMAIN}
      - N8N_PORT=${N8N_PORT}
    volumes:
      - ${DATA_DIR}:/home/node/.n8n
      - ${BACKUP_DIR}:/backups
    expose:
      - "5678"

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

  # Write Caddyfile
  cat > "$CADDYFILE" <<EOF
${DOMAIN} {
  reverse_proxy n8n:5678
  encode zstd gzip
}
EOF

  sudo chown "${INVOKING_USER}:${INVOKING_USER}" "$COMPOSE_FILE" "$CADDYFILE"
  sudo chmod 600 "$COMPOSE_FILE" "$CADDYFILE"

  info "Starting stack (Caddy will obtain TLS certs via Let's Encrypt)..."
  cd "$COMPOSE_DIR" || exit 1
  # pull images best-effort
  $DOCKER_COMPOSE_CMD pull || true
  $DOCKER_COMPOSE_CMD down >/dev/null 2>&1 || true
  $DOCKER_COMPOSE_CMD up -d

  info "If Caddy fails to obtain certificates, check DNS and ports 80/443 access."
  info "Access your n8n at: https://${DOMAIN}"

else
  info "Writing docker-compose.yml for HTTP-only n8n (secure-cookie will be disabled to avoid cookie warning)."

  # If user explicitly forced N8N_SECURE_COOKIE=false via env, use that; otherwise disable since no TLS
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
      - "${N8N_PORT}:5678"
    volumes:
      - ${DATA_DIR}:/home/node/.n8n
      - ${BACKUP_DIR}:/backups
    environment:
      - N8N_PORT=${N8N_PORT}
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=${N8N_USER_FINAL}
      - N8N_BASIC_AUTH_PASSWORD=${N8N_PASS_FINAL}
      - N8N_SECURE_COOKIE=${SEC_COOK_VAL}
      - TZ=Etc/UTC
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5678/healthz"]
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

  info "n8n is available at: http://$(hostname -I | awk '{print $1}'):${N8N_PORT}"
fi

info ""
info "Completed. Check logs with: docker logs -f n8n"
info "Check compose status with: ${DOCKER_COMPOSE_CMD} ps"
