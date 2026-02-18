#!/bin/bash

set -e

print_step() {
  echo ""
  echo "=================================================================="
  echo "🚀  $1"
  echo "=================================================================="
  echo ""
}

# --------------------------------------------------

print_step "Fixing DNS Configuration (Avoid Nameserver Limit Issue)"

rm -f /etc/resolv.conf

cat <<EOF > /etc/resolv.conf
nameserver 8.8.8.8
nameserver 8.8.4.4
EOF

# --------------------------------------------------

print_step "Disabling Swap"

swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# --------------------------------------------------

print_step "Loading Kernel Modules"

modprobe overlay
modprobe br_netfilter

cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# --------------------------------------------------

print_step "Applying Sysctl Network Settings"

cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system

# --------------------------------------------------

print_step "Installing Containerd"

apt-get update
apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# Enable SystemdCgroup (IMPORTANT FIX)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd

# --------------------------------------------------

print_step "Installing Kubernetes Components"

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

# --------------------------------------------------

print_step "Initializing Kubernetes Master Node"

kubeadm init --pod-network-cidr=192.168.0.0/16

# --------------------------------------------------

print_step "Configuring kubectl"

export KUBECONFIG=/etc/kubernetes/admin.conf

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config

# --------------------------------------------------

print_step "Installing Calico Network Plugin"

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

# --------------------------------------------------

print_step "Ensuring Workloads Do NOT Run on Master Node"

kubectl taint nodes $(hostname) node-role.kubernetes.io/control-plane=:NoSchedule --overwrite


print_step "Cluster Setup Completed Successfully 🎉"

echo ""
echo "👉 To add worker nodes, run the following on master:"
echo ""
kubeadm token create --print-join-command
echo ""
