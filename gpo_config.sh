#!/bin/bash

LOG_FILE="/var/log/samba-gpo-setup.log"
DOMAIN="northstar.com"

# Vérification si le fichier de log existe, sinon création
touch "$LOG_FILE"
chmod 600 "$LOG_FILE"

########################################################
# Fonction : create_gpo
# Crée une GPO, puis retourne son GUID et son chemin
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
    GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk '{print $3}')
    # Construction du chemin de la GPO dans SYSVOL
    local GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"

    if [ -z "$GPO_GUID" ]; then
        echo "❌ Erreur : Impossible de récupérer le GUID pour la GPO '$GPO_NAME'." | tee -a "$LOG_FILE"
        exit 1
    fi

    echo "$GPO_GUID" "$GPO_PATH"
}

########################################################
# Fonction : apply_gpo_to_ou
# Applique la GPO à une ou plusieurs OUs
########################################################
apply_gpo_to_ou() {
    local GPO_NAME="$1"
    local GPO_GUID="$2"
    shift 2
    local OUs=("$@")

    for OU_PATH in "${OUs[@]}"; do
        echo "📌 Application de la GPO '$GPO_NAME' à l'OU '$OU_PATH'..." | tee -a "$LOG_FILE"
        
        # Activation de la GPO
        samba-tool gpo setoptions "$GPO_NAME" --enable 2>&1 | tee -a "$LOG_FILE"
        if [ "${PIPESTATUS[0]}" -ne 0 ]; then
            echo "❌ Erreur : Impossible d'activer la GPO '$GPO_NAME' !" | tee -a "$LOG_FILE"
            exit 1
        fi

        # Application de la GPO sur l'OU
        samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH" 2>&1 | tee -a "$LOG_FILE"
        if [ "${PIPESTATUS[0]}" -ne 0 ]; then
            echo "❌ Erreur : Impossible d'appliquer la GPO '$GPO_NAME' à l'OU '$OU_PATH' !" | tee -a "$LOG_FILE"
            exit 1
        fi
    done
}

########################################################
# Fonction : apply_gpo
# Applique la GPO à UNE seule OU (version simplifiée)
########################################################
apply_gpo() {
    local GPO_NAME="$1"
    local OU_PATH="$2"
    local GPO_GUID="$3"
    local GPO_PATH="$4"

    echo "📌 Application de la GPO '$GPO_NAME' à l'OU '$OU_PATH'..." | tee -a "$LOG_FILE"
    samba-tool gpo setoptions "$GPO_NAME" --enable 2>&1 | tee -a "$LOG_FILE"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "❌ Erreur : Impossible d'activer la GPO '$GPO_NAME' !" | tee -a "$LOG_FILE"
        exit 1
    fi

    samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH" 2>&1 | tee -a "$LOG_FILE"
    if [ "${PIPESTATUS[0]}" -ne 0 ]; then
        echo "❌ Erreur : Impossible d'appliquer la GPO '$GPO_NAME' à l'OU '$OU_PATH' !" | tee -a "$LOG_FILE"
        exit 1
    fi
}

########################################################
# Section : Application GPOs globales (T1, T2)
########################################################

echo "🔹 Application des GPOs globales (T1, T2)..." | tee -a "$LOG_FILE"

# Liste des OUs cibles globales (Servers_T1 et AdminWorkstations)
OUs=("OU=NS,OU=Servers_T1,DC=northstar,DC=com" "OU=NS,OU=AdminWorkstations,DC=northstar,DC=com")

# 1. Désactiver l'accès à l'invite de commandes (cmd.exe)
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

# 3. Empêcher l’exécution de .exe, .ps1 et .bat depuis des répertoires temporaires
GPO_NAME="Block_Temp_Executables"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"

cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Software Restriction Policy]
%TEMP%\*.exe = Disallowed
%TEMP%\*.ps1 = Disallowed
%TEMP%\*.bat = Disallowed
%APPDATA%\*.exe = Disallowed
%APPDATA%\*.ps1 = Disallowed
%APPDATA%\*.bat = Disallowed
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

# 6. Restreindre l’accès aux panneaux de configuration et outils d’administration
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
echo "🔹 Début de la configuration pour T0..." | tee -a "$LOG_FILE"

# Création et configuration de la GPO Restrict_T0
GPO_NAME="Restrict_T0"
OU_PATH="OU=NS,OU=Group_ADMT0,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"

echo "🔒 Restriction des accès pour Group_ADMT0..." | tee -a "$LOG_FILE"
mkdir -p "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT0
SeDenyInteractiveLogonRight = NORTHSTAR\Group_ADMT0
SeDenyRemoteInteractiveLogonRight = NORTHSTAR\Group_ADMT0
EOF

apply_gpo "$GPO_NAME" "$OU_PATH" "$GPO_GUID" "$GPO_PATH"

