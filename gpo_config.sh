#!/bin/bash
set -e

###############################################
# Variables globales et initialisation
###############################################
LOG_FILE="/var/log/samba-gpo-setup.log"
DOMAIN="northstar.com"
SMB_PASSWD_FILE="/root/.smbpasswd"
TEMPLATE_DIR="/root/gpo_templates"
SYSVOL_DIR="/var/lib/samba/sysvol"

# Création (ou mise à jour) du fichier de log
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

# Fonction de log
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

###############################################
# 0. Création des templates de paramètres .pol
###############################################
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

# 5. Block_USB_Access.pol : bloque l'accès aux périphériques USB de stockage
cat << 'EOF' > "$TEMPLATE_DIR/Block_USB_Access.pol"
; Registry.pol file for Block_USB_Access
; Bloque l'accès en écriture aux périphériques de stockage USB
[Software\Policies\Microsoft\Windows\RemovableStorageDevices]
"WriteProtect"=dword:00000001
EOF

# 6. Restrict_Control_Panel.pol : restreint l'accès au panneau de configuration
cat << 'EOF' > "$TEMPLATE_DIR/Restrict_Control_Panel.pol"
; Registry.pol file for Restrict_Control_Panel
; Restreint l'accès au panneau de configuration Windows
[Software\Policies\Microsoft\Windows\ControlPanel]
"ProhibitCPL"=dword:00000001
EOF

# 7. NTP_Sync.pol : configure la synchronisation NTP
cat << 'EOF' > "$TEMPLATE_DIR/NTP_Sync.pol"
; NTP_Sync.pol
; Configure le service NTP pour utiliser le DC comme source de temps
[Software\Policies\Microsoft\Windows\W32Time\TimeProviders\NtpClient]
"Enabled"=dword:00000001
"NtpServer"="srv-ns.northstar.com,0x9"
"CrossSiteSyncFlags"=dword:00000002
"SpecialPollInterval"=dword:0000ea60
"EventLogFlags"=dword:00000001
"Type"="NTP"

[Software\Policies\Microsoft\Windows\W32Time\TimeProviders\NtpServer]
"Enabled"=dword:00000000
EOF

# 8. Logon_Warning.pol : message d'avertissement lors de la connexion
cat << 'EOF' > "$TEMPLATE_DIR/Logon_Warning.pol"
; Registry.pol file for Logon_Warning
; Affiche un message d'avertissement à chaque ouverture de session
[Software\Policies\Microsoft\Windows\System]
"legalnoticecaption"="Attention"
"legalnoticetext"="Accès réservé. Toute activité est surveillée. Toute utilisation non autorisée est interdite."
EOF

log "Fichiers .pol créés dans $TEMPLATE_DIR"

###############################################
# 1. Initialisation et configuration générale
###############################################
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
# 3. Réinitialisation et correction des permissions sur SYSVOL
########################################################
log "🔍 Réinitialisation des ACL sur SYSVOL..."
samba-tool ntacl sysvolreset >> "$LOG_FILE" 2>&1
chown -R root:root "$SYSVOL_DIR"
chmod -R 755 "$SYSVOL_DIR"
systemctl restart samba-ad-dc
log "✅ Permissions SYSVOL initialisées."

########################################################
# 4. Chargement des identifiants et authentification Kerberos
########################################################
log "🔑 Chargement des identifiants depuis $SMB_PASSWD_FILE..."
ADMIN_USER=$(grep '^username=' "$SMB_PASSWD_FILE" | cut -d'=' -f2 | tr -d ' ')
ADMIN_PASSWORD=$(grep '^password=' "$SMB_PASSWD_FILE" | cut -d'=' -f2- | tr -d ' ')

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASSWORD" ]; then
    log "❌ Erreur : Impossible de récupérer les identifiants depuis $SMB_PASSWD_FILE."
    exit 1
fi

DOMAIN_UPPER=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
log "🔑 Obtention d'un ticket Kerberos pour $ADMIN_USER@$DOMAIN_UPPER..."
echo "$ADMIN_PASSWORD" | kinit "$ADMIN_USER@$DOMAIN_UPPER" 2>> "$LOG_FILE"
if [ $? -ne 0 ]; then
    log "❌ Erreur : Impossible d'obtenir un ticket Kerberos ! Vérifiez les identifiants et la connectivité."
    exit 1
