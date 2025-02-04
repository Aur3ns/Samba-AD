#!/bin/bash

DOMAIN="northstar.com"

# Liste des OU à créer
OU_LIST=(
    "OU=Group_ADMT0,DC=northstar,DC=com"
    "OU=Group_ADMT1,DC=northstar,DC=com"
    "OU=Group_ADMT2,DC=northstar,DC=com"
    "OU=Servers_T1,DC=northstar,DC=com"
)

echo "🚀 Début de la création des OU..."

# Boucle pour créer chaque OU
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

echo "🚀 Toutes les OU nécessaires sont maintenant créées."