# Ajout des groupes au Tiers T0
echo "👥 Ajout des groupes à Group_ADMT0..." | tee -a "$LOG_FILE"
samba-tool group addmembers "Domain Admins" "Group_ADMT0" 2>&1 | tee -a "$LOG_FILE"
samba-tool group addmembers "Enterprise Admins" "Group_ADMT0" 2>&1 | tee -a "$LOG_FILE"
samba-tool group addmembers "Schema Admins" "Group_ADMT0" 2>&1 | tee -a "$LOG_FILE"
samba-tool group addmembers "Event Log Readers" "Group_ADMT0" 2>&1 | tee -a "$LOG_FILE"

########################################################
# SECTION T1 : Configuration pour T1
########################################################
echo "🔹 Début de la configuration pour T1..." | tee -a "$LOG_FILE"

# 1. Création et configuration de la GPO Enable_RDP_T1
GPO_NAME="Enable_RDP_T1"
OU_PATH="OU=NS,OU=Servers_T1,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"

echo "🛠 Activation du Bureau à distance (RDP)..." | tee -a "$LOG_FILE"
mkdir -p "$GPO_PATH/Machine"
cat <<EOF > "$GPO_PATH/Machine/Registry.pol"
[Registry Settings]
HKLM\System\CurrentControlSet\Control\Terminal Server!fDenyTSConnections=DWORD:0
EOF

apply_gpo "$GPO_NAME" "$OU_PATH" "$GPO_GUID" "$GPO_PATH"

# 2. Création et configuration de la GPO Restrict_T1
GPO_NAME="Restrict_T1"
OU_PATH="OU=NS,OU=Group_ADMT1,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"

echo "🔒 Restriction des accès pour Group_ADMT1..." | tee -a "$LOG_FILE"
mkdir -p "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT1
SeDenyInteractiveLogonRight = NORTHSTAR\Group_ADMT1
SeDenyRemoteInteractiveLogonRight = NORTHSTAR\Group_ADMT1
EOF

apply_gpo "$GPO_NAME" "$OU_PATH" "$GPO_GUID" "$GPO_PATH"

# Ajout de Group_ADMT1 aux groupes tiers
echo "👥 Ajout de Group_ADMT1 à des groupes tiers..." | tee -a "$LOG_FILE"
GROUPS_T1=(
    "Remote Desktop Users"
    "Server Operators"
    "DnsAdmins"
    "Group Policy Creator Owners"
    "Event Log Readers"
    "Network Configuration Operators"
    "Performance Monitor Users"
    "Performance Log Users"
)

for GROUP in "${GROUPS_T1[@]}"; do
    samba-tool group addmembers "$GROUP" "Group_ADMT1" 2>&1 | tee -a "$LOG_FILE"
done

########################################################
# SECTION T2 : Configuration pour T2
########################################################
echo "🔹 Début de la configuration pour T2..." | tee -a "$LOG_FILE"

# 1. Création et configuration de la GPO Restrict_T2
GPO_NAME="Restrict_T2"
OU_PATH="OU=NS,OU=Group_ADMT2,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< "$(create_gpo "$GPO_NAME")"

echo "🛠 Ajout de Group_ADMT2 en tant qu'administrateur local..." | tee -a "$LOG_FILE"
mkdir -p "$GPO_PATH/Machine/Preferences/Groups"
cat <<EOF > "$GPO_PATH/Machine/Preferences/Groups/Groups.xml"
<Groups>
    <UserGroup>
        <Properties action="U" name="Administrators (built-in)" description="Ajout de Group_ADMT2 en admin local"/>
        <Members>
            <Member name="NORTHSTAR\Group_ADMT2" action="ADD" />
        </Members>
    </UserGroup>
</Groups>
EOF

echo "🔒 Restriction des accès pour Group_ADMT2..." | tee -a "$LOG_FILE"
mkdir -p "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT2
SeDenyInteractiveLogonRight = NORTHSTAR\Group_ADMT2
SeDenyRemoteInteractiveLogonRight = NORTHSTAR\Group_ADMT2
EOF

apply_gpo "$GPO_NAME" "$OU_PATH" "$GPO_GUID" "$GPO_PATH"

# Ajout de Group_ADMT2 aux administrateurs locaux
echo "👥 Ajout du groupe Group_ADMT2 aux administrateurs locaux..." | tee -a "$LOG_FILE"
samba-tool group addmembers "Administrators" "Group_ADMT2" 2>&1 | tee -a "$LOG_FILE"

########################################################
# Fin de la configuration
########################################################
echo "===============================" | tee -a "$LOG_FILE"
echo "✅ Configuration complète des GPOs ! " | tee -a "$LOG_FILE"
echo "===============================" | tee -a "$LOG_FILE"
