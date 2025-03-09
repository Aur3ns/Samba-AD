#!/bin/bash
# Script complet pour créer les templates de paramètres .pol, configurer l'authentification Kerberos,
# créer, lier et appliquer les GPO dans Samba.
#
# À exécuter en tant que root.


set -e 

###############################################
# 0. Création des templates de paramètres .pol
###############################################
TEMPLATE_DIR="/root/gpo_templates"
mkdir -p "$TEMPLATE_DIR"

cat << 'EOF' > "$TEMPLATE_DIR/Disable_CMD.pol"
; Registry.pol file for Disable_CMD
; Désactive l'invite de commandes
[Software\Policies\Microsoft\Windows\System]
"DisableCMD"=dword:00000001
EOF

cat << 'EOF' > "$TEMPLATE_DIR/Force_SMB_Encryption.pol"
; Registry.pol file for Force_SMB_Encryption
; Force le chiffrement SMB pour les connexions réseau
[Software\Policies\Microsoft\Windows\LanmanWorkstation]
"EnableSMBEncryption"=dword:00000001
EOF

cat << 'EOF' > "$TEMPLATE_DIR/Block_Temp_Executables.pol"
; Registry.pol file for Block_Temp_Executables
; Bloque l'exécution de programmes depuis les dossiers temporaires
[Software\Policies\Microsoft\Windows\Explorer]
"PreventRun"=dword:00000001
EOF

cat << 'EOF' > "$TEMPLATE_DIR/Disable_Telemetry.pol"
; Registry.pol file for Disable_Telemetry
; Désactive la télémétrie Windows
[Software\Policies\Microsoft\Windows\DataCollection]
"AllowTelemetry"=dword:00000000
EOF

cat << 'EOF' > "$TEMPLATE_DIR/NTP_Sync.pol"
; Registry.pol file for NTP_Sync
; Configure la synchronisation NTP avec le contrôleur de domaine
[Software\Policies\Microsoft\W32Time\Parameters]
"Type"="NTP"
"NtpServer"="northstar.com,0x1"
EOF

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

touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

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
# 3. Application des permissions sur SYSVOL et redémarrage de Samba
########################################################
samba-tool ntacl sysvolreset
chown -R root:root /var/lib/samba/sysvol
chmod -R 755 /var/lib/samba/sysvol
systemctl restart samba-ad-dc

########################################################
# 4. Authentification Kerberos
########################################################
log "🔑 Chargement des identifiants depuis $SMB_PASSWD_FILE..."
ADMIN_USER=$(grep '^username=' "$SMB_PASSWD_FILE" | cut -d'=' -f2)
ADMIN_PASSWORD=$(grep '^password=' "$SMB_PASSWD_FILE" | cut -d'=' -f2)

if [ -z "$ADMIN_USER" ] || [ -z "$ADMIN_PASSWORD" ]; then
    log "❌ Erreur : Identifiants introuvés."
    exit 1
fi

log "🔑 Obtention d'un ticket Kerberos pour $ADMIN_USER..."
DOMAIN_UPPER=$(echo "$DOMAIN" | tr '[:lower:]' '[:upper:]')
echo "$ADMIN_PASSWORD" | kinit "$ADMIN_USER@$DOMAIN_UPPER"
if [ $? -ne 0 ]; then
    log "❌ Erreur : Impossible d'obtenir un ticket Kerberos."
    exit 1
fi
log "✅ Ticket Kerberos obtenu avec succès."

########################################################
# 5. Vérification de la connectivité avec le DC
########################################################
log "🔍 Vérification de la connectivité avec le DC..."
samba-tool dbcheck --cross-ncs | tee -a "$LOG_FILE"
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log "❌ Erreur : DC inaccessible."
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

# Tableau associatif : nom de la GPO -> OU de liaison
declare -A GPO_LIST=(
    ["Disable_CMD"]="OU=UsersWorkstations,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["Force_SMB_Encryption"]="OU=UsersWorkstations,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["Block_Temp_Executables"]="OU=UsersWorkstations,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["Disable_Telemetry"]="OU=UsersWorkstations,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["NTP_Sync"]="OU=UsersWorkstations,OU=Workstations,OU=NS,DC=northstar,DC=com"
    ["Security_Message"]="OU=UsersWorkstations,OU=Workstations,OU=NS,DC=northstar,DC=com"
)
# Tableau associatif pour le type de GPO (Machine ou User)
declare -A GPO_TYPE=(
    ["Disable_CMD"]="Machine"
    ["Force_SMB_Encryption"]="Machine"
    ["Block_Temp_Executables"]="Machine"
    ["Disable_Telemetry"]="Machine"
    ["NTP_Sync"]="Machine"
    ["Security_Message"]="Machine"
)

