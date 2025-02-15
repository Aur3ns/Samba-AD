# Samba-AD-Tiering
scripts
#!/bin/bash

# Début de la configuration
echo "Début de la configuration des utilisateurs, des groupes, des politiques de mot de passe, et des unités d'organisation (OU)..." | tee -a /var/log/samba-setup.log

# Création des groupes selon le modèle Tiering
echo "Création des groupes selon le modèle Tiering..." | tee -a /var/log/samba-setup.log
samba-tool group add Group_ADMT0 | tee -a /var/log/samba-setup.log
samba-tool group add Group_ADMT1 | tee -a /var/log/samba-setup.log
samba-tool group add Group_ADMT2 | tee -a /var/log/samba-setup.log

# Création des utilisateurs et attributions aux groupes
echo "Création des utilisateurs et attribution aux groupes..." | tee -a /var/log/samba-setup.log
PASSWORD_HUGO=$(openssl rand -base64 16)
samba-tool user create Hugo_ADMT0 "$PASSWORD_HUGO" | tee -a /var/log/samba-setup.log
samba-tool group addmembers Group_ADMT0 Hugo_ADMT0 | tee -a /var/log/samba-setup.log

PASSWORD_VOLTAIRE=$(openssl rand -base64 16)
samba-tool user create Voltaire_ADMT1 "$PASSWORD_VOLTAIRE" | tee -a /var/log/samba-setup.log
samba-tool group addmembers Group_ADMT1 Voltaire_ADMT1 | tee -a /var/log/samba-setup.log

PASSWORD_CLEMENCEAU=$(openssl rand -base64 16)
samba-tool user create Clemenceau_ADMT2 "$PASSWORD_CLEMENCEAU" | tee -a /var/log/samba-setup.log
samba-tool group addmembers Group_ADMT2 Clemenceau_ADMT2 | tee -a /var/log/samba-setup.log

# Sauvegarde des mots de passe dans un fichier sécurisé
echo "Sauvegarde des mots de passe générés..." | tee -a /var/log/samba-setup.log
echo "Hugo_ADMT0 : $PASSWORD_HUGO" >> /root/northstar_users.txt
echo "Voltaire_ADMT1 : $PASSWORD_VOLTAIRE" >> /root/northstar_users.txt
echo "Clemenceau_ADMT2 : $PASSWORD_CLEMENCEAU" >> /root/northstar_users.txt
chmod 600 /root/northstar_users.txt  # Seul root peut accéder au fichier

# Application des politiques de mots de passe sécurisées
echo "Application des politiques de mots de passe sécurisées..." | tee -a /var/log/samba-setup.log
samba-tool domain passwordsettings set --complexity=on
samba-tool domain passwordsettings set --history-length=24
samba-tool domain passwordsettings set --min-pwd-age=1
samba-tool domain passwordsettings set --max-pwd-age=90
samba-tool domain passwordsettings set --min-pwd-length=14
samba-tool domain passwordsettings set --account-lockout-threshold=5
samba-tool domain passwordsettings set --account-lockout-duration=30
samba-tool domain passwordsettings set --reset-account-lockout-after=15

# Désactivation du compte invité
echo "Désactivation des comptes inutilisés..." | tee -a /var/log/samba-setup.log
samba-tool user disable guest
samba-tool user setpassword guest --random

# Création des unités d'organisation (OU)
echo "Création des unités d'organisation (OU)..." | tee -a /var/log/samba-setup.log
OU_LIST=(
    "OU=Group_ADMT0,DC=northstar,DC=com"
    "OU=Group_ADMT1,DC=northstar,DC=com"
    "OU=Group_ADMT2,DC=northstar,DC=com"
    "OU=Servers_T1,DC=northstar,DC=com"
)

for OU in "${OU_LIST[@]}"; do
    echo " Vérification de l'existence de $OU..." | tee -a /var/log/samba-setup.log
    samba-tool ou list | grep -q "$(echo $OU | cut -d',' -f1 | cut -d'=' -f2)"
    if [ $? -eq 0 ]; then
        echo " L'OU $OU existe déjà." | tee -a /var/log/samba-setup.log
    else
        echo " Création de l'OU $OU..." | tee -a /var/log/samba-setup.log
        samba-tool ou create "$OU"
        if [ $? -eq 0 ]; then
            echo " L'OU $OU a été créée avec succès." | tee -a /var/log/samba-setup.log
        else
            echo " Échec de la création de l'OU $OU." | tee -a /var/log/samba-setup.log
        fi
    fi
done

# Fin de la configuration
echo "Configuration complète de l'Active Directory terminée !" | tee -a /var/log/samba-setup.log

