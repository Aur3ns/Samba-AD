#!/bin/bash
# Ce script crée le répertoire /root/gpo_templates avec les fichiers .pol pour les GPOs
# (Disable_CMD, Force_SMB_Encryption, Block_Temp_Executables, Disable_Telemetry,
# NTP_Sync et Security_Message) puis configure et applique ces GPOs sur Samba.

###############################################
# 0. Création des templates de paramètres .pol
###############################################
TEMPLATE_DIR="/root/gpo_templates"

# Créer le répertoire s'il n'existe pas déjà
mkdir -p "$TEMPLATE_DIR"

# 1. Disable_CMD.pol : désactive l'accès à l'invite de commandes
cat << 'EOF' > "$TEMPLATE_DIR/Disable_CMD.pol"
; Registry.pol file for Disable_CMD
; Désactive l'invite de commandes
[Software\Policies\Microsoft\Windows\System]
"DisableCMD"=dword:00000001
EOF

# 2. Force_SMB_Encryption.pol : force le chiffrement SMB
cat << 'EOF' > "$TEMPLATE_DIR/Force_SMB_Encryption.pol"
; Registry.pol file for Force_SMB_Encryption
; Force le chiffrement SMB pour les connexions réseau
[Software\Policies\Microsoft\Windows\LanmanWorkstation]
"EnableSMBEncryption"=dword:00000001
EOF

# 3. Block_Temp_Executables.pol : bloque l'exécution depuis le dossier Temp
cat << 'EOF' > "$TEMPLATE_DIR/Block_Temp_Executables.pol"
; Registry.pol file for Block_Temp_Executables
; Bloque l'exécution de programmes depuis les dossiers temporaires
[Software\Policies\Microsoft\Windows\Explorer]
"PreventRun"=dword:00000001
EOF

# 4. Disable_Telemetry.pol : désactive la télémétrie
cat << 'EOF' > "$TEMPLATE_DIR/Disable_Telemetry.pol"
; Registry.pol file for Disable_Telemetry
; Désactive la télémétrie Windows
[Software\Policies\Microsoft\Windows\DataCollection]
"AllowTelemetry"=dword:00000000
EOF

# 5. NTP_Sync.pol : configure la synchronisation NTP avec le contrôleur de domaine
cat << 'EOF' > "$TEMPLATE_DIR/NTP_Sync.pol"
; Registry.pol file for NTP_Sync
; Configure la synchronisation NTP avec le contrôleur de domaine
[Software\Policies\Microsoft\W32Time\Parameters]
"Type"="NTP"
"NtpServer"="northstar.com,0x1"
EOF

# 6. Security_Message.pol : affiche un message de sécurité à l'ouverture d'une session
cat << 'EOF' > "$TEMPLATE_DIR/Security_Message.pol"
; Registry.pol file for Security_Message
; Affiche un message de sécurité à l'ouverture d'une session
[Software\Policies\Microsoft\Windows\System]
"legalnoticecaption"="Security Notice"
"legalnoticetext"="Attention : Ce système est réservé aux utilisateurs autorisés uniquement."
EOF

echo "Fichiers .pol créés dans $TEMPLATE_DIR"

###############################################
# 1. Initialisation et configuration générale
###############################################
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
# 2. Création et sécurisation du fichier d'identifiants
########################################################
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

########################################################
# 3. Application des BONNES permissions sur le SYSVOL ou les GPOs seront stockées
########################################################
samba-tool ntacl sysvolreset
chown -R root:root /var/lib/samba/sysvol
chmod -R 755 /var/lib/samba/sysvol
systemctl restart samba-ad-dc

########################################################
# 4. Chargement des identifiants et authentification Kerberos
########################################################
log "🔑 Chargement des identifiants depuis $SMB_PASSWD_FILE..."

# Lire les identifiants depuis le fichier sécurisé
ADMIN_USER=$(grep '^username=' "$SMB_PASSWD_FILE" | cut -d'=' -f2)
ADMIN_PASSWORD=$(grep '^password=' "$SMB_PASSWD_FILE" | cut -d'=' -f2)

# Vérifier si le fichier est correctement formaté
if [ ! -f "$SMB_PASSWD_FILE" ] || ! grep -q '^username=' "$SMB_PASSWD_FILE" || ! grep -q '^password=' "$SMB_PASSWD_FILE"; then
    log "❌ Erreur : Fichier d'identifiants manquant ou mal formaté."
    log "📌 Correction automatique : Création d'un nouveau fichier."
    
    read -rp "👤 Entrez le nom d'utilisateur du domaine : " ADMIN_USER
    read -rsp "🔑 Entrez le mot de passe : " ADMIN_PASSWORD
    echo ""
    
    echo "username=$ADMIN_USER" > "$SMB_PASSWD_FILE"
    echo "password=$ADMIN_PASSWORD" >> "$SMB_PASSWD_FILE"
    chmod 600 "$SMB_PASSWD_FILE"
    
    log "✅ Fichier d'identifiants créé et sécurisé."
fi

