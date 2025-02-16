#!/bin/bash

LOG_FILE="/var/log/samba-gpo-setup.log"
DOMAIN="northstar.com"

# Vérification si le fichier de log existe, sinon création
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

########################################################
# Fonction : create_gpo
# Crée une GPO et retourne son GUID et son chemin
########################################################
create_gpo() {
    local GPO_NAME="$1"
    
    echo "📌 Création de la GPO '$GPO_NAME'..." | tee -a "$LOG_FILE"
    samba-tool gpo create "$GPO_NAME" 2>&1 | tee -a "$LOG_FILE"
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
# Fonction : apply_gpo_to_ou
# Applique une GPO à une ou plusieurs OUs
########################################################
# Applique la GPO à une OU spécifique
apply_gpo_to_ou() {
    local GPO_NAME="$1"
    local GPO_GUID="$2"
    shift 2
    local OUs=("$@")

    for OU_PATH in "${OUs[@]}"; do
        echo " Lien de la GPO '$GPO_NAME' à l'OU '$OU_PATH'..." | tee -a "$LOG_FILE"
        samba-tool gpo setlink "$OU_PATH" "$GPO_NAME" 2>&1 | tee -a "$LOG_FILE"
        if [ "${PIPESTATUS[0]}" -ne 0 ]; then
            echo " Erreur : Impossible de lier la GPO '$GPO_NAME' à l'OU '$OU_PATH' !" | tee -a "$LOG_FILE"
            exit 1
        fi
    done
}

########################################################
# Application des GPOs globales (T1, T2)
########################################################
echo " Application des GPOs globales (T1, T2)..." | tee -a "$LOG_FILE"

# Liste des OUs cibles globales
OUs=("OU=NS,OU=Servers_T1,DC=northstar,DC=com" "OU=NS,OU=AdminWorkstations,DC=northstar,DC=com")

# 1. Désactivation de l'accès à cmd.exe
GPO_NAME="Disable_CMD"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[System Access]
DisableCMD = 1
EOF
apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "${OUs[@]}"

# 2. Forcer le chiffrement SMB
GPO_NAME="Force_SMB_Encryption"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"
cat <<EOF > "$GPO_PATH/Machine/Registry.pol"
[Registry Settings]
HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters!SMB1=DWORD:0
HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters!EncryptData=DWORD:1
EOF
apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "${OUs[@]}"

# 3. Bloquer les exécutables dans les répertoires temporaires
GPO_NAME="Block_Temp_Executables"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Software Restriction Policy]
%TEMP%\*.exe = Disallowed
%TEMP%\*.ps1 = Disallowed
%TEMP%\*.bat = Disallowed
%APPDATA%\*.exe = Disallowed
EOF
apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "${OUs[@]}"

# 4. Désactivation de la télémétrie Windows
GPO_NAME="Disable_Telemetry"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"
cat <<EOF > "$GPO_PATH/Machine/Registry.pol"
[Registry Settings]
HKLM\Software\Policies\Microsoft\Windows\DataCollection!AllowTelemetry=DWORD:0
EOF
apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "${OUs[@]}"

# 5. Bloquer l’accès aux périphériques USB
GPO_NAME="Block_USB_Access"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"
cat <<EOF > "$GPO_PATH/Machine/Registry.pol"
[Registry Settings]
HKLM\System\CurrentControlSet\Services\USBSTOR!Start=DWORD:4
EOF
apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "${OUs[@]}"

# 6. Restreindre l’accès aux panneaux de configuration
GPO_NAME="Restrict_Control_Panel"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"
cat <<EOF > "$GPO_PATH/User/Microsoft/Windows/Group Policy Objects/GptTmpl.inf"
[User Configuration]
NoControlPanel = 1
EOF
apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "${OUs[@]}"

########################################################
# SECTION T0 : Configuration pour T0
########################################################
echo " Début de la configuration pour T0..." | tee -a "$LOG_FILE"

GPO_NAME="Restrict_T0"
OU_PATH="OU=NS,OU=Group_ADMT0,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT0
SeDenyInteractiveLogonRight = NORTHSTAR\Group_ADMT0
SeDenyRemoteInteractiveLogonRight = NORTHSTAR\Group_ADMT0
EOF
apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "$OU_PATH"

########################################################
# SECTION T1 : Configuration pour T1
########################################################
echo " Début de la configuration pour T1..." | tee -a "$LOG_FILE"

GPO_NAME="Enable_RDP_T1"
OU_PATH="OU=NS,OU=Servers_T1,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"
cat <<EOF > "$GPO_PATH/Machine/Registry.pol"
[Registry Settings]
HKLM\System\CurrentControlSet\Control\Terminal Server!fDenyTSConnections=DWORD:0
EOF
apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "$OU_PATH"

########################################################
# SECTION T2 : Configuration pour T2
########################################################
echo " Début de la configuration pour T2..." | tee -a "$LOG_FILE"

GPO_NAME="Restrict_T2"
OU_PATH="OU=NS,OU=Group_ADMT2,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT2
EOF
apply_gpo_to_ou "$GPO_NAME" "$GPO_GUID" "$OU_PATH"

########################################################
# Fin de la configuration
########################################################
echo "===============================" | tee -a "$LOG_FILE"
echo " Configuration complète des GPOs ! " | tee -a "$LOG_FILE"
echo "===============================" | tee -a "$LOG_FILE"