for GPO_NAME in "${!GPO_LIST[@]}"; do
    OU_PATH="${GPO_LIST[$GPO_NAME]}"
    
    # Récupération de l'utilisateur (déjà vérifié)
    ADMIN_USER=$(grep '^username=' "$SMB_PASSWD_FILE" | awk -F '=' '{gsub(/^ +| +$/, "", $2); print $2}')
    if [ -z "$ADMIN_USER" ]; then
        log "❌ Erreur : Impossible de récupérer l'utilisateur depuis $SMB_PASSWD_FILE"
        exit 1
    fi
    
    # Vérifier si la GPO existe déjà
    EXISTING_GPO=$(samba-tool gpo list "$ADMIN_USER" --use-kerberos=required | grep -E "^$GPO_NAME\s")
    if [ -z "$EXISTING_GPO" ]; then
        log "📌 Création de la GPO '$GPO_NAME'..."
        CREATE_OUTPUT=$(samba-tool gpo create "$GPO_NAME" --use-kerberos=required 2>&1)
        echo "$CREATE_OUTPUT" >> "$LOG_FILE"
        sleep 2  # Attente pour la mise à jour de la liste
    else
        log "✅ La GPO '$GPO_NAME' existe déjà."
    fi
    
    ########################################################
    # Extraction du GUID à partir du champ "dn" du bloc
    ########################################################
    # Extraction du GUID à partir du champ "dn" du bloc
    GPO_GUID=$(samba-tool gpo listall 2>/dev/null | grep -E "^(display name|dn)" | awk -v gpo="$GPO_NAME" '
        BEGIN { IGNORECASE = 1 }
        /^display name[ \t]+:/ {
            if ($NF == gpo) {
                while (getline > 0) {
                    if ($0 ~ /^dn[ \t]+:/) {
                        # Découpe la ligne pour extraire le GUID
                        split($0, arr, "CN={");
                        if (length(arr) > 1) {
                            split(arr[2], arr2, "},");
                            print arr2[1];
                            exit
                        }
                    }
                }
            }
        }')

    


    if [ -z "$GPO_GUID" ]; then
        log "❌ Erreur : Impossible de récupérer le GUID pour la GPO '$GPO_NAME'."
        exit 1
    fi
    log "🔗 Liaison de la GPO '$GPO_NAME' (GUID: {$GPO_GUID}) à l'OU '$OU_PATH'..."
    samba-tool gpo setlink "$OU_PATH" "{$GPO_GUID}" --use-kerberos=required 2>&1 | tee -a "$LOG_FILE"
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log "❌ Erreur : Impossible de lier la GPO '$GPO_NAME' à l'OU '$OU_PATH'."
        exit 1
    fi

    ########################################################
    # 7.1 Application des paramètres via le template
    ########################################################
    TEMPLATE_FILE="$TEMPLATE_DIR/${GPO_NAME}.pol"
    if [ -f "$TEMPLATE_FILE" ]; then
        TYPE="${GPO_TYPE[$GPO_NAME]}"
        if [ "$TYPE" == "Machine" ]; then
            TARGET_FOLDER="/var/lib/samba/sysvol/${DOMAIN}/Policies/{$GPO_GUID}/Machine/Microsoft/Windows/Group Policy"
        else
            TARGET_FOLDER="/var/lib/samba/sysvol/${DOMAIN}/Policies/{$GPO_GUID}/User/Microsoft/Windows/Group Policy"
        fi
        mkdir -p "$TARGET_FOLDER"
        cp "$TEMPLATE_FILE" "$TARGET_FOLDER/Registry.pol"
        log "✅ Paramètres appliqués pour la GPO '$GPO_NAME' dans $TYPE."
    else
        log "⚠️ Aucun template trouvé pour la GPO '$GPO_NAME'."
    fi

    ########################################################
    # 7.2 Mise à jour ou création du fichier GPT.ini
    ########################################################
    GPO_FOLDER="/var/lib/samba/sysvol/${DOMAIN}/Policies/{$GPO_GUID}"
    GPT_FILE="${GPO_FOLDER}/GPT.ini"
    if [ ! -f "$GPT_FILE" ]; then
        cat << 'EOF' > "$GPT_FILE"
[General]
Version=1
EOF
        log "✅ GPT.ini créé pour la GPO '$GPO_NAME'."
    else
        current_version=$(grep '^Version=' "$GPT_FILE" | cut -d'=' -f2)
        new_version=$((current_version + 1))
        sed -i "s/^Version=.*/Version=${new_version}/" "$GPT_FILE"
        log "✅ GPT.ini mis à jour pour la GPO '$GPO_NAME' (Version ${new_version})."
    fi

done

log "==============================="
log "✅ Configuration complète des GPOs appliquée !"
log "==============================="