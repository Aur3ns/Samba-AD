B #!/bin/bash

# Vérification des privilèges
if [ "$EUID" -ne 0 ]; then
  echo "Ce script doit être exécuté en tant que root."
  exit 1
fi

# Variables de configuration
REALM="NORTHSTART.COM"
DOMAIN="NORTHSTAR"
ADMIN_PASS="AdminPassword2025!"
TIER_USERS=("T0_Admin" "T1_Admin" "T2_User")
TIER_GROUPS=("Tier0_Admins" "Tier1_Admins" "Tier2_Users")
PACKAGES="samba krb5-user smbclient winbind auditd audispd-plugins osquery fail2ban ufw"
LOG_FILE="/var/log/samba-setup.log"
RANDOM_PASS_LENGTH=16

# Début de l'installation
echo "Début de la configuration sécurisée de l'Active Directory..." | tee -a $LOG_FILE

# Mise à jour du système et installation des paquets requis
echo "Mise à jour et installation des paquets nécessaires..." | tee -a $LOG_FILE
apt update && apt upgrade -y | tee -a $LOG_FILE
apt install -y $PACKAGES | tee -a $LOG_FILE

# Arrêt des services existants
echo "Arrêt des services Samba existants..." | tee -a $LOG_FILE
systemctl stop smbd nmbd winbind
systemctl disable smbd nmbd winbind

# Configuration de Samba pour le domaine
echo "Configuration de Samba pour l'Active Directory sécurisé..." | tee -a $LOG_FILE
samba-tool domain provision \
  --use-rfc2307 \
  --realm=$REALM \
  --domain=$DOMAIN \
  --adminpass=$ADMIN_PASS \
  --server-role=dc | tee -a $LOG_FILE

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

# Création des utilisateurs et groupes pour le modèle Tiering
echo "Création des utilisateurs et groupes pour le modèle Tiering..." | tee -a $LOG_FILE
for group in "${TIER_GROUPS[@]}"; do
  samba-tool group add $group | tee -a $LOG_FILE
done

for i in "${!TIER_USERS[@]}"; do
  PASSWORD=$(openssl rand -base64 $RANDOM_PASS_LENGTH)
  samba-tool user create "${TIER_USERS[$i]}" "$PASSWORD" | tee -a $LOG_FILE
  samba-tool group addmembers "${TIER_GROUPS[$i]}" "${TIER_USERS[$i]}" | tee -a $LOG_FILE
  echo "Utilisateur ${TIER_USERS[$i]} créé avec le mot de passe : $PASSWORD" | tee -a $LOG_FILE
done

# Renforcement des politiques de mots de passe
echo "Application des politiques de mots de passe sécurisées..." | tee -a $LOG_FILE
samba-tool domain passwordsettings set --complexity=on
samba-tool domain passwordsettings set --history-length=24
samba-tool domain passwordsettings set --min-pwd-age=1
samba-tool domain passwordsettings set --max-pwd-age=90
samba-tool domain passwordsettings set --min-pwd-length=14
samba-tool domain passwordsettings set --account-lockout-threshold=5
samba-tool domain passwordsettings set --account-lockout-duration=30
samba-tool domain passwordsettings set --reset-account-lockout-after=15

# Désactivation des comptes inutilisés
echo "Désactivation des comptes inutilisés et durcissement Samba..." | tee -a $LOG_FILE
samba-tool user disable guest
samba-tool user setpassword guest --random

# Configuration avancée pour les CVE (DSHeuristics)
echo "Mise en place des recommandations pour les CVE (DSHeuristics)..." | tee -a $LOG_FILE
samba-tool gpo set --option="Directory Services Heuristics=0000002" | tee -a $LOG_FILE

# Configuration de la journalisation avec Auditd et Osquery
echo "Installation et configuration de la journalisation avancée..." | tee -a $LOG_FILE
systemctl enable auditd
systemctl start auditd

cat <<EOF >/etc/audit/rules.d/audit.rules
# Surveillance des fichiers sensibles
-w /etc/ -p wa -k etc-changes
-w /var/log/samba/ -p wa -k samba-logs
-w /var/log/audit/ -p wa -k audit-logs
-w /var/lib/samba/private/secrets.ldb -p r -k kerberos-secrets
EOF
systemctl restart auditd

cat <<EOF >/etc/osquery/osquery.conf
{
  "options": {
    "logger_plugin": "filesystem",
    "logger_path": "/var/log/osquery",
    "disable_events": "false",
    "schedule_splay_percent": "10"
  },
  "schedule": {
    "kerberos_audit": {
      "query": "SELECT * FROM processes WHERE name LIKE '%krb%'",
      "interval": 60
    },
    "file_events": {
      "query": "SELECT * FROM file WHERE path LIKE '/etc/%%' OR path LIKE '/var/lib/samba/private/%%'",
      "interval": 60
    }
  }
}
EOF
systemctl restart osqueryd

# Installation et configuration de rsyslog pour la centralisation des logs
echo "Installation et configuration de rsyslog..." | tee -a $LOG_FILE
apt install -y rsyslog | tee -a $LOG_FILE

# Configuration de rsyslog pour transmettre les logs à un serveur distant
RSYSLOG_CONF="/etc/rsyslog.conf"
RSYSLOG_REMOTE_SERVER="192.168.1.100" # Remplacez par l'adresse IP de votre serveur de logs
RSYSLOG_REMOTE_PORT="514"

# Activer le mode client pour envoyer les logs au serveur distant
echo "Configuration pour l'envoi des logs au serveur distant ($RSYSLOG_REMOTE_SERVER:$RSYSLOG_REMOTE_PORT)..." | tee -a $LOG_FILE
sed -i '/^#*.* @@/d' $RSYSLOG_CONF
echo "*.* @@$RSYSLOG_REMOTE_SERVER:$RSYSLOG_REMOTE_PORT" >> $RSYSLOG_CONF

# Redémarrage du service rsyslog
systemctl restart rsyslog
systemctl enable rsyslog

# Configuration pour inclure les logs de auditd dans rsyslog
echo "Configuration pour inclure les logs de auditd dans rsyslog..." | tee -a $LOG_FILE
cat <<EOF >/etc/rsyslog.d/auditd.conf
# Collecte des logs de auditd
module(load="imfile" PollingInterval="10")
input(type="imfile"
      File="/var/log/audit/audit.log"
      Tag="auditd"
      Severity="info"
      Facility="local6")
EOF

# Redémarrer rsyslog pour prendre en compte les changements
systemctl restart rsyslog

# Vérification du fonctionnement
echo "Vérification du bon fonctionnement de rsyslog..." | tee -a $LOG_FILE
if systemctl status rsyslog | grep -q "active (running)"; then
  echo "rsyslog fonctionne correctement." | tee -a $LOG_FILE
else
  echo "Erreur : rsyslog ne fonctionne pas. Veuillez vérifier la configuration." | tee -a $LOG_FILE
  exit 1
fi


# Résumé des configurations
echo "Résumé des configurations appliquées :" | tee -a $LOG_FILE
samba-tool user list | tee -a $LOG_FILE
samba-tool group list | tee -a $LOG_FILE
samba-tool domain passwordsettings show | tee -a $LOG_FILE

echo "Configuration terminée. Consultez $LOG_FILE pour les détails."
