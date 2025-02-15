#!/bin/bash

echo " Démarrage de l'installation et de la configuration" | tee -a /var/log/samba-setup.log

# Mise à jour et installation des paquets nécessaires
echo "Mise à jour et installation des paquets nécessaires..." | tee -a /var/log/samba-setup.log
apt update && apt upgrade -y | tee -a /var/log/samba-setup.log
apt install -y samba krb5-user smbclient winbind auditd lynis audispd-plugins fail2ban ufw krb5-admin-server dnsutils iptables iptables-save | tee -a /var/log/samba-setup.log


# Vérification de l'installation des paquets
for pkg in samba krb5-user smbclient winbind auditd lynis audispd-plugins fail2ban ufw krb5-admin-server dnsutils iptables iptables-save; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo " Erreur : Le paquet $pkg n'a pas été installé !" | tee -a /var/log/samba-setup.log
        exit 1
    fi
done
echo " Tous les paquets ont été installés avec succès !" | tee -a /var/log/samba-setup.log

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
    ldap timeout = 15
    smb ports = 445
    server signing = mandatory
    client signing = mandatory
    max smbd processes = 500
    allow unsafe cluster upgrade = no
    clustering = no
EOF

# Génération des certificats TLS
echo " Génération des certificats TLS..." | tee -a /var/log/samba-setup.log
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/samba/private/tls.key \
    -out /etc/samba/private/tls.crt \
    -subj "/CN=NORTHSTAR.COM"
    
# Protection des certificats TLS, seul l'utilisateur root y'a accés
chmod 600 /etc/samba/private/tls.*
echo " Certificats TLS générés et protégés." | tee -a /var/log/samba-setup.log

# Redémarrage des services Samba
echo "Redémarrage des services Samba..." | tee -a /var/log/samba-setup.log
systemctl restart samba-ad-dc | tee -a /var/log/samba-setup.log
systemctl enable samba-ad-dc | tee -a /var/log/samba-setup.log

# Téléchargement et installation de osquery
echo "Téléchargement et installation de osquery..." | tee -a /var/log/samba-setup.log
wget https://pkg.osquery.io/deb/osquery_5.9.1-1.linux_amd64.deb | tee -a /var/log/samba-setup.log
dpkg -i osquery_5.9.1-1.linux_amd64.deb | tee -a /var/log/samba-setup.log
systemctl restart osqueryd | tee -a /var/log/samba-setup.log

# Configuration d'osquery
echo " Configuration d'osquery..." | tee -a /var/log/samba-setup.log
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
    echo " osqueryd fonctionne !" | tee -a /var/log/samba-setup.log
else
    echo " Erreur : osqueryd n'a pas démarré !" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Sécurisation de SSH
echo " Configuration de SSH..." | tee -a /var/log/samba-setup.log
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
echo "AllowUsers admin" >> /etc/ssh/sshd_config

systemctl restart sshd
if systemctl is-active --quiet sshd; then
    echo " SSH est sécurisé et fonctionne !" | tee -a /var/log/samba-setup.log
else
    echo " Erreur : SSH n'a pas redémarré !" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Configuration de Fail2Ban pour Samba
echo " Configuration de Fail2Ban..." | tee -a /var/log/samba-setup.log
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
    echo " Fail2Ban fonctionne !" | tee -a /var/log/samba-setup.log
else
    echo " Erreur : Fail2Ban n'a pas démarré !" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Configuration d'auditd pour surveiller Samba et Kerberos
echo " Configuration d'auditd..." | tee -a /var/log/samba-setup.log
cat <<EOF > /etc/audit/rules.d/audit.rules
-w /etc/ -p wa -k etc-changes
-w /var/log/samba/ -p wa -k samba-logs
-w /var/log/audit/ -p wa -k audit-logs
-w /var/lib/samba/private/secrets.ldb -p r -k kerberos-secrets
-a always,exit -F arch=b64 -S execve -F euid=0 -k root-commands
EOF

systemctl restart auditd
if systemctl is-active --quiet auditd; then
    echo " auditd fonctionne et surveille Samba et Kerberos !" | tee -a /var/log/samba-setup.log
else
    echo " Erreur : auditd n'a pas redémarré !" | tee -a /var/log/samba-setup.log
    exit 1
fi

# Exécution de Lynis pour l'audit du système
echo " Exécution de Lynis pour l'audit du système..." | tee -a /var/log/samba-setup.log
lynis audit system | tee -a /var/log/lynis-audit.log

# Vérifications finales de Samba
echo " Vérification de Samba..." | tee -a /var/log/samba-setup.log
samba-tool domain info | tee -a /var/log/samba-setup.log

# Fin de l’installation
echo " Installation de Samba et configuration du domaine terminée ! " | tee -a /var/log/samba-setup.log

