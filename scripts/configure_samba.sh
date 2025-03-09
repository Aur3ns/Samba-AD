#!/bin/bash

LOG_FILE="/var/log/samba-ad-setup.log"
REALM="NORTHSTAR.COM"
DOMAIN="NORTHSTAR"
NETBIOS_NAME="SRV-NS"
SAMBA_ADMIN_PASS="@fterTheB@ll33/"  # À CHANGER AVEC UN MOT DE PASSE SÉCURISÉ

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de l'installation de Samba AD..." | tee -a "$LOG_FILE"
trap 'echo " Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# 🛠 Installation de Samba AD et des dépendances
echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation de Samba AD et des dépendances..." | tee -a "$LOG_FILE"
apt update && apt install -y samba samba-ad-dc winbind libnss-winbind libpam-winbind dnsutils openssl

# 🔥 Suppression de `krb5-kdc` et `krb5-admin-server` pour éviter les conflits
echo "$(date '+%Y-%m-%d %H:%M:%S') - Suppression de Kerberos standalone (`krb5-kdc`)..." | tee -a "$LOG_FILE"
apt remove --purge -y krb5-kdc krb5-admin-server

# 🔥 Désactivation des services conflictuels
echo "$(date '+%Y-%m-%d %H:%M:%S') - Désactivation des services conflictuels..." | tee -a "$LOG_FILE"
SERVICES="smbd nmbd winbind avahi-daemon avahi-daemon.socket systemd-resolved named bind9"
for service in $SERVICES; do
    if systemctl list-units --full --all | grep -q "$service"; then
        echo " Arrêt et désactivation de $service..." | tee -a "$LOG_FILE"
        systemctl stop $service
        systemctl disable $service
    fi
done

# 🧹 Suppression des anciennes configurations Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Nettoyage des anciennes configurations..." | tee -a "$LOG_FILE"
rm -rf /etc/samba/smb.conf /var/lib/samba/*

# 🏗 Provisioning du contrôleur de domaine Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - Provisioning du contrôleur de domaine Samba AD..." | tee -a "$LOG_FILE"
samba-tool domain provision --use-rfc2307 --realm="$REALM" --domain="$DOMAIN" --adminpass="$SAMBA_ADMIN_PASS" --server-role=dc --dns-backend=SAMBA_INTERNAL | tee -a "$LOG_FILE"

# Génération des certificats TLS
echo "$(date '+%Y-%m-%d %H:%M:%S') - Génération des certificats TLS pour Samba..." | tee -a "$LOG_FILE"
mkdir -p /etc/samba/private
chmod 700 /etc/samba/private

# 1. Génération de la clé privée pour l'Autorité de Certification (CA)
openssl genrsa -out /etc/samba/private/tls-ca.key 4096

# 2. Création du certificat de l'Autorité de Certification (CA)
openssl req -x509 -new -nodes -key /etc/samba/private/tls-ca.key -sha256 -days 3650 \
    -out /etc/samba/private/tls-ca.crt -subj "/C=FR/ST=Paris/L=Paris/O=Northstar CA/OU=IT Department/CN=Northstar Root CA"

# 3. Clé privée et CSR pour Samba
openssl genrsa -out /etc/samba/private/tls.key 4096
openssl req -new -key /etc/samba/private/tls.key -out /etc/samba/private/tls.csr -subj "/CN=$NETBIOS_NAME.$REALM"

# 4. Signature du certificat de Samba avec l'Autorité de Certification
openssl x509 -req -in /etc/samba/private/tls.csr -CA /etc/samba/private/tls-ca.crt -CAkey /etc/samba/private/tls-ca.key \
    -CAcreateserial -out /etc/samba/private/tls.crt -days 365 -sha256

# Protection des certificats TLS
chmod 600 /etc/samba/private/tls.*

echo "$(date '+%Y-%m-%d %H:%M:%S') - Certificats TLS générés et protégés." | tee -a "$LOG_FILE"

# Déploiement du fichier de configuration `smb.conf`
echo "$(date '+%Y-%m-%d %H:%M:%S') - Déploiement du fichier de configuration Samba..." | tee -a "$LOG_FILE"
cat <<EOF > /etc/samba/smb.conf
[global]
    netbios name = $NETBIOS_NAME
    realm = $REALM
    workgroup = $DOMAIN
    server role = active directory domain controller
    log file = /var/log/samba/log.smbd
    log level = 3 auth:10
    max log size = 5000
    smb ports = 445
    server signing = mandatory
    client signing = mandatory
    ntlm auth = mschapv2-and-ntlmv2-only
    server min protocol = SMB2
    server max protocol = SMB3
    smb encrypt = required
    disable netbios = yes
    dns forwarder = 8.8.8.8
    restrict anonymous = 2
    ldap server require strong auth = yes
    ldap timeout = 15
    allow unsafe cluster upgrade = no
    clustering = no
    rpc server dynamic port range = 50000-55000
    tls enabled = yes
    tls keyfile = /etc/samba/private/tls.key
    tls certfile = /etc/samba/private/tls.crt
    tls cafile = /etc/samba/private/tls-ca.crt

[sysvol]
    path = /var/lib/samba/sysvol
    read only = no

[netlogon]
    path = /var/lib/samba/sysvol/$REALM/scripts
    read only = no
EOF

# Configuration du DNS pour Samba AD
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration du DNS Samba..." | tee -a "$LOG_FILE"
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# Redémarrage du service Samba AD
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage de Samba AD..." | tee -a "$LOG_FILE"
systemctl restart samba-ad-dc
systemctl enable samba-ad-dc

# Vérification de Samba AD
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification de Samba AD..." | tee -a "$LOG_FILE"
if systemctl is-active --quiet samba-ad-dc; then
    echo " Samba AD est opérationnel !" | tee -a "$LOG_FILE"
else
    echo " Samba AD ne s'est pas démarré correctement." | tee -a "$LOG_FILE"
    exit 1
fi

#Symlink de /var/lib/samba/private/krb5.conf vers /etc/krb5.conf
ln -sf /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Test de connexion Kerberos avec `Administrator`
echo "$(date '+%Y-%m-%d %H:%M:%S') - Test de connexion Kerberos avec Administrator..." | tee -a "$LOG_FILE"
echo "$SAMBA_ADMIN_PASS" | kinit Administrator

if klist -s; then
    echo " Ticket Kerberos actif pour Administrator." | tee -a "$LOG_FILE"
else
    echo " Échec de l'authentification Kerberos pour Administrator." | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration complète réussie !" | tee -a "$LOG_FILE"
