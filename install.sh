#!/bin/bash

# Mise à jour et installation des paquets nécessaires
echo "Mise à jour et installation des paquets nécessaires..." | tee -a /var/log/samba-setup.log
apt update && apt upgrade -y | tee -a /var/log/samba-setup.log
apt install -y samba krb5-user smbclient winbind auditd audispd-plugins fail2ban ufw krb5-admin-server dnsutils | tee -a /var/log/samba-setup.log

# Configuration de Kerberos
echo "Configuration de Kerberos avec des options renforcées..." | tee -a /var/log/samba-setup.log
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

# Arrêt et désactivation des services
echo "Arrêt et désactivation des services smbd, nmbd et winbind..." | tee -a /var/log/samba-setup.log
systemctl stop smbd nmbd winbind | tee -a /var/log/samba-setup.log
systemctl disable smbd nmbd winbind | tee -a /var/log/samba-setup.log

# Configuration du contrôleur de domaine Samba
echo "Configuration du contrôleur de domaine Samba..." | tee -a /var/log/samba-setup.log
samba-tool domain provision --use-rfc2307 --realm=NORTHSTAR.COM --domain=NORTHSTAR --adminpass=@fterTheB@ll33/ --server-role=dc | tee -a /var/log/samba-setup.log

# Configuration avancée pour Samba
echo "Durcissement des configurations Samba..." | tee -a /var/log/samba-setup.log
cat <<EOF >>/etc/samba/smb.conf
[global]
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
    ldap timeout = 15
    smb ports = 445
    server signing = mandatory
    client signing = mandatory
    max smbd processes = 500
    allow unsafe cluster upgrade = no
    clustering = no
EOF

# Redémarrage des services Samba
echo "Redémarrage des services Samba..." | tee -a /var/log/samba-setup.log
systemctl restart samba-ad-dc | tee -a /var/log/samba-setup.log
systemctl enable samba-ad-dc | tee -a /var/log/samba-setup.log

# Téléchargement et installation de osquery
echo "Téléchargement et installation de osquery..." | tee -a /var/log/samba-setup.log
wget https://pkg.osquery.io/deb/osquery_5.9.1-1.linux_amd64.deb | tee -a /var/log/samba-setup.log
dpkg -i osquery_5.9.1-1.linux_amd64.deb | tee -a /var/log/samba-setup.log
systemctl restart osqueryd | tee -a /var/log/samba-setup.log
echo "Installation de osqueryd terminée" | tee -a /var/log/samba-setup.log

# Fin de l’installation
echo "Installation et configuration de Samba et osquery terminées !" | tee -a /var/log/samba-setup.log
