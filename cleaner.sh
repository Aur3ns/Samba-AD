#!/bin/bash
set -e
LOG_FILE="/var/log/samba-uninstall.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Démarrage de la désinstallation et du nettoyage" | tee -a "$LOG_FILE"

# Vérification des privilèges root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root." | tee -a "$LOG_FILE"
    exit 1
fi

echo "====================" | tee -a "$LOG_FILE"

# Arrêt des services liés à Samba et Kerberos
echo "$(date '+%Y-%m-%d %H:%M:%S') - Arrêt des services Samba et Kerberos..." | tee -a "$LOG_FILE"
systemctl stop samba-ad-dc smbd nmbd winbind krb5-kdc krb5-admin-server fail2ban osqueryd auditd sshd || true
systemctl disable samba-ad-dc smbd nmbd winbind krb5-kdc krb5-admin-server fail2ban osqueryd auditd sshd || true

# Suppression des utilisateurs et groupes créés
echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression des utilisateurs et groupes Samba..." | tee -a "$LOG_FILE"
samba-tool user delete Hugo_ADMT0 || true
samba-tool user delete Voltaire_ADMT1 || true
samba-tool user delete Clemenceau_ADMT2 || true

samba-tool group delete Group_ADMT0 || true
samba-tool group delete Group_ADMT1 || true
samba-tool group delete Group_ADMT2 || true

# Suppression des unités d'organisation (OU)
OU_LIST=(
    "OU=Group_ADMT0,OU=NS,DC=northstar,DC=com"
    "OU=Group_ADMT1,OU=NS,DC=northstar,DC=com"
    "OU=Group_ADMT2,OU=NS,DC=northstar,DC=com"
    "OU=Servers_T1,OU=NS,DC=northstar,DC=com"
    "OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
)
for OU in "${OU_LIST[@]}"; do
    samba-tool ou delete "$OU" || true
done

samba-tool ou delete "OU=NS,DC=northstar,DC=com" || true

# Suppression des fichiers de configuration
echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression des fichiers de configuration..." | tee -a "$LOG_FILE"
rm -rf /etc/samba /var/lib/samba /var/log/samba /etc/krb5.conf /var/lib/krb5kdc /etc/ssh/sshd_config /etc/osquery /root/kerberos_admin_pass.txt /root/northstar_users.txt
rm -rf /etc/fail2ban/jail.d/samba.conf /etc/fail2ban/filter.d/samba.conf

# Purge des paquets installés
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désinstallation des paquets Samba, Kerberos et outils de sécurité..." | tee -a "$LOG_FILE"
apt remove --purge -y samba-ad-dc krb5-user smbclient winbind auditd lynis audispd-plugins fail2ban ufw krb5-admin-server sudo dnsutils openssh-server osquery
apt autoremove -y
apt autoclean -y

# Suppression des certificats TLS
echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression des certificats TLS..." | tee -a "$LOG_FILE"
rm -f /etc/samba/private/tls.*

# Redémarrage du réseau et services critiques
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage des services réseau et SSH..." | tee -a "$LOG_FILE"
systemctl restart networking
systemctl restart sshd || true

# Affichage du statut final
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désinstallation complète de Samba et de ses composants." | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"
