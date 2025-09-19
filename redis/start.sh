#!/bin/sh
set -eu

echo "=== Redis + RedisInsight + Nginx (with Basic Auth) starter ==="

# Ask for inputs (visible input, because sh does not support hidden -s)
printf "Enter Redis password (this will be used as requirepass): "
read REDIS_PASSWORD
printf "Enter UI username for RedisInsight access: "
read UI_USERNAME
printf "Enter UI password for RedisInsight access: "
read UI_PASSWORD

# Create nginx dir if not exist
mkdir -p nginx

# Create .env file consumed by docker-compose
cat > .env <<EOF
REDIS_PASSWORD=${REDIS_PASSWORD}
EOF


echo "Created .env (contains Redis password)."

# Generate htpasswd (bcrypt) using httpd container's htpasswd tool
echo "Generating htpasswd for user '${UI_USERNAME}'..."
docker run --rm httpd:2.4-alpine htpasswd -Bbn "$UI_USERNAME" "$UI_PASSWORD" > nginx/htpasswd
chmod 640 nginx/htpasswd

echo "Wrote nginx/htpasswd"

# Write nginx default.conf if not present (always overwrite here)
cat > nginx/default.conf <<'EOF'
server {
    listen 80;
    server_name _;

    auth_basic "Restricted - RedisInsight";
    auth_basic_user_file /etc/nginx/htpasswd;

    location / {
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://redisinsight:8001/;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
}
EOF


echo "Ensured nginx/default.conf exists."

# Stop and remove existing compose stack (if any)
echo "Stopping any existing docker-compose stack..."
docker compose down --remove-orphans || true

# Start new stack (recreate containers)
echo "Starting containers..."
docker compose up -d --force-recreate --build

echo "All done."
echo "Access RedisInsight via: http://localhost/"
echo "You will be prompted for username/password (the UI credentials you entered)."
echo "Redis is exposed on port 6379 (requirepass is set)."

                                                                                                                                                                     65,0-1        Bot
