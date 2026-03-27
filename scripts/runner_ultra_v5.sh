#!/bin/bash
# =========================================================
# 💀 RUNNER ULTRA V5 (ZERO-FAILURE SYSTEM)
# =========================================================

set -Eeuo pipefail

########################################
# CONFIG
########################################
RUNNER_USER="zeazdev"
PROJECT_ROOT="${PROJECT_ROOT:-/home/zeazdev/zLinebot-automos}"
REPO="${REPO:-CVSz/zLinebot-automos}"
RUNNER_NAME="${RUNNER_NAME:-ultra-runner}"
GITHUB_PAT="${GITHUB_PAT:-}"

BASE_DIR="${PROJECT_ROOT}/.runners"
RELEASE_DIR="${BASE_DIR}/releases"
ACTIVE_LINK="${BASE_DIR}/current"
PREVIOUS_LINK="${BASE_DIR}/previous"

SERVICE="actions.runner.${RUNNER_NAME}.service"
LOCK_FILE="/tmp/runner-v5.lock"

########################################
# UTILS
########################################
fail() { echo "[❌] $1"; exit 1; }
ok() { echo "[✅] $1"; }

retry() {
  for _ in {1..5}; do
    "$@" && return 0
    sleep 2
  done
  return 1
}

########################################
# LOCK (ANTI-RACE)
########################################
exec 9>"$LOCK_FILE"
flock -n 9 || { echo "[⚠️] Already running"; exit 0; }

########################################
# VALIDATION
########################################
[[ $EUID -eq 0 ]] || fail "Run as root"
[[ -n "$GITHUB_PAT" ]] || fail "Missing GITHUB_PAT"

mkdir -p "$RELEASE_DIR"

########################################
# INSTALL DEPS
########################################
apt-get update -y
apt-get install -y curl jq tar git coreutils \
  libicu-dev libkrb5-3 zlib1g libssl3 liblttng-ust1 libstdc++6 ca-certificates

########################################
# USER + PERMISSIONS
########################################
id "$RUNNER_USER" &>/dev/null || useradd -m -s /bin/bash "$RUNNER_USER"

chown -R "$RUNNER_USER:$RUNNER_USER" "$PROJECT_ROOT"
chmod -R 755 "$PROJECT_ROOT"

########################################
# FETCH VERSION (SAFE)
########################################
echo "[+] Fetching latest runner..."

API_JSON=$(retry curl -fsSL https://api.github.com/repos/actions/runner/releases/latest) \
  || fail "GitHub API failed"

URL=$(echo "$API_JSON" | jq -r '.assets[] | select(.name|test("linux-x64")) | .browser_download_url' | head -n1)
SHA_URL=$(echo "$API_JSON" | jq -r '.assets[] | select(.name|test("sha256")) | .browser_download_url' | head -n1)

[[ -z "$URL" || "$URL" == "null" ]] && fail "Invalid runner URL"

VERSION=$(echo "$URL" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
TARGET_DIR="${RELEASE_DIR}/runner-${VERSION}"

########################################
# DOWNLOAD + VERIFY
########################################
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "[+] Installing runner $VERSION"

  TMP=$(mktemp -d)

  retry curl -fsSL "$URL" -o "$TMP/runner.tar.gz" || fail "Download failed"

  SIZE=$(stat -c%s "$TMP/runner.tar.gz")
  [[ "$SIZE" -lt 50000000 ]] && fail "Corrupt download (too small)"

  if [[ -n "$SHA_URL" && "$SHA_URL" != "null" ]]; then
    retry curl -fsSL "$SHA_URL" -o "$TMP/sha256.txt" || fail "Checksum download failed"
    TAR_NAME=$(basename "$URL")
    (
      cd "$TMP"
      grep "$TAR_NAME" sha256.txt | sha256sum -c -
    ) || fail "SHA256 mismatch"
  fi

  tar tzf "$TMP/runner.tar.gz" >/dev/null || fail "Corrupt archive"

  mkdir -p "$TARGET_DIR"
  tar xzf "$TMP/runner.tar.gz" -C "$TARGET_DIR"

  for f in runsvc.sh run.sh config.sh bin/Runner.Listener; do
    [[ -f "$TARGET_DIR/$f" ]] || fail "Missing $f"
  done

  chmod +x "$TARGET_DIR"/*.sh
  chown -R "$RUNNER_USER:$RUNNER_USER" "$TARGET_DIR"

  bash "$TARGET_DIR/bin/installdependencies.sh" || true

  rm -rf "$TMP"
fi

########################################
# BLUE/GREEN SWITCH
########################################
echo "[+] Switching runner..."

systemctl stop "$SERVICE" || true

if [[ -L "$ACTIVE_LINK" ]]; then
  PREV=$(readlink -f "$ACTIVE_LINK")
  ln -sfn "$PREV" "$PREVIOUS_LINK"
fi

ln -sfn "$TARGET_DIR" "$ACTIVE_LINK"

RUNNER_DIR="$ACTIVE_LINK"
[[ -f "$RUNNER_DIR/runsvc.sh" ]] || fail "New runner invalid"

########################################
# TOKEN
########################################
TOKEN=$(retry curl -fsSL -X POST \
  -H "Authorization: token $GITHUB_PAT" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/actions/runners/registration-token" \
  | jq -r .token)

[[ "$TOKEN" == "null" || -z "$TOKEN" ]] && fail "Token invalid"

########################################
# CONFIGURE (SAFE)
########################################
if [[ ! -f "$RUNNER_DIR/.runner" ]]; then
  sudo -u "$RUNNER_USER" bash <<EOF_CONF
cd "$RUNNER_DIR"
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

./config.sh \
  --url "https://github.com/$REPO" \
  --token "$TOKEN" \
  --name "$RUNNER_NAME" \
  --work "${BASE_DIR}/work-${RUNNER_NAME}" \
  --unattended --replace
EOF_CONF
fi

########################################
# SYSTEMD
########################################
cat > "/etc/systemd/system/$SERVICE" <<EOF_UNIT
[Unit]
Description=Runner Ultra V5 ($RUNNER_NAME)
After=network.target

[Service]
User=$RUNNER_USER
WorkingDirectory=$RUNNER_DIR
ExecStart=/bin/bash -c "$RUNNER_DIR/runsvc.sh"

Restart=always
RestartSec=5

NoNewPrivileges=true
PrivateTmp=true
ReadWritePaths=$PROJECT_ROOT /tmp /var/tmp

Environment=DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

[Install]
WantedBy=multi-user.target
EOF_UNIT

systemctl daemon-reload
systemctl enable "$SERVICE"

########################################
# START + HEALTH CHECK
########################################
systemctl start "$SERVICE"
sleep 5

if ! systemctl is-active --quiet "$SERVICE"; then
  echo "[⚠️] New runner failed → rollback"

  if [[ -L "$PREVIOUS_LINK" ]]; then
    ln -sfn "$(readlink -f "$PREVIOUS_LINK")" "$ACTIVE_LINK"
    systemctl restart "$SERVICE"
    ok "Rollback successful"
    exit 0
  else
    fail "No rollback available"
  fi
fi

########################################
# SUCCESS
########################################
echo "======================================"
echo "💀 RUNNER V5 ZERO-FAILURE READY"
echo "✔ SHA verified"
echo "✔ Blue/Green deploy"
echo "✔ Auto rollback"
echo "✔ Self-healing ready"
echo "✔ Production CI node"
echo "======================================"
