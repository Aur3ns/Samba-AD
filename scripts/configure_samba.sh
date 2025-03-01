#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de la configuration de Samba..." | tee -a "$LOG_FILE"
trap 'echo "Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# Vérification de la configuration de Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification de la configuration Samba..." | tee -a "$LOG_FILE"
ERROR_LOG=$(samba-tool testparm 2>&1 | grep -E 'ERROR|WARNING')

if [ -n "$ERROR_LOG" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Problème détecté dans la configuration Samba !" | tee -a "$LOG_FILE"
    echo "$ERROR_LOG" | tee -a "$LOG_FILE"
    exit 1
fi
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration Samba valide." | tee -a "$LOG_FILE"

# Désactivation des services non nécessaires
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désactivation des services smbd, nmbd et winbind..." | tee -a "$LOG_FILE"
systemctl stop smbd nmbd winbind
systemctl disable smbd nmbd winbind
systemctl enable samba-ad-dc
systemctl restart samba-ad-dc

# Suppression de l'ancien fichier de configuration
echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression du fichier de configuration Samba existant..." | tee -a "$LOG_FILE"
[ -f /etc/samba/smb.conf ] && rm /etc/samba/smb.conf

# Provisioning du contrôleur de domaine Samba
export SAMBA_ADMIN_PASS='@fterTheB@ll33/'
echo "$(date '+%Y-%m-%d %H:%M:%S') - Provisioning du contrôleur de domaine Samba..." | tee -a "$LOG_FILE"
samba-tool domain provision --use-rfc2307 --realm=NORTHSTAR.COM --domain=NORTHSTAR --adminpass="$SAMBA_ADMIN_PASS" --server-role=dc | tee -a "$LOG_FILE"

# Vérification du succès du provisionnement
if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Échec du provisionnement Samba !" | tee -a "$LOG_FILE"
    exit 1
fi

# Génération des certificats TLS
echo "$(date '+%Y-%m-%d %H:%M:%S') - Génération des certificats TLS pour Samba..." | tee -a "$LOG_FILE"
mkdir -p /etc/samba/private
chmod 700 /etc/samba/private

openssl genrsa -out /etc/samba/private/tls-ca.key 2048
openssl req -x509 -new -nodes -key /etc/samba/private/tls-ca.key -sha256 -days 3650 \
    -out /etc/samba/private/tls-ca.crt -subj "/C=FR/ST=Paris/L=Paris/O=Northstar CA/OU=IT Department/CN=Northstar Root CA"

openssl genrsa -out /etc/samba/private/tls.key 2048
openssl req -new -key /etc/samba/private/tls.key -out /etc/samba/private/tls.csr -subj "/CN=NORTHSTAR.COM"

openssl x509 -req -in /etc/samba/private/tls.csr -CA /etc/samba/private/tls-ca.crt -CAkey /etc/samba/private/tls-ca.key \
    -CAcreateserial -out /etc/samba/private/tls.crt -days 365 -sha256

chmod 600 /etc/samba/private/tls.*

echo "$(date '+%Y-%m-%d %H:%M:%S') - Certificats TLS générés et protégés." | tee -a "$LOG_FILE"

# Configuration avancée de Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Application des configurations avancées de Samba..." | tee -a "$LOG_FILE"
cat <<EOF >> /etc/samba/smb.conf
[global]
    tls enabled = yes
    tls keyfile = /etc/samba/private/tls.key
    tls certfile = /etc/samba/private/tls.crt
    tls cafile = /etc/samba/private/tls-ca.crt
    ntlm auth = mschapv2-and-ntlmv2-only
    server min protocol = SMB2
    server max protocol = SMB3
    smb encrypt = required
    disable netbios = yes
    dns forwarder = 8.8.8.8
    restrict anonymous = 2
    ldap server require strong auth = yes
    log level = 3
    log file = /var/log/samba/log.%m
    max log size = 5000
    ldap timeout = 15
    smb ports = 445
    server signing = mandatory
    client signing = mandatory
    max smbd processes = 500
    allow unsafe cluster upgrade = no
    clustering = no

[sysvol]
    path = /var/lib/samba/sysvol
    read only = no
EOF

# Redémarrage des services Samba et vérification
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage de Samba..." | tee -a "$LOG_FILE"
systemctl restart samba-ad-dc

if systemctl status samba-ad-dc | grep -q "active (running)"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Samba est opérationnel." | tee -a "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Samba ne s'est pas démarré correctement." | tee -a "$LOG_FILE"
    exit 1
fi
