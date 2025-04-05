#!/bin/bash
# Script complet pour configurer les OU, créer des utilisateurs répartis dans des OU spécifiques
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
# 1. Suppression automatique des OU existantes (sauf l'OU principale NS)
#############################
echo "$(date '+%Y-%m-%d %H:%M:%S') - Recherche et suppression automatique des OU existantes (sauf l'OU principale NS)..." | tee -a "$LOG_FILE"

# On liste les OU à partir du DN racine
samba-tool ou list "DC=northstar,DC=com" | while read -r OU; do
    if [[ "$OU" != "OU=NS,DC=northstar,DC=com" && -n "$OU" ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression de l'OU : $OU" | tee -a "$LOG_FILE"
        samba-tool ou delete "$OU" | tee -a "$LOG_FILE"
        echo "$(date '+%Y-%m-%d %H:%M:%S') - OU $OU supprimée." | tee -a "$LOG_FILE"
    fi
done

echo "====================" | tee -a "$LOG_FILE"

#############################
# 2. Création des OU
#############################
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création de l'OU principale NS..." | tee -a "$LOG_FILE"
samba-tool ou create "OU=NS,DC=northstar,DC=com" 2>/dev/null || echo "OU NS existe déjà" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - OU NS créée ou déjà existante." | tee -a "$LOG_FILE"

# Création des OU parents indispensables
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des OU parent (Workstations et Users)..." | tee -a "$LOG_FILE"
samba-tool ou create "OU=Workstations,OU=NS,DC=northstar,DC=com" 2>/dev/null || echo "OU Workstations existe déjà" | tee -a "$LOG_FILE"
samba-tool ou create "OU=Users,OU=NS,DC=northstar,DC=com" 2>/dev/null || echo "OU Users existe déjà" | tee -a "$LOG_FILE"

# Liste des sous-OU à créer sous les conteneurs Workstations et Users
OU_LIST=(
    "OU=UsersWorkstations,OU=Workstations,OU=NS,DC=northstar,DC=com"
    "OU=AdminWorkstations,OU=Workstations,OU=NS,DC=northstar,DC=com"
    "OU=Comptabilité,OU=Users,OU=NS,DC=northstar,DC=com"
    "OU=Finance,OU=Users,OU=NS,DC=northstar,DC=com"
    "OU=Administration,OU=Users,OU=NS,DC=northstar,DC=com"
)

echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des autres OU..." | tee -a "$LOG_FILE"
for OU in "${OU_LIST[@]}"; do
    samba-tool ou create "$OU" 2>/dev/null || echo "OU $OU existe déjà" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - OU $OU créée ou déjà existante." | tee -a "$LOG_FILE"
done

echo "====================" | tee -a "$LOG_FILE"

#############################
# 3. Création des utilisateurs répartis dans des OU spécifiques
#############################
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des utilisateurs répartis dans des OU spécifiques..." | tee -a "$LOG_FILE"

# Tableau associatif : chaque utilisateur est mappé à l'OU relative (sans les DC) dans laquelle il doit être créé
declare -A USERS_MAP
USERS_MAP["Victor_Hugo"]="OU=Comptabilité,OU=Users,OU=NS"
USERS_MAP["Jean_Delafontaine"]="OU=Finance,OU=Users,OU=NS"
USERS_MAP["George_Clemenceau"]="OU=Administration,OU=Users,OU=NS"

# Fichier pour sauvegarder les identifiants générés
USER_FILE="/root/northstar_users.txt"
echo "" > "$USER_FILE"

for USER in "${!USERS_MAP[@]}"; do
    PASSWORD=$(openssl rand -base64 16)
    OU_PATH=${USERS_MAP[$USER]}
    samba-tool user create "$USER" "$PASSWORD" --userou="$OU_PATH" | tee -a "$LOG_FILE"
    echo "$USER : $PASSWORD (OU: $OU_PATH)" >> "$USER_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Utilisateur $USER créé dans $OU_PATH avec mot de passe généré." | tee -a "$LOG_FILE"
done

chmod 600 "$USER_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Mots de passe des utilisateurs sauvegardés dans $USER_FILE." | tee -a "$LOG_FILE"

echo "====================" | tee -a "$LOG_FILE"

#############################
# 4. Application des politiques de sécurité (mots de passe)
#############################
echo "$(date '+%Y-%m-%d %H:%M:%S') - Application des politiques de mots de passe..." | tee -a "$LOG_FILE"

# Active la complexité du mot de passe (exige la présence de lettres majuscules, minuscules, chiffres et symboles)
samba-tool domain passwordsettings set --complexity=on | tee -a "$LOG_FILE"

# Définit l'historique des mots de passe à 24, empêchant ainsi la réutilisation des 24 derniers mots de passe
samba-tool domain passwordsettings set --history-length=24 | tee -a "$LOG_FILE"

# Définit l'âge minimum d'un mot de passe à 1 jour (l'utilisateur ne peut pas changer son mot de passe avant 1 jour)
samba-tool domain passwordsettings set --min-pwd-age=1 | tee -a "$LOG_FILE"

# Définit l'âge maximum d'un mot de passe à 90 jours (le mot de passe doit être changé au moins tous les 90 jours)
samba-tool domain passwordsettings set --max-pwd-age=90 | tee -a "$LOG_FILE"

# Définit la longueur minimale du mot de passe à 14 caractères
samba-tool domain passwordsettings set --min-pwd-length=14 | tee -a "$LOG_FILE"

# Définit le seuil de verrouillage du compte à 5 tentatives échouées (après 5 échecs, le compte est verrouillé)
samba-tool domain passwordsettings set --account-lockout-threshold=5 | tee -a "$LOG_FILE"

# Définit la durée du verrouillage du compte à 30 minutes
samba-tool domain passwordsettings set --account-lockout-duration=30 | tee -a "$LOG_FILE"

# Définit le délai de réinitialisation du compteur de verrouillage à 15 minutes (après 15 minutes, le compteur d'échecs est remis à zéro)
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
