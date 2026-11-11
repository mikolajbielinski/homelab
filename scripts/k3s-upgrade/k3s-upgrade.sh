#!/usr/bin/env bash
# Upgrade single-node k3s to a given version, backing up the datastore first.
# See README.md in this directory for the full procedure.
#
# Usage (on the node): sudo ./k3s-upgrade.sh v1.35.10+k3s1
#
# Backup lands in /root/k3s-backup-<current version>/ and contains the SQLite
# datastore, the server token and the current k3s binary.
#
# Rollback:
#   systemctl stop k3s
#   rm -rf /var/lib/rancher/k3s/server/db && cp -a <backup>/db /var/lib/rancher/k3s/server/
#   cp -a <backup>/token /var/lib/rancher/k3s/server/token
#   cp -a <backup>/k3s-binary /usr/local/bin/k3s
#   systemctl start k3s
set -euo pipefail

# Flags k3s was originally installed with. The installer rewrites the systemd
# unit from these, so anything missing here is lost after the upgrade.
K3S_EXEC="server --disable-helm-controller"

SERVER_DIR=/var/lib/rancher/k3s/server

die() { echo "ERROR: $*" >&2; exit 1; }

[[ $# -eq 1 ]] || die "usage: $0 <version, e.g. v1.35.10+k3s1>"
TARGET="$1"
[[ "$TARGET" =~ ^v1\.([0-9]+)\.[0-9]+\+k3s[0-9]+$ ]] || die "invalid version: $TARGET"
TARGET_MINOR="${BASH_REMATCH[1]}"

[[ $EUID -eq 0 ]] || die "run as root (sudo)"

CURRENT="$(k3s --version | awk 'NR==1 {print $3}')"
[[ "$CURRENT" =~ ^v1\.([0-9]+)\. ]] || die "cannot parse current version: $CURRENT"
CURRENT_MINOR="${BASH_REMATCH[1]}"

[[ "$CURRENT" != "$TARGET" ]] || die "already on $TARGET"
(( TARGET_MINOR >= CURRENT_MINOR )) || die "downgrade is not supported ($CURRENT -> $TARGET), use the rollback steps"
(( TARGET_MINOR - CURRENT_MINOR <= 1 )) || die "k3s must be upgraded one minor at a time ($CURRENT -> $TARGET)"

BACKUP_DIR="/root/k3s-backup-$CURRENT"
[[ ! -e "$BACKUP_DIR" ]] || die "$BACKUP_DIR already exists, move it away first"

echo "==> Upgrading $CURRENT -> $TARGET"
echo "==> Backup: $BACKUP_DIR"
read -rp "Continue? [y/N] " answer
[[ "$answer" == [yY] ]] || die "aborted"

# Make sure k3s is running again if anything below fails.
trap 'echo "Upgrade failed, starting k3s back up" >&2; systemctl start k3s' ERR

echo "==> Stopping k3s (pods keep running)"
systemctl stop k3s

echo "==> Backing up datastore, token and binary"
mkdir -p "$BACKUP_DIR"
cp -a "$SERVER_DIR/db" "$SERVER_DIR/token" "$BACKUP_DIR/"
cp -a /usr/local/bin/k3s "$BACKUP_DIR/k3s-binary"
ls -la "$BACKUP_DIR" "$BACKUP_DIR/db"

echo "==> Installing $TARGET (restarts k3s)"
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$TARGET" sh -s - $K3S_EXEC

trap - ERR

echo "==> Waiting for the node to become Ready"
sleep 10
k3s kubectl wait node --all --for=condition=Ready --timeout=300s

echo "==> Done"
k3s --version | head -1
k3s kubectl get nodes -o wide
