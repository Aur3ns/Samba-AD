#!/bin/bash

LOG_FILE="/var/log/secure_ssh_fail2ban.log"
SSH_CONFIG="/etc/ssh/sshd_config"
FAIL2BAN_JAIL="/etc/fail2ban/jail.local"
SAMBA_FILTER="/etc/fail2ban/filter.d/samba.conf"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 🚀 Démarrage de la sécurisation de SSH et de Fail2Ban..." | tee -a "$LOG_FILE"
trap 'echo "❌ Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR
echo "====================" | tee -a "$LOG_FILE"

# ========================
# 🔧 Configuration de SSH
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔧 Configuration de SSH..." | tee -a "$LOG_FILE"
if [ -f "$SSH_CONFIG" ]; then
    sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
    sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONFIG"
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
    sed -i 's/#\?X11Forwarding.*/X11Forwarding no/' "$SSH_CONFIG"
    sed -i 's/#\?AllowTcpForwarding.*/AllowTcpForwarding no/' "$SSH_CONFIG"
    sed -i 's/#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSH_CONFIG"
    sed -i 's/#\?Compression.*/Compression no/' "$SSH_CONFIG"

    echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔄 Redémarrage du service SSH..." | tee -a "$LOG_FILE"
    systemctl restart sshd
    if systemctl is-active --quiet sshd; then
        echo "✅ SSH sécurisé et actif." | tee -a "$LOG_FILE"
    else
        echo "❌ Erreur : SSH n'a pas redémarré correctement !" | tee -a "$LOG_FILE"
        exit 1
    fi
else
    echo "❌ Erreur : Fichier de configuration SSH introuvable !" | tee -a "$LOG_FILE"
    exit 1
fi

echo "✅ Sécurisation de SSH terminée." | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"

# ========================
# 🔍 Vérification de Fail2Ban
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔍 Vérification et installation de Fail2Ban..." | tee -a "$LOG_FILE"
if ! command -v fail2ban-server &> /dev/null; then
    echo "⚠️ Fail2Ban non installé. Installation en cours..." | tee -a "$LOG_FILE"
    apt update && apt install -y fail2ban
fi

# Création du répertoire de socket s'il n'existe pas
if [ ! -d "/var/run/fail2ban" ]; then
    echo "⚠️ Création du répertoire /var/run/fail2ban/..." | tee -a "$LOG_FILE"
    mkdir -p /var/run/fail2ban
    chown fail2ban:fail2ban /var/run/fail2ban
fi

# ========================
# ⚙️ Configuration de Fail2Ban
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - ⚙️ Configuration de Fail2Ban..." | tee -a "$LOG_FILE"

# Configuration principale Fail2Ban (support systemd pour logs)
cat <<EOF > "$FAIL2BAN_JAIL"
[DEFAULT]
backend = systemd
bantime = 10m
findtime = 10m
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = %(syslog_authpriv)s
EOF

# ========================
# 🔍 Correction du Filtre Fail2Ban pour Samba
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔧 Vérification et correction du filtre Samba..." | tee -a "$LOG_FILE"

cat <<EOF > "$SAMBA_FILTER"
[Definition]
failregex = .*smbd.*NT_STATUS_LOGON_FAILURE.*
ignoreregex =
EOF

# ========================
# 🔄 Redémarrage de Fail2Ban
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔄 Redémarrage de Fail2Ban..." | tee -a "$LOG_FILE"
systemctl restart fail2ban
systemctl enable fail2ban

if systemctl is-active --quiet fail2ban; then
    echo "✅ Fail2Ban fonctionne correctement." | tee -a "$LOG_FILE"
else
    echo "❌ Erreur : Fail2Ban ne semble pas fonctionner correctement. Vérifie /var/run/fail2ban/fail2ban.sock." | tee -a "$LOG_FILE"
    exit 1
fi

# ========================
# 🔍 Vérification de Fail2Ban avec fail2ban-client
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔍 Vérification de Fail2Ban avec fail2ban-client..." | tee -a "$LOG_FILE"

fail2ban-client status sshd | tee -a "$LOG_FILE" || echo "⚠️ Impossible de vérifier la prison SSH." | tee -a "$LOG_FILE"
fail2ban-client status samba | tee -a "$LOG_FILE" || echo "⚠️ Impossible de vérifier la prison Samba." | tee -a "$LOG_FILE"

# ========================
# 🔍 Vérification des logs Samba
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔍 Vérification des logs Samba pour NT_STATUS_LOGON_FAILURE..." | tee -a "$LOG_FILE"
if grep -qi "NT_STATUS_LOGON_FAILURE" /var/log/samba/log.smbd; then
    echo "✅ Des échecs de connexion Samba sont bien détectés dans les logs." | tee -a "$LOG_FILE"
else
    echo "⚠️ Aucun log NT_STATUS_LOGON_FAILURE trouvé. Vérification de la configuration Samba..." | tee -a "$LOG_FILE"
    
    LOG_LEVEL=$(testparm -s | grep "log level" | awk '{print $3}')
    if [[ -z "$LOG_LEVEL" || "$LOG_LEVEL" -lt 3 ]]; then
        echo "⚠️ Augmentation du niveau de logs Samba à 3..." | tee -a "$LOG_FILE"
        sed -i 's/^log level.*/log level = 3/' /etc/samba/smb.conf
        systemctl restart smbd
    fi
fi

echo "✅ Sécurisation SSH et configuration de Fail2Ban terminées." | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"
