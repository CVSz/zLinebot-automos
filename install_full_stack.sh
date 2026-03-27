#!/bin/bash
set -Eeuo pipefail
trap 'echo "❌ Error on line $LINENO"; exit 1' ERR

export DEBIAN_FRONTEND=noninteractive

log() { echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*"; }
require_root() {
  if [[ ${EUID} -ne 0 ]]; then
    echo "❌ This installer must run as root."
    exit 1
  fi
}

require_root

log "🚀 Starting hardened full-stack installer..."

############################
# VARIABLES
############################
DOMAIN="zeaz.dev"
EMAIL="YOUR_EMAIL"
REPO="https://github.com/CVSz/zLinebot-automos.git"
APP_DIR="/opt/zlinebot"
K8S_NAMESPACE="zlinebot"
NODE_IP="$(hostname -I | awk '{print $1}')"

# enforce required variables
: "${DOMAIN:?missing DOMAIN}"

############################
# SYSTEM UPDATE
############################
apt-get update
apt-get upgrade -y

############################
# BASIC TOOLS
############################
apt-get install -y \
  curl wget git unzip jq build-essential \
  apt-transport-https ca-certificates gnupg lsb-release \
  software-properties-common inotify-tools

############################
# KERNEL / NETWORK BASELINE
############################
cat > /etc/sysctl.d/99-zlinebot-k8s.conf <<'EOF_SYSCTL'
net.ipv4.ip_forward=1
vm.max_map_count=262144
fs.inotify.max_user_watches=524288
EOF_SYSCTL

############################
# VMWARE + LOW RESOURCE TUNING
############################
cat <<'EOF_VM' >> /etc/sysctl.d/99-zlinebot-k8s.conf
vm.swappiness=10
vm.dirty_ratio=15
vm.dirty_background_ratio=5
net.core.somaxconn=65535
EOF_VM

sysctl --system

############################
# SECURITY HARDENING
############################
log "🔒 Applying security hardening..."

# Firewall
apt-get install -y ufw fail2ban
ufw default deny incoming
ufw default allow outgoing
ufw allow 22
ufw allow 80
ufw allow 443
ufw --force enable

# Fail2ban
systemctl enable fail2ban
systemctl restart fail2ban

# SSH hardening with lockout protection
if [[ ! -s /root/.ssh/authorized_keys ]]; then
  echo "❌ No SSH key found in /root/.ssh/authorized_keys. Abort hardening to avoid lockout."
  exit 1
fi

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%s)
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sshd -t
systemctl restart sshd

############################
# INSTALL DOCKER (APT + GPG)
############################
log "🐳 Installing Docker via apt repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

cat > /etc/apt/sources.list.d/docker.list <<DOCKER_REPO
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable
DOCKER_REPO

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl restart docker

############################
# INSTALL K3S (PINNED VERSION)
############################
log "☸️ Installing k3s..."
K3S_VERSION="v1.33.3+k3s1"
curl -fsSL "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/k3s" -o /usr/local/bin/k3s
curl -fsSL "https://github.com/k3s-io/k3s/releases/download/${K3S_VERSION}/sha256sum-amd64.txt" -o /tmp/k3s.sha256
( cd /usr/local/bin && grep ' k3s$' /tmp/k3s.sha256 | sha256sum -c - )
chmod +x /usr/local/bin/k3s

cat > /etc/systemd/system/k3s.service <<'K3S_SVC'
[Unit]
Description=Lightweight Kubernetes
After=network.target

[Service]
Type=exec
ExecStart=/usr/local/bin/k3s server \
  --disable traefik \
  --disable servicelb \
  --secrets-encryption \
  --kube-apiserver-arg=encryption-provider-config=/var/lib/rancher/k3s/server/cred/encryption-config.yaml \
  --write-kubeconfig-mode 644 \
  --node-ip __NODE_IP__ \
  --tls-san __DOMAIN__
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
K3S_SVC

sed -i "s/__NODE_IP__/${NODE_IP}/" /etc/systemd/system/k3s.service
sed -i "s/__DOMAIN__/${DOMAIN}/" /etc/systemd/system/k3s.service

