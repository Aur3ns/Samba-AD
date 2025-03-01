#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification de la configuration Samba..." | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"

# Vérification de la configuration Samba
ERROR_LOG=$(samba-tool testparm 2>&1 | grep -E 'ERROR|WARNING')

if [ -n "$ERROR_LOG" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Problème détecté dans la configuration Samba !" | tee -a "$LOG_FILE"
    echo "Détails de l'erreur :" | tee -a "$LOG_FILE"
    echo "$ERROR_LOG" | tee -a "$LOG_FILE"
    echo "====================" | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration Samba valide." | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"

# Arrêt et désactivation des services non nécessaires
echo "$(date '+%Y-%m-%d %H:%M:%S') - Arrêt et désactivation des services smbd, nmbd et winbind..." | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"
systemctl stop smbd nmbd winbind
systemctl disable smbd nmbd winbind
systemctl enable samba-ad-dc
systemctl restart samba-ad-dc

# Suppression du fichier de configuration Samba par défaut s'il existe
echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression du fichier de configuration par défaut s'il existe." | tee -a "$LOG_FILE"
if [ -f /etc/samba/smb.conf ]; then
    rm /etc/samba/smb.conf
fi

# Définition du mot de passe administrateur Samba
export SAMBA_ADMIN_PASS='@fterTheB@ll33/'
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration du contrôleur de domaine Samba..." | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"

# Provisionnement du contrôleur de domaine Samba
samba-tool domain provision --use-rfc2307 --realm=NORTHSTAR.COM --domain=NORTHSTAR --adminpass="$SAMBA_ADMIN_PASS" --server-role=dc | tee -a "$LOG_FILE"

# Vérification du succès du provisionnement
if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Échec du provisionnement Samba !" | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Provisionnement du domaine Samba réussi !" | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"
