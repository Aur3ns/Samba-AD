#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"
OSQUERY_DEB="osquery_5.9.1-1.linux_amd64.deb"
OSQUERY_URL="https://pkg.osquery.io/deb/$OSQUERY_DEB"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Début de l'installation et de la configuration d'osquery..." | tee -a "$LOG_FILE"
trap 'echo "Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# Vérification et installation de wget si nécessaire
if ! command -v wget &>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - wget non installé, installation en cours..." | tee -a "$LOG_FILE"
    apt update && apt install -y wget | tee -a "$LOG_FILE"
fi

# Téléchargement du package osquery
echo "$(date '+%Y-%m-%d %H:%M:%S') - Téléchargement de osquery..." | tee -a "$LOG_FILE"
wget -O "$OSQUERY_DEB" "$OSQUERY_URL" | tee -a "$LOG_FILE"

# Installation du package osquery
echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation de osquery..." | tee -a "$LOG_FILE"
dpkg -i "$OSQUERY_DEB" | tee -a "$LOG_FILE"

# Nettoyage du fichier d'installation
rm -f "$OSQUERY_DEB"

# Vérification de l'installation
if ! dpkg -l | grep -qw osquery; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : L'installation de osquery a échoué !" | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - osquery installé avec succès." | tee -a "$LOG_FILE"

# Configuration d'osquery
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration d'osquery..." | tee -a "$LOG_FILE"
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

# Vérification et activation du service osquery
echo "$(date '+%Y-%m-%d %H:%M:%S') - Démarrage et activation de osqueryd..." | tee -a "$LOG_FILE"
systemctl enable osqueryd
systemctl restart osqueryd

# Vérification du statut du service
if systemctl is-active --quiet osqueryd; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - osqueryd fonctionne correctement !" | tee -a "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : osqueryd n'a pas démarré !" | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation et configuration de osquery terminées !" | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"
