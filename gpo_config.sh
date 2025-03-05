#!/bin/bash

LOG_FILE="/var/log/samba-gpo-setup.log"
DOMAIN="northstar.com"
SMB_PASSWD_FILE="/root/.smbpasswd"
KRB5_CACHE="/tmp/krb5cc_samba"

# Vérification du fichier de log
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Fonction pour journaliser et afficher les messages
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

log "==============================="
log "🛠️ Début de la configuration des GPOs..."
log "==============================="

########################################################
# 1️⃣ Création et sécurisation du fichier d'identifiants
########################################################
if [ ! -f "$SMB_PASSWD_FILE" ]; then
    log "🔐 Le fichier $SMB_PASSWD_FILE n'existe pas. Création en cours..."
    
    read -rp "👤 Entrez le nom d'utilisateur du domaine : " ADMIN_USER
    read -rsp "🔑 Entrez le mot de passe : " ADMIN_PASSWORD
    echo ""

    # Écriture dans le fichier avec permissions sécurisées
    echo "username=$ADMIN_USER" > "$SMB_PASSWD_FILE"
    echo "password=$ADMIN_PASSWORD" >> "$SMB_PASSWD_FILE"
    chmod 600 "$SMB_PASSWD_FILE"

    log "✅ Fichier d'identifiants créé et sécurisé."
else
    log "🔐 Le fichier d'identifiants existe déjà. Vérification des permissions..."
    chmod 600 "$SMB_PASSWD_FILE"
fi

########################################################
# 2️⃣ Chargement des identifiants et authentification Kerberos
########################################################
log "🔑 Chargement des identifiants depuis $SMB_PASSWD_FILE..."

# Lire les identifiants depuis le fichier sécurisé
ADMIN_USER=$(grep '^username=' "$SMB_PASSWD_FILE" | cut -d'=' -f2)
ADMIN_PASSWORD=$(grep '^password=' "$SMB_PASSWD_FILE" | cut -d'=' -f2)

# Vérifier si les identifiants ont bien été extraits
# Vérification et correction des identifiants
if [ ! -f "$SMB_PASSWD_FILE" ] || ! grep -q '^username=' "$SMB_PASSWD_FILE" || ! grep -q '^password=' "$SMB_PASSWD_FILE"; then
    log "❌ Erreur : Fichier d'identifiants manquant ou mal formaté."
    log "📌 Correction automatique : Création d'un nouveau fichier."

    read -rp "👤 Entrez le nom d'utilisateur du domaine : " ADMIN_USER
    read -rsp "🔑 Entrez le mot de passe : " ADMIN_PASSWORD
    echo ""

    # Écriture dans le fichier avec permissions sécurisées
    echo "username=$ADMIN_USER" > "$SMB_PASSWD_FILE"
    echo "password=$ADMIN_PASSWORD" >> "$SMB_PASSWD_FILE"
    chmod 600 "$SMB_PASSWD_FILE"

    log "✅ Fichier d'identifiants créé et sécurisé."
fi

# Lecture et nettoyage des identifiants
ADMIN_USER=$(grep '^username=' "$SMB_PASSWD_FILE" | awk -F '=' '{gsub(/^ +| +$/, "", $2); print $2}')
ADMIN_PASSWORD=$(grep '^password=' "$SMB_PASSWD_FILE" | awk -F '=' '{gsub(/^ +| +$/, "", $2); print $2}')

# Vérification finale après correction automatique
if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASSWORD" ]; then
    log "❌ Erreur critique : Impossible de récupérer les identifiants après correction."
    exit 1
fi


log "🔑 Obtention d'un ticket Kerberos pour $ADMIN_USER..."

# Correction du domaine en majuscules
DOMAIN_UPPER=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')

# Tentative de connexion Kerberos
echo "$ADMIN_PASSWORD" | kinit "$ADMIN_USER@$DOMAIN_UPPER" 2>> "$LOG_FILE"

if [ $? -ne 0 ]; then
    log "❌ Erreur : Impossible d'obtenir un ticket Kerberos ! Vérifiez les identifiants et la connectivité."
    exit 1
fi

log "✅ Ticket Kerberos obtenu avec succès."

########################################################
# 3️⃣ Vérification du DC et des permissions
########################################################
log "🔍 Vérification de la connectivité avec le DC..."
samba-tool dbcheck --cross-ncs 2>&1 | tee -a "$LOG_FILE"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    log "❌ Erreur : Impossible de contacter le contrôleur de domaine !"
    exit 1
fi
log "✅ DC accessible, on continue."

########################################################
# 4️⃣ Vérification et correction des permissions SYSVOL
########################################################
log "🔍 Vérification et correction des permissions SYSVOL..."
samba-tool ntacl sysvolreset | tee -a "$LOG_FILE"
chown -R root:"Domain Admins" /var/lib/samba/sysvol
chmod -R 770 /var/lib/samba/sysvol
log "✅ Permissions SYSVOL mises à jour !"

########################################################
# 5️⃣ Création et application des GPOs
########################################################
log "🚀 Application des GPOs..."

declare -A GPO_LIST=(
    ["Disable_CMD"]="OU=NS,OU=Servers_T1,DC=northstar,DC=com"
    ["Force_SMB_Encryption"]="OU=NS,OU=AdminWorkstations,DC=northstar,DC=com"
    ["Block_Temp_Executables"]="OU=NS,OU=Servers_T1,DC=northstar,DC=com"
    ["Disable_Telemetry"]="OU=NS,OU=AdminWorkstations,DC=northstar,DC=com"
    ["Block_USB_Access"]="OU=NS,OU=Servers_T1,DC=northstar,DC=com"
    ["Restrict_Control_Panel"]="OU=NS,OU=AdminWorkstations,DC=northstar,DC=com"
)

for GPO_NAME in "${!GPO_LIST[@]}"; do
    OU_PATH="${GPO_LIST[$GPO_NAME]}"

    # Vérifier si la GPO existe déjà
    EXISTING_GPO=$(samba-tool gpo list | grep -E "^$GPO_NAME\s")
    if [ -z "$EXISTING_GPO" ]; then
        log "📌 Création de la GPO '$GPO_NAME'..."
        samba-tool gpo create "$GPO_NAME" --use-kerberos=required 2>&1 | tee -a "$LOG_FILE"
        sleep 2  # Délai pour s'assurer de la création
    else
        log "✅ La GPO '$GPO_NAME' existe déjà."
    fi

    # Récupération du GUID de manière plus robuste
    GPO_GUID=$(samba-tool gpo list | grep -E "^$GPO_NAME\s" | awk '{print $3}')
    GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"

    if [ -z "$GPO_GUID" ]; then
        log "❌ Erreur : Impossible de récupérer le GUID pour la GPO '$GPO_NAME'."
        exit 1
    fi

    # Appliquer la GPO à l'OU avec Kerberos
    log "🔗 Lien de la GPO '$GPO_NAME' à l'OU '$OU_PATH'..."
    samba-tool gpo setlink "$OU_PATH" "$GPO_NAME" --use-kerberos=required 2>&1 | tee -a "$LOG_FILE"

    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        log "❌ Erreur : Impossible de lier la GPO '$GPO_NAME' à l'OU '$OU_PATH' !"
        exit 1
    fi
done

########################################################
# 6️⃣ Fin de la configuration
########################################################
log "==============================="
log "✅ Configuration complète des GPOs !"
log "==============================="
