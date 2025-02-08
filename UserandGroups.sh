#!/bin/bash
#Script pour créer les utilisateurs, leur attribuer leur groupe en fontion du tiering
#puis configure les politiques de mot de  passe et désactive le compte guest

# Variables de configuration
REALM="NORTHSTAR.COM"
DOMAIN="NORTHSTAR"
TIER_USERS=("Hugo_ADMT0" "Voltaire_ADMT1" "Clemenceau_ADMT2")
TIER_GROUPS=("Group_ADMT0" "Group_ADMT1" "Group_ADMT2")
LOG_FILE="/var/log/samba-setup.log"
RANDOM_PASS_LENGTH=16

# Début de l'installation
echo "Début de la configuration des utilisateurs et administrateurs de l'Active Directory..." | tee -a $LOG_FILE

# Création des groupes selon le modèle Tiering
echo "Création des groupes selon le modèle Tiering..." | tee -a $LOG_FILE
for group in "${TIER_GROUPS[@]}"; do
  samba-tool group add $group | tee -a $LOG_FILE
done

#Création des utilisateurs et attributions aux groupes de tier
echo "Création des utilisateurs et atttribution des groupes" | tee -a $LOG_FILE
for i in "${!TIER_USERS[@]}"; do
  PASSWORD=$(openssl rand -base64 $RANDOM_PASS_LENGTH)
  samba-tool user create "${TIER_USERS[$i]}" "$PASSWORD" | tee -a $LOG_FILE
  samba-tool group addmembers "${TIER_GROUPS[$i]}" "${TIER_USERS[$i]}" | tee -a $LOG_FILE
  samba-tool group list
  samba-tool user list
  sleep 5
  echo "Les utilisateurs du domaine northstar.com ont été crées. Consultez le fichier northstar_user.txt pour plus d'informations" | tee -a $LOG_FILE
  echo "${TIER_USERS[$i]} : $PASSWORD" >> /root/northstar_users.txt
  chmod 600 /root/northstar_users.txt #Seul l'utilisateur root peut accéder aux fichier
done

# Renforcement des politiques de mots de passe
echo "Application des politiques de mots de passe sécurisées..." | tee -a $LOG_FILE
samba-tool domain passwordsettings set --complexity=on
samba-tool domain passwordsettings set --history-length=24
samba-tool domain passwordsettings set --min-pwd-age=1
samba-tool domain passwordsettings set --max-pwd-age=90
samba-tool domain passwordsettings set --min-pwd-length=14
samba-tool domain passwordsettings set --account-lockout-threshold=5
samba-tool domain passwordsettings set --account-lockout-duration=30
samba-tool domain passwordsettings set --reset-account-lockout-after=15

# Désactivation du compte invité
echo "Désactivation des comptes inutilisés" | tee -a $LOG_FILE
samba-tool user disable guest
samba-tool user setpassword guest --random

