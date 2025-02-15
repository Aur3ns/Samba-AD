#!/bin/bash

# Vérifie si le script est exécuté avec les privilèges root
if [ "$EUID" -ne 0 ]; then
  echo "Veuillez exécuter ce script en tant que root."
  exit 1
fi

echo "Modification des paramètres régionaux pour Debian..."

# Change la configuration des locales
sed -i '/^LANG=/c\LANG=fr_FR.UTF-8' /etc/default/locale
sed -i '/^LANGUAGE=/c\LANGUAGE=fr_FR:fr' /etc/default/locale
grep -q "^LC_MESSAGES=" /etc/default/locale || echo "LC_MESSAGES=fr_FR.UTF-8" >> /etc/default/locale

# Vérifie si xdg-user-dirs-update est installé
if ! command -v xdg-user-dirs-update &> /dev/null; then
  echo "Le paquet xdg-user-dirs n'est pas installé. Installation..."
  apt update && apt install -y xdg-user-dirs
fi

# Remet les noms des dossiers utilisateurs en anglais
echo "Modification des noms de dossiers utilisateurs en anglais..."
LANG=C xdg-user-dirs-update --force

echo "Opération terminée. Veuillez redémarrer votre session pour appliquer les changements."
