#!/bin/bash

# Début de l’installation
echo "Mise à jour et installation des paquets nécessaires..." | tee -a /var/log/samba-setup.log
apt update && apt upgrade -y | tee -a /var/log/samba-setup.log
apt install -y samba krb5-user smbclient winbind auditd audispd-plugins fail2ban ufw krb5-admin-server dnsutils | tee -a /var/log/samba-setup.log

# Arrêt et désactivation des services
echo "Arrêt et désactivation des services smbd, nmbd et winbind..." | tee -a /var/log/samba-setup.log
systemctl stop smbd nmbd winbind | tee -a /var/log/samba-setup.log
systemctl disable smbd nmbd winbind | tee -a /var/log/samba-setup.log

# Configuration du contrôleur de domaine Samba
echo "Configuration du contrôleur de domaine Samba..." | tee -a /var/log/samba-setup.log
samba-tool domain provision --use-rfc2307 --realm=NORTHSTAR.COM --domain=NORTHSTAR --adminpass=@fterTheB@ll33/ --server-role=dc | tee -a /var/log/samba-setup.log

# Vérification et redémarrage des services Samba
echo "Redémarrage des services Samba..." | tee -a /var/log/samba-setup.log
systemctl start samba-ad-dc | tee -a /var/log/samba-setup.log
systemctl enable samba-ad-dc | tee -a /var/log/samba-setup.log

# Fin de l’installation
echo "Installation et configuration de Samba terminées !" | tee -a /var/log/samba-setup.log
