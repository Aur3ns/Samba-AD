#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Démarrage de la configuration d'auditd et Lynis..." | tee -a "$LOG_FILE"
trap 'echo "Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Configuration d'auditd
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuration d'auditd pour surveiller Samba et Kerberos..." | tee -a "$LOG_FILE"

cat <<EOF > /etc/audit/rules.d/audit.rules
# Surveillance des modifications dans /etc/
-w /etc/ -p wa -k etc-changes

# Surveillance des logs de Samba
-w /var/log/samba/ -p wa -k samba-logs

# Surveillance des logs d'audit
-w /var/log/audit/ -p wa -k audit-logs

# Surveillance des fichiers sensibles de Kerberos
-w /var/lib/samba/private/secrets.ldb -p r -k kerberos-secrets

# Surveillance des commandes exécutées en root
-a always,exit -F arch=b64 -S execve -F euid=0 -k root-commands
EOF

# Redémarrage d'auditd et vérification
echo "$(date '+%Y-%m-%d %H:%M:%S') - Redémarrage d'auditd..." | tee -a "$LOG_FILE"
systemctl restart auditd

if systemctl is-active --quiet auditd; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - auditd fonctionne et surveille Samba et Kerberos !" | tee -a "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : auditd n'a pas redémarré !" | tee -a "$LOG_FILE"
    exit 1
fi

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Exécution de Lynis pour audit du système
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Exécution de Lynis pour l'audit du système..." | tee -a "$LOG_FILE"

if ! command -v lynis &>/dev/null; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Lynis n'est pas installé. Installation en cours..." | tee -a "$LOG_FILE"
    apt update && apt install -y lynis | tee -a "$LOG_FILE"
fi

lynis audit system | tee -a /var/log/lynis-audit.log

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Vérification de Samba
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Vérification du bon fonctionnement de Samba..." | tee -a "$LOG_FILE"

SAMBA_DOMAIN_INFO=$(samba-tool domain info "$(hostname -I | awk '{print $1}')" 2>&1)

if [ $? -eq 0 ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Samba fonctionne correctement." | tee -a "$LOG_FILE"
else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Erreur : Problème détecté avec Samba !" | tee -a "$LOG_FILE"
    echo "$SAMBA_DOMAIN_INFO" | tee -a "$LOG_FILE"
    exit 1
fi

echo "====================" | tee -a "$LOG_FILE"

# ========================
# Finalisation
# ========================
echo "$(date '+%Y-%m-%d %H:%M:%S') - Installation de Samba et configuration du domaine terminée !" | tee -a "$LOG_FILE"
echo "====================" | tee -a "$LOG_FILE"
