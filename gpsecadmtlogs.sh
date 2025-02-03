#!/bin/bash
#GPO Samba qui force chaque Tier à ne voir que ses propres logs.
GPO_NAME="Restrict_Log_Access"
DOMAIN="northstar.com"
OU_PATH="OU=Group_ADMT1,DC=northstar,DC=com"

echo "📌 Création de la GPO $GPO_NAME..."
samba-tool gpo create "$GPO_NAME"

GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk '{print $3}')
GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"

echo "🔒 Restriction des accès aux logs pour les Tiers..."
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Event Audit]
System Log Access= NORTHSTAR\Group_ADMT0,NORTHSTAR\Group_ADMT1
Security Log Access= NORTHSTAR\Group_ADMT0
Application Log Access= NORTHSTAR\Group_ADMT0,NORTHSTAR\Group_ADMT1,NORTHSTAR\Group_ADMT2
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Servers..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"

echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"
