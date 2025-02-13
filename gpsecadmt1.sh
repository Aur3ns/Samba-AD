#!/bin/bash

DOMAIN="northstar.com"

# Fonction pour créer une GPO et récupérer son GUID
create_gpo() {
    local GPO_NAME="$1"
    local OU_PATH="$2"

    echo "📌 Création de la GPO $GPO_NAME..."
    samba-tool gpo setlink "$GPO_NAME"
    
    local GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk '{print $3}')
    local GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"
    
    echo "$GPO_GUID" "$GPO_PATH"
}

# Création et configuration de la GPO Enable_RDP_T1
GPO_NAME="Enable_RDP_T1"
OU_PATH="OU=Servers_T1,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< $(create_gpo "$GPO_NAME" "$OU_PATH")

echo "🛠 Activation du Bureau à distance (RDP)..."
mkdir -p "$GPO_PATH/Machine"
cat <<EOF > "$GPO_PATH/Machine/Registry.pol"
[Registry Settings]
HKLM\System\CurrentControlSet\Control\Terminal Server!fDenyTSConnections=DWORD:0
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Servers_T1..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"

echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"

# Création et configuration de la GPO Restrict_T1
GPO_NAME="Restrict_T1"
OU_PATH="OU=Group_ADMT1,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< $(create_gpo "$GPO_NAME" "$OU_PATH")

echo "🔒 Restriction des accès pour Group_ADMT1..."
mkdir -p "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT1
SeDenyInteractiveLogonRight = NORTHSTAR\Group_ADMT1
SeDenyRemoteInteractiveLogonRight = NORTHSTAR\Group_ADMT1
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Group_ADMT1..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"

echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"

# Ajout des groupes aux tiers pour Group_ADMT1
echo "👥 Ajout de Group_ADMT1 aux groupes tiers..."
GROUPS=(
    "Remote Desktop Users"
    "Server Operators"
    "DnsAdmins"
    "Group Policy Creator Owners"
    "Event Log Readers"
    "Network Configuration Operators"
    "Performance Monitor Users"
    "Performance Log Users"
)

for GROUP in "${GROUPS[@]}"; do
    samba-tool group addmembers "$GROUP" "Group_ADMT1"
done

echo "✅ Fin de la configuration"
