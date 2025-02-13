#!/bin/bash

DOMAIN="northstar.com"
OU_PATH="OU=Group_ADMT2,DC=northstar,DC=com"

# Fonction pour créer une GPO et récupérer son GUID
create_gpo() {
    local GPO_NAME="$1"
    echo "📌 Création de la GPO $GPO_NAME..."
    samba-tool gpo setlink "$GPO_NAME"
    
    local GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk '{print $3}')
    local GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"
    
    echo "$GPO_GUID" "$GPO_PATH"
}

# Création et configuration de la GPO Restrict_T2
GPO_NAME="Restrict_T2"
read GPO_GUID GPO_PATH <<< $(create_gpo "$GPO_NAME")

echo "🛠 Configuration de l'admin local..."
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

echo "🔒 Restriction des accès..."
mkdir -p "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit"
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

# Création et configuration de la GPO Deny_T2_Network
GPO_NAME="Deny_T2_Network"
read GPO_GUID GPO_PATH <<< $(create_gpo "$GPO_NAME")

echo "🔒 Restriction des accès réseau pour Group_ADMT2..."
mkdir -p "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Privilege Rights]
SeDenyNetworkLogonRight = NORTHSTAR\Group_ADMT2
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Group_ADMT2..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"

echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"

# Ajout de Group_ADMT2 aux administrateurs locaux
echo "👥 Ajout du groupe Group_ADMT2 aux administrateurs locaux..."
samba-tool group addmembers "Administrators" "Group_ADMT2"

echo "✅ Fin de la configuration"
