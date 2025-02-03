#!/bin/bash

GPO_NAME="Restrict_T0"
DOMAIN="northstar.com"
OU_PATH="OU=Group_ADMT0,DC=northstar,DC=com"

echo "📌 Création de la GPO $GPO_NAME..."
samba-tool gpo create "$GPO_NAME"

GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk '{print $3}')
GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"

echo "🔒 Restriction des accès pour Group_ADMT0..."
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT0
SeDenyInteractiveLogonRight = NORTHSTAR\Group_ADMT0
SeDenyRemoteInteractiveLogonRight = NORTHSTAR\Group_ADMT0
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Group_ADMT0..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"

echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"

echo "Ajout des groupes au Tiers..."
samba-tool group addmembers "Domain Admins" "T0_Admins"
samba-tool group addmembers "Enterprise Admins" "T0_Admins"
samba-tool group addmembers "Schema Admins" "T0_Admins"

echo "Fin de la configuration"
