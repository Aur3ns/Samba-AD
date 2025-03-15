#!/bin/bash
# Script d'installation du serveur Wazuh sur Debian/Ubuntu

# Arrêter le script en cas d'erreur
set -e

echo "Mise à jour du système..."
sudo apt update && sudo apt upgrade -y

echo "Ajout de la clé GPG de Wazuh..."
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | sudo apt-key add -

echo "Ajout du dépôt Wazuh..."
echo "deb https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list

echo "Mise à jour des dépôts..."
sudo apt update

echo "Installation du gestionnaire Wazuh..."
sudo apt install -y wazuh-manager

echo "Démarrage et activation du service Wazuh Manager..."
sudo systemctl start wazuh-manager
sudo systemctl enable wazuh-manager

echo "Vérification de l'état du service Wazuh Manager..."
sudo systemctl status wazuh-manager
