#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"
SSH_CONFIG="/etc/ssh/sshd_config"
FAIL2BAN_DIR="/etc/fail2ban"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Démarrage de la configuration de SSH, Samba et Fail2Ban..." | tee -a "$LOG_FILE"
trap 'echo " Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Configuration de SSH
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de SSH..." | tee -a "$LOG_FILE"

if [ -f "$SSH_CONFIG" ]; then
    sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
    sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONFIG"
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
    sed -i 's/#\?X11Forwarding.*/X11Forwarding no/' "$SSH_CONFIG"
    sed -i 's/#\?AllowTcpForwarding.*/AllowTcpForwarding no/' "$SSH_CONFIG"
    sed -i 's/#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSH_CONFIG"
    sed -i 's/#\?Compression.*/Compression no/' "$SSH_CONFIG"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage du service SSH..." | tee -a "$LOG_FILE"
    systemctl restart sshd
    echo " SSH sécurisé et actif." | tee -a "$LOG_FILE"
else
    echo " Erreur : Fichier de configuration SSH introuvable !" | tee -a "$LOG_FILE"
    exit 1
fi

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Installation et configuration de Fail2Ban
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification et installation de Fail2Ban..." | tee -a "$LOG_FILE"
apt update && apt install -y fail2ban

# Suppression des configurations précédentes de Fail2Ban sans toucher au smb.conf
echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression des configurations Fail2Ban existantes..." | tee -a "$LOG_FILE"
rm -f $FAIL2BAN_DIR/jail.d/*.conf
rm -f $FAIL2BAN_DIR/filter.d/*.conf

# Configuration Fail2Ban pour SSH
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de Fail2Ban pour SSH et Samba..." | tee -a "$LOG_FILE"

cat <<EOF > /etc/fail2ban/jail.d/sshd.conf
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(journal)s
maxretry = 3
bantime = 10m
EOF

# Configuration Fail2Ban pour Samba
cat <<EOF > /etc/fail2ban/jail.d/samba.conf
[samba]
enabled = true
filter = samba
port = 139,445
logpath = /var/log/samba/log.smbd
maxretry = 3
bantime = 10m
findtime = 10m
EOF

# Fichier de filtre Fail2Ban pour Samba
cat <<EOF > /etc/fail2ban/filter.d/samba.conf
[Definition]
failregex = .*smbd.*NT_STATUS_LOGON_FAILURE.*
ignoreregex =
EOF

# Redémarrage de Fail2Ban
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage de Fail2Ban..." | tee -a "$LOG_FILE"
systemctl restart fail2ban
systemctl enable fail2ban

if systemctl is-active --quiet fail2ban; then
    echo " Fail2Ban fonctionne correctement." | tee -a "$LOG_FILE"
else
    echo " Erreur : Fail2Ban ne semble pas fonctionner correctement. Vérifie /var/run/fail2ban/fail2ban.sock." | tee -a "$LOG_FILE"
    exit 1
fi

# Vérification des prisons Fail2Ban
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification des prisons Fail2Ban..." | tee -a "$LOG_FILE"
fail2ban-client status sshd | tee -a "$LOG_FILE"
fail2ban-client status samba | tee -a "$LOG_FILE"

echo "====================" | tee -a "$LOG_FILE"

echo " Sécurisation SSH et configuration de Fail2Ban terminées." | tee -a "$LOG_FILE"
