#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"
REALM="NORTHSTAR.COM"
DOMAIN="NORTHSTAR"
NETBIOS_NAME="SRV-NS"
SAMBA_ADMIN_PASS="@fterTheB@ll33/"  # 🔥 À CHANGER

echo "$(date '+%Y-%m-%d %H:%M:%S') - 🚀 Début de l'installation de Samba AD..." | tee -a "$LOG_FILE"
trap 'echo "❌ Erreur à la ligne $LINENO ! Vérifier $LOG_FILE"; exit 1' ERR

echo "====================" | tee -a "$LOG_FILE"

# 🛠 Installation de Samba et des dépendances
echo "$(date '+%Y-%m-%d %H:%M:%S') - 📦 Installation de Samba et des dépendances..." | tee -a "$LOG_FILE"
apt update && apt install -y samba samba-ad-dc krb5-user winbind libnss-winbind libpam-winbind dnsutils

# 🔥 Désactivation des services en conflit
echo "$(date '+%Y-%m-%d %H:%M:%S') - ❌ Désactivation des services conflictuels..." | tee -a "$LOG_FILE"
systemctl stop smbd nmbd winbind samba-ad-dc avahi-daemon avahi-daemon.socket krb5-kdc systemd-resolved
systemctl disable smbd nmbd winbind avahi-daemon avahi-daemon.socket krb5-kdc systemd-resolved

# 🔍 Vérification des ports réseau (53 et 88)
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔍 Vérification des ports réseau..." | tee -a "$LOG_FILE"
if ss -tulnp | grep -E ":53|:88"; then
    echo "⚠️ Un service utilise les ports 53 ou 88. Vérification en cours..." | tee -a "$LOG_FILE"
    systemctl stop named
    systemctl stop bind9
    systemctl disable named
    systemctl disable bind9
fi

# 🧹 Suppression des anciennes configurations Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🧹 Nettoyage des anciennes configurations Samba..." | tee -a "$LOG_FILE"
rm -rf /etc/samba/smb.conf /var/lib/samba/* /etc/krb5.conf

# 🏗 Provisioning du contrôleur de domaine Samba
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🏗 Provisioning du contrôleur de domaine Samba..." | tee -a "$LOG_FILE"
samba-tool domain provision --use-rfc2307 --realm="$REALM" --domain="$DOMAIN" --adminpass="$SAMBA_ADMIN_PASS" --server-role=dc --dns-backend=SAMBA_INTERNAL | tee -a "$LOG_FILE"

# 📜 Génération du fichier de configuration optimisé
echo "$(date '+%Y-%m-%d %H:%M:%S') - 📝 Création du fichier /etc/samba/smb.conf..." | tee -a "$LOG_FILE"
cat <<EOF > /etc/samba/smb.conf
[global]
    netbios name = $NETBIOS_NAME
    realm = $REALM
    workgroup = $DOMAIN
    server role = active directory domain controller
    log file = /var/log/samba/log.%m
    log level = 3
    max log size = 5000
    smb ports = 445
    server signing = mandatory
    client signing = mandatory
    ntlm auth = mschapv2-and-ntlmv2-only
    server min protocol = SMB2
    server max protocol = SMB3
    smb encrypt = required
    disable netbios = yes
    dns forwarder = 8.8.8.8
    restrict anonymous = 2
    ldap server require strong auth = yes
    ldap timeout = 15
    allow unsafe cluster upgrade = no
    clustering = no

[sysvol]
    path = /var/lib/samba/sysvol
    read only = no

[netlogon]
    path = /var/lib/samba/sysvol/$REALM/scripts
    read only = no
EOF

# 🌍 Configuration DNS pour Samba AD
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🌍 Configuration du DNS Samba..." | tee -a "$LOG_FILE"
echo "nameserver 127.0.0.1" > /etc/resolv.conf

# 🔄 Redémarrage de Samba AD
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔄 Redémarrage de Samba AD..." | tee -a "$LOG_FILE"
systemctl restart samba-ad-dc
systemctl enable samba-ad-dc

# ✅ Vérification du service Samba AD
echo "$(date '+%Y-%m-%d %H:%M:%S') - ✅ Vérification de Samba AD..." | tee -a "$LOG_FILE"
if systemctl is-active --quiet samba-ad-dc; then
    echo "✅ Samba AD est opérationnel !" | tee -a "$LOG_FILE"
else
    echo "❌ Samba AD ne s'est pas démarré correctement." | tee -a "$LOG_FILE"
    exit 1
fi

# 🔑 Test d'authentification Kerberos
echo "$(date '+%Y-%m-%d %H:%M:%S') - 🔑 Test de connexion Kerberos..." | tee -a "$LOG_FILE"
echo "$SAMBA_ADMIN_PASS" | kinit administrator

if klist -s; then
    echo "✅ Ticket Kerberos actif pour administrator." | tee -a "$LOG_FILE"
else
    echo "❌ Échec de l'authentification Kerberos." | tee -a "$LOG_FILE"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - 🎉 Configuration de Samba AD terminée avec succès !" | tee -a "$LOG_FILE"