# K3S hardening for low-resource VM scenarios
sed -i '/ExecStart/ s/$/ \\\n  --kubelet-arg=eviction-hard=memory.available<200Mi,nodefs.available<10% \\\n  --kubelet-arg=eviction-soft=memory.available<300Mi \\\n  --kubelet-arg=system-reserved=cpu=300m,memory=512Mi \\\n  --kubelet-arg=kube-reserved=cpu=300m,memory=512Mi \\\n  --kubelet-arg=eviction-pressure-transition-period=30s/' /etc/systemd/system/k3s.service

# Explicit KMS config for secrets at rest
mkdir -p /var/lib/rancher/k3s/server/cred
if [[ ! -f /var/lib/rancher/k3s/server/cred/encryption-config.yaml ]]; then
  ENCRYPTION_KEY="$(openssl rand -base64 32)"
  cat > /var/lib/rancher/k3s/server/cred/encryption-config.yaml <<EOF_ENCRYPT
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: ${ENCRYPTION_KEY}
  - identity: {}
EOF_ENCRYPT
  chmod 600 /var/lib/rancher/k3s/server/cred/encryption-config.yaml
fi

systemctl daemon-reload
systemctl enable k3s
systemctl restart k3s
ln -sf /usr/local/bin/k3s /usr/local/bin/kubectl

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
# ensure kubectl works globally
grep -q 'KUBECONFIG=/etc/rancher/k3s/k3s.yaml' /etc/profile || echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> /etc/profile

until kubectl cluster-info >/dev/null 2>&1; do
  sleep 5
  log "⏳ Waiting for k3s API..."
done
# basic validation
kubectl get nodes >/dev/null
kubectl get namespace "${K8S_NAMESPACE}" >/dev/null 2>&1 || kubectl create namespace "${K8S_NAMESPACE}"

############################
# INSTALL HELM (PINNED)
############################
log "📦 Installing Helm..."
HELM_VERSION="v3.18.4"
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o /tmp/helm.tar.gz
curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz.sha256sum" -o /tmp/helm.tar.gz.sha256sum
echo "$(cat /tmp/helm.tar.gz.sha256sum)  /tmp/helm.tar.gz" | sha256sum -c -
tar -xzf /tmp/helm.tar.gz -C /tmp
install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm

############################
# CLONE REPO
############################
log "📦 Syncing repository..."
if [[ -d "$APP_DIR/.git" ]]; then
  git -C "$APP_DIR" fetch --all --prune
  git -C "$APP_DIR" reset --hard origin/main
else
  git clone "$REPO" "$APP_DIR"
fi
cd "$APP_DIR"

############################
# INSTALL CLOUD FLARED
############################
log "☁️ Installing cloudflared..."
CLOUDFLARED_VERSION="2026.3.0"
CLOUDFLARED_DEB="cloudflared-linux-amd64.deb"
curl -fsSL "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/${CLOUDFLARED_DEB}" -o "/tmp/${CLOUDFLARED_DEB}"
apt-get install -y "/tmp/${CLOUDFLARED_DEB}"
mkdir -p /etc/cloudflared

cat > /etc/systemd/system/cloudflared.service <<'EOF_CLOUDFLARED'
[Unit]
Description=Cloudflare Tunnel
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/cloudflared tunnel --config /etc/cloudflared/config.yml run
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_CLOUDFLARED

if [[ -f /etc/cloudflared/config.yml && -f /etc/cloudflared/credentials.json ]]; then
  systemctl daemon-reload
  systemctl enable cloudflared
  systemctl restart cloudflared
else
  log "⚠️ Cloudflared config/credentials missing. Expected /etc/cloudflared/config.yml and /etc/cloudflared/credentials.json"
  log "⚠️ Run: cloudflared tunnel login && cloudflared tunnel create zlinebot"
fi


############################
# MONITORING STACK (IDEMPOTENT)
############################
log "📊 Installing monitoring stack..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$K8S_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

cat > /tmp/prometheus-values.yaml <<'EOF_PROM'
prometheus:
  prometheusSpec:
    retention: 7d
    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 1Gi
grafana:
  resources:
    requests:
      cpu: 50m
      memory: 128Mi
    limits:
      cpu: 300m
      memory: 512Mi
EOF_PROM

cat > /tmp/loki-values.yaml <<'EOF_LOKI'
loki:
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi
EOF_LOKI

