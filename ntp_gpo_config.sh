; NTP_Sync.pol
; Paramètres de registre pour configurer le service de temps Windows

[Software\Policies\Microsoft\Windows\W32Time\TimeProviders\NtpClient]
"Enabled"=dword:00000001
"NtpServer"="srv-ns.northstar.com,0x9"
"CrossSiteSyncFlags"=dword:00000002
"SpecialPollInterval"=dword:0000ea60
"EventLogFlags"=dword:00000001
"Type"="NTP"

; Si vous ne souhaitez pas que ce client agisse comme serveur NTP
[Software\Policies\Microsoft\Windows\W32Time\TimeProviders\NtpServer]
"Enabled"=dword:00000000




#!/bin/bash
#
# gpo_ntp_sync.sh
#
# Script pour créer/mettre à jour une GPO "NTP_Sync" et lier
# les postes clients à un contrôleur de domaine comme source NTP.
#

LOG_FILE="/var/log/gpo_ntp_sync.log"
DOMAIN="northstar.com"
SMB_PASSWD_FILE="/root/.smbpasswd"
TEMPLATE_DIR="/root/gpo_templates"  # Répertoire contenant les fichiers de paramètres (.pol)
GPO_NAME="NTP_Sync"
OU_PATH="OU=Computers,DC=northstar,DC=com"  # OU à adapter selon votre structure
GPO_TEMPLATE_FILE="$TEMPLATE_DIR/${GPO_NAME}.pol"

# 1. Préparer le fichier de log
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log "================================="
log "⏰ Début de la configuration NTP..."
log "================================="

# 2. Vérifier/créer le fichier d'identifiants Samba/Kerberos
if [ ! -f "$SMB_PASSWD_FILE" ]; then
    log "🔐 Le fichier $SMB_PASSWD_FILE n'existe pas. Création en cours..."

    read -rp "👤 Entrez le nom d'utilisateur du domaine : " ADMIN_USER
    read -rsp "🔑 Entrez le mot de passe : " ADMIN_PASSWORD
    echo ""

    echo "username=$ADMIN_USER" > "$SMB_PASSWD_FILE"
    echo "password=$ADMIN_PASSWORD" >> "$SMB_PASSWD_FILE"
    chmod 600 "$SMB_PASSWD_FILE"

    log "✅ Fichier d'identifiants créé et sécurisé."
else
    log "🔐 Le fichier d'identifiants existe déjà. Vérification des permissions..."
    chmod 600 "$SMB_PASSWD_FILE"
fi

# 3. Charger les identifiants et s'authentifier via Kerberos
ADMIN_USER=$(grep '^username=' "$SMB_PASSWD_FILE" | cut -d'=' -f2)
ADMIN_PASSWORD=$(grep '^password=' "$SMB_PASSWD_FILE" | cut -d'=' -f2)

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASSWORD" ]; then
    log "❌ Erreur : identifiants introuvables ou incomplets."
    exit 1
fi

DOMAIN_UPPER=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
log "🔑 Obtention d'un ticket Kerberos pour $ADMIN_USER@$DOMAIN_UPPER..."
echo "$ADMIN_PASSWORD" | kinit "$ADMIN_USER@$DOMAIN_UPPER" 2>> "$LOG_FILE"
if [ $? -ne 0 ]; then
    log "❌ Erreur : Impossible d'obtenir un ticket Kerberos."
    exit 1
fi
log "✅ Ticket Kerberos obtenu."

# 4. Créer ou vérifier la GPO NTP_Sync
log "🚀 Création / Vérification de la GPO '$GPO_NAME'..."
EXISTING_GPO=$(samba-tool gpo list "$ADMIN_USER" --use-kerberos=required | grep -E "^$GPO_NAME\s")
if [ -z "$EXISTING_GPO" ]; then
    log "📌 La GPO '$GPO_NAME' n'existe pas. Création en cours..."
    samba-tool gpo create "$GPO_NAME" --use-kerberos=required 2>&1 | tee -a "$LOG_FILE"
    sleep 2
else
    log "✅ La GPO '$GPO_NAME' existe déjà."
fi

# 5. Récupération du GUID
log "🔍 Récupération du GUID de la GPO '$GPO_NAME'..."
GPO_GUID=$(samba-tool gpo listall --use-kerberos=required | awk -v gpo="$GPO_NAME" '
    /^GPO[ \t]+:/ { guid=$3 }
    /^display name[ \t]+:/ {
        if ($0 ~ gpo) {
            gsub(/[{}]/, "", guid);
            print guid;
            exit;
        }
    }
')
if [ -z "$GPO_GUID" ]; then
    log "❌ Erreur : Impossible de récupérer le GUID de la GPO '$GPO_NAME'."
    exit 1
fi
log "✅ GUID récupéré : {$GPO_GUID}"

# 6. Appliquer le fichier .pol (template) dans la GPO
if [ ! -f "$GPO_TEMPLATE_FILE" ]; then
    log "⚠️ Aucune template .pol trouvée pour '$GPO_NAME' dans $GPO_TEMPLATE_FILE."
    log "   Impossible d'appliquer les paramètres NTP."
else
    GPO_FOLDER="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"
    mkdir -p "$GPO_FOLDER/Machine"
    cp "$GPO_TEMPLATE_FILE" "$GPO_FOLDER/Machine/Registry.pol"
    log "✅ Paramètres NTP copiés dans la GPO '$GPO_NAME'."
fi

# 7. Lier la GPO à l'OU
log "🔗 Liaison de la GPO '$GPO_NAME' à l'OU '$OU_PATH'..."
samba-tool gpo setlink "$OU_PATH" "{$GPO_GUID}" --use-kerberos=required 2>&1 | tee -a "$LOG_FILE"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    log "❌ Erreur : Impossible de lier la GPO '$GPO_NAME' à l'OU '$OU_PATH'."
    exit 1
fi
log "✅ GPO liée avec succès."

log "================================="
log "✅ Configuration NTP_Sync terminée !"
log "================================="