fi
log "✅ Ticket Kerberos obtenu avec succès."

########################################################
# 5. Vérification de la connectivité avec le contrôleur de domaine
########################################################
log "🔍 Vérification de la connectivité avec le DC..."
samba-tool dbcheck --cross-ncs >> "$LOG_FILE" 2>&1
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    log "❌ Erreur : Impossible de contacter le contrôleur de domaine !"
    exit 1
fi
log "✅ DC accessible, on continue."

log "🔍 Correction finale des permissions SYSVOL..."
samba-tool ntacl sysvolreset >> "$LOG_FILE" 2>&1
chown -R root:"Domain Admins" "$SYSVOL_DIR"
chmod -R 770 "$SYSVOL_DIR"
log "✅ Permissions SYSVOL mises à jour !"

########################################################
# 6. Suppression des GPO existantes (hors celles par défaut)
########################################################
log "🔄 Vérification des GPO existantes (hors GPO par défaut)..."
EXISTING_GPOS=$(samba-tool gpo list --use-kerberos=required | grep -v -E 'Default Domain Policy|Default Domain Controllers Policy')
if [ -n "$EXISTING_GPOS" ]; then
    echo "$EXISTING_GPOS" | while IFS= read -r line; do
        GPO_NAME_EXIST=$(echo "$line" | awk -F'  +' '{print $1}')
        log "🗑️ Suppression de la GPO existante : $GPO_NAME_EXIST"
        samba-tool gpo delete "$GPO_NAME_EXIST" --use-kerberos=required >> "$LOG_FILE" 2>&1
    done
    log "✅ Suppression des GPO existantes (hors GPO par défaut) terminée."
else
    log "✅ Aucune GPO existante à supprimer."
fi

########################################################
# 7. Création, liaison et application des GPOs
########################################################
log "🚀 Création et liaison des nouvelles GPOs..."

# Déclaration de la liste des GPOs et des OU de destination
declare -A GPO_LIST=(
    ["Disable_CMD"]="OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
    ["Force_SMB_Encryption"]="OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
    ["Block_Temp_Executables"]="OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
    ["Disable_Telemetry"]="OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
    ["Block_USB_Access"]="OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
    ["Restrict_Control_Panel"]="OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
    ["NTP_Sync"]="OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
    ["Logon_Warning"]="OU=AdminWorkstations,OU=NS,DC=northstar,DC=com"
)

for GPO_NAME in "${!GPO_LIST[@]}"; do
    OU_PATH="${GPO_LIST[$GPO_NAME]}"
    log "-------------------------------------"
    log "Traitement de la GPO '$GPO_NAME' pour l'OU '$OU_PATH'..."

    # Vérification si la GPO existe déjà
    EXISTING_GPO=$(samba-tool gpo list --use-kerberos=required | grep -E "^$GPO_NAME\s")
    if [ -z "$EXISTING_GPO" ]; then
        log "📌 Création de la GPO '$GPO_NAME'..."
        samba-tool gpo create "$GPO_NAME" --use-kerberos=required >> "$LOG_FILE" 2>&1
        sleep 2  # Petit délai pour assurer la création
    else
        log "✅ La GPO '$GPO_NAME' existe déjà."
    fi

    # Extraction du GUID de la GPO
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
    log "🔍 GUID pour '$GPO_NAME' : {$GPO_GUID}"

    # Définition du dossier de la GPO
    GPO_FOLDER="$SYSVOL_DIR/$DOMAIN/Policies/{$GPO_GUID}"
    log "🔗 Liaison de la GPO '$GPO_NAME' (GUID: {$GPO_GUID}) à l'OU '$OU_PATH'..."
    samba-tool gpo setlink "$OU_PATH" "{$GPO_GUID}" --use-kerberos=required >> "$LOG_FILE" 2>&1
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        log "❌ Erreur : Impossible de lier la GPO '$GPO_NAME' à l'OU '$OU_PATH'."
        exit 1
    fi

    ########################################################
    # Application des paramètres de la GPO via le template .pol
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
