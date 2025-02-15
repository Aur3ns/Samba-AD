#!/bin/bash

# Journal de suppression
LOG_FILE="/var/log/samba-setup.log"
echo "Début de la suppression et du nettoyage..." | tee -a $LOG_FILE

# Arrêt des services
echo "Arrêt des services Samba et osquery..." | tee -a $LOG_FILE
systemctl stop samba-ad-dc osqueryd | tee -a $LOG_FILE

# Suppression des services Samba et osquery du démarrage automatique
echo "Désactivation des services Samba et osquery..." | tee -a $LOG_FILE
systemctl disable samba-ad-dc osqueryd | tee -a $LOG_FILE

# Suppression des paquets installés
echo "Suppression des paquets Samba, osquery, et autres outils installés..." | tee -a $LOG_FILE
apt purge -y samba krb5-user smbclient winbind auditd audispd-plugins fail2ban ufw krb5-admin-server dnsutils | tee -a $LOG_FILE
apt purge -y ./osquery_5.9.1-1.linux_amd64.deb | tee -a $LOG_FILE

# Nettoyage des dépendances inutilisées
echo "Nettoyage des dépendances inutilisées..." | tee -a $LOG_FILE
apt autoremove -y | tee -a $LOG_FILE
apt autoclean | tee -a $LOG_FILE

# Suppression des fichiers de configuration
echo "Suppression des fichiers de configuration Samba et Kerberos..." | tee -a $LOG_FILE
rm -f /etc/krb5.conf | tee -a $LOG_FILE
rm -f /etc/samba/smb.conf | tee -a $LOG_FILE
rm -rf /var/lib/samba /var/cache/samba /etc/samba | tee -a $LOG_FILE

# Suppression des journaux générés par le script précédent
echo "Suppression des fichiers journaux générés..." | tee -a $LOG_FILE
rm -f /var/log/samba-setup.log | tee -a $LOG_FILE

# Fin de la suppression
echo "Suppression et nettoyage terminés !" | tee -a $LOG_FILE
