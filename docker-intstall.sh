#!/bin/bash
set -e

# 1) Remove old key if present
sudo rm -f /etc/apt/trusted.gpg.d/docker.gpg

# 2) Create keyrings directory
sudo mkdir -p /etc/apt/keyrings

# 3) Download and store Docker’s official GPG key
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# 4) Make key readable
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 5) Add Docker repository (using jammy since noble not yet supported)
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu jammy stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 6) Update package index
sudo apt update

# 7) Install Docker + Plugins (Compose included)
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 8) Enable and start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# 9) Add current user to docker group (so you can run docker without sudo)
sudo usermod -aG docker $USER

echo "✅ Docker and Docker Compose installed successfully!"
echo "👉 Please logout and login again (or run: newgrp docker) to use Docker without sudo."
docker --version
docker compose version
