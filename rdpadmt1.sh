#!/bin/bash

GPO_NAME="Enable_RDP_T1"
DOMAIN="northstar.com"
OU_PATH="OU=Servers_T1,DC=northstar,DC=com"

echo "📌 Création de la GPO $GPO_NAME..."
samba-tool gpo create "$GPO_NAME"

GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk '{print $3}')
GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"

echo "🛠 Activation du Bureau à distance (RDP)..."
cat <<EOF > "$GPO_PATH/Machine/Registry.pol"
[Registry Settings]
HKLM\System\CurrentControlSet\Control\Terminal Server!fDenyTSConnections=DWORD:0
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Servers_T1..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"

echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"
