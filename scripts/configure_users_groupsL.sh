#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de la configuration des utilisateurs, groupes et politiques de sécurité..." | tee -a "$LOG_FILE"
trap 'echo "Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Création des groupes
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des groupes selon le modèle Tiering..." | tee -a "$LOG_FILE"

samba-tool group add Group_ADMT0 | tee -a "$LOG_FILE"
samba-tool group add Group_ADMT1 | tee -a "$LOG_FILE"
samba-tool group add Group_ADMT2 | tee -a "$LOG_FILE"

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Création des unités d'organisation (OU)
# ========================
OU_LIST=(
    "OU=Group_ADMT0,OU=NS,DC=northstar,DC=com"
    "OU=Group_ADMT1,OU=NS,DC=northstar,DC=com"
    "OU=Group_ADMT2,OU=NS,DC=northstar,DC=com"
    "OU=Servers_T1,OU=NS,DC=northstar,DC=com"
    "OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
)

echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des unités d'organisation (OU)..." | tee -a "$LOG_FILE"

for OU in "${OU_LIST[@]}"; do
    if samba-tool ou list | grep -q "$(echo $OU | cut -d',' -f1 | cut -d'=' -f2)"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - L'OU $OU existe déjà." | tee -a "$LOG_FILE"
    else
        samba-tool ou create "$OU" | tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - OU $OU créé avec succès." | tee -a "$LOG_FILE"
    fi
done

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Création des utilisateurs et affectation aux groupes
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des utilisateurs et attribution aux groupes..." | tee -a "$LOG_FILE"

USERS=(
    "Hugo_ADMT0:Group_ADMT0"
    "Voltaire_ADMT1:Group_ADMT1"
    "Clemenceau_ADMT2:Group_ADMT2"
)

echo "" > /root/northstar_users.txt

for user in "${USERS[@]}"; do
    USERNAME=$(echo "$user" | cut -d':' -f1)
    GROUPNAME=$(echo "$user" | cut -d':' -f2)
    
    PASSWORD=$(openssl rand -base64 16)
    samba-tool user create "$USERNAME" "$PASSWORD" | tee -a "$LOG_FILE"
    samba-tool group addmembers "$GROUPNAME" "$USERNAME" | tee -a "$LOG_FILE"

    echo "$USERNAME : $PASSWORD" >> /root/northstar_users.txt
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Utilisateur $USERNAME créé avec mot de passe généré." | tee -a "$LOG_FILE"
done

chmod 600 /root/northstar_users.txt
echo "$(date '+%Y-%m-%d %H:%M:%S') - Mots de passe des utilisateurs sauvegardés dans /root/northstar_users.txt." | tee -a "$LOG_FILE"

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Application des politiques de mots de passe sécurisées
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Application des politiques de mots de passe..." | tee -a "$LOG_FILE"

samba-tool domain passwordsettings set --complexity=on
samba-tool domain passwordsettings set --history-length=24
samba-tool domain passwordsettings set --min-pwd-age=1
samba-tool domain passwordsettings set --max-pwd-age=90
samba-tool domain passwordsettings set --min-pwd-length=14
samba-tool domain passwordsettings set --account-lockout-threshold=5
samba-tool domain passwordsettings set --account-lockout-duration=30
samba-tool domain passwordsettings set --reset-account-lockout-after=15

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Désactivation des comptes inutilisés
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désactivation des comptes inutilisés..." | tee -a "$LOG_FILE"

if samba-tool user show guest > /dev/null 2>&1; then
    samba-tool user disable guest | tee -a "$LOG_FILE"
    samba-tool user setpassword guest --random | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Compte 'guest' désactivé avec succès." | tee -a "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Compte 'guest' introuvable ou déjà désactivé." | tee -a "$LOG_FILE"
fi

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Désactivation des groupes inutiles
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désactivation des groupes inutiles..." | tee -a "$LOG_FILE"

GROUPS_TO_DISABLE=(
    "Guests"
    "Domain Guests"
    "Print Operators"
    "Backup Operators"
    "IIS_IUSRS"
)

for GROUP in "${GROUPS_TO_DISABLE[@]}"; do
    if samba-tool group show "$GROUP" > /dev/null 2>&1; then
        MEMBERS=$(samba-tool group listmembers "$GROUP" 2>/dev/null)
        if [ -z "$MEMBERS" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Le groupe '$GROUP' est déjà vide." | tee -a "$LOG_FILE"
        else
            for MEMBER in $MEMBERS; do
                samba-tool group removemembers "$GROUP" "$MEMBER" | tee -a "$LOG_FILE"
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Membre '$MEMBER' supprimé du groupe '$GROUP'." | tee -a "$LOG_FILE"
            done
        fi
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Le groupe '$GROUP' n'existe pas." | tee -a "$LOG_FILE"
    fi
done

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Nettoyage final
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Nettoyage des paquets obsolètes..." | tee -a "$LOG_FILE"
apt autoremove -y
apt autoclean -y

echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration des utilisateurs et groupes terminée avec succès !" | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"
