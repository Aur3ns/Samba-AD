#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration de Kerberos..." | tee -a "$LOG_FILE"

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

echo "$(date '+%Y-%m-%d %H:%M:%S') - Fichier Kerberos créé." | tee -a "$LOG_FILE"
