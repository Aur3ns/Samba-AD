#!/bin/bash

LOG_FILE="/var/log/samba-setup.log"
DOMAIN="northstar.com"
SMB_PASSWD_FILE="/root/.smbpasswd"
ADMIN_USER="Administrator"
ADMIN_PASSWORD="@fterTheB@ll33/"  # ⚠️ Change ici si nécessaire

# Vérification si le fichier de log existe
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

echo "===============================" | tee -a "$LOG_FILE"
echo "🛠️ Début de la configuration des GPOs..." | tee -a "$LOG_FILE"
echo "===============================" | tee -a "$LOG_FILE"

########################################################
# 1️⃣ Création et sécurisation du fichier de mot de passe Samba
########################################################
if [ ! -f "$SMB_PASSWD_FILE" ]; then
    echo "🔒 Création du fichier de mot de passe Samba..."
    echo "username = $ADMIN_USER" > "$SMB_PASSWD_FILE"
    echo "password = $ADMIN_PASSWORD" >> "$SMB_PASSWD_FILE"
    chmod 600 "$SMB_PASSWD_FILE"
    echo "✅ Fichier de mot de passe créé et sécurisé !" | tee -a "$LOG_FILE"
else
    echo "✅ Fichier de mot de passe déjà existant, aucune modification." | tee -a "$LOG_FILE"
fi

########################################################
# 2️⃣ Vérification des permissions du SYSVOL
########################################################
echo "🔍 Vérification et correction des permissions SYSVOL..." | tee -a "$LOG_FILE"
samba-tool ntacl sysvolreset
chown -R root:"Domain Admins" /var/lib/samba/sysvol
chmod -R 770 /var/lib/samba/sysvol
echo "✅ Permissions SYSVOL mises à jour !" | tee -a "$LOG_FILE"

########################################################
# 3️⃣ Fonction : create_gpo
# Crée une GPO et retourne son GUID et chemin
########################################################
create_gpo() {
    local GPO_NAME="$1"
    
    echo "📌 Création de la GPO '$GPO_NAME'..." | tee -a "$LOG_FILE"
    samba-tool gpo create "$GPO_NAME" --configfile="$SMB_PASSWD_FILE" 2>&1 | tee -a "$LOG_FILE"
    
    # Vérification si la création a réussi
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "❌ Erreur : Échec lors de la création de la GPO '$GPO_NAME' !" | tee -a "$LOG_FILE"
        exit 1
    fi

    # Récupération du GUID
    local GPO_GUID
    GPO_GUID=$(samba-tool gpo list | grep -E "^$GPO_NAME\s" | awk '{print $3}')
    local GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"

    if [ -z "$GPO_GUID" ]; then
        echo "❌ Erreur : Impossible de récupérer le GUID pour la GPO '$GPO_NAME'." | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "$GPO_GUID" "$GPO_PATH"
}

########################################################
# 4️⃣ Fonction : apply_gpo_to_ou
# Applique une GPO à une OU spécifique
########################################################
apply_gpo_to_ou() {
    local GPO_NAME="$1"
    local GPO_GUID="$2"
    local OU_PATH="$3"

    echo "🔗 Lien de la GPO '$GPO_NAME' à l'OU '$OU_PATH'..." | tee -a "$LOG_FILE"
    samba-tool gpo setlink "$OU_PATH" "$GPO_NAME" --configfile="$SMB_PASSWD_FILE" 2>&1 | tee -a "$LOG_FILE"
    
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "❌ Erreur : Impossible de lier la GPO '$GPO_NAME' à l'OU '$OU_PATH' !" | tee -a "$LOG_FILE"
        exit 1
    fi
}

########################################################
# 5️⃣ Création, configuration et application des GPOs
########################################################
echo "🚀 Application des GPOs..." | tee -a "$LOG_FILE"

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
    
    # Créer la GPO et récupérer son GUID et chemin
    read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"

    # Modifier les paramètres de la GPO
    case "$GPO_NAME" in
        "Disable_CMD")
            echo "[System Access]
DisableCMD = 1" > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
            ;;
        "Force_SMB_Encryption")
            echo "[Registry Settings]
HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters!SMB1=DWORD:0
HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters!EncryptData=DWORD:1" > "$GPO_PATH/Machine/Registry.pol"
            ;;
        "Block_Temp_Executables")
            echo "[Software Restriction Policy]
%TEMP%\*.exe = Disallowed
%TEMP%\*.ps1 = Disallowed
%TEMP%\*.bat = Disallowed
%APPDATA%\*.exe = Disallowed" > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
            ;;
        "Disable_Telemetry")
            echo "[Registry Settings]
HKLM\Software\Policies\Microsoft\Windows\DataCollection!AllowTelemetry=DWORD:0" > "$GPO_PATH/Machine/Registry.pol"
            ;;
        "Block_USB_Access")
            echo "[Registry Settings]
HKLM\System\CurrentControlSet\Services\USBSTOR!Start=DWORD:4" > "$GPO_PATH/Machine/Registry.pol"
            ;;
        "Restrict_Control_Panel")
            echo "[User Configuration]
NoControlPanel = 1" > "$GPO_PATH/User/Microsoft/Windows/Group Policy Objects/GptTmpl.inf"
            ;;
    esac

    # Appliquer la GPO à l'OU
    apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "$OU_PATH"
done

########################################################
# 6️⃣ Fin de la configuration
########################################################
echo "===============================" | tee -a "$LOG_FILE"
echo "✅ Configuration complète des GPOs !" | tee -a "$LOG_FILE"
echo "===============================" | tee -a "$LOG_FILE"
