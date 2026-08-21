#!/usr/bin/env bash
# Baseline hardening for a fresh Ubuntu/Debian VPS.
#
# Run as root on a NEW server, before the app goes on it. Doing this afterwards
# means downtime; doing it first costs nothing.
#
#   DEPLOY_USER=deploy SSH_PUBKEY="ssh-ed25519 AAAA..." bash harden.sh
#
# IMPORTANT: this disables password SSH login. Open a SECOND terminal and confirm
# you can log in as the new user BEFORE closing your current session. Locking
# yourself out of a server you do not physically control is unrecoverable.

set -euo pipefail

DEPLOY_USER="${DEPLOY_USER:-deploy}"
SSH_PUBKEY="${SSH_PUBKEY:?set SSH_PUBKEY to your public key}"
SWAP_SIZE="${SWAP_SIZE:-2G}"

log(){ printf '\n==> %s\n' "$*"; }

log "Updating packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get upgrade -y -qq

log "Installing fail2ban, ufw, unattended-upgrades"
apt-get install -y -qq ufw fail2ban unattended-upgrades

log "Creating ${DEPLOY_USER} with sudo and your key"
if ! id -u "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
  usermod -aG sudo "$DEPLOY_USER"
fi
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
echo "$SSH_PUBKEY" > "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"
chown "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh/authorized_keys"

log "Hardening sshd (key-only, no root login)"
cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'SSHD'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
X11Forwarding no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
SSHD
sshd -t   # refuse to reload a config that would lock us out
systemctl reload ssh 2>/dev/null || systemctl reload sshd

log "Firewall: deny inbound except SSH, HTTP, HTTPS"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

log "fail2ban on sshd"
cat > /etc/fail2ban/jail.d/sshd.local <<'F2B'
[sshd]
enabled  = true
maxretry = 4
findtime = 10m
bantime  = 1h
F2B
systemctl enable --now fail2ban
systemctl restart fail2ban

log "Unattended security upgrades"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AUTO'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
AUTO

# A 1-2 GB box OOMs during `npm ci` or a Docker build without swap. Swap is not a
# substitute for RAM — it is headroom so a spike degrades instead of killing.
if ! swapon --show | grep -q .; then
  log "Adding ${SWAP_SIZE} swap"
  fallocate -l "$SWAP_SIZE" /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10 >/dev/null
  grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
fi

log "Timezone to UTC"
timedatectl set-timezone UTC

log "Docker with log rotation set globally"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
install -d /etc/docker
cat > /etc/docker/daemon.json <<'DJ'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
DJ
usermod -aG docker "$DEPLOY_USER"
systemctl enable --now docker
systemctl restart docker

cat <<DONE

==> Done. Verify NOW, in a second terminal, before closing this session:

      ssh ${DEPLOY_USER}@<this-host> 'echo ok'

    Then confirm nothing unexpected is listening publicly:

      ss -tlnp        # expect only 22, 80, 443
      ufw status
      swapon --show

DONE
