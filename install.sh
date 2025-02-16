#!/bin/bash

echo "$(date '+%Y-%m-%d %H:%M:%S') - Démarrage de l'installation et de la configuration" | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log


# Mise à jour et installation des paquets nécessaires
echo "$(date '+%Y-%m-%d %H:%M:%S') - Mise à jour et installation des paquets nécessaires..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
apt update && apt upgrade -y | tee -a /var/log/samba-setup.log
apt install -y samba krb5-user smbclient winbind auditd lynis audispd-plugins fail2ban ufw krb5-admin-server dnsutils iptables iptables-save | tee -a /var/log/samba-setup.log


# Vérification de l'installation des paquets
for pkg in samba krb5-user smbclient winbind auditd lynis audispd-plugins fail2ban ufw krb5-admin-server dnsutils iptables iptables-save; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Le paquet $pkg n'a pas été installé !" | tee -a /var/log/samba-setup.log
        echo "====================" | tee -a /var/log/samba-setup.log
        exit 1
    fi
done
echo "$(date '+%Y-%m-%d %H:%M:%S') - Tous les paquets ont été installés avec succès !" | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Configuration de Kerberos
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de Kerberos avec des options renforcées..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
cat <<EOF >/etc/krb5.conf
[libdefaults]
    default_realm = NORTHSTAR.COM
    dns_lookup_realm = false
    dns_lookup_kdc = true
    forwardable = true
    renewable = true
    rdns = false
    ticket_lifetime = 10h
    renew_lifetime = 7d
    default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
    default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
    permitted_enctypes = aes256-cts aes128-cts
EOF

# Vérification de la configuration Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification de la configuration Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
samba-tool testparm -v | grep 'Loaded services file OK'
if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Problème dans la configuration Samba !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    exit 1
fi
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration Samba valide." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log


# Arrêt et désactivation des services
echo "$(date '+%Y-%m-%d %H:%M:%S') - Arrêt et désactivation des services smbd, nmbd et winbind..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
systemctl stop smbd nmbd winbind | tee -a /var/log/samba-setup.log
systemctl disable smbd nmbd winbind | tee -a /var/log/samba-setup.log

# Configuration du contrôleur de domaine Samba
export SAMBA_ADMIN_PASS='@fterTheB@ll33/'
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration du contrôleur de domaine Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
samba-tool domain provision --use-rfc2307 --realm=NORTHSTAR.COM --domain=NORTHSTAR --adminpass="$SAMBA_ADMIN_PASS" --server-role=dc | tee -a /var/log/samba-setup.log

# Configuration avancée pour Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Durcissement des configurations Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
cat <<EOF >>/etc/samba/smb.conf
[global]
    tls enabled = yes
    tls keyfile = /etc/samba/private/tls.key
    tls certfile = /etc/samba/private/tls.crt
    tls cafile = /etc/samba/private/tls-ca.crt
    ntlm auth = mschapv2-and-ntlmv2-only
    server min protocol = SMB2
    server max protocol = SMB3
    smb encrypt = required
    disable netbios = yes
    restrict anonymous = 2
    ldap server require strong auth = yes
    log level = 3
    log file = /var/log/samba/log.%m
    max log size = 5000
    ldap timeout = 15a
    smb ports = 445
    server signing = mandatory
    client signing = mandatory
    max smbd processes = 500
    allow unsafe cluster upgrade = no
    clustering = no
    
    [sysvol]
    path = /var/lib/samba/sysvol
    read only = no
EOF

# Génération de l'Autorité de Certification (CA) et des certificats TLS
echo "$(date '+%Y-%m-%d %H:%M:%S') - Génération de l'Autorité de Certification (CA) et des certificats TLS..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# 1. Créer la clé privée pour l'autorité de certification (CA)
openssl genrsa -out /etc/samba/private/tls-ca.key 2048
# 2. Générer le certificat de l'autorité de certification (CA)
openssl req -x509 -new -nodes -key /etc/samba/private/tls-ca.key -sha256 -days 3650 \
    -out /etc/samba/private/tls-ca.crt -subj "/C=FR/ST=Paris/L=Paris/O=Northstar CA/OU=IT Department/CN=Northstar Root CA"

# 3. Générer une clé privée et une demande de signature de certificat (CSR) pour Samba
openssl genrsa -out /etc/samba/private/tls.key 2048
openssl req -new -key /etc/samba/private/tls.key -out /etc/samba/private/tls.csr -subj "/CN=NORTHSTAR.COM"

