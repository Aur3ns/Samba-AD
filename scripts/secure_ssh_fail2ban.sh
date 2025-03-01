#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"
SSH_CONFIG="/etc/ssh/sshd_config"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Démarrage de la sécurisation de SSH..." | tee -a "$LOG_FILE"
trap 'echo "Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# Vérification et installation d'OpenSSH Server si absent
if ! dpkg -l | grep -qw openssh-server; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - OpenSSH Server non installé. Installation en cours..." | tee -a "$LOG_FILE"
    apt update && apt install -y openssh-server libpam-winbind libnss-winbind sssd | tee -a "$LOG_FILE"
fi

# Configuration de SSH
if [ -f "$SSH_CONFIG" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de SSH..." | tee -a "$LOG_FILE"

    sed -i 's/#\?PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
    sed -i 's/#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSH_CONFIG"
    sed -i 's/#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
    sed -i 's/#\?X11Forwarding.*/X11Forwarding no/' "$SSH_CONFIG"
    sed -i 's/#\?AllowTcpForwarding.*/AllowTcpForwarding no/' "$SSH_CONFIG"
    sed -i 's/#\?ClientAliveCountMax.*/ClientAliveCountMax 2/' "$SSH_CONFIG"
    sed -i 's/#\?Compression.*/Compression no/' "$SSH_CONFIG"

    # Restriction de l'accès SSH aux utilisateurs d'un groupe spécifique
    grep -q "^AllowGroups" "$SSH_CONFIG" && sed -i 's/^AllowGroups.*/AllowGroups NORTHSTAR\\Group_ADMT0/' "$SSH_CONFIG" || echo "AllowGroups NORTHSTAR\\Group_ADMT0" >> "$SSH_CONFIG"

    # Redémarrage de SSH et vérification
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage du service SSH..." | tee -a "$LOG_FILE"
    systemctl restart sshd
    if systemctl is-active --quiet sshd; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - SSH sécurisé et actif." | tee -a "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : SSH n'a pas redémarré correctement !" | tee -a "$LOG_FILE"
        exit 1
    fi
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Fichier de configuration SSH introuvable !" | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Sécurisation de SSH terminée." | tee -a "$LOG_FILE"

# ========================
# Configuration de Fail2Ban
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de Fail2Ban pour protéger Samba..." | tee -a "$LOG_FILE"

# Création de la configuration spécifique pour Samba
cat <<EOF > /etc/fail2ban/jail.d/samba.conf
[samba]
enabled = true
filter = samba
action = iptables-multiport[name=Samba, port="139,445", protocol=tcp]
logpath = /var/log/samba/log.smbd
maxretry = 3
bantime = 600
findtime = 600
EOF

# Vérification et création du filtre pour Samba
if [ ! -f /etc/fail2ban/filter.d/samba.conf ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Création du filtre de détection pour Samba..." | tee -a "$LOG_FILE"
    cat <<EOF > /etc/fail2ban/filter.d/samba.conf
# Fail2Ban filter for Samba
[Definition]
failregex = .*smbd.*authentication.*failed.*
ignoreregex =
EOF
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Filtre Fail2Ban pour Samba déjà présent." | tee -a "$LOG_FILE"
fi

# Redémarrage de Fail2Ban et vérification
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage de Fail2Ban..." | tee -a "$LOG_FILE"
systemctl restart fail2ban

if systemctl is-active --quiet fail2ban; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Fail2Ban fonctionne correctement." | tee -a "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Fail2Ban n'a pas démarré !" | tee -a "$LOG_FILE"
    exit 1
fi

# Vérification des prisons Fail2Ban
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification des prisons Fail2Ban..." | tee -a "$LOG_FILE"
fail2ban-client status samba | tee -a "$LOG_FILE" || echo "Impossible de vérifier la prison Samba." | tee -a "$LOG_FILE"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Sécurisation SSH et configuration de Fail2Ban terminées." | tee -a "$LOG_FILE"
