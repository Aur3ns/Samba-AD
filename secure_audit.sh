#!/bin/bash

# Variables de configuration
REALM="NORTHSTAR.COM"
DOMAIN="NORTHSTAR"
LOG_FILE="/var/log/samba-setup.log"
PACKAGES="smbclient audispd-plugins lynis fail2ban auditd"

echo "🚀 Démarrage de la configuration sécurisée..." | tee -a $LOG_FILE

# Mise à jour du système et installation des paquets de sécurité
echo "📌 Mise à jour du système..." | tee -a $LOG_FILE
apt update && apt upgrade -y | tee -a $LOG_FILE

echo "📌 Installation des paquets nécessaires..." | tee -a $LOG_FILE
apt install -y $PACKAGES | tee -a $LOG_FILE

# Vérification de l'installation des paquets
for pkg in smbclient audispd-plugins lynis fail2ban auditd osqueryd; do
    if ! dpkg -l | grep -qw "$pkg"; then
        echo "❌ Erreur : Le paquet $pkg n'a pas été installé !" | tee -a $LOG_FILE
        exit 1
    fi
done
echo "✅ Tous les paquets ont été installés avec succès." | tee -a $LOG_FILE

# Configuration de Samba avec TLS
echo "📌 Configuration de Samba avec TLS..." | tee -a $LOG_FILE
cat <<EOF > /etc/samba/smb.conf
[global]
    tls enabled = yes
    tls keyfile = /etc/samba/private/tls.key
    tls certfile = /etc/samba/private/tls.crt
    tls cafile = /etc/samba/private/tls-ca.crt
EOF

# Génération des certificats TLS
echo "📌 Génération des certificats TLS..." | tee -a $LOG_FILE
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/samba/private/tls.key \
    -out /etc/samba/private/tls.crt \
    -subj "/CN=$REALM"

chmod 600 /etc/samba/private/tls.*
echo "✅ Certificats TLS générés et protégés." | tee -a $LOG_FILE

# Configuration de Fail2Ban pour Samba
echo "📌 Configuration de Fail2Ban..." | tee -a $LOG_FILE
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
    echo "✅ Fail2Ban fonctionne !" | tee -a $LOG_FILE
else
    echo "❌ Erreur : Fail2Ban n'a pas démarré !" | tee -a $LOG_FILE
    exit 1
fi

# Sécurisation de SSH
echo "📌 Configuration de SSH..." | tee -a $LOG_FILE
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
echo "AllowUsers $ADMIN_USER" >> /etc/ssh/sshd_config

systemctl restart sshd
if systemctl is-active --quiet sshd; then
    echo "✅ SSH est sécurisé et fonctionne !" | tee -a $LOG_FILE
else
    echo "❌ Erreur : SSH n'a pas redémarré !" | tee -a $LOG_FILE
    exit 1
fi

# Configuration d'auditd pour surveiller Samba et Kerberos
echo "📌 Configuration d'auditd..." | tee -a $LOG_FILE
cat <<EOF > /etc/audit/rules.d/audit.rules
# Surveillance des fichiers sensibles
-w /etc/ -p wa -k etc-changes
-w /var/log/samba/ -p wa -k samba-logs
-w /var/log/audit/ -p wa -k audit-logs
-w /var/lib/samba/private/secrets.ldb -p r -k kerberos-secrets

# Surveillance des connexions SSH
-a always,exit -F arch=b64 -S execve -F euid=0 -k root-commands
EOF

systemctl restart auditd
if systemctl is-active --quiet auditd; then
    echo "✅ auditd fonctionne et surveille Samba et Kerberos !" | tee -a $LOG_FILE
else
    echo "❌ Erreur : auditd n'a pas redémarré !" | tee -a $LOG_FILE
    exit 1
fi

# Configuration d'Osquery
echo "📌 Configuration d'Osquery..." | tee -a $LOG_FILE
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
    echo "✅ osqueryd fonctionne !" | tee -a $LOG_FILE
else
    echo "❌ Erreur : osqueryd n'a pas démarré !" | tee -a $LOG_FILE
    exit 1
fi

# Exécution de Lynis pour l'audit du système
echo "📌 Exécution de Lynis pour l'audit du système..." | tee -a $LOG_FILE
lynis audit system | tee -a /var/log/lynis-audit.log

# Vérifications finales de Samba
echo "📌 Vérification de Samba..." | tee -a $LOG_FILE
samba-tool domain info | tee -a $LOG_FILE

echo "🚀 Configuration terminée. Consultez $LOG_FILE pour les détails." | tee -a $LOG_FILE
