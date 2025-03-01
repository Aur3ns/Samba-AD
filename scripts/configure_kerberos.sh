#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de la configuration de Kerberos..." | tee -a "$LOG_FILE"

trap 'echo "Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# Création du fichier de configuration de Kerberos
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création du fichier /etc/krb5.conf..." | tee -a "$LOG_FILE"
cat <<EOF > /etc/krb5.conf
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

[realms]
    NORTHSTAR.COM = {
        kdc = SRV-NS.NORTHSTAR.COM
        admin_server = SRV-NS.NORTHSTAR.COM
        default_domain = NORTHSTAR.COM
    }

[domain_realm]
    .northstar.com = NORTHSTAR.COM
    northstar.com = NORTHSTAR.COM
EOF

echo "$(date '+%Y-%m-%d %H:%M:%S') - Fichier /etc/krb5.conf créé." | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"

# Vérification et initialisation de la base de données Kerberos
if [ ! -f "/var/lib/krb5kdc/principal" ]; then
    echo "====================" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Initialisation de la base de données Kerberos..." | tee -a "$LOG_FILE"

    KDC_MASTER_PASS=$(openssl rand -base64 16)

    echo -e "$KDC_MASTER_PASS\n$KDC_MASTER_PASS" | kdb5_util create -s

    echo "$KDC_MASTER_PASS" > /root/kdc_master_key.txt
    chmod 600 /root/kdc_master_key.txt

    echo "====================" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Base de données Kerberos créée avec succès." | tee -a "$LOG_FILE"
else
    echo "====================" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - La base de données Kerberos existe déjà." | tee -a "$LOG_FILE"
fi

# Vérification et création du fichier ACL
if [ ! -f "/etc/krb5kdc/kadm5.acl" ]; then
    echo "====================" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Création du fichier /etc/krb5kdc/kadm5.acl..." | tee -a "$LOG_FILE"
    echo "*/root@NORTHSTAR.COM *" > /etc/krb5kdc/kadm5.acl
    chmod 600 /etc/krb5kdc/kadm5.acl
else
    echo "====================" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Le fichier ACL existe déjà." | tee -a "$LOG_FILE"
fi

# Création de l'utilisateur root dans Kerberos
echo "====================" | tee -a "$LOG_FILE"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Création de l'utilisateur root..." | tee -a "$LOG_FILE"

ROOT_KERB_PASS=$(openssl rand -base64 16)

echo "$ROOT_KERB_PASS" > /root/kerberos_root_pass.txt
chmod 600 /root/kerberos_root_pass.txt

echo -e "$ROOT_KERB_PASS\n$ROOT_KERB_PASS" | kadmin.local -q "addprinc root"

if kadmin.local -q "getprinc root" | grep -q "Principal: root@"; then
    echo "====================" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Utilisateur root Kerberos créé avec succès." | tee -a "$LOG_FILE"
else
    echo "====================" | tee -a "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : La création de root a échoué !" | tee -a "$LOG_FILE"
    exit 1
fi

# Redémarrage des services Kerberos
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage des services Kerberos..." | tee -a "$LOG_FILE"
systemctl restart krb5-kdc krb5-admin-server
systemctl enable krb5-kdc krb5-admin-server

if systemctl is-active --quiet krb5-kdc && systemctl is-active --quiet krb5-admin-server; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Kerberos fonctionne correctement !" | tee -a "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') -  Erreur : Un des services Kerberos ne fonctionne pas !" | tee -a "$LOG_FILE"
    exit 1
fi

# Test de connexion avec kinit pour root
echo "$(date '+%Y-%m-%d %H:%M:%S') - Test d'authentification avec root..." | tee -a "$LOG_FILE"
echo "$ROOT_KERB_PASS" | kinit root

if klist -s; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Test réussi ! Ticket Kerberos actif pour root." | tee -a "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Échec de l'authentification Kerberos pour root." | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de Kerberos terminée !" | tee -a "$LOG_FILE"
