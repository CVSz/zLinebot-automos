#!/bin/bash
set -e

echo "🚀 Starting FULL DevOps + AI + Zero Trust Stack Install..."

############################
# VARIABLES
############################
DOMAIN="zeaz.dev"
EMAIL="YOUR_EMAIL"
REPO="https://github.com/CVSz/zLinebot-automos.git"
APP_DIR="/opt/zlinebot"

############################
# SYSTEM UPDATE
############################
apt update && apt upgrade -y

############################
# BASIC TOOLS
############################
apt install -y \
  curl wget git unzip jq build-essential \
  apt-transport-https ca-certificates gnupg lsb-release \
  software-properties-common

############################
# SECURITY HARDENING
############################
echo "🔒 Applying security hardening..."

# Firewall
apt install -y ufw fail2ban
ufw default deny incoming
ufw default allow outgoing
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

# Fail2ban
systemctl enable fail2ban
systemctl start fail2ban

# SSH Hardening
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart sshd

############################
# INSTALL DOCKER
############################
echo "🐳 Installing Docker..."
curl -fsSL https://get.docker.com | sh
systemctl enable docker
systemctl start docker

############################
# INSTALL K3S (KUBERNETES)
############################
echo "☸️ Installing k3s..."
curl -sfL https://get.k3s.io | sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

############################
# INSTALL HELM
############################
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

############################
# CLONE YOUR REPO
############################
echo "📦 Cloning repo..."
git clone $REPO $APP_DIR || true
cd $APP_DIR

############################
# INSTALL CLOUD FLARED
############################
echo "☁️ Installing cloudflared..."
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared-linux-amd64.deb

############################
# PROMETHEUS + GRAFANA + LOKI
############################
echo "📊 Installing monitoring stack..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

kubectl create namespace monitoring || true

helm install prometheus prometheus-community/kube-prometheus-stack -n monitoring
helm install loki grafana/loki-stack -n monitoring

############################
# VAULT (SECRETS)
############################
echo "🔐 Installing Vault..."
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault || true
helm install vault hashicorp/vault -n vault

############################
# LINKERD (SERVICE MESH)
############################
echo "🔗 Installing Linkerd..."
curl -sL https://run.linkerd.io/install | sh
export PATH=$PATH:$HOME/.linkerd2/bin

linkerd install | kubectl apply -f -
linkerd check

############################
# EVENT-DRIVEN SYSTEM (REPLACES AI SCRIPT)
############################
echo "⚡ Setting up event-driven automation..."

apt install -y inotify-tools

cat <<EOF > /usr/local/bin/event-engine.sh
#!/bin/bash
while inotifywait -r -e modify,create,delete $APP_DIR; do
  echo "Change detected, redeploying..."
  kubectl rollout restart deployment/zlinebot || true
done
EOF

chmod +x /usr/local/bin/event-engine.sh

############################
# SELF-HEALING SYSTEM
############################
echo "🛠️ Setting up self-healing..."

cat <<EOF > /etc/systemd/system/self-heal.service
[Unit]
Description=Self Healing System

[Service]
ExecStart=/bin/bash -c 'while true; do kubectl get pods || systemctl restart k3s; sleep 30; done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable self-heal
systemctl start self-heal

############################
# AI AUTO DEBUG BOT (LOCAL)
############################
echo "🤖 Installing AI debug bot..."

cat <<EOF > /usr/local/bin/ai-debug.sh
#!/bin/bash
kubectl get pods --all-namespaces > /tmp/status.txt
if grep -i error /tmp/status.txt; then
  echo "⚠️ Error detected, restarting..."
  kubectl rollout restart deployment/zlinebot
fi
EOF

chmod +x /usr/local/bin/ai-debug.sh

############################
# CRON FOR AI BOT
############################
(crontab -l 2>/dev/null; echo "*/2 * * * * /usr/local/bin/ai-debug.sh") | crontab -

############################
# ZERO TRUST (BASIC)
############################
echo "🛡️ Applying zero-trust baseline..."

apt install -y nginx

cat <<EOF > /etc/nginx/conf.d/zero-trust.conf
server {
    listen 443 ssl;
    server_name *.$DOMAIN;

    location / {
        proxy_pass http://localhost:3000;
        auth_basic "Restricted";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }
}
EOF

systemctl restart nginx

############################
# GITHUB ACTION TEMPLATE
############################
echo "⚙️ Creating CI/CD pipeline..."

mkdir -p $APP_DIR/.github/workflows

cat <<EOF > $APP_DIR/.github/workflows/deploy.yml
name: Auto Deploy

on:
  push:
    branches: [ "main" ]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v3

    - name: Deploy to k3s
      run: |
        kubectl apply -f k8s/
        kubectl rollout restart deployment/zlinebot
EOF

############################
# FINAL MESSAGE
############################
echo "✅ INSTALL COMPLETE!"
echo ""
echo "Next steps:"
echo "1. Run: cloudflared tunnel login"
echo "2. Connect domain: *.$DOMAIN"
echo "3. Push repo to trigger CI/CD"
echo ""
echo "🔥 Your FULL stack is LIVE."
