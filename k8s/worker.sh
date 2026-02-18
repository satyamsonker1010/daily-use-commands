#!/bin/bash

set -e

# ===== Ask for Worker Name =====
read -p "Enter Worker Node Name (example: worker-1): " NODE_NAME
hostnamectl set-hostname $NODE_NAME

echo "===== Hostname Set to $NODE_NAME ====="

echo "===== Disable Swap ====="
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

echo "===== Load Kernel Modules ====="
modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

echo "===== Set Sysctl Params ====="
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

echo "===== Install Containerd ====="
apt-get update
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd

echo "===== Install Kubernetes Packages ====="
apt-get update
apt-get install -y apt-transport-https ca-certificates curl gpg

mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
| tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
systemctl enable kubelet

echo "===== Worker Ready ====="
echo "Now run the kubeadm join command from master node."
