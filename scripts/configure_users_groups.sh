#!/bin/bash
# Script complet pour configurer les OU, créer des utilisateurs (sans groupes personnalisés)
# et appliquer les politiques de sécurité sur Samba AD.
#
# IMPORTANT : Sauvegardez vos données avant d'exécuter ce script en production.
#
# Log file
LOG_FILE="/var/log/samba-setup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de la configuration des OU, utilisateurs et politiques de sécurité..." | tee -a "$LOG_FILE"
trap 'echo "Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

#############################
# 1. Suppression automatique des OU existantes
#############################
echo "$(date '+%Y-%m-%d %H:%M:%S') - Recherche et suppression automatique des OU existantes (sauf l'OU principale NS)..." | tee -a "$LOG_FILE"

# La commande "samba-tool ou list" doit retourner une ligne par OU
samba-tool ou list | while read -r OU; do
    # Exclure l'OU principale NS
    if [[ "$OU" != "OU=NS,DC=northstar,DC=com" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression de l'OU : $OU" | tee -a "$LOG_FILE"
        samba-tool ou delete "$OU" | tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - OU $OU supprimée." | tee -a "$LOG_FILE"
    fi
done

echo "====================" | tee -a "$LOG_FILE"

#############################
# 2. Création des OU
#############################
# Création de l'OU principale "NS"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création de l'OU principale NS..." | tee -a "$LOG_FILE"
samba-tool ou create "OU=NS,DC=northstar,DC=com" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - OU NS créée avec succès." | tee -a "$LOG_FILE"

# Définition d'un tableau des autres OU à recréer
OU_LIST=(
    "OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
    "OU=Group_ADMT0,OU=NS,DC=northstar,DC=com"
    "OU=Group_ADMT1,OU=NS,DC=northstar,DC=com"
    "OU=Group_ADMT2,OU=NS,DC=northstar,DC=com"
)

echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des autres OU..." | tee -a "$LOG_FILE"
for OU in "${OU_LIST[@]}"; do
    samba-tool ou create "$OU" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - OU $OU créée avec succès." | tee -a "$LOG_FILE"
done

echo "====================" | tee -a "$LOG_FILE"

#############################
# 3. Création des utilisateurs
#############################
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des utilisateurs..." | tee -a "$LOG_FILE"

# Liste des utilisateurs à créer
USERS=(
    "Hugo_ADMT0"
    "Voltaire_ADMT1"
    "Clemenceau_ADMT2"
)

# Fichier pour sauvegarder les identifiants générés
USER_FILE="/root/northstar_users.txt"
echo "" > "$USER_FILE"

for USER in "${USERS[@]}"; do
    PASSWORD=$(openssl rand -base64 16)
    samba-tool user create "$USER" "$PASSWORD" | tee -a "$LOG_FILE"
    # Les utilisateurs créés sont automatiquement ajoutés au groupe "Domain Users"
    echo "$USER : $PASSWORD" >> "$USER_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Utilisateur $USER créé avec mot de passe généré." | tee -a "$LOG_FILE"
done

chmod 600 "$USER_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Mots de passe des utilisateurs sauvegardés dans $USER_FILE." | tee -a "$LOG_FILE"

echo "====================" | tee -a "$LOG_FILE"

#############################
# 4. Application des politiques de sécurité (mots de passe)
#############################
echo "$(date '+%Y-%m-%d %H:%M:%S') - Application des politiques de mots de passe..." | tee -a "$LOG_FILE"

samba-tool domain passwordsettings set --complexity=on | tee -a "$LOG_FILE"
samba-tool domain passwordsettings set --history-length=24 | tee -a "$LOG_FILE"
samba-tool domain passwordsettings set --min-pwd-age=1 | tee -a "$LOG_FILE"
samba-tool domain passwordsettings set --max-pwd-age=90 | tee -a "$LOG_FILE"
samba-tool domain passwordsettings set --min-pwd-length=14 | tee -a "$LOG_FILE"
samba-tool domain passwordsettings set --account-lockout-threshold=5 | tee -a "$LOG_FILE"
samba-tool domain passwordsettings set --account-lockout-duration=30 | tee -a "$LOG_FILE"
samba-tool domain passwordsettings set --reset-account-lockout-after=15 | tee -a "$LOG_FILE"

echo "====================" | tee -a "$LOG_FILE"

#############################
# 5. Nettoyage final
#############################
echo "$(date '+%Y-%m-%d %H:%M:%S') - Nettoyage des paquets obsolètes..." | tee -a "$LOG_FILE"
apt autoremove -y | tee -a "$LOG_FILE"
apt autoclean -y | tee -a "$LOG_FILE"

echo "$(date '+%Y-%m-%d %H:%M:%S') - 🎉 Configuration des OU, utilisateurs et politiques de sécurité terminée avec succès !" | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"

