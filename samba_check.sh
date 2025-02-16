#!/bin/bash

LOGFILE="/var/log/samba_diagnostic.log"
echo "============================" > $LOGFILE
echo "$(date '+%Y-%m-%d %H:%M:%S') - Début du diagnostic Samba" >> $LOGFILE
echo "============================" >> $LOGFILE

check_file() {
    if [ -f "$1" ]; then
        echo "[OK] Le fichier $1 existe." | tee -a $LOGFILE
    else
        echo "[ERREUR] Le fichier $1 est manquant !" | tee -a $LOGFILE
    fi
}

check_service() {
    systemctl is-active --quiet $1
    if [ $? -eq 0 ]; then
        echo "[OK] Le service $1 est actif." | tee -a $LOGFILE
    else
        echo "[ERREUR] Le service $1 n'est pas actif !" | tee -a $LOGFILE
    fi
}

# Vérification des fichiers essentiels
echo "Vérification des fichiers essentiels..." | tee -a $LOGFILE
check_file "/etc/samba/smb.conf"
check_file "/var/lib/samba/private/secrets.ldb"
check_file "/var/lib/samba/private/sam.ldb"
check_file "/var/log/samba/log.smbd"

# Vérification des services Samba
echo "Vérification des services Samba..." | tee -a $LOGFILE
check_service "smbd"
check_service "nmbd"
check_service "winbind"
check_service "samba-ad-dc"

# Vérification de la configuration Samba
echo "Vérification de la configuration Samba avec testparm..." | tee -a $LOGFILE
testparm -s 2>&1 | tee -a $LOGFILE

# Vérification de la base de données Samba
echo "Vérification de la base de données Samba avec samba-tool dbcheck..." | tee -a $LOGFILE
samba-tool dbcheck --cross-ncs --fix 2>&1 | tee -a $LOGFILE

# Vérification des utilisateurs et groupes
echo "Vérification des utilisateurs et des groupes Samba..." | tee -a $LOGFILE
samba-tool user list 2>&1 | tee -a $LOGFILE
samba-tool group list 2>&1 | tee -a $LOGFILE

# Résumé du diagnostic
echo "============================" | tee -a $LOGFILE
echo "$(date '+%Y-%m-%d %H:%M:%S') - Fin du diagnostic Samba" | tee -a $LOGFILE
echo "============================" | tee -a $LOGFILE

echo "Le diagnostic est terminé. Consultez le fichier de log : $LOGFILE"