# 4. Signer le certificat de Samba avec l'autorité de certification (CA)
openssl x509 -req -in /etc/samba/private/tls.csr -CA /etc/samba/private/tls-ca.crt -CAkey /etc/samba/private/tls-ca.key \
    -CAcreateserial -out /etc/samba/private/tls.crt -days 365 -sha256

# Protection des certificats TLS
chmod 600 /etc/samba/private/tls.*
echo "$(date '+%Y-%m-%d %H:%M:%S') - Certificats TLS générés et protégés." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log


# Redémarrage des services Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage des services Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
systemctl restart samba-ad-dc | tee -a /var/log/samba-setup.log
systemctl enable samba-ad-dc | tee -a /var/log/samba-setup.log

# Vérification de la configuration Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Test de la configuration Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
testparm -s > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Problème dans smb.conf" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    exit 1
fi
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration Samba valide." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Téléchargement et installation de osquery
echo "$(date '+%Y-%m-%d %H:%M:%S') - Téléchargement et installation de osquery..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
wget https://pkg.osquery.io/deb/osquery_5.9.1-1.linux_amd64.deb | tee -a /var/log/samba-setup.log
dpkg -i osquery_5.9.1-1.linux_amd64.deb | tee -a /var/log/samba-setup.log
systemctl restart osqueryd | tee -a /var/log/samba-setup.log

# Configuration d'osquery
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration d'osquery..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
cat <<EOF > /etc/osquery/osquery.conf
{
    "options": {
        "logger_plugin": "filesystem",
        "logger_path": "/var/log/osquery",
        "disable_events": "false",
        "schedule_splay_percent": "10"
    },
    "schedule": {
        "kerberos_audit": {
            "query": "SELECT * FROM processes WHERE name LIKE '%krb%';",
            "interval": 60
        },
        "file_events": {
            "query": "SELECT * FROM file WHERE path LIKE '/etc/%' OR path LIKE '/var/lib/samba/private/%';",
            "interval": 60
        },
        "ssh_audit": {
            "query": "SELECT * FROM process_open_sockets WHERE family = '2' AND remote_address IS NOT NULL;",
            "interval": 60
        }
    }
}
EOF

systemctl enable osqueryd
systemctl restart osqueryd
if systemctl is-active --quiet osqueryd; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - osqueryd fonctionne !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : osqueryd n'a pas démarré !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Sécurisation de SSH
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de SSH..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
echo "AllowUsers admin" >> /etc/ssh/sshd_config

systemctl restart sshd
if systemctl is-active --quiet sshd; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - SSH est sécurisé et fonctionne !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : SSH n'a pas redémarré !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Configuration de Fail2Ban pour Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de Fail2Ban..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
cat <<EOF > /etc/fail2ban/jail.d/samba.conf
[samba]
enabled = true
filter = samba
action = iptables[name=Samba, port=445, protocol=tcp]
logpath = /var/log/samba/log.smbd
maxretry = 3
bantime = 600
EOF

systemctl restart fail2ban
if systemctl is-active --quiet fail2ban; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Fail2Ban fonctionne !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Fail2Ban n'a pas démarré !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Configuration d'auditd pour surveiller Samba et Kerberos
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration d'auditd..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
cat <<EOF > /etc/audit/rules.d/audit.rules
-w /etc/ -p wa -k etc-changes
-w /var/log/samba/ -p wa -k samba-logs
-w /var/log/audit/ -p wa -k audit-logs
-w /var/lib/samba/private/secrets.ldb -p r -k kerberos-secrets
-a always,exit -F arch=b64 -S execve -F euid=0 -k root-commands
EOF

systemctl restart auditd
if systemctl is-active --quiet auditd; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - auditd fonctionne et surveille Samba et Kerberos !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : auditd n'a pas redémarré !" | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Exécution de Lynis pour l'audit du système
echo "$(date '+%Y-%m-%d %H:%M:%S') - Exécution de Lynis pour l'audit du système..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
lynis audit system | tee -a /var/log/lynis-audit.log

# Vérifications finales de Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification de Samba..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
samba-tool domain info | tee -a /var/log/samba-setup.log

# Fin de l’installation et de la configuration du domaine et du serveur
echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation de Samba et configuration du domaine terminée ! " | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log


# Début de la configuration des groupes et utilisateurs
echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de la configuration des utilisateurs, groupes, politiques de mot de passe, unités d'organisation (OU) et GPO..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Création des groupes selon le modèle Tiering
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des groupes selon le modèle Tiering en cours..." | tee -a /var/log/samba-setup.log
samba-tool group add Group_ADMT0 | tee -a /var/log/samba-setup.log
samba-tool group add Group_ADMT1 | tee -a /var/log/samba-setup.log
samba-tool group add Group_ADMT2 | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Création des utilisateurs et attributions aux groupes
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des utilisateurs et attribution aux groupes en cours..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