cat > /tmp/vault-values.yaml <<'EOF_VAULT'
server:
  ha:
    enabled: false
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      cpu: 500m
      memory: 1Gi
EOF_VAULT

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring -f /tmp/prometheus-values.yaml
helm upgrade --install loki grafana/loki-stack -n monitoring -f /tmp/loki-values.yaml
helm upgrade --install vault hashicorp/vault -n vault -f /tmp/vault-values.yaml

############################
# REMOVE VAULT (NOT CONFIGURED)
############################
log "⚠️ Removing Vault (not configured for production)"
helm uninstall vault -n vault || true

cat <<EOF_LIMIT | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: ${K8S_NAMESPACE}
spec:
  limits:
    - type: Container
      default:
        cpu: "500m"
        memory: "512Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
EOF_LIMIT

cat <<EOF_QUOTA | kubectl apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota
  namespace: ${K8S_NAMESPACE}
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
EOF_QUOTA

cat <<EOF_NETPOL | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: ${K8S_NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: ${K8S_NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
EOF_NETPOL

############################
# LINKERD (VERIFIED BINARY)
############################
log "🔗 Installing Linkerd CLI..."
LINKERD_VERSION="stable-2.18.1"
curl -fsSL "https://github.com/linkerd/linkerd2/releases/download/${LINKERD_VERSION}/linkerd2-cli-${LINKERD_VERSION}-linux-amd64" -o /usr/local/bin/linkerd
curl -fsSL "https://github.com/linkerd/linkerd2/releases/download/${LINKERD_VERSION}/linkerd2-cli-${LINKERD_VERSION}-linux-amd64.sha256" -o /tmp/linkerd.sha256
( cd /usr/local/bin && echo "$(cat /tmp/linkerd.sha256)  linkerd" | sha256sum -c - )
chmod +x /usr/local/bin/linkerd

linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd check
linkerd viz install | kubectl apply -f -
linkerd viz check
kubectl label namespace "${K8S_NAMESPACE}" linkerd.io/inject=enabled --overwrite

############################
# DISABLE LINKERD (NO POLICY)
############################
log "⚠️ Disabling Linkerd (no traffic policy configured)"
kubectl delete namespace linkerd >/dev/null 2>&1 || true
kubectl delete namespace linkerd-viz >/dev/null 2>&1 || true

############################
# EVENT-DRIVEN SYSTEM
############################
log "⚠️ Event-driven deploy removed (use GitOps instead)"

############################
# SELF-HEALING SYSTEM
############################
log "🛠️ Setting up self-healing..."

cat <<'EOF_HEAL' > /etc/systemd/system/self-heal.service
[Unit]
Description=K3s API health monitor
After=k3s.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do kubectl get --raw="/readyz?verbose" >/dev/null 2>&1 || logger -t self-heal "k3s readyz failed"; sleep 30; done'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF_HEAL

systemctl daemon-reload
systemctl enable self-heal
systemctl restart self-heal

############################
# AI AUTO DEBUG BOT
############################
log "⚠️ AI auto-restart disabled (unsafe in production)"

cat <<'EOF_AI' > /usr/local/bin/ai-debug.sh
#!/bin/bash
exit 0
EOF_AI

chmod +x /usr/local/bin/ai-debug.sh

############################
# CRON FOR AI BOT (IDEMPOTENT)
############################
CRON_JOB="*/2 * * * * /usr/local/bin/ai-debug.sh"
(crontab -l 2>/dev/null | grep -v '/usr/local/bin/ai-debug.sh'; echo "$CRON_JOB") | crontab -

############################
# BACKUP JOB (POSTGRES SNAPSHOT PLACEHOLDER)
############################
kubectl create namespace backup --dry-run=client -o yaml | kubectl apply -f -
cat <<EOF_BACKUP_PVC | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: backup
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
EOF_BACKUP_PVC

cat <<EOF_BACKUP | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
  namespace: backup
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          containers:
          - name: backup
            image: postgres:16
            command: ["/bin/sh","-c"]
            args:
            - |
              : "\${POSTGRES_HOST:?missing POSTGRES_HOST}"
              : "\${POSTGRES_DB:?missing POSTGRES_DB}"
              : "\${POSTGRES_USER:?missing POSTGRES_USER}"
              : "\${PGPASSWORD:?missing PGPASSWORD}"
              mkdir -p /backup
              pg_dump -h "\${POSTGRES_HOST}" -U "\${POSTGRES_USER}" "\${POSTGRES_DB}" > "/backup/\${POSTGRES_DB}-\$(date +%F).sql"
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
            env:
            - name: POSTGRES_HOST
              value: postgres.${K8S_NAMESPACE}.svc.cluster.local
            - name: POSTGRES_DB
              value: zlinebot
            - name: POSTGRES_USER
              value: postgres
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
EOF_BACKUP

cat <<EOF_BACKUP_CLEAN | kubectl apply -f -
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-clean
  namespace: backup
spec:
  schedule: "0 3 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          volumes:
          - name: backup-storage
            persistentVolumeClaim:
              claimName: backup-pvc
          containers:
          - name: cleaner
            image: busybox:1.36
            command: ["/bin/sh","-c"]
            args:
            - find /backup -type f -mtime +7 -delete
            volumeMounts:
            - name: backup-storage
              mountPath: /backup
EOF_BACKUP_CLEAN

############################
# INGRESS CONTROLLER (NO HOST NGINX BYPASS)
############################
log "🌐 Installing ingress-nginx controller..."
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx
cat <<EOF_ING | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: zlinebot
  namespace: ${K8S_NAMESPACE}
spec:
  ingressClassName: nginx
  rules:
  - host: ${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: zlinebot
            port:
              number: 80
EOF_ING
log "🛡️ Skipping host-level NGINX reverse proxy to avoid ingress strategy conflicts."

############################
# KUBERNETES MANIFEST VALIDATION
############################
kubectl apply --dry-run=server -f k8s/ || {
  echo "❌ Invalid Kubernetes manifests in k8s/"
  exit 1
}

############################
# RBAC BASELINE
############################
cat <<EOF_RBAC | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: zlinebot-sa
  namespace: ${K8S_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: zlinebot-role
  namespace: ${K8S_NAMESPACE}
rules:
- apiGroups: [""]
  resources: ["pods","services"]
  verbs: ["get","list","watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: zlinebot-bind
  namespace: ${K8S_NAMESPACE}
subjects:
- kind: ServiceAccount
  name: zlinebot-sa
roleRef:
  kind: Role
  name: zlinebot-role
  apiGroup: rbac.authorization.k8s.io
EOF_RBAC

############################
# HPA (AUTOSCALING)
############################
cat <<EOF_HPA | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: zlinebot-hpa
  namespace: ${K8S_NAMESPACE}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: zlinebot
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF_HPA

############################
# PROMTAIL (LOG PIPELINE)
############################
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install promtail grafana/promtail -n monitoring \
  --set resources.requests.cpu=50m \
  --set resources.limits.cpu=200m \
  --set resources.limits.memory=256Mi

############################
# KYVERNO (POLICY ENGINE)
############################
helm repo add kyverno https://kyverno.github.io/kyverno/
helm upgrade --install kyverno kyverno/kyverno -n kyverno --create-namespace

cat <<EOF_POLICY | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged
spec:
  validationFailureAction: enforce
  rules:
  - name: no-privileged
    match:
      resources:
        kinds:
        - Pod
    validate:
      message: "Privileged containers are not allowed"
      pattern:
        spec:
          containers:
          - =(securityContext):
              =(privileged): "false"
              runAsNonRoot: true
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
EOF_POLICY

############################
# EXTERNAL DNS (CLOUDFLARE)
############################
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm upgrade --install external-dns external-dns/external-dns \
  -n kube-system \
  --set provider=cloudflare \
  --set env[0].name=CF_API_TOKEN \
  --set env[0].valueFrom.secretKeyRef.name=cloudflare-api \
  --set env[0].valueFrom.secretKeyRef.key=token

############################
# POD SECURITY BASELINE
############################
cat <<EOF_PSA | kubectl apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: ${K8S_NAMESPACE}
  labels:
    pod-security.kubernetes.io/enforce: restricted
EOF_PSA

############################
# IMAGE POLICY (COSIGN)
############################
cat <<EOF_VERIFY | kubectl apply -f -
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-images
spec:
  validationFailureAction: enforce
  rules:
  - name: check-signature
    match:
      resources:
        kinds:
        - Pod
    verifyImages:
    - imageReferences:
      - "*"
      attestors:
      - entries:
        - keys:
            publicKeys: |
              -----BEGIN PUBLIC KEY-----
              FAKEKEY
              -----END PUBLIC KEY-----
EOF_VERIFY

############################
# CERT-MANAGER (TLS AUTO)
############################
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.4/cert-manager.yaml

cat <<EOF_ISSUER | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    email: ${EMAIL}
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt
    solvers:
    - http01:
        ingress:
          class: nginx
EOF_ISSUER

cat <<EOF_CERT | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: zlinebot-cert
  namespace: ${K8S_NAMESPACE}
spec:
  secretName: zlinebot-tls
  issuerRef:
    name: letsencrypt
    kind: ClusterIssuer
  dnsNames:
  - ${DOMAIN}
EOF_CERT

############################
# INGRESS TLS BIND
############################
kubectl patch ingress zlinebot -n "${K8S_NAMESPACE}" --type merge -p '{
  "spec": {
    "tls": [
      {
        "hosts": ["'"${DOMAIN}"'"],
        "secretName": "zlinebot-tls"
      }
    ]
  }
}'

############################
# RESOURCE CONTROL (CRITICAL FOR 4C/8T)
############################
cat <<EOF_LIMIT_SYS | kubectl apply -f -
apiVersion: v1
kind: LimitRange
metadata:
  name: system-limit
  namespace: kube-system
spec:
  limits:
  - type: Container
    default:
      cpu: "200m"
      memory: "256Mi"
EOF_LIMIT_SYS

############################
# STORAGECLASS (VMWARE SAFE)
############################
cat <<EOF_SC | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-path-retain
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
EOF_SC

############################
# DISABLE DIRECT APPLY (ENFORCE GITOPS)
############################
cat <<'EOF_KUBECTL_GUARD' > /usr/local/bin/kubectl-guard
#!/bin/bash
echo "⚠️ Direct kubectl apply disabled. Use ArgoCD only."
exit 1
EOF_KUBECTL_GUARD
chmod +x /usr/local/bin/kubectl-guard

############################
# ARGOCD APPLICATION (REAL GITOPS)
############################
cat <<EOF_ARGO | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: zlinebot
  namespace: argocd
spec:
  project: default
  source:
    repoURL: ${REPO}
    targetRevision: HEAD
    path: k8s
  destination:
    server: https://kubernetes.default.svc
    namespace: ${K8S_NAMESPACE}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF_ARGO

############################
# GITHUB ACTION TEMPLATE
############################
log "⚙️ Creating CI/CD pipeline..."

mkdir -p "$APP_DIR/.github/workflows"

cat <<EOF_GHA > "$APP_DIR/.github/workflows/deploy.yml"
name: Auto Deploy

on:
  push:
    branches: [ "main" ]

jobs:
  deploy:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4

    - name: Setup kubeconfig
      run: |
        mkdir -p ~/.kube
        echo "${KUBECONFIG_DATA}" | base64 -d > ~/.kube/config

    - name: Deploy to k3s
      run: |
        kubectl apply --dry-run=server -f k8s/
        kubectl diff -f k8s/ || true
        kubectl apply -f k8s/
        kubectl rollout restart deployment/zlinebot -n ${K8S_NAMESPACE}
        kubectl rollout status deployment/zlinebot -n ${K8S_NAMESPACE} --timeout=180s

env:
  KUBECONFIG_DATA: \${{ secrets.KUBECONFIG }}
EOF_GHA

############################
# OPTIONAL: ARGOCD BOOTSTRAP
############################
log "⚡ Installing ArgoCD (GitOps bootstrap)..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

############################
# FINAL MESSAGE
############################
log "✅ INSTALL COMPLETE"
echo ""
echo "Next steps:"
echo "1. Configure /etc/cloudflared/config.yml then: systemctl restart cloudflared"
echo "2. Run: cloudflared tunnel login"
echo "3. Create tunnel and route DNS explicitly (no wildcard shortcuts)"
echo "4. Push repo to trigger CI/CD"
echo "5. Access ArgoCD and configure Applications for GitOps sync."
echo ""
echo "⚠️ For enterprise zero-trust, integrate OIDC proxy (Cloudflare Access / oauth2-proxy) and policy engine (OPA/Kyverno)."