# Lecture et nettoyage des identifiants
ADMIN_USER=$(grep '^username=' "$SMB_PASSWD_FILE" | awk -F '=' '{gsub(/^ +| +$/, "", $2); print $2}')
ADMIN_PASSWORD=$(grep '^password=' "$SMB_PASSWD_FILE" | awk -F '=' '{gsub(/^ +| +$/, "", $2); print $2}')

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASSWORD" ]; then
    log "❌ Erreur critique : Impossible de récupérer les identifiants après correction."
    exit 1
fi

log "🔑 Obtention d'un ticket Kerberos pour $ADMIN_USER..."
DOMAIN_UPPER=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
echo "$ADMIN_PASSWORD" | kinit "$ADMIN_USER@$DOMAIN_UPPER" 2>> "$LOG_FILE"
if [ $? -ne 0 ]; then
    log "❌ Erreur : Impossible d'obtenir un ticket Kerberos ! Vérifiez les identifiants et la connectivité."
    exit 1
fi
log "✅ Ticket Kerberos obtenu avec succès."

########################################################
# 5. Vérification du DC et des permissions
########################################################
log "🔍 Vérification de la connectivité avec le DC..."
samba-tool dbcheck --cross-ncs 2>&1 | tee -a "$LOG_FILE"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    log "❌ Erreur : Impossible de contacter le contrôleur de domaine !"
    exit 1
fi
log "✅ DC accessible, on continue."

########################################################
# 6. Vérification et correction des permissions SYSVOL
########################################################
log "🔍 Vérification et correction des permissions SYSVOL..."
samba-tool ntacl sysvolreset | tee -a "$LOG_FILE"
chown -R root:"Domain Admins" /var/lib/samba/sysvol
chmod -R 770 /var/lib/samba/sysvol
log "✅ Permissions SYSVOL mises à jour !"

########################################################
# 7. Création, liaison et application des GPOs
########################################################
log "🚀 Application des GPOs..."

declare -A GPO_LIST=(
    ["Disable_CMD"]="UsersWorkstation,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["Force_SMB_Encryption"]="UsersWorkstation,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["Block_Temp_Executables"]="UsersWorkstation,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["Disable_Telemetry"]="UsersWorkstation,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["NTP_Sync"]="UsersWorkstation,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["Security_Message"]="UsersWorkstation,OU=Workstations,OU=NS,DC=northstar,DC=com"
)

for GPO_NAME in "${!GPO_LIST[@]}"; do
    OU_PATH="${GPO_LIST[$GPO_NAME]}"
    
    # Vérification que l'utilisateur est défini
    ADMIN_USER=$(grep '^username=' "$SMB_PASSWD_FILE" | awk -F '=' '{gsub(/^ +| +$/, "", $2); print $2}')
    if [ -z "$ADMIN_USER" ]; then
        log "❌ Erreur : Impossible de récupérer l'utilisateur depuis $SMB_PASSWD_FILE"
        exit 1
    fi
    
    # Vérifier si la GPO existe déjà
    EXISTING_GPO=$(samba-tool gpo list "$ADMIN_USER" --use-kerberos=required | grep -E "^$GPO_NAME\s")
    if [ -z "$EXISTING_GPO" ]; then
        log "📌 Création de la GPO '$GPO_NAME'..."
        samba-tool gpo create "$GPO_NAME" --use-kerberos=required 2>&1 | tee -a "$LOG_FILE"
        sleep 2  # Délai pour s'assurer de la création
    else
        log "✅ La GPO '$GPO_NAME' existe déjà."
    fi
    
    # Extraction du GUID de la GPO de manière robuste
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
        log "❌ Erreur : Impossible de récupérer le GUID pour la GPO '$GPO_NAME'."
        exit 1
    fi
    
    # Construction du dossier de la GPO
    GPO_FOLDER="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"
    log "🔗 Lien de la GPO '$GPO_NAME' (GUID: {$GPO_GUID}) à l'OU '$OU_PATH'..."
    samba-tool gpo setlink "$OU_PATH" "{$GPO_GUID}" --use-kerberos=required 2>&1 | tee -a "$LOG_FILE"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        log "❌ Erreur : Impossible de lier la GPO '$GPO_NAME' à l'OU '$OU_PATH' !"
        exit 1
    fi
    
    ########################################################
    # 7.1 Application des paramètres de la GPO à partir d'un template
    ########################################################
    TEMPLATE_FILE="$TEMPLATE_DIR/${GPO_NAME}.pol"
    if [ -f "$TEMPLATE_FILE" ]; then
        mkdir -p "$GPO_FOLDER/Machine"
        cp "$TEMPLATE_FILE" "$GPO_FOLDER/Machine/Registry.pol"
        log "✅ Paramètres appliqués pour la GPO '$GPO_NAME'."
    else
        log "⚠️ Aucun template trouvé pour la GPO '$GPO_NAME'. Aucun paramètre appliqué."
    fi
done

########################################################
# 8. Fin de la configuration
########################################################
log "==============================="
log "✅ Configuration complète des GPOs !"
log "==============================="