PASSWORD_HUGO=$(openssl rand -base64 16)
samba-tool user create Hugo_ADMT0 "$PASSWORD_HUGO" | tee -a /var/log/samba-setup.log
samba-tool group addmembers Group_ADMT0 Hugo_ADMT0 | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

PASSWORD_VOLTAIRE=$(openssl rand -base64 16)
samba-tool user create Voltaire_ADMT1 "$PASSWORD_VOLTAIRE" | tee -a /var/log/samba-setup.log
samba-tool group addmembers Group_ADMT1 Voltaire_ADMT1 | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

PASSWORD_CLEMENCEAU=$(openssl rand -base64 16)
samba-tool user create Clemenceau_ADMT2 "$PASSWORD_CLEMENCEAU" | tee -a /var/log/samba-setup.log
samba-tool group addmembers Group_ADMT2 Clemenceau_ADMT2 | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log

# Sauvegarde des mots de passe générés
echo "$(date '+%Y-%m-%d %H:%M:%S') - Sauvegarde des mots de passe générés..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
echo "Hugo_ADMT0 : $PASSWORD_HUGO" >> /root/northstar_users.txt
echo "Voltaire_ADMT1 : $PASSWORD_VOLTAIRE" >> /root/northstar_users.txt
echo "Clemenceau_ADMT2 : $PASSWORD_CLEMENCEAU" >> /root/northstar_users.txt
chmod 600 /root/northstar_users.txt

# Application des politiques de mots de passe sécurisées
echo "$(date '+%Y-%m-%d %H:%M:%S') - Application des politiques de mots de passe sécurisées en cours..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
samba-tool domain passwordsettings set --complexity=on
samba-tool domain passwordsettings set --history-length=24
samba-tool domain passwordsettings set --min-pwd-age=1
samba-tool domain passwordsettings set --max-pwd-age=90
samba-tool domain passwordsettings set --min-pwd-length=14
samba-tool domain passwordsettings set --account-lockout-threshold=5
samba-tool domain passwordsettings set --account-lockout-duration=30
samba-tool domain passwordsettings set --reset-account-lockout-after=15

# Désactivation des comptes inutilisés
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désactivation des comptes inutilisés et vulnérable..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
samba-tool user disable guest
samba-tool user setpassword guest --random

# Création des unités d'organisation (OU)
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création des unités d'organisation (OU)..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
OU_LIST=(
    "OU=NS,OU=Group_ADMT0,DC=northstar,DC=com"
    "OU=NS,OU=Group_ADMT1,DC=northstar,DC=com"
    "OU=NS,OU=Group_ADMT2,DC=northstar,DC=com"
    "OU=NS,OU=Servers_T1,DC=northstar,DC=com"
    "OU=NS,OU=AdminWorkstations,DC=northstar,DC=com"
)

for OU in "${OU_LIST[@]}"; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification de l'existence de $OU..." | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    samba-tool ou list | grep -q "$(echo $OU | cut -d',' -f1 | cut -d'=' -f2)"
    if [ $? -eq 0 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - L'OU $OU existe déjà." | tee -a /var/log/samba-setup.log
        echo "====================" | tee -a /var/log/samba-setup.log
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Création de l'OU $OU..." | tee -a /var/log/samba-setup.log
        echo "====================" | tee -a /var/log/samba-setup.log
        samba-tool ou create "$OU" | tee -a /var/log/samba-setup.log
    fi
done

# Désactivation des groupes inutiles
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désactivation des groupes inutiles..." | tee -a /var/log/samba-setup.log
echo "====================" | tee -a /var/log/samba-setup.log
GROUPS_TO_DISABLE=(
    "Guests"
    "Domain Guests"
    "Print Operators"
    "Backup Operators"
    "IIS_IUSRS"
)

for GROUP in "${GROUPS_TO_DISABLE[@]}"; do
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Désactivation des permissions pour le groupe '$GROUP'..." | tee -a /var/log/samba-setup.log
    echo "====================" | tee -a /var/log/samba-setup.log
    samba-tool group setmembers "$GROUP" "" | tee -a /var/log/samba-setup.log
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Membres du groupe '$GROUP' supprimés." | tee -a /var/log/samba-setup.log
done

echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration Terminée"
