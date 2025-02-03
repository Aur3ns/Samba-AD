#!/bin/bash

GPO_NAME="Restrict_T2"
DOMAIN="northstar.com"
OU_PATH="OU=Group_ADMT2,DC=northstar,DC=com"

echo "📌 Création de la GPO $GPO_NAME..."
samba-tool gpo create "$GPO_NAME"

GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk '{print $3}')
GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"

echo "🛠 Configuration de l'admin local..."
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

echo "🔒 Restriction des accès..."
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT2
SeDenyInteractiveLogonRight = NORTHSTAR\Group_ADMT2
SeDenyRemoteInteractiveLogonRight = NORTHSTAR\Group_ADMT2
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Group_ADMT2..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"


echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"

echo " Ajout des groupes aux tiers en cours..."
samba-tool group addmembers "Administrators" "Group_ADMT2"

echo " Fin de la configuration"
