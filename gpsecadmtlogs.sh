#!/bin/bash

DOMAIN="northstar.com"
LOG_FILE="/var/log/samba-ad-config.log"

echo "🚀 Début de la configuration du domaine $DOMAIN..." | tee -a $LOG_FILE

# Liste des OU à créer
OU_LIST=(
    "OU=Group_ADMT0,DC=northstar,DC=com"
    "OU=Group_ADMT1,DC=northstar,DC=com"
    "OU=Group_ADMT2,DC=northstar,DC=com"
    "OU=Servers_T1,DC=northstar,DC=com"
)

echo "📌 Création des OU nécessaires..." | tee -a $LOG_FILE

for OU in "${OU_LIST[@]}"; do
    echo "🔍 Vérification de l'existence de $OU..." | tee -a $LOG_FILE
    
    if samba-tool ou list | grep -q "$(echo $OU | cut -d',' -f1 | cut -d'=' -f2)"; then
        echo "✅ L'OU $OU existe déjà." | tee -a $LOG_FILE
    else
        echo "➕ Création de l'OU $OU..." | tee -a $LOG_FILE
        samba-tool ou create "$OU"
        
        if [ $? -eq 0 ]; then
            echo "✅ L'OU $OU a été créée avec succès." | tee -a $LOG_FILE
        else
            echo "❌ Échec de la création de l'OU $OU." | tee -a $LOG_FILE
        fi
    fi
done

# Désactivation des groupes inutiles
echo "📌 Désactivation des groupes inutiles..." | tee -a $LOG_FILE
GROUPS_TO_DISABLE=(
    "Guests"
    "Domain Guests"
    "Print Operators"
    "Backup Operators"
    "Cryptographic Operators"
    "IIS_IUSRS"
)

for GROUP in "${GROUPS_TO_DISABLE[@]}"; do
    echo "🔒 Modification de la description du groupe '$GROUP' pour indiquer qu'il est désactivé..." | tee -a $LOG_FILE
    samba-tool group edit "$GROUP" --description="Désactivé pour des raisons de sécurité" && echo "✅ Groupe '$GROUP' mis à jour." | tee -a $LOG_FILE
done

# Vérification DNS
echo "📌 Vérification et mise à jour des enregistrements DNS..." | tee -a $LOG_FILE
DNS_RECORDS=(
    "_ldap._tcp.$DOMAIN"
    "_kerberos._tcp.$DOMAIN"
)

for RECORD in "${DNS_RECORDS[@]}"; do
    if ! samba-tool dns query 127.0.0.1 "$DOMAIN" "$RECORD" A | grep -q "Name="; then
        echo "⚠️  Enregistrement DNS $RECORD non trouvé. Tentative de mise à jour..." | tee -a $LOG_FILE
        samba-tool dns add 127.0.0.1 "$DOMAIN" "$RECORD" A 10.0.0.1
    else
        echo "✅ Enregistrement DNS $RECORD trouvé." | tee -a $LOG_FILE
    fi
done

# Fonction pour créer une GPO et récupérer son GUID
create_gpo() {
    local GPO_NAME="$1"
    local OU_PATH="$2"

    echo "📌 Création de la GPO $GPO_NAME..." | tee -a $LOG_FILE
    samba-tool gpo create "$GPO_NAME"
    
    local GPO_GUID=$(samba-tool gpo list | grep "$GPO_NAME" | awk 'NR==1 {print $3}')
    local GPO_PATH="/var/lib/samba/sysvol/$DOMAIN/Policies/{$GPO_GUID}"
    
    echo "$GPO_GUID" "$GPO_PATH"
}

# Création et configuration de la GPO Restrict_Log_Access
GPO_NAME="Restrict_Log_Access"
OU_PATH="OU=Group_ADMT1,DC=northstar,DC=com"
read GPO_GUID GPO_PATH <<< $(create_gpo "$GPO_NAME" "$OU_PATH")

echo "🔒 Restriction des accès aux logs pour les Tiers..." | tee -a $LOG_FILE
mkdir -p "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit"
cat <<EOF > "$GPO_PATH/Machine/Microsoft/Windows NT/SecEdit/GptTmpl.inf"
[Event Audit]
System Log Access= NORTHSTAR\Group_ADMT0,NORTHSTAR\Group_ADMT1
Security Log Access= NORTHSTAR\Group_ADMT0
Application Log Access= NORTHSTAR\Group_ADMT0,NORTHSTAR\Group_ADMT1,NORTHSTAR\Group_ADMT2
EOF

chmod -R 770 "$GPO_PATH"

echo "📌 Lien de la GPO '$GPO_NAME' à l'OU $OU_PATH..." | tee -a $LOG_FILE
samba-tool gpo setlink "$GPO_NAME" "$OU_PATH" --option="displayname=$GPO_NAME"

# Application des permissions sur les dossiers critiques
echo "📌 Application des permissions sur les dossiers critiques..." | tee -a $LOG_FILE
chmod 750 /var/lib/samba/sysvol
chmod 750 /etc/samba/
chmod 750 /var/log/samba/

echo "✅ Permissions appliquées." | tee -a $LOG_FILE
echo "🚀 Fin de la configuration. Consultez $LOG_FILE pour les détails." | tee -a $LOG_FILE
