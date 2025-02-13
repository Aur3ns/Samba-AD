#!/bin/bash

DOMAIN="northstar.com"

echo "🚀 Début de la configuration du domaine $DOMAIN..."

# Liste des OU à créer
OU_LIST=(
@@ -12,30 +13,28 @@ OU_LIST=(
    "OU=Servers_T1,DC=northstar,DC=com"
)

echo "📌 Création des OU nécessaires..."

for OU in "${OU_LIST[@]}"; do
    echo "🔍 Vérification de l'existence de $OU..."

    # Vérifier si l'OU existe déjà
    samba-tool ou list | grep -q "$(echo $OU | cut -d',' -f1 | cut -d'=' -f2)"
    
    if [ $? -eq 0 ]; then
        echo "✅ L'OU $OU existe déjà."
    else
        echo "➕ Création de l'OU $OU..."
        samba-tool ou create "$OU"

        if [ $? -eq 0 ]; then
            echo "✅ L'OU $OU a été créée avec succès."
        else
            echo "❌ Échec de la création de l'OU $OU."
        fi
    fi
done

echo "📌 Suppression des groupes inutiles..."
GROUPS_TO_DELETE=(
    "Guests"
    "Domain Guests"
    "Print Operators"
@@ -44,16 +43,33 @@ GROUPS_TO_DELETE=(
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
    samba-tool gpo setlink "$GPO_NAME"

    local GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk 'NR==1 {print $3}')
@@ -67,7 +83,7 @@ GPO_NAME="Restrict_Log_Access"
OU_PATH="OU=Group_ADMT1,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< $(create_gpo "$GPO_NAME" "$OU_PATH")

echo "🔒 Restriction des accès aux logs pour les Tiers..."
mkdir -p "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Event Audit]
@@ -78,15 +94,14 @@ EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Application de la GPO à l'OU Servers..."
samba-tool gpo setoptions "$GPO_NAME" --enable
samba-tool gpo acl "$GPO_GUID" --assign="$OU_PATH"
echo "✅ GPO '$GPO_NAME' appliquée avec succès à $OU_PATH"

echo "📌 Application des ACL sur les dossiers critiques. Seuls les administrateurs auront accès."
chmod 750 /var/lib/samba/sysvol
chmod 750 /etc/samba/
chmod 750 /var/log/samba/

echo "🚀 Fin de la configuration."
