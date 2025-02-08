#!/bin/bash

#Variables 
LOG_FILE="/var/log/samba-setup.log"
REALM="NORTHSTAR.COM"

# Configuration de Kerberos avec des options avancées
echo "Configuration de Kerberos avec des options renforcées..." | tee -a $LOG_FILE
cat <<EOF >/etc/krb5.conf
[libdefaults]
    default_realm = $REALM
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

# Configuration avancée pour Samba
echo "Durcissement des configurations Samba..." | tee -a $LOG_FILE
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

systemctl restart samba-ad-dc
systemctl restart krb5-admin-server
