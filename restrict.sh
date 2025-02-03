samba-tool group delete "Guests"
samba-tool group delete "Domain Guests"
samba-tool group delete "Print Operators"
samba-tool group delete "Backup Operators"
samba-tool group delete "Cryptographic Operators"
samba-tool group delete "IIS_IUSRS"
#!/bin/bash

GPO_NAME="Deny_T2_Network"
DOMAIN="northstar.com"
OU_PATH="OU=Group_ADMT2,DC=northstar,DC=com"
#GPO empechant le groupe ADMT2 de modifier les configurations réseaux des serveurs
echo "📌 Création de la GPO $GPO_NAME..."
samba-tool gpo create "$GPO_NAME"

GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk '{print $3}')
GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"

echo "🔒 Restriction des accès réseau pour Group_ADMT2..."
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT2
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Group_ADMT2..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"

echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"
