#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"

rm -f "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Démarrage de l'installation des paquets" | tee -a "$LOG_FILE"

apt update && apt upgrade -y | tee -a "$LOG_FILE"
apt install -y samba-ad-dc krb5-user smbclient winbind auditd lynis audispd-plugins fail2ban sudo ufw dnsutils openssh-server | tee -a "$LOG_FILE"

# Vérification des paquets installés
for pkg in samba-ad-dc krb5-user smbclient winbind auditd lynis audispd-plugins fail2ban sudo ufw dnsutils openssh-server; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Le paquet $pkg n'a pas été installé !" | tee -a "$LOG_FILE"
        exit 1
    fi
done

echo "$(date '+%Y-%m-%d %H:%M:%S') - Tous les paquets ont été installés avec succès !" | tee -a "$LOG_FILE"
