#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de la configuration des utilisateurs, groupes et politiques de sécurité..." | tee -a "$LOG_FILE"
trap 'echo "Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# ========================
# 🚨 Suppression des OUs et groupes existants
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression des OUs et groupes existants..." | tee -a "$LOG_FILE"

# Liste des OUs à supprimer
OU_LIST=(
    "OU=Group_ADMT0,OU=NS,DC=northstar,DC=com"
    "OU=Group_ADMT1,OU=NS,DC=northstar,DC=com"
    "OU=Group_ADMT2,OU=NS,DC=northstar,DC=com"
    "OU=Servers_T1,OU=NS,DC=northstar,DC=com"
    "OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
    "OU=NS,DC=northstar,DC=com"
)

# Suppression des utilisateurs
USERS=(
    "Hugo_ADMT0"
    "Voltaire_ADMT1"
    "Clemenceau_ADMT2"
)

for USER in "${USERS[@]}"; do
    if samba-tool user show "$USER" > /dev/null 2>&1; then
        samba-tool user delete "$USER" | tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Utilisateur $USER supprimé." | tee -a "$LOG_FILE"
    fi
done

# Suppression des groupes
GROUPS=("Group_ADMT0" "Group_ADMT1" "Group_ADMT2")

for GROUP in "${GROUPS[@]}"; do
    if samba-tool group list | grep -q "$GROUP"; then
        samba-tool group delete "$GROUP" | tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Groupe $GROUP supprimé." | tee -a "$LOG_FILE"
    fi
done

# Suppression des OUs (de bas en haut)
for ((i=${#OU_LIST[@]}-1; i>=0; i--)); do
    OU="${OU_LIST[i]}"
    OU_NAME=$(echo "$OU" | cut -d',' -f1 | cut -d'=' -f2)

    if samba-tool ou list | grep -q "$OU_NAME"; then
        samba-tool ou delete "$OU" | tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - OU $OU supprimée." | tee -a "$LOG_FILE"
    fi
done

echo "====================" | tee -a "$LOG_FILE"

# ========================
# 📌 Création de l'OU principale "NS"
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création de l'OU principale NS..." | tee -a "$LOG_FILE"

samba-tool ou create "OU=NS,DC=northstar,DC=com" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - OU NS créée avec succès." | tee -a "$LOG_FILE"

# ========================
# 📌 Création des autres OUs
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des unités d'organisation (OU)..." | tee -a "$LOG_FILE"

for OU in "${OU_LIST[@]:0:5}"; do  # On exclut l'OU "NS" qui a déjà été créée
    samba-tool ou create "$OU" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - OU $OU créée avec succès." | tee -a "$LOG_FILE"
done

echo "====================" | tee -a "$LOG_FILE"

# ========================
# 📌 Création des groupes
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des groupes..." | tee -a "$LOG_FILE"

for GROUP in "${GROUPS[@]}"; do
    samba-tool group add "$GROUP" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Groupe $GROUP créé avec succès." | tee -a "$LOG_FILE"
done

echo "====================" | tee -a "$LOG_FILE"

# ========================
# 📌 Création des utilisateurs et affectation aux groupes
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des utilisateurs et attribution aux groupes..." | tee -a "$LOG_FILE"

echo "" > /root/northstar_users.txt

for user in "${USERS[@]}"; do
    USERNAME=$(echo "$user" | cut -d':' -f1)
    GROUPNAME="Group_${USERNAME#*_}"  # Récupère la partie après "ADMT"

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
# 📌 Application des politiques de sécurité
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
# 📌 Nettoyage final
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Nettoyage des paquets obsolètes..." | tee -a "$LOG_FILE"
apt autoremove -y
apt autoclean -y

echo "$(date '+%Y-%m-%d %H:%M:%S') - 🎉 Configuration des utilisateurs et groupes terminée avec succès !" | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"
