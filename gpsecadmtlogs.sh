#!/bin/bash

DOMAIN="northstar.com"

# Suppression des groupes inutiles
echo "🗑 Suppression des groupes inutiles..."
GROUPS_TO_DELETE=(
    "Guests"
    "Domain Guests"
    "Print Operators"
    "Backup Operators"
    "Cryptographic Operators"
    "IIS_IUSRS"
)

for GROUP in "${GROUPS_TO_DELETE[@]}"; do
    samba-tool group delete "$GROUP" && echo "✅ Groupe '$GROUP' supprimé."
done

# Fonction pour créer une GPO et récupérer son GUID
create_gpo() {
    local GPO_NAME="$1"
    local OU_PATH="$2"

    echo "📌 Création de la GPO $GPO_NAME..."
    samba-tool gpo create "$GPO_NAME"
    
    local GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk 'NR==1 {print $3}')
    local GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"
    
    echo "$GPO_GUID" "$GPO_PATH"
}

# Création et configuration de la GPO Restrict_Log_Access
GPO_NAME="Restrict_Log_Access"
OU_PATH="OU=Group_ADMT1,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< $(create_gpo "$GPO_NAME" "$OU_PATH")

echo "🔒 Restriction des accès aux logs pour les Tiers..."
mkdir -p "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit"
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
echo "🚀 Fin de la configuration."
