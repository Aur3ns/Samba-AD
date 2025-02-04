#!/bin/bash

# Variables de configuration
REALM="NORTHSTAR.COM"
DOMAIN="NORTHSTAR"
LOG_FILE="/var/log/audit_script.log"

echo "🚀 Début de l'installation et de la configuration d'Auditd et Osquery..." | tee -a $LOG_FILE

# Installation de Auditd et Osquery
echo "📌 Installation des paquets nécessaires..." | tee -a $LOG_FILE
apt install -y auditd osqueryd 2>&1 | tee -a $LOG_FILE

# Vérifier si les paquets sont bien installés
if ! command -v auditctl &> /dev/null; then
    echo "❌ Erreur : auditd n'est pas installé !" | tee -a $LOG_FILE
    exit 1
fi

if ! command -v osqueryi &> /dev/null; then
    echo "❌ Erreur : osqueryd n'est pas installé !" | tee -a $LOG_FILE
    exit 1
fi

echo "✅ Installation réussie !" | tee -a $LOG_FILE

# Activer et démarrer auditd
echo "📌 Activation et démarrage d'auditd..." | tee -a $LOG_FILE
systemctl enable auditd
systemctl start auditd

# Vérifier que auditd fonctionne
if systemctl is-active --quiet auditd; then
    echo "✅ auditd fonctionne !" | tee -a $LOG_FILE
else
    echo "❌ Erreur : auditd n'a pas démarré !" | tee -a $LOG_FILE
    exit 1
fi

# Configuration de auditd pour surveiller les fichiers critiques
echo "📌 Configuration de auditd..." | tee -a $LOG_FILE

cat <<EOF > /etc/audit/rules.d/audit.rules
# Surveillance des fichiers sensibles
-w /etc/ -p wa -k etc-changes
-w /var/log/samba/ -p wa -k samba-logs
-w /var/log/audit/ -p wa -k audit-logs
-w /var/lib/samba/private/secrets.ldb -p r -k kerberos-secrets

# Surveillance des connexions SSH
-a always,exit -F arch=b64 -S execve -F euid=0 -k root-commands
EOF

# Redémarrer auditd
systemctl restart auditd

# Vérifier que auditd redémarre bien
if systemctl is-active --quiet auditd; then
    echo "✅ auditd redémarré avec succès !" | tee -a $LOG_FILE
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

# Activer et démarrer Osquery
echo "📌 Activation et démarrage d'Osquery..." | tee -a $LOG_FILE
systemctl enable osqueryd
systemctl restart osqueryd

# Vérifier que osqueryd fonctionne
if systemctl is-active --quiet osqueryd; then
    echo "✅ osqueryd fonctionne !" | tee -a $LOG_FILE
else
    echo "❌ Erreur : osqueryd n'a pas démarré !" | tee -a $LOG_FILE
    exit 1
fi

echo "🚀 Fin de la configuration ! Auditd et Osquery sont en place." | tee -a $LOG_FILE
