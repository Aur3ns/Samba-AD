# Variables de configuration
PACKAGES="samba krb5-user smbclient winbind auditd audispd-plugins fail2ban ufw krb5-admin-server"
LOG_FILE="/var/log/samba-setup.log"

# Début de l'installat
# Mise à jour du système et installation des paquets requis
echo "Mise à jour et installation des paquets nécessaires..." | tee -a $LOG_FILE
apt update && apt upgrade -y | tee -a $LOG_FILE
apt install -y $PACKAGES | tee -a $LOG_FILE
